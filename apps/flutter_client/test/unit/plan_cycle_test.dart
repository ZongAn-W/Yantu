import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/application/onboarding_controller.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/plan_cycle.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

PlannerData openGoalPlan({
  Map<String, int> weekly = const {
    '0': 0,
    '1': 120,
    '2': 120,
    '3': 120,
    '4': 120,
    '5': 120,
    '6': 0,
  },
  String start = '2026-10-12',
  String end = '2026-10-25',
}) {
  final base = plannerFixture();
  return base.copyWith(
    profile: base.profile.copyWith(
      goalText: '从零学习 Python，能独立处理 CSV',
      goalType: GoalType.skill,
      goalSubtype: '',
      targetDate: '',
      examDate: '',
      examEndDate: '',
      planStartDate: start,
      planEndDate: end,
      weeklyMinutes: weekly,
      dailyLimitMinutes: 180,
      bufferMinutes: 30,
    ),
    tasks: [
      Task(
        id: 'python-1',
        userId: base.profile.userId,
        tagIds: const [],
        title: '基础练习',
        estimatedMinutes: 600,
        completedMinutes: 0,
        priority: 2,
        deadline: end,
        deadlineKind: ItemDateKind.planEnd,
        earliestDate: start,
        isFixed: false,
        status: TaskStatus.notStarted,
        createdAt: '2026-10-01T00:00:00Z',
        updatedAt: '2026-10-01T00:00:00Z',
      ),
    ],
    blocks: const [],
    logs: const [],
    fixedEvents: const [],
  );
}

