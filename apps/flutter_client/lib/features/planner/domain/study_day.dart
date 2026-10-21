import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';
import '../../../shared/models/task_lifecycle.dart';
import 'planner_format.dart';
import 'scheduler/planner_scheduler.dart' as scheduler;
import 'task_editing.dart';

/// 三类学习关系的界面标签，与 [LogSource]（记录方式）相互独立。
const timeLogRelationLabels = {
  TimeLogRelation.scheduled: '今日原定学习',
  TimeLogRelation.extra: '已有事项加学',
  TimeLogRelation.adHoc: '全新临时学习',
  TimeLogRelation.legacyUnknown: '历史记录',
};

/// Plan and actual minutes for one calendar day, matching the Web `dayStats`.
///
/// [scheduled] is the capped original-plan achievement (scheduled logs plus the
/// limited legacy inference); it is never inflated by extra or temporary study.
class DayStats {
  const DayStats({
    required this.planned,
    required this.actual,
    required this.remaining,
    required this.excess,
    required this.rate,
    this.scheduled = 0,
    this.extra = 0,
    this.adHoc = 0,
    this.legacyUnknown = 0,
  });

  final int planned;
  final int actual;
  final int remaining;
  final int excess;
  final int rate;
  final int scheduled;
  final int extra;
  final int adHoc;
  final int legacyUnknown;
}

/// Execution facts of one day split by learning relation.
///
/// Every valid log minute appears exactly once: `scheduled + legacyUnknown +
/// extra + adHoc` is split by relation without duplicating whole segments.
class DayExecutionSummary {
  const DayExecutionSummary({
    required this.planned,
    required this.scheduledByTask,
    required this.extra,
    required this.adHoc,
    required this.legacyUnknown,
  });

  final int planned;
  final Map<String, int> scheduledByTask;
  final int extra;
  final int adHoc;
  final int legacyUnknown;

  int get scheduled =>
      scheduledByTask.values.fold<int>(0, (sum, value) => sum + value);
  int get actual => scheduled + legacyUnknown + extra + adHoc;
}

