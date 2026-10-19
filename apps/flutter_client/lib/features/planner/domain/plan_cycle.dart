import '../../../shared/models/planner_models.dart';
import 'capacity.dart' as capacity;
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

/// 计划周期模式：full 一次生成并覆盖整个有限周期；rolling 是旧的按窗口细化。
enum PlanPeriodMode { rolling, full }

/// 从 `planning` 元数据判断周期模式（旧数据缺失按滚动处理）。
///
/// - `mode == "full"`：新客户端/服务端生成的全量计划；
/// - `mode == "rolling"`：旧滚动计划；
/// - 缺少 `mode` 时：显式 `rolling == false` 视为旧的全量计划（不自动覆盖），
///   其余按滚动计划提供一次性“补全本周期安排”。
PlanPeriodMode planPeriodMode(JsonMap? planning) {
  final mode = planning?['mode'];
  if (mode == 'full') return PlanPeriodMode.full;
  if (mode == 'rolling') return PlanPeriodMode.rolling;
  return planning?['rolling'] == false
      ? PlanPeriodMode.full
      : PlanPeriodMode.rolling;
}

bool isFullPeriodPlan(JsonMap? planning) =>
    planPeriodMode(planning) == PlanPeriodMode.full;

/// 旧滚动计划的每日安排是否已经被用户确认补全到周期末。
bool planPeriodNeedsCompletion(PlannerData data, {required String today}) {
  if (planPeriodMode(data.planning) == PlanPeriodMode.full) return false;
  final end = data.profile.resolvedPlanEnd(today);
  return end.compareTo(today) >= 0;
}

/// 写入 full 模式元数据；与 [planPeriodMode] 配套，重复写入是幂等的。
JsonMap? fullPeriodPlanning(
  JsonMap? planning, {
  required String start,
  required String end,
}) {
  final span = daysBetween(start, end) + 1;
  return {
    ...?planning,
    'mode': 'full',
    'rolling': false,
    'detail_days': span < 1 ? 1 : span,
    'detailed_until': end,
    'forecast': null,
  };
}

/// 把计划切换为 full 周期模式（不改动任何事项、时间块或学习记录）。
PlannerData applyFullPeriodCycle(
  PlannerData data, {
  String? today,
  String? start,
  String? end,
}) {
  final day = today ?? shanghaiToday();
  final startDate = start ?? data.profile.resolvedPlanStart(day);
  final endDate = end ?? data.profile.resolvedPlanEnd(day);
  return data.copyWith(
    profile: data.profile.copyWith(
      planStartDate: startDate,
      planEndDate: endDate,
    ),
    planning: fullPeriodPlanning(data.planning, start: startDate, end: endDate),
  );
}

/// 把尚未安排的事项排进 [from] 到 [to]（含）的每日安排。
///
/// 只新增与周期相交的安排：已有安排、已完成事项和历史学习记录都不改动，
/// 因此对同一区间重复执行是幂等的，不会重复生成已经存在的每日安排。
///
/// 只有显式标记为滚动（`rolling == true` 或 `mode == "rolling"`）的计划才保留旧的
/// `detail_days` 窗口截断；full 模式与未标记的旧本地计划按传入区间完整生成。
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
  final rolling =
      data.planning?['rolling'] == true || data.planning?['mode'] == 'rolling';
  if (rolling) {
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
  final full = isFullPeriodPlan(data.planning);
  final planStart = data.profile.planStartDate.isNotEmpty
      ? data.profile.planStartDate
      : start;
  final detailDays = daysBetween(planStart, end) + 1;
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
              if (full) ...{
                'mode': 'full',
                'rolling': false,
                'detail_days': detailDays < 1 ? 1 : detailDays,
              },
            },
    ),
    blocks: result.added,
    scheduledMinutes: result.scheduledMinutes,
    unscheduledMinutes: result.unscheduledMinutes,
    gaps: gaps,
  );
}

/// “补全本周期安排”的预览结果：把旧滚动计划未来缺失的安排补齐到周期末。
///
/// 不移动、不删除任何已有安排：历史、固定、已完成、有实际用时或有日志引用的记录
/// 全部保持不变，只新增尚未生成的每日安排。重复预览/确认是幂等的。
class PlanCompletion {
  const PlanCompletion({
    required this.previousMode,
    required this.from,
    required this.to,
    required this.result,
    required this.protectedBlocks,
    required this.realDeadlineImpacts,
  });

  final PlanPeriodMode previousMode;
  final String from;
  final String to;
  final PlanGenerationResult result;

  /// 周期内已有的、不会被本次补全改动的安排数量。
  final int protectedBlocks;

  /// 真实截止日期（`deadline_kind == deadline`）仍有内容未能安排的事项说明。
  final List<String> realDeadlineImpacts;

  PlannerData get data => result.data;
  int get addedBlocks => result.blocks;
  int get scheduledMinutes => result.scheduledMinutes;
  int get unscheduledMinutes => result.unscheduledMinutes;
  List<String> get gaps => result.gaps;

