import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';
import 'planner_format.dart';
import 'study_day.dart';

/// One row of the weekly planned/actual comparison chart.
class SubjectWeekStat {
  const SubjectWeekStat({
    required this.subject,
    required this.planned,
    required this.actual,
    required this.totalActual,
    this.scheduled = 0,
    this.extra = 0,
    this.adHoc = 0,
  });

  final Subject subject;
  final int planned;
  final int actual;
  final int totalActual;

  /// Original-plan execution achieved this week (capped per task/day).
  final int scheduled;

  /// Active extra study and temporary learning recorded this week.
  final int extra;
  final int adHoc;
}

/// One cell of the monthly heat map.
class HeatCell {
  const HeatCell({
    required this.date,
    required this.actual,
    required this.planned,
    required this.rate,
    required this.level,
    required this.past,
    this.scheduled = 0,
    this.extra = 0,
    this.adHoc = 0,
  });

  final String date;
  final int actual;
  final int planned;
  final int rate;

  /// 0 for no recorded time, otherwise 1..4 by 120 minute steps.
  final int level;
  final bool past;
  final int scheduled;
  final int extra;
  final int adHoc;
}

/// Remaining work per subject, used by the progress overview.
class SubjectProgress {
  const SubjectProgress({
    required this.subject,
    required this.estimated,
    required this.completed,
    required this.remaining,
    required this.actual,
  });

  final Subject subject;
  final int estimated;
  final int completed;
  final int remaining;
  final int actual;

  double get ratio => estimated == 0 ? 0 : completed / estimated;
}

/// Everything the progress page needs, computed once from the current plan.
class ProgressMetrics {
  const ProgressMetrics({
    required this.date,
    required this.week,
    required this.totalActual,
    required this.scheduledActual,
    required this.extraActual,
    required this.adHocActual,
    required this.goalActual,
    required this.remainingMinutes,
    required this.overallMinutes,
    required this.targetDate,
    required this.targetConfirmed,
    required this.cycleEnd,
    required this.forecast,
    required this.paceMinutes,
    required this.lagging,
    required this.weekStats,
    required this.maxWeekly,
    required this.heatCells,
    required this.heatLead,
    required this.interruptedDays,
    required this.burnDays,
    required this.burnValues,
    required this.subjectProgress,
  });

  final String date;
  final List<String> week;
  final int totalActual;

  /// Total actual minutes split by learning relation. Each valid minute appears
  /// exactly once; content completion stays expressed by [subjectProgress].
  final int scheduledActual;
  final int extraActual;
  final int adHocActual;

  /// Task-attributed actual minutes used for the goal pace forecast. Temporary
  /// learning has no task, so it never speeds up a course goal on its own.
  final int goalActual;
  final int remainingMinutes;
  final int overallMinutes;

  /// 用户目标日期，可能为空；与本次规划周期分别表达。
  final String targetDate;
  final bool targetConfirmed;

  /// 本次规划周期的结束日期。
  final String cycleEnd;

  /// `null` until there is at least one study record.
  final String? forecast;
  final double paceMinutes;
  final bool lagging;
  final List<SubjectWeekStat> weekStats;
  final int maxWeekly;
  final List<HeatCell> heatCells;
  final int heatLead;
  final int interruptedDays;
  final List<String> burnDays;
  final List<int> burnValues;
  final List<SubjectProgress> subjectProgress;
}

