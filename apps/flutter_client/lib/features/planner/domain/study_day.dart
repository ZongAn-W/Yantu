import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';
import 'planner_format.dart';
import 'scheduler/planner_scheduler.dart' as scheduler;

/// Plan and actual minutes for one calendar day, matching the Web `dayStats`.
class DayStats {
  const DayStats({
    required this.planned,
    required this.actual,
    required this.remaining,
    required this.excess,
    required this.rate,
  });

  final int planned;
  final int actual;
  final int remaining;
  final int excess;
  final int rate;
}

DayStats dayStats(PlannerData data, String date) {
  final planned = data.blocks
      .where((block) => block.date == date)
      .fold<int>(0, (sum, block) => sum + block.durationMinutes);
  final actual = data.logs
      .where((log) => log.date == date)
      .fold<int>(0, (sum, log) => sum + log.minutes);
  return DayStats(
    planned: planned,
    actual: actual,
    remaining: math.max(0, planned - actual),
    excess: math.max(0, actual - planned),
    rate: planned != 0 ? jsRound(actual / planned * 100) : 0,
  );
}

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

class TaskDayReview {
  const TaskDayReview({
    required this.taskId,
    required this.actualMinutes,
    required this.completionStatus,
    required this.feedback,
  });
  final String taskId;
  final int actualMinutes;
  final CompletionStatus completionStatus;
  final String feedback;

  TaskDayReview copyWith({
    int? actualMinutes,
    CompletionStatus? completionStatus,
    String? feedback,
  }) => TaskDayReview(
    taskId: taskId,
    actualMinutes: actualMinutes ?? this.actualMinutes,
    completionStatus: completionStatus ?? this.completionStatus,
    feedback: feedback ?? this.feedback,
  );
}

List<TaskDayReview> dailyReviewEntries(PlannerData data, String date) => [
  for (final group in groupDailyBlocks(
    data.blocks.where((block) => block.date == date),
    data.tasks,
  ))
    TaskDayReview(
      taskId: group.first.taskId,
      actualMinutes: taskDayMinutes(data, group.first.taskId, date),
      completionStatus: () {
        final statuses = group
            .map(
              (block) =>
                  block.completionStatus ??
                  (block.status == BlockStatus.completed
                      ? CompletionStatus.completed
                      : CompletionStatus.notStarted),
            )
            .toSet();
        if (statuses.length == 1) return statuses.single;
        return statuses.contains(CompletionStatus.partial) ||
                statuses.contains(CompletionStatus.completed)
            ? CompletionStatus.partial
            : CompletionStatus.notStarted;
      }(),
      feedback: group
          .map((block) => block.feedback ?? '')
          .where((text) => text.isNotEmpty)
          .toSet()
          .join('\n'),
    ),
];

PlannerData applyDailyReview(
  PlannerData data,
  String date, {
  required List<TaskDayReview> original,
  required List<TaskDayReview> edited,
  required String originalFeedback,
  required String feedback,
}) {
  final before = {for (final entry in original) entry.taskId: entry};
  if (edited.map((entry) => entry.taskId).toSet().length != edited.length) {
    throw StateError('今日记录包含重复事项');
  }
  for (final entry in edited) {
    if (before[entry.taskId] == null ||
        !data.tasks.any((task) => task.id == entry.taskId) ||
        !taskIsPlannedOn(data, entry.taskId, date)) {
      throw StateError('今日安排已变化，请重新打开记录');
    }
    if (entry.actualMinutes < 0 || entry.actualMinutes > 1440) {
      throw StateError('请输入 0 至 1440 的整数分钟');
    }
  }
  var next = data;
  final stamp = nowIso();
  for (final entry in edited) {
    final old = before[entry.taskId]!;
    if (entry.actualMinutes != old.actualMinutes) {
      next = scheduler.recordTaskDayMinutes(
        next,
        entry.taskId,
        date,
        entry.actualMinutes,
      );
    }
    final statusChanged = entry.completionStatus != old.completionStatus;
    final feedbackChanged = entry.feedback != old.feedback;
    if (!statusChanged && !feedbackChanged) continue;
    next = next.copyWith(
      blocks: [
        for (final block in next.blocks)
          if (block.taskId == entry.taskId && block.date == date)
            block.copyWith(
              status: statusChanged
                  ? (entry.completionStatus == CompletionStatus.completed
                        ? BlockStatus.completed
                        : BlockStatus.planned)
                  : block.status,
              completionStatus: statusChanged
                  ? entry.completionStatus
                  : block.completionStatus,
              feedback: feedbackChanged ? entry.feedback : block.feedback,
              updatedAt: stamp,
            )
          else
            block,
      ],
    );
  }
  if (feedback != originalFeedback) {
    next = next.copyWith(
      dailyFeedback: {...?next.dailyFeedback, date: feedback},
    );
  }
  return next;
}

int taskDayPlannedMinutes(PlannerData data, String taskId, String date) => data
    .blocks
    .where((block) => block.taskId == taskId && block.date == date)
    .fold<int>(0, (sum, block) => sum + block.durationMinutes);