/// Original-plan achievement per task on one day, capped by that task's plan.
///
/// Only logs whose relation is [TimeLogRelation.scheduled] count. Legacy logs
/// without a relation are inferred only from reliable evidence (CONTEXT §2.4):
///
/// 1. a `block_id` that resolves to a block of the same task is treated as
///    scheduled (the record was bound to that plan);
/// 2. remaining unclassified logs of a task/day that has blocks are allocated to
///    the plan in start-time order, never exceeding the planned minutes.
///
/// Everything else stays [TimeLogRelation.legacyUnknown]: counted in actual time
/// but never in original-plan achievement.
DayExecutionSummary dayExecutionSummary(PlannerData data, String date) {
  final blocks = data.blocks.where((block) => block.date == date).toList();
  final plannedByTask = <String, int>{};
  for (final block in blocks) {
    plannedByTask[block.taskId] =
        (plannedByTask[block.taskId] ?? 0) + block.durationMinutes;
  }
  final blockById = {for (final block in data.blocks) block.id: block};
  final scheduledLogs = <String, int>{};
  final legacyByTask = <String, List<TimeLog>>{};
  var extra = 0, adHoc = 0, legacyUnknown = 0;
  for (final log in data.logs) {
    if (log.date != date) continue;
    final taskId = log.taskId;
    if (taskId == null) {
      if (log.relation == TimeLogRelation.adHoc) {
        adHoc += log.minutes;
      } else {
        // A task-less log that is not ad-hoc has no owner to attribute to; it
        // still counts once as unknown actual time.
        legacyUnknown += log.minutes;
      }
      continue;
    }
    switch (log.relation) {
      case TimeLogRelation.scheduled:
        scheduledLogs[taskId] = (scheduledLogs[taskId] ?? 0) + log.minutes;
      case TimeLogRelation.extra:
        extra += log.minutes;
      case TimeLogRelation.adHoc:
        adHoc += log.minutes;
      case TimeLogRelation.legacyUnknown:
        final block = log.blockId == null ? null : blockById[log.blockId];
        if (block != null && block.taskId == taskId) {
          scheduledLogs[taskId] = (scheduledLogs[taskId] ?? 0) + log.minutes;
        } else {
          legacyByTask.putIfAbsent(taskId, () => []).add(log);
        }
    }
  }
  final scheduledByTask = <String, int>{};
  final taskIds = {
    ...plannedByTask.keys,
    ...scheduledLogs.keys,
    ...legacyByTask.keys,
  };
  for (final taskId in taskIds) {
    final planned = math.max(0, plannedByTask[taskId] ?? 0);
    final explicit = scheduledLogs[taskId] ?? 0;
    var covered = math.min(planned, explicit);
    final pending = legacyByTask[taskId] ?? const <TimeLog>[];
    final legacyTotal = pending.fold<int>(0, (sum, log) => sum + log.minutes);
    var inferredTotal = 0;
    var remaining = math.max(0, planned - covered);
    if (remaining > 0 && pending.isNotEmpty) {
      final sorted = [...pending]
        ..sort((a, b) {
          final byStart = a.startedAt.compareTo(b.startedAt);
          return byStart != 0 ? byStart : a.id.compareTo(b.id);
        });
      for (final log in sorted) {
        final inferred = math.min(remaining, log.minutes);
        inferredTotal += inferred;
        remaining -= inferred;
        if (remaining <= 0) break;
      }
    }
    covered += inferredTotal;
    if (covered > 0) scheduledByTask[taskId] = covered;
    // Explicit scheduled minutes that exceed the plan still count as actual time
    // (once) but can never raise original-plan achievement above 100%.
    legacyUnknown += math.max(0, explicit - math.min(planned, explicit));
    // Legacy minutes that could not be attributed stay actual but unknown.
    legacyUnknown += math.max(0, legacyTotal - inferredTotal);
  }
  return DayExecutionSummary(
    planned: plannedByTask.values.fold<int>(0, (sum, value) => sum + value),
    scheduledByTask: scheduledByTask,
    extra: extra,
    adHoc: adHoc,
    legacyUnknown: legacyUnknown,
  );
}

/// Capped scheduled achievement (scheduled + limited legacy inference) per task.
Map<String, int> scheduledMinutesByTask(PlannerData data, String date) =>
    dayExecutionSummary(data, date).scheduledByTask;

/// Original-plan achievement for one task and day, capped by its planned minutes.
int scheduledMinutesForTaskDay(PlannerData data, String taskId, String date) {
  final planned = taskDayPlannedMinutes(data, taskId, date);
  if (planned <= 0) return 0;
  return math.min(planned, scheduledMinutesByTask(data, date)[taskId] ?? 0);
}

/// Minutes of active extra study recorded for one task and day.
int extraMinutesForTaskDay(PlannerData data, String taskId, String date) => data
    .logs
    .where(
      (log) =>
          log.taskId == taskId &&
          log.date == date &&
          log.relation == TimeLogRelation.extra,
    )
    .fold<int>(0, (sum, log) => sum + log.minutes);

/// Minutes of temporary (task-less) learning recorded on one day.
int adHocMinutesOnDate(PlannerData data, String date) => data.logs
    .where((log) => log.date == date && log.relation == TimeLogRelation.adHoc)
    .fold<int>(0, (sum, log) => sum + log.minutes);

/// Minutes recorded for one temporary learning entity on one day.
int adHocMinutesForEntity(PlannerData data, String adHocId, String date) => data
    .logs
    .where(
      (log) => log.adHocId == adHocId && log.date == date && log.minutes > 0,
    )
    .fold<int>(0, (sum, log) => sum + log.minutes);