ProgressMetrics progressMetrics(
  PlannerData data, {
  required String date,
  required String month,
}) {
  final week = [for (var index = 6; index >= 0; index--) addDate(date, -index)];
  final weekSet = week.toSet();
  final taskById = {for (final task in data.tasks) task.id: task};
  final activeTasks = data.tasks
      .where((task) => task.status != TaskStatus.archived)
      .toList();

  final totalActual = data.logs.fold<int>(0, (sum, log) => sum + log.minutes);
  var extraActual = 0, adHocActual = 0;
  for (final log in data.logs) {
    switch (log.relation) {
      case TimeLogRelation.extra:
        extraActual += log.minutes;
      case TimeLogRelation.adHoc:
        adHocActual += log.minutes;
      case TimeLogRelation.scheduled:
      case TimeLogRelation.legacyUnknown:
        break;
    }
  }
  // Original-plan execution per logged day, capped per task/day; total actual
  // minutes never stand in for it.
  final loggedDates = data.logs.map((log) => log.date).toSet();
  var scheduledActual = 0;
  for (final day in loggedDates) {
    scheduledActual += dayExecutionSummary(data, day).scheduled;
  }
  final activeTaskIds = {for (final task in activeTasks) task.id};
  final goalLogs = [
    for (final log in data.logs)
      if (log.taskId != null && activeTaskIds.contains(log.taskId)) log,
  ];
  final goalActual = goalLogs.fold<int>(0, (sum, log) => sum + log.minutes);
  final remainingMinutes = activeTasks.fold<int>(
    0,
    (sum, task) =>
        sum + math.max(0, task.estimatedMinutes - task.completedMinutes),
  );

  final pastLogs = [
    for (final log in goalLogs)
      if (log.date.compareTo(date) <= 0) log,
  ];
  var elapsed = 1;
  if (pastLogs.isNotEmpty) {
    var first = pastLogs.first.date;
    for (final log in pastLogs) {
      if (log.date.compareTo(first) < 0) first = log.date;
    }
    elapsed = math.max(1, daysBetween(first, date) + 1);
  }
  final pace = pastLogs.fold<int>(0, (sum, log) => sum + log.minutes) / elapsed;
  final String? forecast;
  final bool lagging;
  if (pace == 0 || !pace.isFinite) {
    forecast = null;
    lagging = false;
  } else {
    final projected = addDate(date, (remainingMinutes / pace).ceil());
    forecast = projected;
    final horizon = data.profile.resolvedTargetDate.isNotEmpty
        ? data.profile.resolvedTargetDate
        : data.profile.resolvedPlanEnd(date);
    lagging = projected.compareTo(horizon) > 0;
  }

  final overall = activeTasks.fold<int>(
    0,
    (sum, task) => sum + task.estimatedMinutes,
  );

  final weekStats = <SubjectWeekStat>[];
  final adHocById = {
    for (final entity in data.adHocLearnings) entity.id: entity,
  };
  final scheduledBySubject = <String, int>{};
  for (final day in week) {
    final summary = dayExecutionSummary(data, day);
    for (final entry in summary.scheduledByTask.entries) {
      final subjectId = taskById[entry.key]?.subjectId;
      if (subjectId == null) continue;
      scheduledBySubject[subjectId] =
          (scheduledBySubject[subjectId] ?? 0) + entry.value;
    }
  }
  for (final subject in data.subjects) {
    var planned = 0, actual = 0, total = 0, extra = 0, adHoc = 0;
    for (final block in data.blocks) {
      if (!weekSet.contains(block.date)) continue;
      if (taskById[block.taskId]?.subjectId != subject.id) continue;
      planned += block.durationMinutes;
    }
    for (final log in data.logs) {
      final subjectId = log.taskId != null
          ? taskById[log.taskId]?.subjectId
          : (log.adHocId == null ? null : adHocById[log.adHocId!]?.subjectId);
      if (subjectId != subject.id) continue;
      total += log.minutes;
      if (!weekSet.contains(log.date)) continue;
      actual += log.minutes;
      if (log.relation == TimeLogRelation.extra) extra += log.minutes;
      if (log.relation == TimeLogRelation.adHoc) adHoc += log.minutes;
    }
    weekStats.add(
      SubjectWeekStat(
        subject: subject,
        planned: planned,
        actual: actual,
        totalActual: total,
        scheduled: scheduledBySubject[subject.id] ?? 0,
        extra: extra,
        adHoc: adHoc,
      ),
    );
  }
  var maxWeekly = 60;
  for (final stat in weekStats) {
    maxWeekly = math.max(maxWeekly, math.max(stat.planned, stat.actual));
  }

  final monthStartDate = monthStart(month);
  final monthLength = daysInMonth(month);
  final heatCells = <HeatCell>[];
  var interrupted = 0;
  for (var index = 0; index < monthLength; index++) {
    final day = addDate(monthStartDate, index);
    final stats = dayStats(data, day);
    final hasPlan = data.blocks.any((block) => block.date == day);
    // A day is interrupted when its original plan was not executed at all; extra
    // or temporary learning on that day does not hide the missing arrangement.
    if (day.compareTo(date) <= 0 && hasPlan && stats.scheduled == 0) {
      interrupted++;
    }
    heatCells.add(
      HeatCell(
        date: day,
        actual: stats.actual,
        planned: stats.planned,
        rate: stats.rate,
        level: stats.actual == 0 ? 0 : math.min(4, (stats.actual / 120).ceil()),
        past: day.compareTo(date) <= 0,
        scheduled: stats.scheduled,
        extra: stats.extra,
        adHoc: stats.adHoc,
      ),
    );
  }

  final burnDays = [
    for (var index = 14; index >= 0; index--) addDate(date, -index),
  ];
  final burnValues = [
    for (final day in burnDays)
      math.max(
        0,
        overall -
            activeTasks.fold<int>(0, (sum, task) {
              final logged = data.logs
                  .where(
                    (log) =>
                        log.taskId == task.id && log.date.compareTo(day) <= 0,
                  )
                  .fold<int>(0, (inner, log) => inner + log.minutes);
              return sum + math.min(task.estimatedMinutes, logged);
            }),
      ),
  ];

  final subjectProgress = <SubjectProgress>[];
  for (final subject in data.subjects) {
    final tasks = activeTasks
        .where((task) => task.subjectId == subject.id)
        .toList();
    final estimated = tasks.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes,
    );
    final completed = tasks.fold<int>(
      0,
      (sum, task) => sum + task.completedMinutes,
    );
    final actual = data.tasks
            .where((task) => task.subjectId == subject.id)
            .fold<int>(0, (sum, task) => sum + taskTotalMinutes(data, task.id)) +
        data.logs
            .where((log) {
              if (log.taskId != null) return false;
              final adHocId = log.adHocId;
              return adHocId != null &&
                  adHocById[adHocId]?.subjectId == subject.id;
            })
            .fold<int>(0, (sum, log) => sum + log.minutes);
    subjectProgress.add(
      SubjectProgress(
        subject: subject,
        estimated: estimated,
        completed: completed,
        remaining: math.max(0, estimated - completed),
        actual: actual,
      ),
    );
  }

  return ProgressMetrics(
    date: date,
    week: week,
    totalActual: totalActual,
    scheduledActual: scheduledActual,
    extraActual: extraActual,
    adHocActual: adHocActual,
    goalActual: goalActual,
    remainingMinutes: remainingMinutes,
    overallMinutes: overall,
    targetDate: data.profile.resolvedTargetDate,
    targetConfirmed: data.profile.targetDateConfirmed,
    cycleEnd: data.profile.resolvedPlanEnd(date),
    forecast: forecast,
    paceMinutes: pace.isFinite ? pace : 0,
    lagging: lagging,
    weekStats: weekStats,
    maxWeekly: maxWeekly,
    heatCells: heatCells,
    heatLead: mondayIndex(monthStartDate),
    interruptedDays: interrupted,
    burnDays: burnDays,
    burnValues: burnValues,
    subjectProgress: subjectProgress,
  );
}
