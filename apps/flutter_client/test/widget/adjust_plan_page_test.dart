import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/adjust/data/plan_adjust_api.dart';
import 'package:sjtu_study_planner_client/features/adjust/presentation/adjust_plan_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

const _stamp = '2026-01-01T00:00:00.000Z';

/// 一份「相对今天」的小计划，覆盖真实截止、本期边界、已超预算（clamp 到 100%）
/// 与近 7 天用时，供调整页四个面板渲染。
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

/// 一份符合设计 §3 的预览 JSON：too_light 结论、延长周期、提高强度、
/// 调整 + 新增事项、释放/重排安排、一条截止风险、提醒与说明。
Map<String, dynamic> _previewJson() {
  final today = shanghaiToday();
  return {
    'id': 'job-9',
    'base_revision': 1,
    'assessment': '目标需要约 1500–2500 小时，当前计划仅 400 小时，明显偏轻；'
        '因此延长周期、提高每周投入，并补上真题与政治强化。',
    'verdict': 'too_light',
    'hours': {
      'current_minutes': 24000,
      'next_minutes': 108000,
      'remaining_minutes': 96000,
      'required_min_minutes': 90000,
      'required_max_minutes': 150000,
    },
    'cycle': {
      'start_date': addDate(today, -3),
      'previous_end_date': addDate(today, 25),
      'end_date': addDate(today, 300),
      'previous_days': 29,
      'days': 304,
      'remaining_days': 301,
    },
    'intensity': {
      'previous_weekly_minutes': 840,
      'weekly_minutes': 1800,
      'reason': '近期实际每周约 11 小时，目标需要提高投入',
    },
    'workload': {
      'updated_tasks': [
        {
          'task_id': 't1',
          'title': '基础一轮',
          'subject': '高数',
          'previous_minutes': 600,
          'minutes': 1200,
          'reason': '补齐章节练习',
        },
      ],
      'new_tasks': [
        {
          'title': '408 真题 15 套',
          'subject': '408',
          'minutes': 9000,
          'deadline_kind': 'plan_end',
          'deadline': addDate(today, 300),
          'reason': '补齐目标所需学习量',
        },
      ],
      'subjects': [
        {
          'subject_id': 's1',
          'name': '高数',
          'previous_minutes': 600,
          'minutes': 1500,
        },
      ],
    },
    'schedule': {
      'protected_blocks': 2,
      'released_blocks': 5,
      'released_minutes': 300,
      'added_blocks': 8,
      'added_minutes': 480,
      'unscheduled_minutes': 0,
    },
    'deadline_risks': [
      {
        'task_id': 't2',
        'title': '线性代数强化',
        'deadline': addDate(today, 20),
        'unscheduled_minutes': 60,
      },
    ],
    'warnings': ['调整后总时长仍低于目标所需下限'],
    'notes': ['规划周期延长到目标日期前一天；真实截止日期未改动'],
  };
}

PlanAdjustPreview _preview() => PlanAdjustPreview.fromJson(_previewJson());

/// 深拷贝为可变 `Map<String, dynamic>`：`_previewJson()` 的嵌套字面量会被推断成
/// `Map<String, int>` 等更窄类型，直接塞入错误类型/ null 会触发运行时类型错误。
Map<String, dynamic> _mutablePreviewJson() =>
    jsonDecode(jsonEncode(_previewJson())) as Map<String, dynamic>;

/// 记录调用的 fake 调整接口；可注入失败模拟 409 / 502。
class _FakePlanAdjustApi implements PlanAdjustApi {
  _FakePlanAdjustApi() : preview = PlanAdjustPreview.fromJson(_previewJson());

  final PlanAdjustPreview preview;
  int createCalls = 0;
  int? expectedRevision;
  String? requestId;
  int confirmCalls = 0;
  String? confirmedId;
  int? confirmedRevision;
  Object? createError;
  Object? confirmError;