DayStats dayStats(PlannerData data, String date) {
  final summary = dayExecutionSummary(data, date);
  final planned = summary.planned;
  final actual = summary.actual;
  return DayStats(
    planned: planned,
    actual: actual,
    remaining: math.max(0, planned - summary.scheduled),
    excess: math.max(0, actual - planned),
    rate: planned != 0 ? jsRound(actual / planned * 100) : 0,
    scheduled: summary.scheduled,
    extra: summary.extra,
    adHoc: summary.adHoc,
    legacyUnknown: summary.legacyUnknown,
  );
}

/// Capacity accounting of one day that never bills an executed minute twice.
///
/// The acceptance example (net capacity 120; maths planned 60 with 30 learned;
/// 20 minutes of temporary photography learning) must produce actual 50,
/// reserved 30 and available 40 — never `120 - 60 - 30 - 20`.
class DayCapacityBreakdown {
  const DayCapacityBreakdown({
    required this.date,
    required this.capacity,
    required this.planned,
    required this.actual,
    required this.scheduled,
    required this.extra,
    required this.adHoc,
    required this.legacyUnknown,
    required this.reserved,
    required this.available,
    required this.over,
  });

  final String date;

  /// Effective study capacity for the day (never below zero).
  final int capacity;
  final int planned;
  final int actual;
  final int scheduled;
  final int extra;
  final int adHoc;
  final int legacyUnknown;

  /// Effective reservation of unfinished original-plan blocks.
  final int reserved;
  final int available;
  final int over;
}

/// Effective capacity of one day from the configured learning budget.
int effectiveDayCapacity(PlannerData data, String date) =>
    scheduler.availableDailyMinutes(data.profile, data.fixedEvents, date);

DayCapacityBreakdown dayCapacityBreakdown(
  PlannerData data,
  String date, {
  int? capacity,
}) {
  final summary = dayExecutionSummary(data, date);
  final effective = capacity ?? effectiveDayCapacity(data, date);
  final blocks = data.blocks.where((block) => block.date == date).toList()
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  var reserved = 0;
  final remainingCovered = Map<String, int>.from(summary.scheduledByTask);
  for (final block in blocks) {
    var covered = remainingCovered[block.taskId] ?? 0;
    final used = math.min(covered, block.durationMinutes);
    covered -= used;
    remainingCovered[block.taskId] = covered;
    final done =
        block.status == BlockStatus.completed ||
        block.completionStatus == CompletionStatus.completed;
    if (!done) {
      reserved += math.max(0, block.durationMinutes - used);
    }
  }
  final actual = summary.actual;
  return DayCapacityBreakdown(
    date: date,
    capacity: effective,
    planned: summary.planned,
    actual: actual,
    scheduled: summary.scheduled,
    extra: summary.extra,
    adHoc: summary.adHoc,
    legacyUnknown: summary.legacyUnknown,
    reserved: reserved,
    available: math.max(0, effective - actual - reserved),
    over: math.max(0, actual - effective),
  );
}

/// Minutes actually recorded for one temporary learning entity, all days.
int adHocTotalMinutes(PlannerData data, String adHocId) => data.logs
    .where((log) => log.adHocId == adHocId && log.minutes > 0)
    .fold<int>(0, (sum, log) => sum + log.minutes);

/// One temporary learning entity with its recorded minutes.
class AdHocLearningEntry {
  const AdHocLearningEntry({
    required this.learning,
    required this.todayMinutes,
    required this.totalMinutes,
    required this.byDate,
    required this.lastDate,
  });

  final AdHocLearning learning;
  final int todayMinutes;
  final int totalMinutes;

  /// Recorded minutes per Shanghai date (only days with records).
  final Map<String, int> byDate;
  final String lastDate;
}

