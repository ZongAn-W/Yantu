// Independent acceptance (WS-V): capacity dedup + three learning relations (§7, §9, §10).
//
// Drives the production domain functions (`study_day.dart`) with hand-built plans that
// mirror the requirement's acceptance examples, and asserts the documented numbers
// directly (not through UI copy or golden text):
//   - §10.1 net 120 / maths planned 60 learned 30 / photography 20
//     => actual 50, reserved 30, available 40 (never 120-60-30-20=10);
//   - §9.5 planned 60 actually studied 90 => total 90, original plan capped 60, extra 30;
//   - §10.1/§13 same task/day scheduled + active extra do not merge or double count;
//   - §10.1 legacy logs with block_id == null are not automatically "outside plan";
//   - §10.2 achievement: maths+english 60 each, only maths studied 120 => english is not done;
//   - §8 ad-hoc temporary learning with a null task id counts once and never as plan;
//   - §10.1 zero-capacity day / real work can still be recorded (over budget, not dropped).
//
// Run from apps/flutter_client:
//   flutter test --no-pub test/acceptance/capacity_dedup_acceptance_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

const acceptanceDate = '2026-10-18';
const acceptanceStamp = '2026-10-18T00:00:00.000Z';

PlannerData legacyBase() => PlannerData.fromJson(
    jsonDecode(File('test/fixtures/planner_v1.json').readAsStringSync()) as JsonMap);

Profile netProfile(int dayMinutes) => legacyBase().profile.copyWith(
      capacityBasis: CapacityBasis.net,
      weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': dayMinutes},
      dailyLimitMinutes: 480,
      bufferMinutes: 30,
      granularityMinutes: 30,
    );

final base = legacyBase();
final uid = base.profile.userId;
final mathTask = base.tasks.first
    .copyWith(id: 'task-math', title: '线性代数第三章', deadline: '2026-12-31');
final englishTask = base.tasks.first
    .copyWith(id: 'task-english', title: '英语阅读', deadline: '2026-12-31');

ScheduleBlock block(
  String taskId, {
  String? id,
  int duration = 60,
  BlockStatus status = BlockStatus.planned,
  String date = acceptanceDate,
}) =>
    ScheduleBlock(
      id: id ?? 'block-$taskId-$date-$duration',
      userId: uid,
      taskId: taskId,
      date: date,
      startMinute: 0,
      durationMinutes: duration,
      actualMinutes: 0,
      isFixed: false,
      status: status,
      createdAt: acceptanceStamp,
      updatedAt: acceptanceStamp,
    );

TimeLog log(
  String id, {
  String? taskId,
  String? blockId,
  required int minutes,
  TimeLogRelation relation = TimeLogRelation.legacyUnknown,
  String? adHocId,
  String? sessionId,
  LogSource source = LogSource.timer,
  String date = acceptanceDate,
}) =>
    TimeLog(
      id: id,
      userId: uid,
      taskId: taskId,
      blockId: blockId,
      date: date,
      minutes: minutes,
      startedAt: acceptanceStamp,
      endedAt: acceptanceStamp,
      source: source,
      relation: relation,
      sessionId: sessionId,
      adHocId: adHocId,
    );

AdHocLearning adHoc(String id, String title) => AdHocLearning(
      id: id,
      userId: uid,
      title: title,
      createdAt: acceptanceStamp,
      updatedAt: acceptanceStamp,
    );

PlannerData plan({
  required Profile profile,
  required List<Task> tasks,
  required List<ScheduleBlock> blocks,
  required List<TimeLog> logs,
  List<AdHocLearning> adHocLearnings = const [],
}) =>
    base.copyWith(
      profile: profile,
      tasks: tasks,
      blocks: blocks,
      logs: logs,
      adHocLearnings: adHocLearnings,
      fixedEvents: const [],
      replanRuns: const [],
      phases: const [],
    );

