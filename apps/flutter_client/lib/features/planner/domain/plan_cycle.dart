import '../../../shared/models/planner_models.dart';
import 'planner_format.dart';
import 'scheduler/planner_scheduler.dart' as scheduler;
import 'scheduler/strategy_scheduler.dart' as strategy;

/// 生成每日安排的结果，包含没有排入的剩余量，便于界面解释原因。
class PlanGenerationResult {
  const PlanGenerationResult({
    required this.data,
    required this.blocks,
    required this.scheduledMinutes,
    required this.unscheduledMinutes,
    required this.gaps,
  });

  final PlannerData data;
  final int blocks;
  final int scheduledMinutes;
  final int unscheduledMinutes;

  /// 未能安排的原因说明，直接展示给用户。
  final List<String> gaps;
}

/// 把尚未安排的事项排进 [from] 到 [to]（含）的每日安排。
///
/// 只新增与周期相交的安排：已有安排、已完成事项、固定事件和历史学习记录都不改动，
/// 因此对同一区间重复执行是幂等的，不会重复生成已经存在的每日安排。
PlanGenerationResult generatePlanBlocks(
  PlannerData data, {
  required String from,
  required String to,
  String? timestamp,
  String Function()? nextId,
}) {
  final stamp = timestamp ?? nowIso();
  final id = nextId ?? scheduler.newUuid;
  final start = from.compareTo(to) <= 0 ? from : to;
  var end = from.compareTo(to) <= 0 ? to : from;
  if (data.planning?['rolling'] == true) {
    final detailEnd = addDate(
      start,
      (data.planning?['detail_days'] as int? ?? 14) - 1,
    );
    if (detailEnd.compareTo(end) < 0) end = detailEnd;
  }
  final result = strategy.scheduleStrategy(
    data,
    start,
    end,
    runtime: scheduler.SchedulerRuntime(now: DateTime.parse(stamp), nextId: id),
  );
  var restDays = 0;
  final gaps = <String>[];
  for (var date = start; date.compareTo(end) <= 0; date = addDate(date, 1)) {
    if (scheduler.dailyStudyBudget(data.profile, date) <= 0) restDays++;
  }
  if (restDays > 0) {
    gaps.add('有 $restDays 天可用时间为 0，没有生成学习安排');
  }
  if (result.unscheduledMinutes > 0) {
    final left = duration(result.unscheduledMinutes);
    gaps.add('还有 $left 未能排入，请调整每日可用时间或事项日期');
  }
  gaps.addAll(
    result.issues
        .where((issue) => issue.code != 'WORK_UNSCHEDULED')
        .map((issue) => issue.message)
        .toSet(),
  );
  return PlanGenerationResult(
    data: data.copyWith(
      blocks: result.blocks,
      planning: data.planning == null
          ? null
          : {
              ...data.planning!,
              'detailed_until': end,
              'needs_review': true,
              'quality': null,
              'forecast': null,
            },
    ),
    blocks: result.added,
    scheduledMinutes: result.scheduledMinutes,
    unscheduledMinutes: result.unscheduledMinutes,
    gaps: gaps,
  );
}

/// 把本期安排边界延展到新的规划周期，真实截止日期保持不变。
PlannerData extendPlanCycle(
  PlannerData data, {
  required String start,
  required String end,
  required String today,
}) {
  if (end.compareTo(start) < 0) {
    throw StateError('规划结束日期不能早于开始日期');
  }
  return data.copyWith(
    profile: data.profile.copyWith(planStartDate: start, planEndDate: end),
    tasks: [
      for (final task in data.tasks)
        if (task.deadlineKind == ItemDateKind.planEnd &&
            task.status != TaskStatus.completed &&
            task.status != TaskStatus.archived)
          () {
            final earliest = task.earliestDate ?? today;
            final deadline = end.compareTo(earliest) < 0 ? task.deadline : end;
            return task.copyWith(deadline: deadline);
          }()
        else
          task,
    ],
  );
}

/// 一次“应用新排程约束”的调整结果。
class ScheduleAdjustment {
  const ScheduleAdjustment({
    required this.data,
    required this.beforeLoad,
    required this.afterLoad,
    required this.releasedBlocks,
    required this.releasedMinutes,
    required this.placedBlocks,
    required this.placedMinutes,
    required this.unscheduledMinutes,
    required this.protectedBlocks,
    required this.notes,
  });

  final PlannerData data;

  /// 日期到计划分钟数，覆盖调整前后的受影响区间。
  final Map<String, int> beforeLoad;
  final Map<String, int> afterLoad;
  final int releasedBlocks;
  final int releasedMinutes;
  final int placedBlocks;
  final int placedMinutes;
  final int unscheduledMinutes;
  final int protectedBlocks;
  final List<String> notes;