/// Temporary learning entities that have real records, newest activity first.
///
/// [includeIds] adds entities with no minute-level log yet (for example a
/// temporary-learning timer that just started) so the live row is not missing
/// until the first whole minute is flushed.
List<AdHocLearningEntry> adHocLearningEntries(
  PlannerData data, {
  String? date,
  Set<String> includeIds = const {},
}) {
  final learningById = {
    for (final learning in data.adHocLearnings) learning.id: learning,
  };
  final byEntity = <String, Map<String, int>>{};
  for (final log in data.logs) {
    final adHocId = log.adHocId;
    if (adHocId == null || log.minutes <= 0) continue;
    if (!learningById.containsKey(adHocId)) continue;
    final days = byEntity.putIfAbsent(adHocId, () => {});
    days[log.date] = (days[log.date] ?? 0) + log.minutes;
  }
  final entries = <AdHocLearningEntry>[];
  final ids = {...byEntity.keys, ...includeIds};
  for (final adHocId in ids) {
    final learning = learningById[adHocId];
    if (learning == null) continue;
    final days = byEntity[adHocId] ?? const <String, int>{};
    final sortedDates = days.keys.toList()..sort();
    entries.add(
      AdHocLearningEntry(
        learning: learning,
        todayMinutes: date == null ? 0 : (days[date] ?? 0),
        totalMinutes: days.values.fold<int>(0, (sum, value) => sum + value),
        byDate: days,
        lastDate: sortedDates.isEmpty ? (date ?? '') : sortedDates.last,
      ),
    );
  }
  entries.sort((a, b) {
    final byDate = b.lastDate.compareTo(a.lastDate);
    return byDate != 0 ? byDate : a.learning.title.compareTo(b.learning.title);
  });
  return entries;
}

/// Outcome of creating or reusing a temporary learning entity.
class AdHocUpsert {
  const AdHocUpsert(this.data, this.learning, {required this.created});
  final PlannerData data;
  final AdHocLearning learning;
  final bool created;
}

