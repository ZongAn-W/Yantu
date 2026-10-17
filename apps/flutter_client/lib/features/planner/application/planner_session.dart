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
    show
        ScheduleOutcome,
        TaskDraft,
        validateTaskDraft,
        resolveSubjectId,
        fixedEventConflict;

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

  // ------------------------------------------------------------------ tasks

  Future<void> createTask(TaskDraft draft) => edit(
    (data) => applyTaskDraft(
      data,
      draft,
      taskId: scheduler.SchedulerRuntime().ids(),
      updatedAt: nowIso(),
    ),
  );

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

  Future<void> setTaskDayCompletion(
    Iterable<ScheduleBlock> blocks,
    bool completed,
  ) => edit((data) => day_ops.setTaskDayCompletion(data, blocks, completed));

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

  Future<void> moveTaskDay(
    List<ScheduleBlock> blocks,
    String targetDate,
  ) async {
    final result = day_ops.moveTaskDay(data, blocks, targetDate);
    if (!result.ok) throw StateError(result.error!);
    await edit((data) => data.copyWith(blocks: result.blocks));
  }

  Future<void> createFixedEvent(FixedEvent event) =>
      edit((data) => addFixedEvent(data, event));

  Future<void> deleteFixedEvent(String eventId) => edit(
    (data) => data.copyWith(
      fixedEvents: data.fixedEvents
          .where((event) => event.id != eventId)
          .toList(),
    ),
  );

  // ---------------------------------------------------------------- records

  Future<void> recordDayMinutes(String taskId, String date, int minutes) =>
      coordinator.recordDayMinutes(taskId, date, minutes);

  Future<void> saveDailyReview(
    String date, {
    required List<day_ops.TaskDayReview> original,
    required List<day_ops.TaskDayReview> edited,
    required String originalFeedback,
    required String feedback,
  }) => edit(
    (data) => day_ops.applyDailyReview(
      data,
      date,
      original: original,
      edited: edited,
      originalFeedback: originalFeedback,
      feedback: feedback,
    ),
  );

  // ------------------------------------------------------------ plan cycle

  /// 延展本次规划周期，并只把本期安排边界类事项的日期跟随新周期。
  Future<void> updatePlanCycle({
    required String start,
    required String end,
  }) => edit(
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
    final result = generatePlanBlocks(data, from: from, to: to);
    await edit((_) => result.data);
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
