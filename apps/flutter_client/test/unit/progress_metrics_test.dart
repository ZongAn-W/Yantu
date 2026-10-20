import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/progress_metrics.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

PlannerData progressFixture() {
  final base = plannerFixture();
  final tagId = base.tags.first.id;
  final second = base.tasks.first.copyWith(
    id: 'task-2',
    tagIds: [tagId],
    title: '真题精读',
    estimatedMinutes: 600,
    completedMinutes: 0,
  );
  return base.copyWith(
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
    final metrics = progressMetrics(data, date: '2026-10-16', month: '2026-10');
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
  test('weekly planned and actual totals count tasks once', () {
    final metrics = progressMetrics(
      progressFixture(),
      date: '2026-10-16',
      month: '2026-10',
    );
    // The fixture plans 30 minutes and records 35 + 60 minutes across tasks.
    expect(metrics.weekProgress.planned, 30);
    expect(metrics.weekProgress.actual, 95);
    expect(metrics.maxWeekly, 95);
  });
  test('task progress reports one overall completed and remaining budget', () {
    final metrics = progressMetrics(
      progressFixture(),
      date: '2026-10-16',
      month: '2026-10',
    );
    expect(metrics.overallMinutes, 16200);
    // Completed mirrors task fields, while actual minutes come from logs.
    expect(metrics.completedMinutes, 0);
    expect(metrics.remainingMinutes, 16200);
  });

  test('adding multiple tags does not duplicate progress totals', () {
    final data = progressFixture();
    final task = data.tasks.first;
    final addedTag = Tag(
      id: 'second-tag',
      userId: data.profile.userId,
      name: '薄弱项',
    );
    final tagged = data.copyWith(
      tags: [...data.tags, addedTag],
      tasks: [
        task.copyWith(tagIds: [...task.tagIds, addedTag.id]),
        ...data.tasks.skip(1),
      ],
    );
    final original = progressMetrics(
      data,
      date: '2026-10-16',
      month: '2026-10',
    );
    final withMultipleTags = progressMetrics(
      tagged,
      date: '2026-10-16',
      month: '2026-10',
    );
    expect(withMultipleTags.overallMinutes, original.overallMinutes);
    expect(withMultipleTags.completedMinutes, original.completedMinutes);
    expect(withMultipleTags.remainingMinutes, original.remainingMinutes);
    expect(withMultipleTags.totalActual, original.totalActual);
    expect(
      withMultipleTags.weekProgress.planned,
      original.weekProgress.planned,
    );
    expect(withMultipleTags.weekProgress.actual, original.weekProgress.actual);
    expect(
      withMultipleTags.weekProgress.scheduled,
      original.weekProgress.scheduled,
    );
  });

  test('burn values never fall below zero', () {
    final data = progressFixture();
    final metrics = progressMetrics(data, date: '2026-10-16', month: '2026-10');
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
    final paced = progressMetrics(base, date: '2026-10-16', month: '2026-10');
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
    final metrics = progressMetrics(data, date: '2026-10-16', month: '2026-10');
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
    final metrics = progressMetrics(data, date: '2026-10-20', month: '2026-10');
    // Only 2026-10-16 has both a plan and a record, so nothing is interrupted.
    expect(metrics.interruptedDays, 0);
    final planned = data.copyWith(
      logs: const [],
      blocks: [data.blocks.first.copyWith(date: '2026-10-18')],
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

  group('learning relation statistics', () {
    const date = '2026-10-16';

    TimeLog logFor(
      PlannerData data,
      int minutes, {
      required String id,
      String? taskId,
      String? adHocId,
      TimeLogRelation relation = TimeLogRelation.scheduled,
      String day = date,
    }) => TimeLog(
      id: id,
      userId: data.profile.userId,
      taskId: taskId,
      blockId: null,
      date: day,
      minutes: minutes,
      startedAt: '${day}T00:00:00.000Z',
      endedAt: '${day}T01:00:00.000Z',
      source: LogSource.timer,
      relation: relation,
      adHocId: adHocId,
    );

    test('actual minutes are split by relation and counted once', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final data = base.copyWith(
        logs: [
          logFor(base, 60, id: 'scheduled', taskId: task.id),
          logFor(
            base,
            20,
            id: 'extra',
            taskId: task.id,
            relation: TimeLogRelation.extra,
          ),
          logFor(
            base,
            40,
            id: 'ad-hoc',
            adHocId: 'photo',
            relation: TimeLogRelation.adHoc,
          ),
        ],
        adHocLearnings: [
          AdHocLearning(
            id: 'photo',
            userId: base.profile.userId,
            title: '摄影构图',
            createdAt: '2026-10-01T00:00:00.000Z',
            updatedAt: '2026-10-01T00:00:00.000Z',
          ),
        ],
        blocks: [base.blocks.single.copyWith(durationMinutes: 60)],
      );
      final metrics = progressMetrics(data, date: date, month: '2026-10');
      expect(metrics.totalActual, 120);
      expect(metrics.scheduledActual, 60);
      expect(metrics.extraActual, 20);
      expect(metrics.adHocActual, 40);
      expect(metrics.goalActual, 80, reason: '临时学习不属于任何正式事项目标');
      expect(
        metrics.scheduledActual + metrics.extraActual + metrics.adHocActual,
        metrics.totalActual,
      );
    });

    test('temporary learning never speeds up the goal content forecast', () {
      final base = plannerFixture();
      final without = progressMetrics(base, date: date, month: '2026-10');
      final withAdHoc = progressMetrics(
        base.copyWith(
          logs: [
            ...base.logs,
            logFor(
              base,
              500,
              id: 'photo-log',
              adHocId: 'photo',
              relation: TimeLogRelation.adHoc,
            ),
          ],
          adHocLearnings: [
            AdHocLearning(
              id: 'photo',
              userId: base.profile.userId,
              title: '摄影构图',
              createdAt: '2026-10-01T00:00:00.000Z',
              updatedAt: '2026-10-01T00:00:00.000Z',
            ),
          ],
        ),
        date: date,
        month: '2026-10',
      );
      expect(withAdHoc.totalActual, without.totalActual + 500);
      expect(withAdHoc.goalActual, without.goalActual);
      expect(withAdHoc.forecast, without.forecast);
      expect(withAdHoc.paceMinutes, without.paceMinutes);
    });

    test('weekly totals aggregate extra and temporary minutes once', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final data = base.copyWith(
        logs: [
          logFor(base, 60, id: 'scheduled', taskId: task.id),
          logFor(
            base,
            15,
            id: 'extra',
            taskId: task.id,
            relation: TimeLogRelation.extra,
          ),
          logFor(
            base,
            30,
            id: 'ad-hoc',
            adHocId: 'photo',
            relation: TimeLogRelation.adHoc,
          ),
        ],
        adHocLearnings: [
          AdHocLearning(
            id: 'photo',
            userId: base.profile.userId,
            title: '摄影构图',
            createdAt: '2026-10-01T00:00:00.000Z',
            updatedAt: '2026-10-01T00:00:00.000Z',
          ),
        ],
        blocks: [base.blocks.single.copyWith(durationMinutes: 60)],
      );
      final metrics = progressMetrics(data, date: date, month: '2026-10');
      final weekly = metrics.weekProgress;
      expect(weekly.planned, 60);
      expect(weekly.actual, 105);
      expect(weekly.scheduled, 60);
      expect(weekly.extra, 15);
      expect(weekly.adHoc, 30);
    });

    test(
      'heat cells separate relations and interruption ignores temporary time',
      () {
        final base = plannerFixture();
        final data = base.copyWith(
          blocks: [base.blocks.single.copyWith(date: '2026-10-10')],
          logs: [
            logFor(
              base,
              30,
              id: 'photo-log',
              adHocId: 'photo',
              relation: TimeLogRelation.adHoc,
              day: '2026-10-10',
            ),
          ],
          adHocLearnings: [
            AdHocLearning(
              id: 'photo',
              userId: base.profile.userId,
              title: '摄影构图',
              createdAt: '2026-10-01T00:00:00.000Z',
              updatedAt: '2026-10-01T00:00:00.000Z',
            ),
          ],
        );
        final metrics = progressMetrics(data, date: date, month: '2026-10');
        final cell = metrics.heatCells
            .where((item) => item.date == '2026-10-10')
            .single;
        expect(cell.actual, 30);
        expect(cell.scheduled, 0);
        expect(cell.adHoc, 30);
        expect(metrics.interruptedDays, 1, reason: '临时学习不能冒充当天原定安排已执行');
      },
    );
  });
}