  @override
  Future<PlanAdjustPreview> create({
    required int expectedRevision,
    required String requestId,
  }) async {
    createCalls += 1;
    this.expectedRevision = expectedRevision;
    this.requestId = requestId;
    if (createError != null) throw createError!;
    return preview;
  }

  @override
  Future<void> confirm(String id, {required int expectedRevision}) async {
    confirmCalls += 1;
    confirmedId = id;
    confirmedRevision = expectedRevision;
    if (confirmError != null) throw confirmError!;
  }
}

/// 同步占位实现：页面测试覆盖了 [PlannerSession.sync]，因此不会被真正调用。
class _NoopSyncApi implements SyncApi {
  @override
  Future<RemoteSnapshot> pull({int? revision}) async =>
      RemoteSnapshot(null, revision ?? 0);

  @override
  Future<RemoteSnapshot> push(
    PlannerData data,
    PlannerData? base,
    int revision,
  ) async => RemoteSnapshot(base ?? data, revision);
}

/// 只覆盖 [PlannerSession.sync] 的会话：确认后页面会调用它拉取新计划，
/// 测试里不需要真实网络与本机数据库。
class _FakePlannerSession extends PlannerSession {
  _FakePlannerSession()
    : super(
        PlannerCoordinator(
          userId: 'u1',
          scope: 'adjust-page-test',
          storage: MemoryStorageRepository(),
          api: _NoopSyncApi(),
          retryInterval: null,
        ),
      );

  int syncCalls = 0;
  Object? syncError;

  @override
  Future<void> sync() async {
    syncCalls += 1;
    if (syncError != null) throw syncError!;
  }
}

class _Harness {
  const _Harness({required this.api, required this.session});

  final _FakePlanAdjustApi api;
  final _FakePlannerSession session;
}

