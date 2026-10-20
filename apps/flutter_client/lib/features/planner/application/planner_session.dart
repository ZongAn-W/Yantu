import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/planner_coordinator.dart';
import '../../../core/sync/sync_state.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/plan_cycle.dart';
import '../domain/planner_format.dart';
import '../domain/scheduler/planner_scheduler.dart' as scheduler;
import '../domain/study_day.dart' as day_ops;
import '../domain/task_editing.dart';
import 'planner_sync.dart';

export '../domain/task_editing.dart'
    show ScheduleOutcome, TaskDraft, validateTaskDraft;

/// Immutable view of the sync coordinator for widgets.
///
/// It is rebuilt whenever the coordinator notifies, so `ref.watch` re-renders the
/// pages on local saves, remote pulls and status changes.
@immutable
class PlannerSnapshot {
  const PlannerSnapshot({
    required this.data,
    required this.revision,
    required this.pending,
    required this.status,
    required this.message,
    required this.blocked,
    required this.ready,
    required this.busy,
    required this.conflicts,
  });

  final PlannerData? data;
  final int revision;
  final bool pending;
  final SyncStatus status;
  final String message;
  final bool blocked;
  final bool ready;
  final bool busy;
  final List<String> conflicts;

  bool get editable => data != null && !blocked;
}

final plannerDataProvider = Provider<PlannerSnapshot>((ref) {
  final coordinator = ref.watch(plannerSyncProvider);
  return PlannerSnapshot(
    data: coordinator.data,
    revision: coordinator.metadata.revision,
    pending: coordinator.metadata.pending,
    status: coordinator.status,
    message: coordinator.message,
    blocked: coordinator.blocked,
    ready: coordinator.ready,
    busy: coordinator.busy,
    conflicts: coordinator.conflicts,
  );
});

/// Commands the pages call. Every change is written to the local database first and
/// then handed to the existing sync coordinator; no page talks to HTTP or Sembast.
class PlannerSession {
  PlannerSession(this.coordinator);
  final PlannerCoordinator coordinator;

  PlannerData get data {
    final value = coordinator.data;
    if (value == null) throw StateError('本机计划尚未读取完成');
    return value;
  }

  Future<void> edit(PlannerData Function(PlannerData) change) =>
      coordinator.edit(change);

