import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/features/dashboard/presentation/dashboard_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/presentation/task_study_timer.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const _aiPlanning = Key('dashboard-ai-planning');
const _emptyTitle = '还没有长期计划，也没关系';
const _interviewMarker = 'interview-route-marker';

final _today = shanghaiToday();

PlannerData _emptyPlan() => plannerFixture().copyWith(
  planning: null,
  tags: const [],
  tasks: const [],
  blocks: const [],
  logs: const [],
  fixedEvents: const [],
);

PlannerData _plannedPlan() {
  final fixture = plannerFixture();
  return fixture.copyWith(
    planning: {'version': 1, 'mode': 'full', 'rolling': false},
    blocks: [fixture.blocks.single.copyWith(date: _today)],
    logs: const [],
    fixedEvents: const [],
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

/// Mounts the merged today page with a router so the AI-planning entry can
/// navigate to `/interview`.
Future<({_RecordingSession session, GoRouter router})> _mount(
  WidgetTester tester,
  PlannerSnapshot snapshot,
) async {
  final data = snapshot.data ?? _emptyPlan();
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
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: DashboardPage()),
      ),
      GoRoute(
        path: '/interview',
        builder: (_, _) => const Scaffold(body: Text(_interviewMarker)),
      ),
    ],
  );
  addTearDown(router.dispose);
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return (session: session, router: router);
}

void main() {
  for (final missing in ['tasks']) {
    testWidgets(
      'empty plan keeps AI planning and the all-items entry when $missing is empty',
      (tester) async {
        final complete = _plannedPlan();
        final data = complete.copyWith(tasks: const []);
        await _mount(tester, _snapshot(data: data));
        expect(find.text(_emptyTitle), findsOneWidget);
        expect(find.byKey(const Key('dashboard-empty-plan')), findsOneWidget);
        expect(find.byKey(_aiPlanning), findsOneWidget);
        expect(find.text('AI 长期规划'), findsOneWidget);
        // The directory remains directly usable without a task prerequisite.
        expect(find.text('全部事项'), findsOneWidget);
        expect(find.byKey(const Key('new-task-button')), findsOneWidget);
        // 旧的「开始计时」快捷入口与临时学习入口已下线。
        expect(find.byKey(const Key('dashboard-quick-start')), findsNothing);
        expect(find.text('今天想学什么？'), findsNothing);
      },
    );
  }

  testWidgets('manual tasks work without a planning document or tags', (
    tester,
  ) async {
    final data = plannerFixture().copyWith(
      planning: null,
      tags: const [],
      tasks: [plannerFixture().tasks.single.copyWith(tagIds: const [])],
    );
    await _mount(tester, _snapshot(data: data));
    expect(find.byKey(const Key('dashboard-empty-plan')), findsNothing);
    expect(find.text('全部事项'), findsOneWidget);
    expect(find.byKey(const Key('new-task-button')), findsOneWidget);
    expect(find.text(data.tasks.single.title), findsWidgets);
  });

  testWidgets('empty plan AI planning action opens the interview route', (
    tester,
  ) async {
    final mounted = await _mount(tester, _snapshot(data: _emptyPlan()));
    await tester.tap(find.byKey(_aiPlanning));
    await tester.pumpAndSettle();
    expect(
      mounted.router.routeInformationProvider.value.uri.path,
      '/interview',
    );
    expect(find.text(_interviewMarker), findsOneWidget);
  });

  testWidgets(
    'planned day keeps the study timer card and adds the item directory',
    (tester) async {
      final data = _plannedPlan();
      final task = data.tasks.single;
      await _mount(tester, _snapshot(data: data));
      expect(find.text(_emptyTitle), findsNothing);
      expect(find.byKey(const Key('dashboard-empty-plan')), findsNothing);
      expect(find.byKey(_aiPlanning), findsNothing);
      expect(find.text('今日学习'), findsOneWidget);
      expect(find.byType(TaskStudyTimer), findsOneWidget);
      expect(
        find.byKey(Key('study-timer-action-${task.id}-$_today')),
        findsOneWidget,
      );
      expect(find.text(task.title), findsWidgets);
      expect(find.text('全部事项'), findsOneWidget);
      expect(find.byKey(const Key('new-task-button')), findsOneWidget);
      expect(find.byKey(Key('task-extra-timer-${task.id}')), findsOneWidget);
      // 今日饼图、净容量与临时学习区块都已从产品移除。
      expect(find.byKey(const Key('today-capacity-breakdown')), findsNothing);
      expect(find.text('今日临时学习'), findsNothing);
      expect(find.text('临时学习记录'), findsNothing);
    },
  );

  testWidgets(
    'dashboard waits for the local planner snapshot before showing entries',
    (tester) async {
      await _mount(tester, _snapshot(ready: false));
      expect(find.text('正在读取本机计划…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_emptyTitle), findsNothing);
      expect(find.byKey(_aiPlanning), findsNothing);
      expect(find.text('全部事项'), findsNothing);
    },
  );

  testWidgets('blocked local planner data keeps its reload action', (
    tester,
  ) async {
    final mounted = await _mount(
      tester,
      _snapshot(
        blocked: true,
        status: SyncStatus.error,
        message: '本地数据读取失败，已停止编辑和同步。',
      ),
    );
    expect(find.text('本地数据读取失败，已停止编辑和同步。'), findsOneWidget);
    expect(find.byKey(_aiPlanning), findsNothing);
    expect(find.text('全部事项'), findsNothing);
    await tester.tap(find.text('重新读取本机数据'));
    await tester.pumpAndSettle();
    expect(mounted.session.reloads, 1);
    expect(mounted.session.syncs, 0);
  });

  testWidgets('failed planner load keeps its sync retry action', (
    tester,
  ) async {
    final mounted = await _mount(
      tester,
      _snapshot(status: SyncStatus.error, message: '读取失败，请重试'),
    );
    expect(find.text('还没有读取到学习计划。'), findsOneWidget);
    expect(find.text('读取失败，请重试'), findsOneWidget);
    expect(find.byKey(_aiPlanning), findsNothing);
    expect(find.text('全部事项'), findsNothing);
    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle();
    expect(mounted.session.syncs, 1);
    expect(mounted.session.reloads, 0);
  });
}
