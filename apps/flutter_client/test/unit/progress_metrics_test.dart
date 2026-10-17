import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/progress_metrics.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

PlannerData progressFixture() {
  final base = plannerFixture();
  final subject = Subject(
    id: 'english',
    userId: base.profile.userId,
    name: '英语',
    color: '#1f7a5a',
    priority: 2,
  );
  final second = base.tasks.first.copyWith(
    id: 'task-2',
    subjectId: 'english',
    title: '真题精读',
    estimatedMinutes: 600,
    completedMinutes: 0,
  );
  return base.copyWith(
    subjects: [...base.subjects, subject],
    tasks: [base.tasks.first, second],
    logs: [
      ...base.logs,
      base.logs.first.copyWith(
        id: 'log-2',
        taskId: 'task-2',
        date: '2026-10-16',
        minutes: 60,
      ),
    ],
  );
}

void main() {
  test('totals, remaining budget and target date come from the plan', () {
    final data = progressFixture();
    final metrics = progressMetrics(
      data,
      date: '2026-10-16',
      month: '2026-10',
    );
    expect(metrics.totalActual, 95);
    expect(
      metrics.remainingMinutes,
      (15600 - 0) + 600,
      reason: '预算扣除各事项 completed_minutes；日志由 refreshTaskProgress 汇总',
    );
    expect(metrics.overallMinutes, 15600 + 600);
    expect(metrics.targetDate, '2027-12-25');
    expect(metrics.week, hasLength(7));
    expect(metrics.week.last, '2026-10-16');
    expect(metrics.week.first, '2026-10-10');
  });
  test('per-subject planned, actual and lifetime totals stay separated', () {
    final metrics = progressMetrics(
      progressFixture(),
      date: '2026-10-16',
      month: '2026-10',
    );
    final calculus = metrics.weekStats.firstWhere(
      (stat) => stat.subject.id == 'calculus',
    );
    final english = metrics.weekStats.firstWhere(
      (stat) => stat.subject.id == 'english',
    );
    // The fixture plans 30 minutes of calculus and logs 35; the English task has
    // a 60 minute log but no planned block.
    expect(calculus.planned, 30);
    expect(calculus.actual, 35);
    expect(english.planned, 0);
    expect(english.actual, 60);
    expect(calculus.totalActual, 35);
    expect(english.totalActual, 60);
    expect(metrics.maxWeekly, 60);
  });
  test('subject progress reports completed, remaining and completion rate', () {
    final metrics = progressMetrics(
      progressFixture(),
      date: '2026-10-16',
      month: '2026-10',
    );
    final calculus = metrics.subjectProgress.firstWhere(
      (item) => item.subject.id == 'calculus',
    );
    expect(calculus.estimated, 15600);
    // `completed` mirrors the task field, which `refreshTaskProgress` maintains
    // whenever minutes are recorded; `actual` always reads the study log.
    expect(calculus.completed, 0);
    expect(calculus.remaining, 15600);
    expect(calculus.actual, 35);
    expect(calculus.ratio, 0);
    final english = metrics.subjectProgress.firstWhere(
      (item) => item.subject.id == 'english',
    );
    expect(english.estimated, 600);
    expect(english.actual, 60);
  });

  test('burn values never fall below zero', () {
    final data = progressFixture();
    final metrics = progressMetrics(
      data,
      date: '2026-10-16',
      month: '2026-10',
    );
    expect(metrics.burnDays, hasLength(15));
    expect(metrics.burnValues, hasLength(15));
    expect(metrics.burnValues.every((value) => value >= 0), isTrue);
    // 15 days ago nothing was recorded, so the full budget remains.
    expect(metrics.burnValues.first, metrics.overallMinutes);
    // On the last day the recorded minutes are already applied.
    expect(metrics.burnValues.last, metrics.overallMinutes - 95);
  });

  test('forecast is absent without records and lagging is detected with one', () {
    final base = plannerFixture();
    final empty = progressMetrics(
      base.copyWith(logs: const []),
      date: '2026-10-16',
      month: '2026-10',
    );
    expect(empty.forecast, isNull);
    expect(empty.lagging, isFalse);
    expect(empty.paceMinutes, 0);

    // 35 minutes on day one against a 15600 minute budget cannot finish in time.
    final paced = progressMetrics(
      base,
      date: '2026-10-16',
      month: '2026-10',
    );
    expect(paced.forecast, isNotNull);
    expect(paced.paceMinutes, 35);
    expect(paced.lagging, isTrue);
    expect(
      paced.forecast!.compareTo(base.profile.resolvedTargetDate),
      greaterThan(0),
    );
  });

  test('heat map covers the month with a Monday-leading offset', () {
    final data = progressFixture();
    final metrics = progressMetrics(
      data,
      date: '2026-10-16',
      month: '2026-10',
    );
    expect(metrics.heatCells, hasLength(31));
    // 2026-10-01 is a Thursday, so four leading blanks in a Monday-first grid.
    expect(metrics.heatLead, 3);
    expect(metrics.heatCells.first.date, '2026-10-01');
    expect(metrics.heatCells.last.date, '2026-10-31');
    final first = metrics.heatCells.first;
    final sixteenth = metrics.heatCells[15];
    expect(first.level, 0);
    expect(first.past, isTrue);
    // 95 minutes against a 30 minute plan on 2026-10-16.
    expect(sixteenth.date, '2026-10-16');
    expect(sixteenth.level, 1);
    expect(sixteenth.rate, 317);
  });

  test('interrupted days count planned past days without records', () {
    final data = progressFixture();
    final metrics = progressMetrics(
      data,
      date: '2026-10-20',
      month: '2026-10',
    );
    // Only 2026-10-16 has both a plan and a record, so nothing is interrupted.
    expect(metrics.interruptedDays, 0);
    final planned = data.copyWith(
      logs: const [],
      blocks: [
        data.blocks.first.copyWith(date: '2026-10-18'),
      ],
    );
    expect(
      progressMetrics(
        planned,
        date: '2026-10-20',
        month: '2026-10',
      ).interruptedDays,
      1,
    );
  });

  test('heat level steps by 120 minutes and caps at four', () {
    final base = plannerFixture();
    for (final (minutes, level) in const [
      (0, 0),
      (1, 1),
      (120, 1),
      (121, 2),
      (360, 3),
      (480, 4),
      (1440, 4),
    ]) {
      final metrics = progressMetrics(
        base.copyWith(
          logs: [
            base.logs.first.copyWith(date: '2026-10-05', minutes: minutes),
          ],
        ),
        date: '2026-10-16',
        month: '2026-10',
      );
      expect(
        metrics.heatCells[4].level,
        level,
        reason: '$minutes 分钟应为 level $level',
      );
    }
  });

  test('weekday and month formatting helpers agree with the grid', () {
    expect(monthStart('2026-10-16'), '2026-10-01');
    expect(mondayIndex('2026-10-01'), 3);
    expect(daysInMonth('2026-10'), 31);
  });
}