void main() {
  test('a goal without a target date never fabricates a countdown', () {
    final data = openGoalPlan();
    expect(data.profile.resolvedTargetDate, isEmpty);
    final line = dashboardGoalLine(data.profile, '2026-10-12');
    expect(line.contains('距离'), isFalse);
    expect(line.contains('本次规划还剩'), isTrue);
    expect(goalStatusLine(data.profile, '2026-10-12'), contains('本次规划'));
  });

  test(
    'an ended cycle is reported as ended instead of a negative countdown',
    () {
      final data = openGoalPlan(start: '2026-09-01', end: '2026-09-14');
      expect(planCycleState(data.profile, '2026-10-12'), PlanCycleState.ended);
      expect(dashboardGoalLine(data.profile, '2026-10-12'), contains('已结束'));
    },
  );

  test('zero-minute weekdays never receive study blocks', () {
    final data = openGoalPlan();
    final result = generatePlanBlocks(
      data,
      from: '2026-10-12',
      to: '2026-10-25',
      timestamp: '2026-10-12T00:00:00Z',
      nextId: () => 'block-${DateTime.now().microsecondsSinceEpoch}',
    );
    expect(result.blocks, greaterThan(0));
    final dates = result.data.blocks.map((block) => block.date).toSet();
    expect(dates.contains('2026-10-17'), isFalse, reason: '周六休息');
    expect(dates.contains('2026-10-18'), isFalse, reason: '周日休息');
    for (final date in dates) {
      final minutes = result.data.blocks
          .where((block) => block.date == date)
          .fold<int>(0, (sum, block) => sum + block.durationMinutes);
      expect(minutes, lessThanOrEqualTo(90), reason: '每天 120 分钟预算扣掉 30 分钟机动');
    }
  });

  test(
    'generating the same cycle twice does not duplicate existing blocks',
    () {
      final first = generatePlanBlocks(
        openGoalPlan(),
        from: '2026-10-12',
        to: '2026-10-25',
      );
      final second = generatePlanBlocks(
        first.data,
        from: '2026-10-12',
        to: '2026-10-25',
      );
      expect(second.blocks, 0);
      expect(second.data.blocks.length, first.data.blocks.length);
    },
  );

  test(
    'extending the cycle moves plan boundaries but keeps real deadlines',
    () {
      final data = openGoalPlan();
      final withDeadline = data.copyWith(
        tasks: [
          ...data.tasks,
          data.tasks.first.copyWith(
            id: 'exam-1',
            title: '期末考试',
            deadlineKind: ItemDateKind.deadline,
            deadline: '2026-10-20',
          ),
        ],
      );
      final extended = extendPlanCycle(
        withDeadline,
        start: '2026-10-26',
        end: '2026-11-22',
        today: '2026-10-12',
      );
      expect(extended.profile.planStartDate, '2026-10-26');
      expect(extended.profile.planEndDate, '2026-11-22');
      expect(
        extended.tasks.firstWhere((task) => task.id == 'python-1').deadline,
        '2026-11-22',
      );
      expect(
        extended.tasks.firstWhere((task) => task.id == 'exam-1').deadline,
        '2026-10-20',
      );
    },
  );

  test('settings validation reports the current operation', () {
    final data = openGoalPlan();
    final draft = ProfileSettingsDraft.from(data.profile, today: '2026-10-12');
    expect(validateSettingsDraft(draft), isNull);
    expect(validateSettingsDraft(draft.copyWith(planEndDate: '')), '请选择规划结束日期');
    expect(
      validateSettingsDraft(draft.copyWith(planEndDate: '2026-10-01')),
      '规划结束日期不能早于开始日期',
    );
    expect(
      validateSettingsDraft(
        draft.copyWith(
          weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 0},
        ),
      ),
      contains('机动'),
    );
  });

  test('plan date or weekly changes require the preview and confirm flow', () {
    final data = openGoalPlan();
    final draft = ProfileSettingsDraft.from(data.profile, today: '2026-10-12');
    expect(settingsAffectSchedule(data, draft), isFalse);
    expect(
      settingsAffectSchedule(data, draft.copyWith(planEndDate: '2026-11-22')),
      isTrue,
    );
    expect(
      settingsAffectSchedule(
        data,
        draft.copyWith(weeklyMinutes: {...draft.weeklyMinutes, '1': 60}),
      ),
      isTrue,
    );
  });

  test('removing one day moves its adjustable work instead of keeping it', () {
    const start = '2026-10-12';
    const end = '2026-10-18';
    final base = openGoalPlan(
      start: start,
      end: end,
      weekly: const {
        '0': 120,
        '1': 120,
        '2': 120,
        '3': 120,
        '4': 120,
        '5': 120,
        '6': 120,
      },
    );
    final generated = generatePlanBlocks(base, from: start, to: end);
    final mondayLoad = generated.data.blocks
        .where((block) => block.date == start)
        .fold<int>(0, (sum, block) => sum + block.durationMinutes);
    expect(mondayLoad, 90, reason: '周一 120 分钟预算扣除 30 分钟机动');

    final relaxed = generated.data.copyWith(
      profile: generated.data.profile.copyWith(
        weeklyMinutes: {
          for (var day = 0; day < 7; day++) '$day': day == 1 ? 0 : 120,
        },
      ),
    );
    final adjustment = reschedulePlan(
      relaxed,
      today: start,
      start: start,
      end: end,
    );
    expect(adjustment.afterLoad[start], 0);
    expect(adjustment.releasedBlocks, greaterThan(0));
    // 未安排的工作量仍然可见，不会被静默丢弃。
    expect(adjustment.unscheduledMinutes, greaterThan(0));
    for (final entry in adjustment.afterLoad.entries) {
      if (entry.key == start) continue;
      expect(entry.value, lessThanOrEqualTo(90), reason: '其他日期按各自预算安排');
    }
  });

  test('a recorded rest day keeps its history and explains the conflict', () {
    const start = '2026-10-12';
    const end = '2026-10-18';
    final base = openGoalPlan(
      start: start,
      end: end,
      weekly: const {
        '0': 120,
        '1': 120,
        '2': 120,
        '3': 120,
        '4': 120,
        '5': 120,
        '6': 120,
      },
    );
    final generated = generatePlanBlocks(base, from: start, to: end).data;
    final mondayBlock = generated.blocks.firstWhere(
      (block) => block.date == start,
    );
    final logged = generated.copyWith(
      blocks: [
        for (final block in generated.blocks)
          block.id == mondayBlock.id
              ? block.copyWith(actualMinutes: 30)
              : block,
      ],
      logs: [
        TimeLog(
          id: 'log-monday',
          userId: generated.profile.userId,
          taskId: mondayBlock.taskId,
          blockId: mondayBlock.id,
          date: start,
          minutes: 30,
          startedAt: '2026-10-12T00:00:00Z',
          endedAt: '2026-10-12T00:00:00Z',
          source: LogSource.manual,
        ),
      ],
      profile: generated.profile.copyWith(
        weeklyMinutes: {
          for (var day = 0; day < 7; day++) '$day': day == 1 ? 0 : 120,
        },
      ),
    );
    final adjustment = reschedulePlan(
      logged,
      today: start,
      start: start,
      end: end,
    );
    // 已记录用时的安排必须保留，并给出可理解的说明。
    expect(
      adjustment.data.blocks.any((block) => block.id == mondayBlock.id),
      isTrue,
    );
    expect(adjustment.notes.join('\n'), contains('休息日'));
    expect(adjustment.data.logs, hasLength(1));
  });

  test(
    'shortening the cycle removes adjustable work outside the new window',
    () {
      const start = '2026-10-12';
      final base = openGoalPlan(start: start, end: '2026-10-25');
      final generated = generatePlanBlocks(
        base,
        from: start,
        to: '2026-10-25',
      ).data;
      expect(
        generated.blocks.any((block) => block.date.compareTo('2026-10-16') > 0),
        isTrue,
        reason: '缩短前存在新边界之外的安排',
      );
      final adjustment = reschedulePlan(
        generated,
        today: start,
        start: start,
        end: '2026-10-16',
      );
      expect(
        adjustment.data.blocks.every(
          (block) => block.date.compareTo('2026-10-16') <= 0,
        ),
        isTrue,
      );
      // 预览会保留被清空日期的键（用于显示 X → 0），但新边界之外不再有安排。
      for (final entry in adjustment.afterLoad.entries) {
        if (entry.key.compareTo('2026-10-16') > 0) {
          expect(entry.value, 0, reason: '新边界之外不再安排学习');
        }
      }
      expect(adjustment.unscheduledMinutes, greaterThan(0));
    },
  );

  test('fixed, completed and historical arrangements stay untouched', () {
    const start = '2026-10-12';
    final base = openGoalPlan(start: start, end: '2026-10-18');
    final generated = generatePlanBlocks(
      base,
      from: start,
      to: '2026-10-18',
    ).data;
    final target = generated.blocks.firstWhere(
      (block) => block.date == '2026-10-13',
    );
    final protected = generated.copyWith(
      blocks: [
        for (final block in generated.blocks)
          block.id == target.id
              ? block.copyWith(isFixed: true, durationMinutes: 120)
              : block,
      ],
      profile: generated.profile.copyWith(
        weeklyMinutes: {
          for (var day = 0; day < 7; day++) '$day': day == 2 ? 0 : 120,
        },
      ),
    );
    final adjustment = reschedulePlan(
      protected,
      today: start,
      start: start,
      end: '2026-10-18',
    );
    final kept = adjustment.data.blocks.firstWhere(
      (block) => block.id == target.id,
    );
    expect(kept.isFixed, isTrue);
    expect(kept.durationMinutes, 120);
  });

  test('applying the same constraints twice converges', () {
    const start = '2026-10-12';
    final base = openGoalPlan(start: start, end: '2026-10-18');
    final generated = generatePlanBlocks(
      base,
      from: start,
      to: '2026-10-18',
    ).data;
    final relaxed = generated.copyWith(
      profile: generated.profile.copyWith(
        weeklyMinutes: {
          for (var day = 0; day < 7; day++) '$day': day == 3 ? 60 : 120,
        },
      ),
    );
    final first = reschedulePlan(
      relaxed,
      today: start,
      start: start,
      end: '2026-10-18',
    );
    final second = reschedulePlan(
      first.data,
      today: start,
      start: start,
      end: '2026-10-18',
    );
    expect(second.afterLoad, first.afterLoad);
    expect(second.unscheduledMinutes, first.unscheduledMinutes);
  });

  test('a larger buffer reduces daily capacity and requires the preview', () {
    final data = openGoalPlan(start: '2026-10-12', end: '2026-10-18');
    final draft = ProfileSettingsDraft.from(data.profile, today: '2026-10-12');
    expect(
      settingsAffectSchedule(data, draft.copyWith(bufferMinutes: 60)),
      isTrue,
    );
    expect(
      settingsAffectSchedule(data, draft.copyWith(planStartDate: '2026-10-13')),
      isTrue,
    );
    expect(settingsAffectSchedule(data, draft), isFalse);
    // 目标描述和目标日期不影响已有安排，不触发重排。
    expect(
      settingsAffectSchedule(
        data,
        draft.copyWith(targetDate: '2027-06-01', goalText: '新的目标描述'),
      ),
      isFalse,
    );
  });
}