/// Recomputes `completed_minutes` from the study log, mirroring `refreshTaskProgress`.
///
/// A task that the user marked completed stays completed unless its id is listed in
/// [correctedTaskIds]; otherwise a task with progress becomes in progress and one
/// that lost all progress falls back to not started.
PlannerData refreshTaskProgress(
  PlannerData data, {
  List<String> correctedTaskIds = const [],
  String? updatedAt,
}) {
  final stamp = updatedAt ?? nowIso();
  return data.copyWith(
    tasks: [
      for (final task in data.tasks)
        () {
          final actual = taskTotalMinutes(data, task.id);
          final completed = math.min(task.estimatedMinutes, actual);
          final TaskStatus status;
          if (task.status == TaskStatus.archived) {
            status = TaskStatus.archived;
          } else if (task.status == TaskStatus.completed &&
              !correctedTaskIds.contains(task.id)) {
            status = TaskStatus.completed;
          } else if (completed > 0) {
            status = TaskStatus.inProgress;
          } else if (task.status == TaskStatus.completed) {
            status = TaskStatus.notStarted;
          } else {
            status = task.status;
          }
          return task.copyWith(
            completedMinutes: completed,
            status: status,
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
  if (task.status == TaskStatus.archived) return 0;
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

/// Moves a whole task day to [targetDate], matching the Web `moveTaskDay` rules.
///
/// The move is refused when the source day already has recorded time, when any
/// block is fixed or completed, or when the target day rejects the placement.
MoveResult moveTaskDay(
  PlannerData data,
  List<ScheduleBlock> blocks,
  String targetDate, {
  String? updatedAt,
}) {
  if (blocks.isEmpty) return MoveResult.success(data.blocks);
  final stamp = updatedAt ?? nowIso();
  final task = data.tasks
      .where((item) => item.id == blocks.first.taskId)
      .firstOrNull;
  if (task?.status == TaskStatus.archived) {
    return const MoveResult.failure('已归档事项不可安排');
  }
  if (task != null && taskDayMinutes(data, task.id, blocks.first.date) > 0) {
    return const MoveResult.failure('已记录用时的事项保留在学习当天；请为剩余事项另行安排日期');
  }
  final taskById = {for (final item in data.tasks) item.id: item};
  if (blocks.any(
    (block) =>
        block.isFixed ||
        block.status == BlockStatus.completed ||
        taskById[block.taskId]?.isFixed == true,
  )) {
    return const MoveResult.failure('固定或已完成的事项不可移动');
  }
  final moving = {for (final block in blocks) block.id};
  final remaining = data.blocks
      .where((block) => !moving.contains(block.id))
      .toList();
  final placed = <ScheduleBlock>[];
  final sorted = [...blocks]
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

/// Marks every block of one task day completed/planned, matching the dashboard check box.
PlannerData setTaskDayCompletion(
  PlannerData data,
  Iterable<ScheduleBlock> blocks,
  bool completed, {
  String? updatedAt,
}) {
  final stamp = updatedAt ?? nowIso();
  final ids = {for (final block in blocks) block.id};
  return data.copyWith(
    blocks: [
      for (final block in data.blocks)
        ids.contains(block.id)
            ? block.copyWith(
                status: completed ? BlockStatus.completed : BlockStatus.planned,
                updatedAt: stamp,
              )
            : block,
    ],
  );
}

/// Marks a task complete: records the reported minutes, keeps history, drops future
/// planned blocks and completes the remaining ones.
PlannerData completeTask(
  PlannerData data,
  String taskId, {
  required String date,
  required int actualMinutes,
  String? updatedAt,
}) {
  final stamp = updatedAt ?? nowIso();
  if (data.tasks.any(
    (task) => task.id == taskId && task.status == TaskStatus.archived,
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
    correctedTaskIds: [taskId],
    updatedAt: stamp,
  );
  return refreshed.copyWith(
    tasks: [
      for (final task in refreshed.tasks)
        task.id == taskId
            ? task.copyWith(status: TaskStatus.completed, updatedAt: stamp)
            : task,
    ],
  );
}

/// Deletes a task together with its daily plan and study records.
PlannerData deleteTask(PlannerData data, String taskId) => data.copyWith(
  tasks: data.tasks.where((task) => task.id != taskId).toList(),
  blocks: data.blocks.where((block) => block.taskId != taskId).toList(),
  logs: data.logs.where((log) => log.taskId != taskId).toList(),
);

/// One day of the calendar with its plan, fixed events and capacity information.
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
  final fixedMinutes = scheduler.fixedEventMinutesForDate(
    data.fixedEvents,
    date,
    includeRest: data.profile.planningMode != PlanningMode.timed,
  );
  final capacity = scheduler.availableDailyMinutes(
    data.profile,
    data.fixedEvents,
    date,
  );
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
    fixedMinutes: fixedMinutes,
    capacity: capacity,
    capacityWarning: warning,
  );
}

List<FixedEvent> fixedEventsOn(PlannerData data, String date) {
  final events = [
    for (final event in data.fixedEvents)
      if (scheduler.eventOccursOn(event, date)) event,
  ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));
  return events;
}
