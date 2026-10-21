import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/plan_cycle.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

const _stamp = '2026-01-01T00:00:00.000Z';

Profile _netProfile({
  required String start,
  required String end,
  Map<String, int>? weekly,
  int? baseline,
  Map<String, WeekCapacityOverride>? weeks,
  Map<String, int>? dates,
}) => Profile(
  userId: 'u1',
  planStartDate: start,
  planEndDate: end,
  weeklyMinutes: weekly ?? {for (var day = 0; day < 7; day++) '$day': 60},
  capacityBasis: CapacityBasis.net,
  weeklyBaselineMinutes: baseline,
  weekCapacityOverrides: weeks,
  dateCapacityOverrides: dates,
  dailyLimitMinutes: 480,
  granularityMinutes: 30,
  bufferMinutes: 30,
  studyStartMinute: 0,
  studyEndMinute: 1440,
  foundation: '',
);

Profile _legacyProfile({required String start, required String end}) => Profile(
  userId: 'u1',
  planStartDate: start,
  planEndDate: end,
  weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 60},
  dailyLimitMinutes: 60,
  granularityMinutes: 30,
  bufferMinutes: 30,
  studyStartMinute: 0,
  studyEndMinute: 1440,
  foundation: '',
);

Task _task(String id, int estimatedMinutes, String deadline) => Task(
  id: id,
  userId: 'u1',
  title: '事项 $id',
  estimatedMinutes: estimatedMinutes,
  completedMinutes: 0,
  priority: 2,
  deadline: deadline,
  isFixed: false,
  createdAt: _stamp,
  updatedAt: _stamp,
);

PlannerData _plan({
  required Profile profile,
  List<Task> tasks = const [],
  List<ScheduleBlock> blocks = const [],
  List<TimeLog> logs = const [],
  JsonMap? planning,
}) => PlannerData(
  version: 1,
  profile: profile,
  tags: const [],
  tasks: tasks,
  blocks: blocks,
  logs: logs,
  fixedEvents: const [],
  replanRuns: const [],
  phases: const [],
  planning: planning,
);

JsonMap _fullPlanning(int span, String end) => {
  'version': 1,
  'mode': 'full',
  'rolling': false,
  'detail_days': span,
  'detailed_until': end,
  'forecast': null,
};