void _useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _useNarrow(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<_Harness> _mount(
  WidgetTester tester, {
  required PlannerData data,
  bool pending = false,
  int revision = 1,
  _FakePlanAdjustApi? api,
}) async {
  final fakeApi = api ?? _FakePlanAdjustApi();
  final session = _FakePlannerSession();
  addTearDown(session.coordinator.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plannerDataProvider.overrideWithValue(
          PlannerSnapshot(
            data: data,
            revision: revision,
            pending: pending,
            status: SyncStatus.connected,
            message: '',
            blocked: false,
            ready: true,
            busy: false,
            conflicts: const [],
          ),
        ),
        planAdjustApiProvider.overrideWithValue(fakeApi),
        plannerSessionProvider.overrideWithValue(session),
      ],
      child: MaterialApp(
        theme: plannerTheme(),
        home: const Scaffold(body: AdjustPlanPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(api: fakeApi, session: session);
}

/// SnackBar 的 4 秒自动消失计时器在入场动画结束后才启动；推进到退场结束，
/// 避免测试结束时还挂着计时器。
Future<void> _drainSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> _tapApply(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('adjust-apply')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('adjust-apply')));
  await tester.pumpAndSettle();
}

void main() {
  group('PlanAdjustPreview 解析（契约 §3）', () {
    test('解析全部字段', () {
      final preview = _preview();
      expect(preview.id, 'job-9');
      expect(preview.baseRevision, 1);
      expect(preview.assessment, isNotEmpty);
      expect(preview.verdict, PlanAdjustVerdict.tooLight);
      expect(preview.verdict.label, '强度/总量偏轻');
      expect(preview.hours.currentMinutes, 24000);
      expect(preview.hours.requiredMaxMinutes, 150000);
      expect(preview.cycle.deltaDays, 275);
      expect(preview.cycle.remainingDays, 301);
      expect(preview.intensity.previousWeeklyMinutes, 840);
      expect(preview.intensity.weeklyMinutes, 1800);
      expect(preview.workload.updatedTasks.single.title, '基础一轮');
      expect(preview.workload.newTasks.single.minutes, 9000);
      expect(
        preview.workload.newTasks.single.deadlineKind,
        ItemDateKind.planEnd,
      );
      expect(preview.workload.subjects.single.name, '高数');
      expect(preview.schedule.protectedBlocks, 2);
      expect(preview.deadlineRisks.single.taskId, 't2');
      expect(preview.warnings, hasLength(1));
      expect(preview.notes, hasLength(1));
      expect(preview.withId('job-10').id, 'job-10');
    });

    test('数值缺失或类型错误抛 ResponseFailure', () {
      final missingHours = _mutablePreviewJson()..remove('hours');
      expect(
        () => PlanAdjustPreview.fromJson(missingHours),
        throwsA(isA<ResponseFailure>()),
      );

      final brokenHours = _mutablePreviewJson();
      (brokenHours['hours'] as Map<String, dynamic>)['current_minutes'] =
          '24000';
      expect(
        () => PlanAdjustPreview.fromJson(brokenHours),
        throwsA(isA<ResponseFailure>()),
      );

      final brokenCycle = _mutablePreviewJson();
      (brokenCycle['cycle'] as Map<String, dynamic>)['days'] = null;
      expect(
        () => PlanAdjustPreview.fromJson(brokenCycle),
        throwsA(isA<ResponseFailure>()),
      );

      final unknownVerdict = _mutablePreviewJson()..['verdict'] = 'unknown';
      expect(
        () => PlanAdjustPreview.fromJson(unknownVerdict),
        throwsA(isA<ResponseFailure>()),
      );
    });

    test('legacy_default 的周容量 null 可解析（预览显示未设置）', () {
      final json = _mutablePreviewJson();
      final intensity = json['intensity'] as Map<String, dynamic>;
      intensity['previous_weekly_minutes'] = null;
      intensity['weekly_minutes'] = null;
      final preview = PlanAdjustPreview.fromJson(json);
      expect(preview.intensity.previousWeeklyMinutes, isNull);
      expect(preview.intensity.weeklyMinutes, isNull);
    });
  });

  test('HttpPlanAdjustApi 带幂等键、用响应 id 覆盖预览并校验确认结果', () async {
    final client = _RecordingApiClient();
    final api = HttpPlanAdjustApi(client);

    client.responseData = {
      'id': 'job-9',
      'preview': _previewJson()..['id'] = 'preview-inner',
    };
    final preview = await api.create(expectedRevision: 7, requestId: 'req-1');
    expect(client.paths.single, '/api/ai/plan-adjustments');
    expect(client.bodies.single, {
      'expectedRevision': 7,
      'requestId': 'req-1',
    });
    expect(client.options.single?.headers?['Idempotency-Key'], 'req-1');
    expect(preview.id, 'job-9');

    client.responseData = {'confirmed': true};
    await api.confirm('job-9', expectedRevision: 7);
    expect(client.paths.last, '/api/ai/plan-adjustments/job-9/confirm');
    expect(client.bodies.last, {'expectedRevision': 7});

    client.responseData = {'confirmed': false};
    await expectLater(
      api.confirm('job-9', expectedRevision: 7),
      throwsA(isA<ResponseFailure>()),
    );

    client.responseData = {'id': 'job-9'};
    await expectLater(
      api.create(expectedRevision: 7, requestId: 'req-2'),
      throwsA(isA<ResponseFailure>()),
    );
  });

  testWidgets('渲染人物画像、学习进度、近期学习时间与一键调整四个区块（AI 口径）', (
    tester,
  ) async {
    _useDesktop(tester);
    await _mount(tester, data: _data());

    expect(find.text('调整学习计划'), findsOneWidget);
    expect(find.textContaining('让 AI 审查并调整后续安排'), findsOneWidget);
    expect(find.byKey(const Key('adjust-profile')), findsOneWidget);
    expect(find.byKey(const Key('adjust-progress')), findsOneWidget);
    expect(find.byKey(const Key('adjust-capacity')), findsOneWidget);
    expect(find.byKey(const Key('adjust-apply')), findsOneWidget);

    // 人物画像与学习进度保持原样。
    expect(find.textContaining('预计目标日期'), findsOneWidget);
    expect(find.textContaining('上海交通大学'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('adjust-total-actual'))).data,
      '30分钟',
    );
    expect(find.textContaining('完成 2小时 / 预算 10小时 · 20%'), findsOneWidget);

    // 近期学习时间：今天起 7 天与最近 7 天实际用时。
    for (var index = 0; index < 7; index++) {
      expect(
        find.byKey(Key('adjust-capacity-day-${addDate(shanghaiToday(), index)}')),
        findsOneWidget,
      );
    }
    expect(
      tester.widget<Text>(find.byKey(const Key('adjust-recent-actual'))).data,
      '30分钟',
    );

    // 一键调整：统计项保留，文案改为 AI 审查口径并提示耗时。
    expect(find.text('剩余天数'), findsOneWidget);
    expect(find.text('待安排事项'), findsOneWidget);
    expect(find.text('剩余工作量'), findsNWidgets(2));
    expect(find.text('一键调整后续计划'), findsOneWidget);
    expect(
      find.textContaining('AI 会审查目标所需时长与当前计划是否匹配'),
      findsOneWidget,
    );
    expect(find.textContaining('可能需要 1–2 分钟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏下页面滚动到一键调整按钮且不横向溢出', (tester) async {
    _useNarrow(tester);
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

  testWidgets('未同步修改时点击一键调整只提示等待，不发起 AI 请求', (tester) async {
    _useDesktop(tester);
    final harness = await _mount(tester, data: _data(), pending: true);

    await _tapApply(tester);
    expect(harness.api.createCalls, 0);
    expect(find.text('本机修改尚未同步，请等待同步完成后再调整'), findsOneWidget);
    await _drainSnackBar(tester);

    // 提示后按钮仍可用（同步完成后可直接重试）。
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('adjust-apply')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击一键调整调用 create 并以快照 revision 请求，随后展示 AI 预览', (
    tester,
  ) async {
    _useDesktop(tester);
    final harness = await _mount(tester, data: _data(), revision: 4);

    await _tapApply(tester);

    expect(harness.api.createCalls, 1);
    expect(harness.api.expectedRevision, 4);
    expect(harness.api.requestId, isNotNull);
    expect(harness.api.requestId, isNotEmpty);

    // 预览对话框：结论、assessment、时长、周期、强度、工作量、日程、风险、提醒。
    expect(find.text('预览 AI 调整方案'), findsOneWidget);
    expect(find.byKey(const Key('plan-adjust-verdict')), findsOneWidget);
    expect(find.text('强度/总量偏轻'), findsOneWidget);
    expect(find.byKey(const Key('plan-adjust-assessment')), findsOneWidget);
    expect(
      find.textContaining('目标需要约 1500–2500 小时'),
      findsOneWidget,
    );
    expect(find.text('1500–2500 小时'), findsOneWidget);
    expect(find.text('400 小时'), findsOneWidget);
    expect(find.text('1800 小时'), findsOneWidget);
    expect(find.byKey(const Key('plan-adjust-cycle-new')), findsOneWidget);
    expect(find.textContaining('+275 天'), findsOneWidget);
    expect(find.byKey(const Key('plan-adjust-intensity')), findsOneWidget);
    expect(find.textContaining('+114%'), findsOneWidget);
    expect(find.text('10 → 20 小时'), findsOneWidget);
    expect(find.text('408 真题 15 套'), findsOneWidget);
    expect(find.text('新增 150 小时'), findsOneWidget);
    expect(find.text('10 → 25 小时'), findsOneWidget);
    expect(find.text('保持不变（保护）'), findsOneWidget);
    expect(find.text('仍未安排'), findsOneWidget);
    expect(find.textContaining('未排 1小时'), findsOneWidget);
    expect(find.text('调整后总时长仍低于目标所需下限'), findsOneWidget);
    expect(
      find.text('规划周期延长到目标日期前一天；真实截止日期未改动'),
      findsOneWidget,
    );
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确认并应用'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 取消不 confirm、不写数据，按钮恢复可用。
    await tester.tap(find.byKey(const Key('plan-adjust-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('预览 AI 调整方案'), findsNothing);
    expect(harness.api.confirmCalls, 0);
    expect(harness.session.syncCalls, 0);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('adjust-apply')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认预览后调用 confirm 并拉取新计划', (tester) async {
    _useDesktop(tester);
    final harness = await _mount(tester, data: _data(), revision: 4);

    await _tapApply(tester);
    await tester.tap(find.byKey(const Key('plan-adjust-confirm')));
    await tester.pumpAndSettle();

    expect(harness.api.confirmCalls, 1);
    expect(harness.api.confirmedId, 'job-9');
    expect(harness.api.confirmedRevision, 4);
    expect(harness.session.syncCalls, 1);
    expect(find.text('预览 AI 调整方案'), findsNothing);
    expect(
      find.text('AI 已按目标、学习进度与近期学习时间重排后续计划。'),
      findsOneWidget,
    );
    await _drainSnackBar(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('adjust-apply')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认接口 409 时直接展示服务端消息且不拉取计划', (tester) async {
    _useDesktop(tester);
    final api = _FakePlanAdjustApi()
      ..confirmError = const ConflictFailure('计划已更新，请重新预览');
    final harness = await _mount(tester, data: _data(), api: api);

    await _tapApply(tester);
    await tester.tap(find.byKey(const Key('plan-adjust-confirm')));
    await tester.pumpAndSettle();

    expect(harness.api.confirmCalls, 1);
    expect(harness.session.syncCalls, 0);
    expect(find.text('计划已更新，请重新预览'), findsOneWidget);
    await _drainSnackBar(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('生成预览失败时展示可读错误并恢复按钮', (tester) async {
    _useDesktop(tester);
    final api = _FakePlanAdjustApi()
      ..createError = const ServerFailure('AI 服务暂不可用，请稍后重试');
    final harness = await _mount(tester, data: _data(), api: api);

    await _tapApply(tester);

    expect(harness.api.createCalls, 1);
    expect(find.text('AI 服务暂不可用，请稍后重试'), findsOneWidget);
    expect(find.text('预览 AI 调整方案'), findsNothing);
    await _drainSnackBar(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('adjust-apply')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认成功但拉取新计划失败时提示调整已提交', (tester) async {
    _useDesktop(tester);
    final harness = await _mount(tester, data: _data());
    harness.session.syncError = const OfflineFailure();

    await _tapApply(tester);
    await tester.tap(find.byKey(const Key('plan-adjust-confirm')));
    await tester.pumpAndSettle();

    expect(harness.api.confirmCalls, 1);
    expect(harness.session.syncCalls, 1);
    expect(
      find.textContaining('调整已提交，正在同步新计划'),
      findsOneWidget,
    );
    await _drainSnackBar(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('规划周期已结束时提示并禁用一键调整', (tester) async {
    _useDesktop(tester);
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

/// 记录请求的 fake [ApiClient]；不产生真实网络请求。
class _RecordingApiClient extends ApiClient {
  _RecordingApiClient()
    : super(
        config: const AppConfig(apiBaseUrl: 'http://test.local'),
        tokenStore: MemoryTokenStore(),
        dio: Dio(),
      );

  final List<String> paths = [];
  final List<Object?> bodies = [];
  final List<Options?> options = [];
  Object? responseData;

  @override
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Options? options,
  }) async {
    paths.add(path);
    bodies.add(data);
    this.options.add(options);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: path),
      data: responseData,
      statusCode: 200,
    );
  }
}
