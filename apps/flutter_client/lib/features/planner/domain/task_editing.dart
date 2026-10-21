import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';
import '../../../shared/models/task_lifecycle.dart';
import 'planner_format.dart';
import 'scheduler/planner_scheduler.dart' as scheduler;
import 'study_day.dart';

/// Editable task fields, shared by the create and edit forms.
class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.description,
    this.tagIds = const [],
    required this.estimatedMinutes,
    required this.priority,
    required this.deadline,
    required this.earliestDate,
    required this.isFixed,
    this.archived = false,
    this.deadlineKind = ItemDateKind.deadline,
  });

  final String title;
  final String description;
  final List<String> tagIds;
  final int estimatedMinutes;
  final int priority;
  final String deadline;
  final String earliestDate;
  final bool isFixed;
  /// 归档标记；新建默认 false，编辑保留原值。
  final bool archived;

  /// 截止日期是真实日期，还是仅表示本期安排边界。
  final ItemDateKind deadlineKind;

  TaskDraft copyWith({
    String? title,
    String? description,
    List<String>? tagIds,
    int? estimatedMinutes,
    int? priority,
    String? deadline,
    String? earliestDate,
    bool? isFixed,
    bool? archived,
    ItemDateKind? deadlineKind,
  }) => TaskDraft(
    title: title ?? this.title,
    description: description ?? this.description,
    tagIds: tagIds ?? this.tagIds,
    estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
    priority: priority ?? this.priority,
    deadline: deadline ?? this.deadline,
    earliestDate: earliestDate ?? this.earliestDate,
    isFixed: isFixed ?? this.isFixed,
    archived: archived ?? this.archived,
    deadlineKind: deadlineKind ?? this.deadlineKind,
  );

  static TaskDraft blank(PlannerData data, String today) => TaskDraft(
    title: '',
    description: '',
    tagIds: const [],
    estimatedMinutes: 120,
    priority: 3,
    deadline: today,
    earliestDate: today,
    isFixed: false,
  );

  static TaskDraft from(Task task) => TaskDraft(
    title: task.title,
    description: task.description ?? '',
    tagIds: task.tagIds,
    estimatedMinutes: task.estimatedMinutes,
    priority: task.priority,
    deadline: task.deadline,
    earliestDate: task.earliestDate ?? task.deadline,
    isFixed: task.isFixed,
    archived: task.archived,
    deadlineKind: task.deadlineKind,
  );
}

/// Field-level validation shared by the form and the domain command.
String? validateTaskDraft(TaskDraft draft, {int completedMinutes = 0}) {
  if (draft.title.trim().isEmpty) return '请填写事项名称';
  if (draft.deadline.compareTo(draft.earliestDate) < 0) {
    return '截止日期不能早于开始日期';
  }
  if (draft.estimatedMinutes < completedMinutes) {
    return '预计时长不能少于已完成时长';
  }
  if (draft.estimatedMinutes < 30) return '预计总时长至少 30 分钟';
  return null;
}

/// Creates or updates one task. Tags are optional labels and never affect scheduling.
PlannerData applyTaskDraft(
  PlannerData data,
  TaskDraft draft, {
  required String taskId,
  required String updatedAt,
}) {
  final title = draft.title.trim();
  final error = validateTaskDraft(
    draft,
    completedMinutes:
        data.tasks
            .where((task) => task.id == taskId)
            .firstOrNull
            ?.completedMinutes ??
        0,
  );
  if (error != null) throw StateError(error);
  final validTagIds = draft.tagIds
      .toSet()
      .intersection(data.tags.map((tag) => tag.id).toSet())
      .toList(growable: false);
  final existing = data.tasks.where((task) => task.id == taskId).firstOrNull;
  if (existing == null) {
    return data.copyWith(
      tasks: [
        ...data.tasks,
        Task(
          id: taskId,
          userId: data.profile.userId,
          tagIds: validTagIds,
          title: title,
          description: draft.description.isEmpty ? null : draft.description,
          estimatedMinutes: draft.estimatedMinutes,
          completedMinutes: 0,
          priority: draft.priority,
          deadline: draft.deadline,
          deadlineKind: draft.deadlineKind,
          earliestDate: draft.earliestDate,
          isFixed: draft.isFixed,
          archived: draft.archived,
          createdAt: updatedAt,
          updatedAt: updatedAt,
        ),
      ],
    );
  }
  return data.copyWith(
    tasks: [
      for (final task in data.tasks)
        task.id == taskId
            ? task.copyWith(
                tagIds: validTagIds,
                title: title,
                description: draft.description.isEmpty
                    ? null
                    : draft.description,
                estimatedMinutes: draft.estimatedMinutes,
                priority: draft.priority,
                deadline: draft.deadline,
                deadlineKind: draft.deadlineKind,
                earliestDate: draft.earliestDate,
                isFixed: draft.isFixed,
                archived: draft.archived,
                updatedAt: updatedAt,
              )
            : task,
    ],
  );
}