  /// 已经覆盖整个周期且没有新增安排时，重复确认不会再改变计划。
  bool get alreadyComplete => addedBlocks == 0 && unscheduledMinutes == 0;
}

/// 把旧滚动计划一次性补全为本周期全量计划（先预览，确认后再写入）。
PlanCompletion completePlanPeriod(
  PlannerData data, {
  required String today,
  String? timestamp,
  String Function()? nextId,
}) {
  final start = data.profile.resolvedPlanStart(today);
  final end = data.profile.resolvedPlanEnd(today);
  final from = start.compareTo(today) > 0 ? start : today;
  final base = applyFullPeriodCycle(data, today: today, start: start, end: end);
  final protectedBlocks = base.blocks
      .where((block) => block.date.compareTo(today) >= 0)
      .length;
  final result = generatePlanBlocks(
    base,
    from: from,
    to: end,
    timestamp: timestamp,
    nextId: nextId,
  );
  final impacts = <String>[
    for (final task in data.tasks)
      if (task.deadlineKind == ItemDateKind.deadline &&
          task.status != TaskStatus.archived &&
          task.status != TaskStatus.completed &&
          task.deadline.compareTo(end) <= 0 &&
          scheduler.forecastRemainingMinutes(
                task,
                result.data.logs,
                result.data.blocks,
                from: from,
              ) >
              0)
        '「${task.title}」真实截止日期 ${task.deadline} 前仍有内容未排入，'
            '请调整容量或确认范围。',
  ];
  return PlanCompletion(
    previousMode: planPeriodMode(data.planning),
    from: from,
    to: end,
    result: result,
    protectedBlocks: protectedBlocks,
    realDeadlineImpacts: impacts,
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
    this.realDeadlineImpacts = const [],
  });

  final PlannerData data;

  /// 日期到计划分钟数，覆盖调整前后的受影响区间。
  final Map<String, int> beforeLoad;
  final Map<String, int> afterLoad;

  /// 被释放并重新分配的可调整安排数量与分钟数。
  final int releasedBlocks;
  final int releasedMinutes;

  /// 重新排入的新增安排数量与分钟数。
  final int placedBlocks;
  final int placedMinutes;

  /// 仍未能排入的分钟数（结构化缺口，不会静默丢弃）。
  final int unscheduledMinutes;

  /// 周期内保持不动的历史、固定、已完成或已有记录安排数量。
  final int protectedBlocks;
  final List<String> notes;

  /// 真实截止日期受到影响的事项说明（安排减少或仍有内容未安排）。
  final List<String> realDeadlineImpacts;

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
  // 周容量设置冲突必须显式提示，不能静默选择一边。
  final seenWeeks = <String>{};
  for (var date = from; date.compareTo(end) <= 0; date = addDate(date, 1)) {
    final monday = capacity.capacityWeekMonday(date);
    if (seenWeeks.add(monday)) {
      for (final conflict
          in capacity
              .resolveWeekCapacity(generated.data.profile, monday)
              .conflicts) {
        notes.add(
          conflict.code == capacity.CapacityConflictCode.weekTotalExceeded
              ? '包含 $monday 的一周容量设置冲突：日期/逐日覆盖合计 '
                    '${duration(conflict.resolved)}，超过周总量 '
                    '${duration(conflict.total)}，请调整或明确接受。'
              : '包含 $monday 的一周周总量 ${duration(conflict.total)} 无法分配到'
                    '非休息日（仅能安排 ${duration(conflict.resolved)}），'
                    '请调整模板或该周设置。',
        );
      }
    }
  }
  notes.addAll(generated.gaps);
  final realDeadlineImpacts = <String>[];
  for (final task in data.tasks) {
    if (task.deadlineKind != ItemDateKind.deadline) continue;
    if (task.status == TaskStatus.archived ||
        task.status == TaskStatus.completed) {
      continue;
    }
    int plannedInRange(Iterable<ScheduleBlock> blocks) => blocks
        .where(
          (block) =>
              block.taskId == task.id &&
              block.date.compareTo(from) >= 0 &&
              block.date.compareTo(end) <= 0,
        )
        .fold<int>(0, (sum, block) => sum + block.durationMinutes);
    final beforePlanned = plannedInRange(data.blocks);
    final afterPlanned = plannedInRange(generated.data.blocks);
    final uncovered = scheduler.forecastRemainingMinutes(
      task,
      generated.data.logs,
      generated.data.blocks,
      from: from,
    );
    if (afterPlanned < beforePlanned) {
      realDeadlineImpacts.add(
        '「${task.title}」真实截止日期 ${task.deadline} 前的安排减少 '
        '${duration(beforePlanned - afterPlanned)}。',
      );
    } else if (uncovered > 0 && task.deadline.compareTo(end) <= 0) {
      realDeadlineImpacts.add(
        '「${task.title}」真实截止日期 ${task.deadline} 前仍有 '
        '${duration(uncovered)} 未安排。',
      );
    }
  }

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
    realDeadlineImpacts: realDeadlineImpacts,
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
