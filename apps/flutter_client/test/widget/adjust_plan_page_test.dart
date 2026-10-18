import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/adjust/presentation/adjust_plan_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

const _stamp = '2026-01-01T00:00:00.000Z';

/// 一份「相对今天」的小计划，保证重排区间只有 20 多天，测试保持快速，
/// 同时覆盖真实截止、本期边界、已超预算（clamp 到 100%）和近 7 天用时。
PlannerData _data({String? planEnd}) {
  final today = shanghaiToday();
  final end = planEnd ?? addDate(today, 25);
  return PlannerData(
    version: 1,
    profile: Profile(
      userId: 'u1',
      goalText: '通过研究生入学考试',
      goalType: GoalType.exam,
      goalSubtype: '考研',
      targetDate: addDate(today, 300),
      targetDateConfirmed: false,
      planStartDate: addDate(today, -3),
      planEndDate: end,
      weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 120},
      constraints: '周三晚上有课',
      targetSchool: '上海交通大学',
      targetProgram: '计算机技术',
      dailyLimitMinutes: 480,
      granularityMinutes: 30,
      bufferMinutes: 30,
      subjectLimitMinutes: 240,
      studyStartMinute: 0,
      studyEndMinute: 1440,
      foundation: '高数基础一轮',
      capacityBasis: CapacityBasis.net,
    ),
    subjects: const [
      Subject(
        id: 's1',
        userId: 'u1',
        name: '高数',
        color: '#4565c7',
        priority: 3,
      ),
    ],
    tasks: [
      Task(
        id: 't1',
        userId: 'u1',
        subjectId: 's1',
        title: '基础一轮',
        estimatedMinutes: 600,
        completedMinutes: 120,
        priority: 2,
        deadline: addDate(today, 20),
        deadlineKind: ItemDateKind.deadline,
        isFixed: false,
        status: TaskStatus.inProgress,
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
      // 完成分钟超过预算：进度条和百分比必须封顶到 100%。
      Task(
        id: 't2',
        userId: 'u1',
        subjectId: 's1',
        title: '线性代数强化',
        estimatedMinutes: 300,
        completedMinutes: 360,
        priority: 1,
        deadline: end,
        deadlineKind: ItemDateKind.planEnd,
        isFixed: false,
        status: TaskStatus.inProgress,
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
    ],
    blocks: [
      ScheduleBlock(
        id: 'b1',
        userId: 'u1',
        taskId: 't1',
        date: today,
        startMinute: 0,
        durationMinutes: 60,
        actualMinutes: 0,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
      ScheduleBlock(
        id: 'b2',
        userId: 'u1',
        taskId: 't2',
        date: addDate(today, 1),
        startMinute: 60,
        durationMinutes: 30,
        actualMinutes: 0,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: _stamp,
        updatedAt: _stamp,
      ),
    ],
    logs: [
      TimeLog(
        id: 'l1',
        userId: 'u1',
        taskId: 't1',
        blockId: null,
        date: addDate(today, -1),
        minutes: 30,
        startedAt: _stamp,
        endedAt: _stamp,
        source: LogSource.manual,
        relation: TimeLogRelation.scheduled,
      ),
    ],
    fixedEvents: const [],
    replanRuns: const [],
    phases: const [],
  );
}

Future<void> _mount(WidgetTester tester, {required PlannerData data}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plannerDataProvider.overrideWithValue(
          PlannerSnapshot(
            data: data,
            revision: 1,
            pending: false,
            status: SyncStatus.connected,
            message: '',
            blocked: false,
            ready: true,
            busy: false,
            conflicts: const [],
          ),
        ),
      ],
      child: MaterialApp(
        theme: plannerTheme(),
        home: const Scaffold(body: AdjustPlanPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders 人物画像、学习进度、近期学习时间与一键调整四个区块', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final today = shanghaiToday();
    await _mount(tester, data: _data());

    expect(find.text('调整学习计划'), findsOneWidget);
    expect(find.textContaining('一键重排后续安排'), findsOneWidget);
    expect(find.byKey(const Key('adjust-profile')), findsOneWidget);
    expect(find.byKey(const Key('adjust-progress')), findsOneWidget);
    expect(find.byKey(const Key('adjust-capacity')), findsOneWidget);
    expect(find.byKey(const Key('adjust-apply')), findsOneWidget);

    // 人物画像：目标摘要、目标日期（含“预计”）、院校专业、进度与约束。
    expect(find.textContaining('预计目标日期'), findsOneWidget);
    expect(find.text('目标'), findsOneWidget);
    expect(find.text('目标日期'), findsOneWidget);
    expect(find.text('院校专业'), findsOneWidget);
    expect(find.textContaining('上海交通大学'), findsOneWidget);
    expect(find.text('当前进度'), findsOneWidget);
    expect(find.text('高数基础一轮'), findsOneWidget);
    expect(find.text('时间约束'), findsOneWidget);
    expect(find.text('周三晚上有课'), findsOneWidget);
    expect(find.text('继续访谈完善画像'), findsOneWidget);
    expect(find.text('修改目标与规划'), findsOneWidget);

    // 学习进度：累计实际、剩余工作量、lagging 状态与逐事项完成度。
    expect(find.text('累计实际学习'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('adjust-total-actual'))).data,
      '30分钟',
    );
    expect(find.text('进度状态'), findsOneWidget);
    expect(find.text('基础一轮'), findsOneWidget);
    expect(find.text('线性代数强化'), findsOneWidget);
    expect(
      find.textContaining('完成 2小时 / 预算 10小时 · 20%'),
      findsOneWidget,
    );
    expect(
      find.textContaining('完成 6小时 / 预算 5小时 · 100%'),
      findsOneWidget,
    );
    expect(find.text('真实截止 ${addDate(today, 20)}'), findsOneWidget);
    expect(find.text('本期边界 ${addDate(today, 25)}'), findsOneWidget);
    expect(find.text('查看完整进度'), findsOneWidget);
    expect(find.text('管理事项'), findsOneWidget);

    // 近期学习时间：今天起 7 天都可滚动查看，且最近 7 天实际用时可见。
    for (var index = 0; index < 7; index++) {
      expect(
        find.byKey(Key('adjust-capacity-day-${addDate(today, index)}')),
        findsOneWidget,
      );
    }
    expect(find.textContaining('可排 2小时'), findsNWidgets(7));
    expect(
      tester.widget<Text>(find.byKey(const Key('adjust-recent-actual'))).data,
      '30分钟',
    );
    expect(find.text('调整可用时间'), findsOneWidget);

    // 一键调整：规划区间、剩余天数、待安排事项与剩余工作量。
    final range =
        tester.widget<Text>(find.byKey(const Key('adjust-cycle-range'))).data ??
        '';
    expect(range, contains(addDate(today, -3)));
    expect(range, contains(addDate(today, 25)));
    expect(find.text('剩余天数'), findsOneWidget);
    expect(find.text('26 天'), findsOneWidget);
    expect(find.text('待安排事项'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);
    // 进度面板与一键调整面板各展示一次“剩余工作量”。
    expect(find.text('剩余工作量'), findsNWidgets(2));
    expect(find.text('一键调整后续计划'), findsOneWidget);
    expect(find.textContaining('真实截止日期不会被改写'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏下页面滚动到一键调整按钮且不横向溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _mount(tester, data: _data());

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('adjust-profile')), findsOneWidget);
    expect(find.byKey(const Key('adjust-progress')), findsOneWidget);
    expect(find.byKey(const Key('adjust-capacity')), findsOneWidget);
    expect(find.byKey(const Key('adjust-apply')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('adjust-apply')));
    await tester.pumpAndSettle();
    expect(find.text('一键调整后续计划'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击一键调整后续计划先展示日程调整预览', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _mount(tester, data: _data());

    await tester.ensureVisible(find.byKey(const Key('adjust-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adjust-apply')));
    await tester.pumpAndSettle();

    expect(find.text('预览日程调整'), findsOneWidget);
    expect(find.textContaining('规划区间：'), findsOneWidget);
    expect(find.text('已释放的未来安排'), findsOneWidget);
    expect(find.text('重新排入'), findsOneWidget);
    expect(find.text('仍未安排'), findsOneWidget);
    expect(find.text('确认并应用'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 取消预览不写入任何改动，按钮恢复可用。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('预览日程调整'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('adjust-apply')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('规划周期已结束时提示并禁用一键调整', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final today = shanghaiToday();
    await _mount(tester, data: _data(planEnd: addDate(today, -1)));

    expect(
      find.text('本期规划周期已结束，请先在今日页继续安排下一周期。'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('adjust-apply')))
          .onPressed,
      isNull,
    );
    expect(find.text('已结束'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