/// Outcome of scheduling one task onto one day.
class ScheduleOutcome {
  const ScheduleOutcome({
    required this.placed,
    required this.requested,
    required this.remaining,
    required this.conflict,
    required this.message,
  });

  final int placed;
  final int requested;
  final int remaining;
  final bool conflict;
  final String message;
}

class ScheduleResult {
  const ScheduleResult(this.data, this.outcome);
  final PlannerData data;
  final ScheduleOutcome outcome;
}

/// Splits [minutes] (or the whole unscheduled remainder) into 30 minute blocks on
/// [date]. A capacity shortfall marks the task as conflicted, matching the Web
/// "安排时间块" dialog.
ScheduleResult scheduleTaskDay(
  PlannerData data,
  String taskId,
  String date,
  int? minutes, {
  scheduler.SchedulerRuntime runtime = const scheduler.SchedulerRuntime(),
}) {
  final task = data.tasks.where((item) => item.id == taskId).firstOrNull;
  if (task == null) throw StateError('请先创建并选择事项');
  if (task.isArchived) throw StateError('已归档事项不可安排');
  final remaining = unscheduledTaskMinutes(data, task, from: date);
  final requested = minutes == null ? remaining : math.min(remaining, minutes);
  if (requested <= 0) {
    throw StateError('请填写大于零的安排时长');
  }
  final stamp = runtime.timestamp();
  final next = [...data.blocks];
  var scheduled = 0;
  for (final chunk in splitIntoGranules(requested)) {
    ScheduleBlock? placed;
    if (data.profile.planningMode != PlanningMode.timed) {
      final candidate = _block(
        runtime: runtime,
        data: data,
        task: task,
        date: date,
        startMinute: 0,
        minutes: chunk,
        timestamp: stamp,
      );
      if (scheduler.validateBlockPlacement(
            data.copyWith(blocks: next),
            candidate,
          ) ==
          null) {
        placed = candidate;
      }
    } else {
      for (
        var start = data.profile.studyStartMinute;
        start + chunk <= data.profile.studyEndMinute;
        start += 30
      ) {
        final candidate = _block(
          runtime: runtime,
          data: data,
          task: task,
          date: date,
          startMinute: start,
          minutes: chunk,
          timestamp: stamp,
        );
        if (scheduler.validateBlockPlacement(
              data.copyWith(blocks: next),
              candidate,
            ) ==
            null) {
          placed = candidate;
          break;
        }
      }
    }
    if (placed == null) break;
    next.add(placed);
    scheduled += chunk;
  }
  final conflict = scheduled < requested;
  // 时间口径下容量不足只作为本次安排的结果提示，不再写入事项状态。
  final updated = data.copyWith(blocks: next);
  final String message;
  if (remaining == 0) {
    message = '该事项的剩余时长已全部安排';
  } else if (conflict) {
    message =
        '已安排 ${duration(scheduled)}，剩余 ${duration(requested - scheduled)} '
        '容量不足，事项已标记冲突。';
  } else {
    message = '已安排 ${duration(scheduled)} 到 $date';
  }
  return ScheduleResult(
    updated,
    ScheduleOutcome(
      placed: scheduled,
      requested: requested,
      remaining: remaining,
      conflict: conflict,
      message: message,
    ),
  );
}

ScheduleBlock _block({
  required scheduler.SchedulerRuntime runtime,
  required PlannerData data,
  required Task task,
  required String date,
  required int startMinute,
  required int minutes,
  required String timestamp,
}) => ScheduleBlock(
  id: runtime.ids(),
  userId: data.profile.userId,
  taskId: task.id,
  date: date,
  startMinute: startMinute,
  durationMinutes: minutes,
  actualMinutes: 0,
  isFixed: task.isFixed,
  status: BlockStatus.planned,
  createdAt: timestamp,
  updatedAt: timestamp,
);
