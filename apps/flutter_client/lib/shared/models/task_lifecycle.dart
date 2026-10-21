import 'dart:math' as math;

import 'planner_models.dart';

/// Time-only progress model for tasks (items).
///
/// The canonical progress source is time: [Task.estimatedMinutes] is the budget
/// and actual study minutes come from [PlannerData.logs] (uncapped). Completion
/// is [Task.completedAt]; `archived` is an independent lifecycle flag.
class TaskTimeProgress {
  const TaskTimeProgress({
    required this.task,
    required this.actualMinutes,
    required this.archived,
    required this.completed,
    required this.ratio,
  });

  final Task task;

  /// Uncapped study minutes: log sum, or legacy `completedMinutes` when the task
  /// has no logs at all (imported/legacy data).
  final int actualMinutes;
  final bool archived;
  final bool completed;

  /// `actual / estimated`; null when the estimate is not positive.
  final double? ratio;

  bool get started => completed || actualMinutes > 0;

  /// Completion rate in percent, e.g. `62` or `120`.
  int? get percent => ratio == null ? null : (ratio! * 100).round();

  /// Compact label for rows: `未开始` / `进行中` / `45%` / `完成` / `120%` / `已归档`.
  String get shortLabel {
    if (archived) return '已归档';
    if (completed) return percent != null && percent! > 100 ? '$percent%' : '完成';
    if (percent == null) return '未开始';
    if (percent! <= 0) return actualMinutes > 0 ? '进行中' : '未开始';
    return '$percent%';
  }

  /// Descriptive label including over-budget wording.
  String get statusLabel {
    if (archived) return '已归档';
    if (completed) {
      return percent != null && percent! > 100 ? '完成 · 超额 ${percent! - 100}%' : '完成';
    }
    if (started) {
      return percent == null || percent! <= 0 ? '进行中' : '进行中 $percent%';
    }
    return '未开始';
  }
}

/// Sum of study-log minutes per task. Uncapped and independent of estimates.
Map<String, int> actualMinutesByTask(PlannerData data) =>
    loggedMinutesByTask(data.logs);

Map<String, int> loggedMinutesByTask(Iterable<TimeLog> logs) {
  final totals = <String, int>{};
  for (final log in logs) {
    final taskId = log.taskId;
    if (taskId == null) continue;
    totals[taskId] = (totals[taskId] ?? 0) + math.max(0, log.minutes);
  }
  return totals;
}

int taskActualMinutes(PlannerData data, Task task, {Map<String, int>? byTask}) {
  final totals = byTask ?? actualMinutesByTask(data);
  return totals[task.id] ?? task.completedMinutes;
}

/// `actual / estimated`, uncapped. Null when the estimate is not positive.
double? timeProgressRatio(Task task, int actualMinutes) {
  if (task.estimatedMinutes <= 0) return null;
  return actualMinutes / task.estimatedMinutes;
}

/// Time-only completion: explicit [Task.completedAt] or the estimate being
/// exhausted. Archived tasks are never "completed".
bool taskCompletedByTime(Task task, int actualMinutes) {
  if (task.isArchived) return false;
  return task.completedAt != null ||
      (task.estimatedMinutes > 0 && actualMinutes >= task.estimatedMinutes);
}

TaskTimeProgress taskTimeProgress(
  PlannerData data,
  Task task, {
  Map<String, int>? byTask,
}) {
  final actual = taskActualMinutes(data, task, byTask: byTask);
  final archived = task.isArchived;
  return TaskTimeProgress(
    task: task,
    actualMinutes: actual,
    archived: archived,
    completed: !archived && taskCompletedByTime(task, actual),
    ratio: timeProgressRatio(task, actual),
  );
}

bool taskIsCompleted(PlannerData data, Task task, {Map<String, int>? byTask}) =>
    taskTimeProgress(data, task, byTask: byTask).completed;

bool taskIsArchived(Task task) => task.isArchived;

/// Lifecycle flags used across the app; the model now stores these facts
/// directly ([Task.archived] / [Task.completedAt]).
extension TaskLifecycleFlags on Task {
  bool get isArchived => archived;
  bool get isCompleted => completedAt != null;
}

String _stampNow() => DateTime.now().toUtc().toIso8601String();

/// Normalizes every task to the time-only lifecycle:
///
/// - fills `completedAt` when the estimate is exhausted (sticky completion);
/// - derives `completedMinutes = min(estimate, actual)`.
///
/// Returns [data] unchanged when nothing needs updating.
PlannerData normalizeTaskLifecycle(PlannerData data, {String? now}) {
  final totals = actualMinutesByTask(data);
  final stamp = now ?? _stampNow();
  var changed = false;
  final tasks = [
    for (final task in data.tasks)
      _normalizeTask(task, totals[task.id], stamp, () => changed = true),
  ];
  return changed ? data.copyWith(tasks: tasks) : data;
}

/// Same normalization for scheduler entry points that receive tasks/logs without a
/// full [PlannerData] (golden contract fixtures, manual placement validation).
List<Task> normalizeTaskRows(
  Iterable<Task> tasks,
  Map<String, int> actualByTask, {
  String? now,
}) {
  final stamp = now ?? _stampNow();
  return [
    for (final task in tasks)
      _normalizeTask(task, actualByTask[task.id], stamp, () {}),
  ];
}

Task _normalizeTask(
  Task task,
  int? loggedMinutes,
  String stamp,
  void Function() markChanged,
) {
  // Legacy imports may only have completed_minutes without logs; keep that
  // historical value so progress does not silently drop to zero.
  final actual = loggedMinutes ?? task.completedMinutes;
  final archived = task.isArchived;
  final completed = !archived && taskCompletedByTime(task, actual);
  final completedAt = task.completedAt ??
      (completed
          ? (task.updatedAt.isNotEmpty ? task.updatedAt : stamp)
          : null);
  final completedMinutes = math.min(task.estimatedMinutes, actual);
  if (task.completedAt == completedAt &&
      task.completedMinutes == completedMinutes) {
    return task;
  }
  markChanged();
  return task.copyWith(
    completedAt: completedAt,
    completedMinutes: completedMinutes,
  );
}