  Future<String> createTag({required String name, String? color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('请填写标签名称');
    if (color != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      throw StateError('标签颜色格式不正确');
    }
    final existing = data.tags
        .where((tag) => tag.name.trim().toLowerCase() == trimmed.toLowerCase())
        .firstOrNull;
    if (existing != null) return existing.id;
    final tagId = 'tag-${DateTime.now().microsecondsSinceEpoch}';
    final stamp = nowIso();
    await edit(
      (data) => data.copyWith(
        tags: [
          ...data.tags,
          Tag(
            id: tagId,
            userId: data.profile.userId,
            name: trimmed,
            color: color,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        ],
      ),
    );
    return tagId;
  }

  Future<void> renameTag(String tagId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('请填写标签名称');
    final duplicate = data.tags.any(
      (tag) =>
          tag.id != tagId &&
          tag.name.trim().toLowerCase() == trimmed.toLowerCase(),
    );
    if (duplicate) throw StateError('已存在同名标签');
    await edit(
      (data) => data.copyWith(
        tags: [
          for (final tag in data.tags)
            tag.id == tagId
                ? tag.copyWith(name: trimmed, updatedAt: nowIso())
                : tag,
        ],
      ),
    );
  }

  Future<void> recolorTag(String tagId, String? color) async {
    if (color != null && !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      throw StateError('标签颜色格式不正确');
    }
    await edit(
      (data) => data.copyWith(
        tags: [
          for (final tag in data.tags)
            tag.id == tagId ? tag.copyWith(color: color) : tag,
        ],
      ),
    );
  }

  Future<void> deleteTag(String tagId) => edit(
    (data) => data.copyWith(
      tags: data.tags.where((tag) => tag.id != tagId).toList(growable: false),
      tasks: [
        for (final task in data.tasks)
          task.copyWith(
            tagIds: task.tagIds
                .where((id) => id != tagId)
                .toList(growable: false),
          ),
      ],
    ),
  );

  Future<void> setTaskTags(String taskId, List<String> tagIds) => edit(
    (data) => data.copyWith(
      tasks: [
        for (final task in data.tasks)
          task.id == taskId
              ? task.copyWith(
                  tagIds: tagIds
                      .where((id) => data.tags.any((tag) => tag.id == id))
                      .toSet()
                      .toList(growable: false),
                  updatedAt: nowIso(),
                )
              : task,
      ],
    ),
  );

  // ------------------------------------------------------------------ tasks

  Future<String> createTask(TaskDraft draft) async {
    final taskId = scheduler.SchedulerRuntime().ids();
    await edit(
      (data) =>
          applyTaskDraft(data, draft, taskId: taskId, updatedAt: nowIso()),
    );
    return taskId;
  }

  Future<void> updateTask(String taskId, TaskDraft draft) => edit(
    (data) => applyTaskDraft(data, draft, taskId: taskId, updatedAt: nowIso()),
  );

  Future<void> deleteTask(String taskId) =>
      edit((data) => day_ops.deleteTask(data, taskId));

  Future<void> completeTask(
    String taskId, {
    required int actualMinutes,
    required String date,
  }) => edit(
    (data) => day_ops.completeTask(
      data,
      taskId,
      date: date,
      actualMinutes: actualMinutes,
    ),
  );

  // --------------------------------------------------------------- schedule

  Future<ScheduleOutcome> scheduleTask({
    required String taskId,
    required String date,
    required int? minutes,
  }) async {
    ScheduleOutcome? outcome;
    await edit((data) {
      final result = scheduleTaskDay(data, taskId, date, minutes);
      outcome = result.outcome;
      return result.data;
    });
    return outcome!;
  }

  /// Moves the day the dialog opened on. Only the stable ids and the expected
  /// source date are handed to the serialized edit; the current records are read
  /// from the latest state, so a stale snapshot cannot overwrite newer plans.
  Future<void> moveTaskDay(List<ScheduleBlock> blocks, String targetDate) =>
      moveTaskDayByIds(
        [for (final block in blocks) block.id],
        targetDate,
        sourceDate: blocks.isEmpty ? targetDate : blocks.first.date,
      );

  /// Moves the given records after resolving them from the latest serialized
  /// plan. Fails with a user-understandable [StateError] without writing anything
  /// when a record was deleted, changed day or became protected meanwhile.
  Future<void> moveTaskDayByIds(
    Iterable<String> blockIds,
    String targetDate, {
    required String sourceDate,
  }) async {
    final ids = [...blockIds];
    if (ids.isEmpty) return;
    await edit((current) {
      final result = day_ops.moveTaskDayByIds(
        current,
        ids,
        targetDate,
        expectedSourceDate: sourceDate,
      );
      if (!result.ok) throw StateError(result.error!);
      return current.copyWith(blocks: result.blocks);
    });
  }

  // ---------------------------------------------------------------- records

  Future<void> recordDayMinutes(String taskId, String date, int minutes) =>
      coordinator.recordDayMinutes(taskId, date, minutes);

  /// 把临时学习转为新的正式事项：原日志/会话标识与用时保持不变，只补上事项归属，
  /// 临时实体归档并记录 `converted_task_id`；重复确认不会复制分钟。
  Future<day_ops.AdHocConvertResult> convertAdHocToTask({
    required String adHocId,
    required TaskDraft draft,
  }) async {
    late day_ops.AdHocConvertResult result;
    await edit((current) {
      result = day_ops.convertAdHocToTask(
        current,
        adHocId,
        draft,
        taskId: scheduler.SchedulerRuntime().ids(),
        updatedAt: nowIso(),
      );
      return result.data;
    });
    return result;
  }

  /// 把临时学习的真实记录关联到已有事项，历史仍标记为临时学习关系。
  Future<day_ops.AdHocConvertResult> linkAdHocToTask({
    required String adHocId,
    required String taskId,
  }) async {
    late day_ops.AdHocConvertResult result;
    await edit((current) {
      result = day_ops.linkAdHocToTask(
        current,
        adHocId,
        taskId,
        updatedAt: nowIso(),
      );
      return result.data;
    });
    return result;
  }

  // ------------------------------------------------------------ plan cycle

  /// 延展本次规划周期，并只把本期安排边界类事项的日期跟随新周期。
  Future<void> updatePlanCycle({required String start, required String end}) =>
      edit(
        (data) => extendPlanCycle(
          data,
          start: start,
          end: end,
          today: shanghaiToday(),
        ),
      );

  /// 生成 [from] 到 [to] 的每日安排；重复执行不会重复生成已有安排。
  Future<PlanGenerationResult> generateSchedule({
    required String from,
    required String to,
  }) async {
    // Generate inside the serialized edit so the result is computed from the
    // latest plan; computing outside and writing the whole snapshot back would
    // drop edits or sync changes that landed while the dialog was open.
    late PlanGenerationResult result;
    await edit((current) {
      result = generatePlanBlocks(current, from: from, to: to);
      return result.data;
    });
    return result;
  }

  // ----------------------------------------------------------------- replan

  Future<ReplanPreview> previewReplan({
    required String today,
    ReplanMode mode = ReplanMode.unfinished,
    int? excessMinutes,
  }) => coordinator.previewReplan(
    today: today,
    mode: mode,
    excessMinutes: excessMinutes,
  );

  /// Drops the unconfirmed proposal.
  ///
  /// The dialog calls this from `dispose`, so the notification is deferred by a
  /// microtask: notifying listeners while the widget tree is still being finalized
  /// makes Riverpod rebuild a provider mid-unmount.
  void cancelReplan() {
    coordinator.replanProposal = null;
    Future.microtask(coordinator.notifyProposalChanged);
  }

  Future<void> confirmReplan() => coordinator.confirmReplan();
  Future<void> undoReplan() => coordinator.undoReplan();

  // ------------------------------------------------------------------ admin

  Future<void> sync() => coordinator.sync();
  Future<void> exportJson() => coordinator.exportJson();
  Future<void> importJson() => coordinator.importJson();
  Future<void> recover() => coordinator.recover();
  Future<void> resolveConflict({required bool useLocal}) =>
      coordinator.resolve(useLocal: useLocal);
  Future<void> reload() => coordinator.initialize();
}

final plannerSessionProvider = Provider<PlannerSession>(
  (ref) => PlannerSession(ref.watch(plannerSyncProvider)),
);