/// Creates a temporary learning entity, or reuses the exact-title non-archived
/// one so starting the same ad-hoc content twice never duplicates entities.
///
/// Only the name is required; no budget, deadline, priority or schedule is
/// fabricated. [subjectId] is accepted only for old callers and is ignored.
AdHocUpsert upsertAdHocLearning(
  PlannerData data, {
  required String title,
  String? subjectId,
  required String id,
  required String updatedAt,
}) {
  final trimmed = title.trim();
  if (trimmed.isEmpty) throw StateError('请填写临时学习名称');
  if (trimmed.length > 150) throw StateError('临时学习名称不能超过 150 个字符');
  final existing = data.adHocLearnings
      .where((learning) => !learning.archived && learning.title == trimmed)
      .firstOrNull;
  if (existing != null) {
    return AdHocUpsert(data, existing, created: false);
  }
  final learning = AdHocLearning(
    id: id,
    userId: data.profile.userId,
    title: trimmed,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
  return AdHocUpsert(
    data.copyWith(adHocLearnings: [...data.adHocLearnings, learning]),
    learning,
    created: true,
  );
}

/// Result of turning temporary learning into a formal task or linking it to an
/// existing item. [taskId] is the resulting owner of the original records.
class AdHocConvertResult {
  const AdHocConvertResult(this.data, this.taskId);
  final PlannerData data;
  final String taskId;
}

/// Converts temporary learning into a new formal task.
///
/// The original logs and their session ids keep their minutes, timestamps and
/// history relation (`ad_hoc`); only the owner task id and the archived
/// conversion pointer change, so no minute is duplicated. A repeated call with
/// the same archived entity is a no-op.
AdHocConvertResult convertAdHocToTask(
  PlannerData data,
  String adHocId,
  TaskDraft draft, {
  required String taskId,
  String? updatedAt,
}) {
  final learning = data.adHocLearnings
      .where((item) => item.id == adHocId)
      .firstOrNull;
  if (learning == null) throw StateError('临时学习已不存在，请刷新后重试');
  if (learning.archived) {
    final converted = learning.convertedTaskId;
    if (converted != null && data.tasks.any((task) => task.id == converted)) {
      return AdHocConvertResult(data, converted);
    }
    throw StateError('该临时学习已归档');
  }
  final stamp = updatedAt ?? nowIso();
  final applied = applyTaskDraft(data, draft, taskId: taskId, updatedAt: stamp);
  return AdHocConvertResult(
    _adoptAdHocOwner(applied, learning, taskId, stamp),
    taskId,
  );
}

/// Links temporary learning records to an existing task.
///
/// The logs keep their temporary relation (`ad_hoc`) and `ad_hoc_id` for an
/// explainable history while their task attribution updates course/item stats.
/// A repeated call with the same target task is a no-op.
AdHocConvertResult linkAdHocToTask(
  PlannerData data,
  String adHocId,
  String taskId, {
  String? updatedAt,
}) {
  final learning = data.adHocLearnings
      .where((item) => item.id == adHocId)
      .firstOrNull;
  if (learning == null) throw StateError('临时学习已不存在，请刷新后重试');
  final task = data.tasks.where((item) => item.id == taskId).firstOrNull;
  if (task == null) throw StateError('所选事项不存在，请刷新后重试');
  if (task.isArchived) throw StateError('已归档事项不可关联学习记录');
  if (learning.archived) {
    if (learning.convertedTaskId == taskId) {
      return AdHocConvertResult(data, taskId);
    }
    throw StateError('该临时学习已转为其他事项或已归档');
  }
  final stamp = updatedAt ?? nowIso();
  return AdHocConvertResult(
    _adoptAdHocOwner(data, learning, taskId, stamp),
    taskId,
  );
}

PlannerData _adoptAdHocOwner(
  PlannerData data,
  AdHocLearning learning,
  String taskId,
  String updatedAt,
) => data.copyWith(
  logs: [
    for (final log in data.logs)
      log.adHocId == learning.id ? log.copyWith(taskId: taskId) : log,
  ],
  adHocLearnings: [
    for (final item in data.adHocLearnings)
      item.id == learning.id
          ? item.copyWith(
              archived: true,
              convertedTaskId: taskId,
              updatedAt: updatedAt,
            )
          : item,
  ],
);

/// Groups the blocks of one day per task and orders each group by start minute.
List<List<ScheduleBlock>> groupDailyBlocks(
  Iterable<ScheduleBlock> blocks,
  List<Task> tasks,
) {
  final ids = {for (final task in tasks) task.id: task};
  final groups = <String, List<ScheduleBlock>>{};
  final order = <String>[];
  for (final block in blocks) {
    if (!ids.containsKey(block.taskId)) continue;
    final key = '${block.taskId}:${block.date}';
    final group = groups[key];
    if (group == null) {
      groups[key] = [block];
      order.add(key);
    } else {
      group.add(block);
    }
  }
  return [
    for (final key in order)
      groups[key]!..sort((a, b) => a.startMinute.compareTo(b.startMinute)),
  ];
}

/// Actual minutes recorded for one task on one day.
int taskDayMinutes(PlannerData data, String taskId, String date) => data.logs
    .where((log) => log.taskId == taskId && log.date == date)
    .fold<int>(0, (sum, log) => sum + log.minutes);

/// Total actual minutes recorded for one task on every day.
int taskTotalMinutes(PlannerData data, String taskId) => data.logs
    .where((log) => log.taskId == taskId)
    .fold<int>(0, (sum, log) => sum + log.minutes);

int taskDayPlannedMinutes(PlannerData data, String taskId, String date) => data
    .blocks
    .where((block) => block.taskId == taskId && block.date == date)
    .fold<int>(0, (sum, block) => sum + block.durationMinutes);

/// Recomputes the time-only completion facts from the study log.
///
/// `completed_minutes = min(estimate, actual)`; reaching the estimate fills
/// `completed_at` (sticky). [correctedTaskIds] clears a completion marker when a
/// record is corrected, then re-derives it from the remaining actual minutes.
PlannerData refreshTaskProgress(
  PlannerData data, {
  List<String> correctedTaskIds = const [],
  String? updatedAt,
}) {
  final stamp = updatedAt ?? nowIso();
  final corrected = correctedTaskIds.toSet();
  final totals = actualMinutesByTask(data);
  return data.copyWith(
    tasks: [
      for (final task in data.tasks)
        () {
          final isCorrected = corrected.contains(task.id);
          final actual = totals[task.id] ?? 0;
          final archived = task.isArchived;
          final reachedBudget =
              task.estimatedMinutes > 0 && actual >= task.estimatedMinutes;
          final completedAt = archived
              ? task.completedAt
              : isCorrected
              ? (reachedBudget ? stamp : null)
              : (task.completedAt ?? (reachedBudget ? stamp : null));
          return task.copyWith(
            completedMinutes: math.min(task.estimatedMinutes, actual),
            completedAt: completedAt,
            updatedAt: stamp,
          );
        }(),
    ],
  );
}

/// Tasks that still owe minutes inside the planning horizon.
bool taskIsPlannedOn(PlannerData data, String taskId, String date) =>
    data.blocks.any((block) => block.taskId == taskId && block.date == date);

/// The remaining minutes of one task that still need a day and a time block.
int unscheduledTaskMinutes(
  PlannerData data,
  Task task, {
  required String from,
}) {
  if (task.isArchived) return 0;
  final planned = data.blocks
      .where(
        (block) =>
            block.taskId == task.id &&
            block.status == BlockStatus.planned &&
            block.date.compareTo(from) >= 0,
      )
      .fold<int>(
        0,
        (sum, block) =>
            sum + math.max(0, block.durationMinutes - block.actualMinutes),
      );
  return math.max(0, task.estimatedMinutes - task.completedMinutes - planned);
}

/// Splits a requested amount into 30 minute chunks with the remainder last.
List<int> splitIntoGranules(int minutes) {
  if (minutes <= 0) return const [];
  final chunks = <int>[];
  for (var left = minutes; left > 0; left -= 30) {
    chunks.add(math.min(30, left));
  }
  return chunks;
}

/// Result of moving one task's blocks to another day.
class MoveResult {
  const MoveResult.success(this.blocks) : error = null;
  const MoveResult.failure(this.error) : blocks = const [];
  final List<ScheduleBlock> blocks;
  final String? error;
  bool get ok => error == null;
}

/// Moves a whole task day described by [blocks] to [targetDate].
///
/// Only the stable ids of [blocks] are used: the current records are resolved
/// from [data] so a stale dialog snapshot can never overwrite newer state. New
/// code should call [moveTaskDayByIds] with the ids and the expected source date.
MoveResult moveTaskDay(
  PlannerData data,
  List<ScheduleBlock> blocks,
  String targetDate, {
  String? updatedAt,
}) => moveTaskDayByIds(
  data,
  [for (final block in blocks) block.id],
  targetDate,
  expectedSourceDate: blocks.isEmpty ? null : blocks.first.date,
  updatedAt: updatedAt,
);

/// Moves the records with [blockIds] to [targetDate], matching the Web rules.
///
/// The current records are resolved from [data] by id; a snapshot passed by a
/// dialog is not authoritative. The move is refused when a record was deleted in
/// the meantime, when the source day changed since [expectedSourceDate], when the
/// source day already has recorded time, when any block is fixed or completed, or
/// when the target day rejects the placement. Unrelated blocks in [data], other
/// days and arrangements written by a concurrent sync are always kept because the
/// result is built from the current plan, never from the snapshot.
MoveResult moveTaskDayByIds(
  PlannerData data,
  Iterable<String> blockIds,
  String targetDate, {
  String? expectedSourceDate,
  String? updatedAt,
}) {
  final ids = {...blockIds};
  if (ids.isEmpty) return MoveResult.success(data.blocks);
  final current = [
    for (final block in data.blocks)
      if (ids.contains(block.id)) block,
  ];
  if (current.length != ids.length) {
    return const MoveResult.failure('部分安排已不存在，请刷新后重试');
  }
  final sourceDate = expectedSourceDate ?? current.first.date;
  if (current.any((block) => block.date != sourceDate)) {
    return const MoveResult.failure('安排已变化，请重新打开移动窗口');
  }
  final stamp = updatedAt ?? nowIso();
  final task = data.tasks
      .where((item) => item.id == current.first.taskId)
      .firstOrNull;
  if (task?.isArchived ?? false) {
    return const MoveResult.failure('已归档事项不可安排');
  }
  if (task != null && taskDayMinutes(data, task.id, sourceDate) > 0) {
    return const MoveResult.failure('已记录用时的事项保留在学习当天；请为剩余事项另行安排日期');
  }
  final taskById = {for (final item in data.tasks) item.id: item};
  if (current.any(
    (block) =>
        block.isFixed ||
        block.status == BlockStatus.completed ||
        taskById[block.taskId]?.isFixed == true,
  )) {
    return const MoveResult.failure('固定或已完成的事项不可移动');
  }
  final remaining = data.blocks
      .where((block) => !ids.contains(block.id))
      .toList();
  final placed = <ScheduleBlock>[];
  final sorted = [...current]
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  for (final block in sorted) {
    if (data.profile.planningMode != PlanningMode.timed) {
      final candidate = block.copyWith(
        date: targetDate,
        startMinute: 0,
        updatedAt: stamp,
      );
      final error = scheduler.validateBlockPlacement(
        data.copyWith(blocks: [...remaining, ...placed]),
        candidate,
      );
      if (error != null) return MoveResult.failure(error);
      placed.add(candidate);
      continue;
    }
    ScheduleBlock? found;
    final quantum = data.profile.granularityMinutes;
    final aligned =
        ((data.profile.studyStartMinute + quantum - 1) ~/ quantum) * quantum;
    for (
      var start = aligned;
      start + block.durationMinutes <= data.profile.studyEndMinute;
      start += quantum
    ) {
      final candidate = block.copyWith(
        date: targetDate,
        startMinute: start,
        updatedAt: stamp,
      );
      if (scheduler.validateBlockPlacement(
            data.copyWith(blocks: [...remaining, ...placed]),
            candidate,
          ) ==
          null) {
        found = candidate;
        break;
      }
    }
    if (found == null) {
      return const MoveResult.failure('目标日期容量不足，请选择其他日期');
    }
    placed.add(found);
  }
  return MoveResult.success([...remaining, ...placed]);
}

/// Marks a task complete early: records the reported minutes, keeps history, drops
/// future planned blocks and completes the remaining ones. In the time-only model
/// an explicit completion is stored as [Task.completedAt]; exhausting the time
/// budget completes a task automatically without this call.
PlannerData completeTask(
  PlannerData data,
  String taskId, {
  required String date,
  required int actualMinutes,
  String? updatedAt,
}) {
  final stamp = updatedAt ?? nowIso();
  if (data.tasks.any(
    (task) => task.id == taskId && task.isArchived,
  )) {
    throw StateError('已归档事项不能标记完成');
  }
  var next = data;
  if (actualMinutes > 0) {
    next = scheduler.recordTaskDayMinutes(next, taskId, date, actualMinutes);
  }
  final kept = [
    for (final block in next.blocks)
      if (block.taskId != taskId ||
          block.date.compareTo(date) <= 0 ||
          block.isFixed ||
          block.status == BlockStatus.completed)
        block.taskId == taskId
            ? block.copyWith(status: BlockStatus.completed, updatedAt: stamp)
            : block,
  ];
  final refreshed = refreshTaskProgress(
    next.copyWith(blocks: kept),
    updatedAt: stamp,
  );
  return refreshed.copyWith(
    tasks: [
      for (final task in refreshed.tasks)
        task.id == taskId
            ? task.copyWith(
                completedAt: task.completedAt ?? stamp,
                updatedAt: stamp,
              )
            : task,
    ],
  );
}

/// Deletes a task together with its daily plan and study records.
///
/// Deletion is refused when another item declares this task as a prerequisite:
/// silently dropping that dependency would unlock the dependent item without the
/// user deciding, so the user must remove the relation first. Learning-route
/// stages that reference the task are updated consistently; a stage left without
/// items is removed instead of leaving meaningless metadata behind. Plan quality
/// assessments and confirmation results are invalidated (never replaced with a
/// fabricated pass) because the plan changed. Legacy items without planning
/// metadata keep the original delete behavior.
PlannerData deleteTask(PlannerData data, String taskId) {
  final task = data.tasks.where((item) => item.id == taskId).firstOrNull;
  if (task == null) throw StateError('事项已不存在，请刷新后重试');
  final dependents = [
    for (final item in data.tasks)
      if (item.id != taskId &&
          (item.planning?['dependencies'] as List? ?? const []).any(
            (dependency) =>
                dependency is Map && dependency['task_id'] == taskId,
          ))
        item.title,
  ];
  if (dependents.isNotEmpty) {
    final names = dependents.take(3).map((title) => '「$title」').join('、');
    final suffix = dependents.length > 3 ? ' 等 ${dependents.length} 个事项' : '';
    throw StateError('「${task.title}」是$names$suffix的前置事项，请先解除前置依赖后再删除');
  }
  final planning = data.planning;
  JsonMap? nextPlanning = planning;
  if (planning != null) {
    final route = planning['route'];
    final stages = <dynamic>[];
    var routeChanged = false;
    if (route is List) {
      for (final stage in route) {
        if (stage is Map) {
          final itemIds = stage['item_ids'];
          if (itemIds is List && itemIds.contains(taskId)) {
            routeChanged = true;
            final kept = [
              for (final item in itemIds)
                if (item != taskId) item,
            ];
            if (kept.isEmpty) continue;
            stages.add({...Map<String, dynamic>.from(stage), 'item_ids': kept});
            continue;
          }
        }
        stages.add(stage);
      }
    }
    nextPlanning = {
      ...planning,
      if (routeChanged) 'route': stages,
      'needs_review': true,
      'quality': null,
      'forecast': null,
    };
  }
  return data.copyWith(
    tasks: data.tasks.where((item) => item.id != taskId).toList(),
    blocks: data.blocks.where((block) => block.taskId != taskId).toList(),
    logs: data.logs.where((log) => log.taskId != taskId).toList(),
    // A temporary learning converted into this deleted task keeps its history
    // (archived) but must not keep a dangling conversion pointer.
    adHocLearnings: [
      for (final learning in data.adHocLearnings)
        learning.convertedTaskId == taskId
            ? learning.copyWith(convertedTaskId: null)
            : learning,
    ],
    planning: nextPlanning,
  );
}

/// One day of the calendar with its learning plan and capacity information.
class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.planned,
    required this.actual,
    required this.fixedMinutes,
    required this.capacity,
    required this.capacityWarning,
  });

  final String date;
  final int planned;
  final int actual;
  final int fixedMinutes;
  final int capacity;
  final String? capacityWarning;
}

CalendarDay calendarDay(PlannerData data, String date) {
  final stats = dayStats(data, date);
  final capacity = scheduler.dailyStudyBudget(data.profile, date);
  final String? warning;
  if (stats.planned > capacity) {
    warning = '已安排 ${duration(stats.planned)}，超出当天可用 ${duration(capacity)}';
  } else {
    warning = null;
  }
  return CalendarDay(
    date: date,
    planned: stats.planned,
    actual: stats.actual,
    fixedMinutes: 0,
    capacity: capacity,
    capacityWarning: warning,
  );
}

/// Compatibility helper for imported plans; fixed events are no longer displayed.
List<FixedEvent> fixedEventsOn(PlannerData data, String date) => const [];
