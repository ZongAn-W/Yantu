import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/features/dashboard/presentation/dashboard_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/presentation/planner_dialogs.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const _quickStart = Key('dashboard-quick-start');
const _aiPlanning = Key('dashboard-ai-planning');
const _emptyTitle = '还没有长期计划，也没关系';

PlannerData _completePlan() => plannerFixture().copyWith(
  planning: {'version': 1},
  blocks: const [],
  logs: const [],
  fixedEvents: const [],
);

PlannerData _adHocOnlyPlan() {
  final data = _completePlan();
  final timestamp = nowIso();
  return data.copyWith(
    planning: null,
    subjects: const [],
    tasks: const [],
    adHocLearnings: [
      AdHocLearning(
        id: 'adhoc-only',
        userId: data.profile.userId,
        title: '背英语单词',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ],
    logs: [
      TimeLog(
        id: 'adhoc-log',
        userId: data.profile.userId,
        taskId: null,
        blockId: null,
        date: shanghaiToday(),
        minutes: 12,
        startedAt: timestamp,
        endedAt: timestamp,
        source: LogSource.timer,
        relation: TimeLogRelation.adHoc,
        adHocId: 'adhoc-only',
        sessionId: 'adhoc-session',
      ),
    ],
  );
}

PlannerSnapshot _snapshot({
  PlannerData? data,
  bool ready = true,
  bool blocked = false,
  SyncStatus status = SyncStatus.connected,
  String message = '',
}) => PlannerSnapshot(
  data: data,
  revision: 1,
  pending: false,
  status: status,
  message: message,
  blocked: blocked,
  ready: ready,
  busy: false,
  conflicts: const [],
);

class _NoopSync implements SyncApi {
  @override
  Future<RemoteSnapshot> pull({int? revision}) async =>
      const RemoteSnapshot(null, 0);

  @override
  Future<RemoteSnapshot> push(
    PlannerData data,
    PlannerData? base,
    int revision,
  ) async => RemoteSnapshot(data, revision + 1);
}

class _MemoryTimerStore implements StudyTimerStore {
  JsonMap? value;

  @override
  Future<JsonMap?> load(String key) async => value;

  @override
  Future<void> save(String key, JsonMap value) async {
    this.value = value;
  }
}

class _RecordingSession extends PlannerSession {
  _RecordingSession(super.coordinator);

  int reloads = 0;
  int syncs = 0;

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<void> sync() async {
    syncs++;
  }
}

Future<_RecordingSession> _mount(
  WidgetTester tester,
  PlannerSnapshot snapshot,
) async {
  final data = snapshot.data ?? _completePlan();
  final coordinator =
      PlannerCoordinator(
          userId: data.profile.userId,
          scope: 'dashboard-quick-start-widget',
          storage: MemoryStorageRepository(),
          api: _NoopSync(),
          retryInterval: null,
        )
        ..data = data
        ..ready = true;
  final session = _RecordingSession(coordinator);
  final container = ProviderContainer(
    overrides: [
      plannerDataProvider.overrideWithValue(snapshot),
      plannerSessionProvider.overrideWithValue(session),
      studyTimerProvider.overrideWith(
        (ref) => StudyTimer(
          coordinator: coordinator,
          store: _MemoryTimerStore(),
          tickInterval: null,
        ),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    coordinator.dispose();
  });
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: DashboardPage())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return session;
}

void _expectQuickStart() {
  expect(find.text(_emptyTitle), findsOneWidget);
  expect(find.byKey(_quickStart), findsOneWidget);
  expect(find.byKey(_aiPlanning), findsOneWidget);
  expect(find.text('开始计时'), findsOneWidget);
  expect(find.text('请先完成学习目标访谈'), findsNothing);
}

void main() {
  for (final missing in ['planning', 'subjects', 'tasks']) {
    testWidgets('dashboard offers quick start when $missing is empty', (
      tester,
    ) async {
      final complete = _completePlan();
      final data = switch (missing) {
        'planning' => complete.copyWith(planning: null),
        'subjects' => complete.copyWith(subjects: const []),
        _ => complete.copyWith(tasks: const []),
      };
      await _mount(tester, _snapshot(data: data));
      _expectQuickStart();
      expect(
        tester.widget<FilledButton>(find.byKey(_quickStart)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<OutlinedButton>(find.byKey(_aiPlanning)).onPressed,
        isNotNull,
      );
    });
  }

  testWidgets('dashboard keeps quick start beside temporary learning history', (
    tester,
  ) async {
    await _mount(tester, _snapshot(data: _adHocOnlyPlan()));
    _expectQuickStart();
    expect(find.text('今日临时学习'), findsOneWidget);
    expect(find.text('背英语单词'), findsWidgets);
    expect(
      find.byKey(Key('ad-hoc-adhoc-only:${shanghaiToday()}')),
      findsOneWidget,
    );
  });

  testWidgets(
    'complete plan has one timer action and no empty-plan shortcuts',
    (tester) async {
      await _mount(tester, _snapshot(data: _completePlan()));
      expect(find.text(_emptyTitle), findsNothing);
      expect(find.byKey(_quickStart), findsNothing);
      expect(find.byKey(_aiPlanning), findsNothing);
      expect(find.text('开始计时'), findsOneWidget);
      await tester.tap(find.text('开始计时'));
      // The existing async toolbar button stays busy until its dialog closes.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(StartStudyDialog), findsOneWidget);
      expect(find.byKey(const Key('start-study-scheduled')), findsOneWidget);
      expect(find.byKey(const Key('start-study-extra')), findsOneWidget);
      expect(find.byKey(const Key('start-study-adhoc')), findsOneWidget);
    },
  );

  testWidgets('no-task quick start opens the name-only learning dialog', (
    tester,
  ) async {
    final data = _completePlan().copyWith(
      planning: null,
      subjects: const [],
      tasks: const [],
    );
    await _mount(tester, _snapshot(data: data));
    await tester.tap(find.byKey(_quickStart));
    await tester.pumpAndSettle();
    expect(find.byType(AdHocStudyDialog), findsOneWidget);
    expect(find.byType(StartStudyDialog), findsNothing);
    expect(find.text('今天想学什么？'), findsOneWidget);
    expect(find.byKey(const Key('ad-hoc-title')), findsOneWidget);
    expect(find.byKey(const Key('ad-hoc-subject')), findsOneWidget);
    expect(find.byKey(const Key('ad-hoc-create-task')), findsOneWidget);
  });

  testWidgets(
    'unfinished planning preserves the three choices for existing tasks',
    (tester) async {
      final data = _completePlan().copyWith(planning: null);
      await _mount(tester, _snapshot(data: data));
      await tester.tap(find.byKey(_quickStart));
      await tester.pumpAndSettle();
      expect(find.byType(StartStudyDialog), findsOneWidget);
      expect(find.byKey(const Key('start-study-scheduled')), findsOneWidget);
      expect(find.byKey(const Key('start-study-extra')), findsOneWidget);
      expect(find.byKey(const Key('start-study-adhoc')), findsOneWidget);
    },
  );

  testWidgets(
    'dashboard waits for the local planner snapshot before quick start',
    (tester) async {
      await _mount(tester, _snapshot(ready: false));
      expect(find.text('正在读取本机计划…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_emptyTitle), findsNothing);
      expect(find.byKey(_quickStart), findsNothing);
      expect(find.byKey(_aiPlanning), findsNothing);
    },
  );

  testWidgets('blocked local planner data keeps its reload action', (
    tester,
  ) async {
    final session = await _mount(
      tester,
      _snapshot(
        blocked: true,
        status: SyncStatus.error,
        message: '本地数据读取失败，已停止编辑和同步。',
      ),
    );
    expect(find.text('本地数据读取失败，已停止编辑和同步。'), findsOneWidget);
    expect(find.byKey(_quickStart), findsNothing);
    expect(find.byKey(_aiPlanning), findsNothing);
    await tester.tap(find.text('重新读取本机数据'));
    await tester.pumpAndSettle();
    expect(session.reloads, 1);
    expect(session.syncs, 0);
  });

  testWidgets('failed planner load keeps its sync retry action', (
    tester,
  ) async {
    final session = await _mount(
      tester,
      _snapshot(status: SyncStatus.error, message: '读取失败，请重试'),
    );
    expect(find.text('还没有读取到学习计划。'), findsOneWidget);
    expect(find.text('读取失败，请重试'), findsOneWidget);
    expect(find.byKey(_quickStart), findsNothing);
    expect(find.byKey(_aiPlanning), findsNothing);
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(session.syncs, 1);
    expect(session.reloads, 0);
  });
}