void main() {
  group('§10.1 容量去重关键验收算例', () {
    test('净120/数学原定60已学30/摄影20 => 实际50 预留30 可新增40', () {
      final data = plan(
        profile: netProfile(120),
        tasks: [mathTask],
        blocks: [block('task-math')],
        logs: [
          log('log-math-scheduled', taskId: 'task-math', minutes: 30,
              relation: TimeLogRelation.scheduled),
          log('log-photo-adhoc', minutes: 20,
              relation: TimeLogRelation.adHoc, adHocId: 'adhoc-photo'),
        ],
        adHocLearnings: [adHoc('adhoc-photo', '摄影构图')],
      );
      final breakdown = dayCapacityBreakdown(data, acceptanceDate);
      expect(breakdown.capacity, 120);
      expect(breakdown.planned, 60);
      expect(breakdown.actual, 50);
      expect(breakdown.scheduled, 30);
      expect(breakdown.adHoc, 20);
      expect(breakdown.reserved, 30);
      expect(breakdown.available, 40,
          reason: '不接受 120-60-30-20=10 的重复扣减结果');
      expect(breakdown.over, 0);
      // 实际投入每段只出现一次。
      expect(breakdown.actual,
          breakdown.scheduled + breakdown.extra + breakdown.adHoc + breakdown.legacyUnknown);
    });

    test('原定60实学90 => 总投入90，原定贡献封顶60，额外30单独计入', () {
      final data = plan(
        profile: netProfile(120),
        tasks: [mathTask],
        blocks: [block('task-math')],
        logs: [
          // 计时器在 60 分钟后把同一 session 拆成 scheduled 60 + extra 30。
          log('log-math-scheduled', taskId: 'task-math', minutes: 60,
              relation: TimeLogRelation.scheduled, sessionId: 'session-1'),
          log('log-math-extra', taskId: 'task-math', minutes: 30,
              relation: TimeLogRelation.extra, sessionId: 'session-1'),
        ],
      );
      final stats = dayStats(data, acceptanceDate);
      expect(stats.actual, 90);
      expect(stats.scheduled, 60);
      expect(stats.extra, 30);
      expect(scheduledMinutesForTaskDay(data, 'task-math', acceptanceDate), 60);
      final breakdown = dayCapacityBreakdown(data, acceptanceDate);
      expect(breakdown.actual, 90);
      expect(breakdown.reserved, 0, reason: '原定块已被 scheduled 执行覆盖，不再预留');
      expect(breakdown.available, 30);
    });

    test('旧 scheduled 日志超出原定额度时原定封顶，超出部分仍只计一次实际', () {
      final data = plan(
        profile: netProfile(120),
        tasks: [mathTask],
        blocks: [block('task-math')],
        logs: [
          log('log-legacy-oversize', taskId: 'task-math', minutes: 90,
              relation: TimeLogRelation.scheduled),
        ],
      );
      final stats = dayStats(data, acceptanceDate);
      expect(stats.actual, 90, reason: '真实用时不能因分类而丢失');
      expect(stats.scheduled, 60, reason: '原定达成最多按该事项当日额度封顶');
      expect(scheduledMinutesForTaskDay(data, 'task-math', acceptanceDate), 60);
      expect(stats.actual, stats.scheduled + stats.extra + stats.adHoc + stats.legacyUnknown);
    });

    test('同一事项同日原定+主动加学不因 task/date 汇总混淆', () {
      final data = plan(
        profile: netProfile(120),
        tasks: [mathTask],
        blocks: [block('task-math')],
        logs: [
          log('log-math-scheduled', taskId: 'task-math', minutes: 30,
              relation: TimeLogRelation.scheduled),
          log('log-math-extra', taskId: 'task-math', minutes: 40,
              relation: TimeLogRelation.extra),
        ],
      );
      final stats = dayStats(data, acceptanceDate);
      expect(stats.scheduled, 30);
      expect(stats.extra, 40);
      expect(stats.actual, 70);
      expect(extraMinutesForTaskDay(data, 'task-math', acceptanceDate), 40);
      expect(scheduledMinutesForTaskDay(data, 'task-math', acceptanceDate), 30);
      final breakdown = dayCapacityBreakdown(data, acceptanceDate);
      expect(breakdown.reserved, 30);
      expect(breakdown.available, 120 - 70 - 30);
    });
  });

  group('§10.2 达成率与内容进度分离', () {
    test('数学和英语各原定60，仅数学学120：英语不被算作完成', () {
      final data = plan(
        profile: netProfile(240),
        tasks: [mathTask, englishTask],
        blocks: [
          block('task-math', id: 'block-math'),
          block('task-english', id: 'block-english'),
        ],
        logs: [
          log('log-math-scheduled', taskId: 'task-math', minutes: 60,
              relation: TimeLogRelation.scheduled),
          log('log-math-extra', taskId: 'task-math', minutes: 60,
              relation: TimeLogRelation.extra),
        ],
      );
      final math = scheduledMinutesForTaskDay(data, 'task-math', acceptanceDate);
      final english = scheduledMinutesForTaskDay(data, 'task-english', acceptanceDate);
      expect(math, 60);
      expect(english, 0, reason: '其他事项的加学不能抵消未做的原定事项');
      final stats = dayStats(data, acceptanceDate);
      expect(stats.scheduled, 60, reason: '原定执行按事项分别封顶合计，不是总实际用时');
      expect(stats.actual, 120, reason: '数学实际学习 120 分钟全部保留');
    });

    test('临时学习不计入任何事项的原定达成', () {
      final data = plan(
        profile: netProfile(120),
        tasks: [mathTask],
        blocks: const [],
        logs: [
          log('log-photo', minutes: 25,
              relation: TimeLogRelation.adHoc, adHocId: 'adhoc-photo'),
        ],
        adHocLearnings: [adHoc('adhoc-photo', '摄影构图')],
      );
      expect(adHocMinutesOnDate(data, acceptanceDate), 25);
      expect(adHocTotalMinutes(data, 'adhoc-photo'), 25);
      final stats = dayStats(data, acceptanceDate);
      expect(stats.planned, 0);
      expect(stats.actual, 25);
      expect(stats.scheduled, 0);
      expect(stats.adHoc, 25);
      expect(scheduledMinutesForTaskDay(data, 'task-math', acceptanceDate), 0);
      // 费用只占一次容量。
      final breakdown = dayCapacityBreakdown(data, acceptanceDate);
      expect(breakdown.available, 120 - 25);
      expect(breakdown.over, 0);
    });
  });

  group('§9 旧日志分类与提前学习', () {
    test('block_id 为 null 的旧日志不自动视为计划外：有当日安排时有限推断原定', () {
      final data = plan(
        profile: netProfile(120),
        tasks: [mathTask],
        blocks: [block('task-math')],
        logs: [
          log('log-legacy-1', taskId: 'task-math', minutes: 30),
          log('log-legacy-2', taskId: 'task-math', minutes: 40),
        ],
      );
      final stats = dayStats(data, acceptanceDate);
      expect(stats.scheduled, 60,
          reason: '旧日志按当日剩余额度有限推断为原定，最多不超过原定 60');
      expect(stats.legacyUnknown, 10, reason: '超出推断额度的分钟保留为未知实际');
      expect(stats.actual, 70);
      expect(scheduledMinutesForTaskDay(data, 'task-math', acceptanceDate), 60);
    });

    test('没有当日安排的旧日志保持未知，不冒充原定执行', () {
      final data = plan(
        profile: netProfile(120),
        tasks: [mathTask],
        blocks: const [],
        logs: [log('log-legacy-free', taskId: 'task-math', minutes: 30)],
      );
      final stats = dayStats(data, acceptanceDate);
      expect(stats.scheduled, 0);
      expect(stats.legacyUnknown, 30);
      expect(stats.actual, 30, reason: '无 blockId 的既有计时仍然是真实投入');
      expect(scheduledMinutesForTaskDay(data, 'task-math', acceptanceDate), 0);
      expect(dayCapacityBreakdown(data, acceptanceDate).actual, 30);
    });

    test('零容量日仍允许记录真实学习并显示超出，不删除记录', () {
      final profile = netProfile(120).copyWith(
        dateCapacityOverrides: {acceptanceDate: 0},
      );
      final data = plan(
        profile: profile,
        tasks: [mathTask],
        blocks: const [],
        logs: [
          log('log-extra-on-rest', taskId: 'task-math', minutes: 35,
              relation: TimeLogRelation.extra),
        ],
      );
      final breakdown = dayCapacityBreakdown(data, acceptanceDate);
      expect(breakdown.capacity, 0);
      expect(breakdown.actual, 35);
      expect(breakdown.over, 35);
      expect(data.logs.single.minutes, 35);
    });
  });
}