  /// 计划时长发生变化的日期，按日期排序。
  List<String> get changedDays {
    final dates = {...beforeLoad.keys, ...afterLoad.keys}.toList()..sort();
    return [
      for (final date in dates)
        if ((beforeLoad[date] ?? 0) != (afterLoad[date] ?? 0)) date,
    ];
  }
}

/// 按新的容量与周期重新安排可调整的未来安排。
///
/// 保护历史日期、已完成安排、固定时间块/固定事项、有实际用时或有日志引用的记录。
/// 其余未来安排会被释放，并按剩余工作量重新排入 [start]..[end]；
/// 排不完的部分保留为未安排量，不会静默丢弃，也不改写事项的真实截止日期。
ScheduleAdjustment reschedulePlan(
  PlannerData data, {
  required String today,
  required String start,
  required String end,
  String? timestamp,
  String Function()? nextId,
}) {
  final from = start.compareTo(today) > 0 ? start : today;
  final taskById = {for (final task in data.tasks) task.id: task};
  final loggedTaskDays = {
    for (final log in data.logs) '${log.taskId}:${log.date}',
  };
  final loggedBlocks = {
    for (final log in data.logs)
      if (log.blockId != null) log.blockId!,
  };
  bool adjustable(ScheduleBlock block) {
    final task = taskById[block.taskId];
    if (block.date.compareTo(today) < 0) return false;
    if (block.isFixed || block.status == BlockStatus.completed) return false;
    if (block.actualMinutes > 0) return false;
    if (loggedBlocks.contains(block.id)) return false;
    if (loggedTaskDays.contains('${block.taskId}:${block.date}')) return false;
    if (task == null || task.isFixed) return false;
    if (task.status == TaskStatus.completed ||
        task.status == TaskStatus.archived) {
      return false;
    }
    return true;
  }

  final kept = <ScheduleBlock>[];
  final releasedDates = <String>{};
  var releasedBlocks = 0;
  var releasedMinutes = 0;
  var protectedBlocks = 0;
  for (final block in data.blocks) {
    if (adjustable(block)) {
      releasedBlocks++;
      releasedMinutes += block.durationMinutes;
      releasedDates.add(block.date);
      continue;
    }
    kept.add(block);
    if (block.date.compareTo(from) >= 0 && block.date.compareTo(end) <= 0) {
      protectedBlocks++;
    }
  }

  final before = _plannedByDate(
    data.blocks,
    from: from,
    to: end,
    extraDates: releasedDates,
  );
  final generated = generatePlanBlocks(
    data.copyWith(blocks: kept),
    from: from,
    to: end,
    timestamp: timestamp,
    nextId: nextId,
  );
  final after = _plannedByDate(
    generated.data.blocks,
    from: from,
    to: end,
    extraDates: releasedDates,
  );

  // 休息日仍有不可撤销记录时，如实说明原因。
  final notes = <String>[];
  final restDays = <String>{};
  for (final block in kept) {
    if (block.date.compareTo(from) < 0 || block.date.compareTo(end) > 0) {
      continue;
    }
    if (scheduler.dailyStudyBudget(generated.data.profile, block.date) > 0) {
      continue;
    }
    restDays.add(block.date);
  }
  for (final date in restDays.toList()..sort()) {
    notes.add(
      '${monthDayLabel(date)} ${weekdayLabel(date)} 已设为休息日，'
      '但保留了已记录用时或固定安排，请核对后再调整。',
    );
  }
  if (releasedBlocks > 0) {
    notes.add(
      '已释放 $releasedBlocks 段未来安排（${duration(releasedMinutes)}）按新约束重新分配。',
    );
  }
  notes.addAll(generated.gaps);

  return ScheduleAdjustment(
    data: generated.data,
    beforeLoad: before,
    afterLoad: after,
    releasedBlocks: releasedBlocks,
    releasedMinutes: releasedMinutes,
    placedBlocks: generated.blocks,
    placedMinutes: generated.scheduledMinutes,
    unscheduledMinutes: generated.unscheduledMinutes,
    protectedBlocks: protectedBlocks,
    notes: notes,
  );
}

Map<String, int> _plannedByDate(
  Iterable<ScheduleBlock> blocks, {
  required String from,
  required String to,
  required Set<String> extraDates,
}) {
  final dates = <String>{...extraDates};
  for (var date = from; date.compareTo(to) <= 0; date = addDate(date, 1)) {
    dates.add(date);
  }
  final result = {for (final date in dates) date: 0};
  for (final block in blocks) {
    final current = result[block.date];
    if (current != null) result[block.date] = current + block.durationMinutes;
  }
  return result;
}