void main() {
  group('full-period generation is not truncated', () {
    for (final span in [28, 90, 431]) {
      test('$span-day plan covers the last day', () {
        const start = '2026-01-01';
        final end = addDate(start, span - 1);
        final data = _plan(
          profile: _netProfile(start: start, end: end),
          tasks: [_task('t', span * 60, end)],
          planning: _fullPlanning(span, end),
        );
        final result = generatePlanBlocks(data, from: start, to: end);
        expect(result.data.blocks, isNotEmpty);
        expect(
          result.data.blocks.any((block) => block.date == end),
          isTrue,
          reason: '$span 天周期的最后一天必须有正式安排，不能被 14/90 天窗口截断',
        );
        final lastDate = result.data.blocks
            .map((block) => block.date)
            .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
        expect(lastDate, end);
        expect(result.unscheduledMinutes, 0);
        expect(result.data.planning!['mode'], 'full');
        expect(result.data.planning!['rolling'], isFalse);
        expect(result.data.planning!['detail_days'], span);
        expect(result.data.planning!['detailed_until'], end);
        expect(result.data.planning!['forecast'], isNull);
        expect(result.data.profile.planEndDate, end);
      });
    }
  });

  test('old rolling plans keep the legacy detail window clamp', () {
    const start = '2026-01-01';
    final end = addDate(start, 27);
    final data = _plan(
      profile: _legacyProfile(start: start, end: end),
      tasks: [_task('t', 2000, end)],
      planning: {
        'version': 1,
        'rolling': true,
        'detail_days': 14,
        'detailed_until': addDate(start, 13),
      },
    );
    final result = generatePlanBlocks(data, from: start, to: end);
    final lastDate = result.data.blocks
        .map((block) => block.date)
        .reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    expect(lastDate, addDate(start, 13));
    expect(result.data.planning!['detailed_until'], addDate(start, 13));
    // 滚动计划的元数据不写 full，避免静默升级。
    expect(result.data.planning!['rolling'], isTrue);
    expect(result.data.planning!.containsKey('mode'), isFalse);
  });

  group('plan period mode', () {
    test('legacy and explicit modes are distinguished', () {
      expect(planPeriodMode(null), PlanPeriodMode.rolling);
      expect(planPeriodMode({'rolling': true}), PlanPeriodMode.rolling);
      expect(planPeriodMode({'version': 1}), PlanPeriodMode.rolling);
      expect(planPeriodMode({'mode': 'rolling'}), PlanPeriodMode.rolling);
      expect(planPeriodMode({'mode': 'full'}), PlanPeriodMode.full);
      expect(planPeriodMode({'rolling': false}), PlanPeriodMode.full);
    });
  });

  group('rolling -> full completion', () {
    const today = '2026-10-12';
    final end = addDate(today, 27);

    PlannerData rollingPlan() {
      final keepBlocks = [
        for (var index = 0; index < 3; index++)
          ScheduleBlock(
            id: 'keep-$index',
            userId: 'u1',
            taskId: 't',
            date: addDate(today, index),
            startMinute: 0,
            durationMinutes: 60,
            actualMinutes: 0,
            isFixed: false,
            status: BlockStatus.planned,
            createdAt: '2026-09-01T00:00:00.000Z',
            updatedAt: '2026-09-01T00:00:00.000Z',
          ),
      ];
      return _plan(
        profile: _netProfile(start: today, end: end),
        tasks: [_task('t', 28 * 60, end)],
        blocks: keepBlocks,
        planning: {
          'version': 1,
          'rolling': true,
          'detail_days': 7,
          'detailed_until': addDate(today, 6),
        },
        logs: const [],
      );
    }

    test('converts metadata, fills missing days, protects existing blocks', () {
      final data = rollingPlan();
      var ids = 0;
      final completion = completePlanPeriod(
        data,
        today: today,
        timestamp: '2026-10-01T00:00:00.000Z',
        nextId: () => 'new-${++ids}',
      );
      expect(completion.previousMode, PlanPeriodMode.rolling);
      expect(completion.data.planning!['mode'], 'full');
      expect(completion.data.planning!['rolling'], isFalse);
      expect(completion.data.planning!['detail_days'], 28);
      expect(completion.data.planning!['detailed_until'], end);
      expect(completion.data.planning!['forecast'], isNull);
      for (final block in data.blocks) {
        final kept = completion.data.blocks
            .where((item) => item.id == block.id)
            .firstOrNull;
        expect(kept, isNotNull, reason: '已有安排 ${block.id} 不能被删除或重建');
        expect(kept!.toJson(), block.toJson());
      }
      expect(completion.addedBlocks, greaterThan(0));
      expect(completion.data.blocks.any((block) => block.date == end), isTrue);
      // 原有 3 天各 60 分钟之外，继续补到周期末。
      expect(
        completion.data.blocks.fold<int>(
          0,
          (sum, block) => sum + block.durationMinutes,
        ),
        28 * 60,
      );
    });

    test('second preview/confirm is idempotent', () {
      final data = rollingPlan();
      var ids = 0;
      String nextId() => 'new-${++ids}';
      final first = completePlanPeriod(
        data,
        today: today,
        nextId: nextId,
        timestamp: '2026-10-01T00:00:00.000Z',
      );
      final second = completePlanPeriod(
        first.data,
        today: today,
        nextId: nextId,
        timestamp: '2026-10-02T00:00:00.000Z',
      );
      expect(second.addedBlocks, 0);
      expect(second.scheduledMinutes, 0);
      expect(second.unscheduledMinutes, 0);
      expect(second.data.blocks.length, first.data.blocks.length);
      expect(second.data.planning!['mode'], 'full');
      expect(second.data.planning!['detail_days'], 28);
    });
  });

  group('capacity overrides drive the scheduler', () {
    test('date override zero is an explicit rest day, not a fallback', () {
      const start = '2026-10-12';
      final end = addDate(start, 2);
      final data = _plan(
        profile: _netProfile(start: start, end: end, dates: {start: 0}),
        tasks: [_task('t', 120, end)],
        planning: _fullPlanning(3, end),
      );
      final result = generatePlanBlocks(data, from: start, to: end);
      expect(
        result.data.blocks.any((block) => block.date == start),
        isFalse,
        reason: '显式 0 的日期是休息日，不能回退成默认容量',
      );
      expect(
        result.data.blocks.fold<int>(
          0,
          (sum, block) => sum + block.durationMinutes,
        ),
        120,
      );
    });

    test('week total override is distributed and respected', () {
      const monday = '2026-10-12';
      final sunday = addDate(monday, 6);
      final data = _plan(
        profile: _netProfile(
          start: monday,
          end: sunday,
          weeks: {monday: const WeekCapacityOverride(totalMinutes: 210)},
        ),
        tasks: [_task('t', 210, sunday)],
        planning: _fullPlanning(7, sunday),
      );
      final result = generatePlanBlocks(data, from: monday, to: sunday);
      final weekMinutes = result.data.blocks
          .where(
            (block) =>
                block.date.compareTo(monday) >= 0 &&
                block.date.compareTo(sunday) <= 0,
          )
          .fold<int>(0, (sum, block) => sum + block.durationMinutes);
      expect(weekMinutes, 210);
      expect(
        result.data.blocks.any(
          (block) =>
              block.date.compareTo(monday) >= 0 &&
              block.date.compareTo(sunday) <= 0,
        ),
        isTrue,
      );
    });
  });

  group('recordTaskDayMinutes preserves real records', () {
    TimeLog log(
      String id,
      int minutes, {
      TimeLogRelation relation = TimeLogRelation.legacyUnknown,
      LogSource source = LogSource.manual,
      String? blockId,
    }) => TimeLog(
      id: id,
      userId: 'u1',
      taskId: 't',
      blockId: blockId,
      date: '2026-10-12',
      minutes: minutes,
      startedAt: _stamp,
      endedAt: _stamp,
      source: source,
      relation: relation,
    );

    test(
      'keeps extra/ad_hoc/timer logs and rewrites only the manual total',
      () {
        final block = ScheduleBlock(
          id: 'block-1',
          userId: 'u1',
          taskId: 't',
          date: '2026-10-12',
          startMinute: 0,
          durationMinutes: 60,
          actualMinutes: 0,
          isFixed: false,
          status: BlockStatus.planned,
          createdAt: _stamp,
          updatedAt: _stamp,
        );
        final data = _plan(
          profile: _netProfile(start: '2026-10-12', end: '2026-10-18'),
          tasks: [_task('t', 600, '2026-10-18')],
          blocks: [block],
          logs: [
            log('extra-log', 20, relation: TimeLogRelation.extra),
            log(
              'timer-scheduled',
              5,
              relation: TimeLogRelation.scheduled,
              source: LogSource.timer,
            ),
            log('legacy-manual', 10, blockId: 'block-1'),
          ],
        );
        var nextId = 0;
        final result = recordTaskDayMinutes(
          data,
          't',
          '2026-10-12',
          60,
          runtime: SchedulerRuntime(
            now: DateTime.parse('2026-10-12T00:00:00.000Z'),
            nextId: () => 'rebuilt-${++nextId}',
          ),
        );
        final ids = result.logs.map((log) => log.id).toSet();
        expect(ids, contains('extra-log'));
        expect(ids, contains('timer-scheduled'));
        expect(ids, isNot(contains('legacy-manual')));
        final rebuilt = result.logs.where(
          (log) => log.source == LogSource.manual && log.id != 'extra-log',
        );
        expect(rebuilt.fold<int>(0, (sum, log) => sum + log.minutes), 60);
        expect(
          result.logs.fold<int>(0, (sum, log) => sum + log.minutes),
          85,
          reason: '总用时包含加学与计时记录，但当天合计只重建 manual 部分',
        );
        expect(result.tasks.single.completedMinutes, 85);
        // 原定达成只由 scheduled/legacy 覆盖，加学不冒充原定执行。
        expect(result.blocks.single.actualMinutes, 60);
      },
    );
  });

  group('capacity change impact preview', () {
    test('reports unscheduled true-deadline items', () {
      const today = '2026-10-12';
      final end = addDate(today, 2);
      final data = _plan(
        profile: _netProfile(start: today, end: end),
        tasks: [_task('t', 500, addDate(today, 1))],
      );
      final adjustment = reschedulePlan(
        data,
        today: today,
        start: today,
        end: end,
      );
      expect(adjustment.unscheduledMinutes, greaterThan(0));
      expect(adjustment.realDeadlineImpacts, isNotEmpty);
      expect(adjustment.realDeadlineImpacts.join(), contains('真实截止日期'));
    });
  });
}
