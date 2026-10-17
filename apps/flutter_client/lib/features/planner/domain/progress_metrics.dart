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
  });

  final Subject subject;
  final int planned;
  final int actual;
  final int totalActual;
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
  });

  final String date;
  final int actual;
  final int planned;
  final int rate;

  /// 0 for no recorded time, otherwise 1..4 by 120 minute steps.
  final int level;
  final bool past;
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
    required this.remainingMinutes,
    required this.overallMinutes,
    required this.examDate,
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
  final int remainingMinutes;
  final int overallMinutes;

  /// Exam date from the profile, shown as the burndown target.
  final String examDate;

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

  final totalActual = data.logs.fold<int>(0, (sum, log) => sum + log.minutes);
  final remainingMinutes = data.tasks.fold<int>(
    0,
    (sum, task) =>
        sum + math.max(0, task.estimatedMinutes - task.completedMinutes),
  );

  final pastLogs = [
    for (final log in data.logs)
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
    lagging = projected.compareTo(data.profile.examDate) > 0;
  }

  final overall = data.tasks.fold<int>(
    0,
    (sum, task) => sum + task.estimatedMinutes,
  );

  final weekStats = <SubjectWeekStat>[];
  for (final subject in data.subjects) {
    var planned = 0, actual = 0, total = 0;
    for (final block in data.blocks) {
      if (!weekSet.contains(block.date)) continue;
      if (taskById[block.taskId]?.subjectId != subject.id) continue;
      planned += block.durationMinutes;
    }
    for (final log in data.logs) {
      if (taskById[log.taskId]?.subjectId != subject.id) continue;
      total += log.minutes;
      if (weekSet.contains(log.date)) actual += log.minutes;
    }
    weekStats.add(
      SubjectWeekStat(
        subject: subject,
        planned: planned,
        actual: actual,
        totalActual: total,
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
    final hasActual = data.logs.any((log) => log.date == day && log.minutes > 0);
    if (day.compareTo(date) <= 0 && hasPlan && !hasActual) interrupted++;
    heatCells.add(
      HeatCell(
        date: day,
        actual: stats.actual,
        planned: stats.planned,
        rate: stats.rate,
        level: stats.actual == 0
            ? 0
            : math.min(4, (stats.actual / 120).ceil()),
        past: day.compareTo(date) <= 0,
      ),
    );
  }

  final burnDays = [for (var index = 14; index >= 0; index--) addDate(date, -index)];
  final burnValues = [
    for (final day in burnDays)
      math.max(
        0,
        overall -
            data.tasks.fold<int>(0, (sum, task) {
              final logged = data.logs
                  .where(
                    (log) => log.taskId == task.id && log.date.compareTo(day) <= 0,
                  )
                  .fold<int>(0, (inner, log) => inner + log.minutes);
              return sum + math.min(task.estimatedMinutes, logged);
            }),
      ),
  ];

  final subjectProgress = <SubjectProgress>[];
  for (final subject in data.subjects) {
    final tasks = data.tasks
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
    final actual = tasks.fold<int>(
      0,
      (sum, task) => sum + taskTotalMinutes(data, task.id),
    );
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
    remainingMinutes: remainingMinutes,
    overallMinutes: overall,
    examDate: data.profile.examDate,
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
