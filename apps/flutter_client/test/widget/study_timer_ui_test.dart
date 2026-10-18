import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/app.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/features/planner/presentation/task_study_timer.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/http_adapter.dart';
import '../support/planner_fixture.dart';

var _databaseSequence = 0;

class _Clock {
  _Clock(this.origin);
  final DateTime origin;
  Duration elapsed = Duration.zero;

  DateTime now() => origin.add(elapsed);
}

class _FixtureSync implements SyncApi {
  _FixtureSync(this.data);
  PlannerData data;
  int revision = 1;

  @override
  Future<RemoteSnapshot> pull({int? revision}) async => RemoteSnapshot(data, this.revision);

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    data = next;
    return RemoteSnapshot(data, ++revision);
  }
}

PlannerData _planFor(String date) {
  final fixture = plannerFixture();
  return fixture.copyWith(
    blocks: [fixture.blocks.single.copyWith(date: date)],
    logs: const [],
  );
}

LocalDatabase _database() => LocalDatabase(
  open: () => databaseFactoryMemory.openDatabase(
    'study-timer-widget-${_databaseSequence++}',
  ),
);

Future<({StudyTimer timer, PlannerCoordinator coordinator})> _mountTimer(
  WidgetTester tester,
  _Clock clock, {
  int targetMinutes = 90,
  bool canStart = true,
  bool canDiscard = true,
  double width = 500,
  JsonMap? savedTimer,
}) async {
  final plan = _planFor(shanghaiToday(clock.now()));
  final setup = (await tester.runAsync(() async {
    final database = _database();
    final coordinator = PlannerCoordinator(
      userId: plan.profile.userId,
      scope: 'widget-test',
      storage: SembastStorageRepository(database: database),
      api: _FixtureSync(plan),
      retryInterval: null,
    );
    await coordinator.initialize();
    final timerStore = LocalStudyTimerStore(database);
    if (savedTimer != null) {
      await timerStore.save('${coordinator.key}:study-timer-v1', savedTimer);
    }
    final timer = StudyTimer(
      coordinator: coordinator,
      store: timerStore,
      now: clock.now,
      monotonicNow: () => clock.elapsed,
      tickInterval: null,
    );
    await timer.initialize();
    return (database: database, coordinator: coordinator, timer: timer);
  }))!;
  final database = setup.database;
  final coordinator = setup.coordinator;
  final timer = setup.timer;
  final container = ProviderContainer(
    overrides: [studyTimerProvider.overrideWith((ref) => timer)],
  );
  addTearDown(() async {
    container.dispose();
    coordinator.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: TaskStudyTimer(
                taskId: plan.tasks.single.id,
                date: shanghaiToday(clock.now()),
                plannedMinutes: targetMinutes,
                color: Colors.blue,
                canStart: canStart,
                canDiscard: canDiscard,
                heading: const Text('高数基础一轮：概念梳理与基础题'),
                secondaryAction: TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('改日期'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (timer: timer, coordinator: coordinator);
}

Future<void> _pressTimer(
  WidgetTester tester,
  StudyTimer timer,
  String action,
) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(action));
    await Future<void>.delayed(Duration.zero);
    while (timer.busy) {
      await Future<void>.delayed(Duration.zero);
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('inline controls keep seconds across pause and resume', (
    tester,
  ) async {
    final clock = _Clock(DateTime.utc(2026, 10, 17, 4));
    final harness = await _mountTimer(tester, clock);

    expect(find.text('00:00:00'), findsOneWidget);
    await _pressTimer(tester, harness.timer, '开始计时');
    expect(find.text('暂停计时'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextField), findsNothing);

    clock.elapsed = const Duration(seconds: 37, milliseconds: 500);
    await _pressTimer(tester, harness.timer, '暂停计时');
    expect(find.text('00:00:37'), findsOneWidget);
    expect(find.text('继续计时'), findsOneWidget);

    clock.elapsed += const Duration(hours: 1);
    await _pressTimer(tester, harness.timer, '继续计时');
    clock.elapsed += const Duration(seconds: 25, milliseconds: 500);
    await _pressTimer(tester, harness.timer, '暂停计时');

    expect(find.text('00:01:03'), findsOneWidget);
    expect(
      harness.timer.elapsedFor(
        harness.coordinator.data!.tasks.single.id,
        '2026-10-17',
      ),
      const Duration(seconds: 63),
    );
    expect(
      taskDayMinutes(
        harness.coordinator.data!,
        harness.coordinator.data!.tasks.single.id,
        '2026-10-17',
      ),
      1,
    );
  });

  testWidgets('ring exposes elapsed and goal without an adjustment action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final clock = _Clock(DateTime.utc(2026, 10, 17, 4));
    final harness = await _mountTimer(tester, clock, targetMinutes: 1);
    await _pressTimer(tester, harness.timer, '开始计时');
    clock.elapsed = const Duration(seconds: 90);
    await _pressTimer(tester, harness.timer, '暂停计时');

    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.value, 1);
    expect(find.text('00:01:30'), findsOneWidget);
    final taskId = harness.coordinator.data!.tasks.single.id;
    expect(
      tester.getSemantics(find.byKey(Key('study-progress-$taskId-2026-10-17'))),
      matchesSemantics(
        label: '学习用时',
        value: '已学 00:01:30，目标 1分钟',
        textDirection: TextDirection.ltr,
      ),
    );
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    semantics.dispose();
  });

  testWidgets('a narrow timer keeps its heading above compact controls', (
    tester,
  ) async {
    await _mountTimer(
      tester,
      _Clock(DateTime.utc(2026, 10, 17, 4)),
      width: 220,
      canStart: false,
      targetMinutes: 150,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('目标 2小时30分'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('改日期'), findsOneWidget);
    final ring = find.byType(CircularProgressIndicator);
    expect(tester.getSize(ring), const Size(96, 96));
    expect(
      tester.getTopLeft(ring).dy,
      greaterThan(tester.getBottomLeft(find.text('高数基础一轮：概念梳理与基础题')).dy),
    );
    expect(
      tester.getTopLeft(find.byType(FilledButton)).dx,
      greaterThan(tester.getBottomRight(ring).dx),
    );
  });

  testWidgets('undo confirmation removes only the latest paused session', (
    tester,
  ) async {
    final clock = _Clock(DateTime.utc(2026, 10, 17, 4));
    final harness = await _mountTimer(tester, clock);
    final taskId = harness.coordinator.data!.tasks.single.id;
    final undo = find.byTooltip('撤销上一段计时');

    expect(undo, findsNothing);
    await _pressTimer(tester, harness.timer, '开始计时');
    clock.elapsed = const Duration(seconds: 61);
    await _pressTimer(tester, harness.timer, '暂停计时');
    final firstSession = harness.timer.lastSessionFor(taskId, '2026-10-17')!;
    expect(find.text('上一段 00:01:01'), findsOneWidget);

    await _pressTimer(tester, harness.timer, '继续计时');
    expect(undo, findsNothing);
    clock.elapsed += const Duration(seconds: 29);
    await _pressTimer(tester, harness.timer, '暂停计时');
    final latestSession = harness.timer.lastSessionFor(taskId, '2026-10-17')!;
    expect(latestSession.id, isNot(firstSession.id));
    expect(find.text('上一段 00:00:29'), findsOneWidget);
    expect(find.text('00:01:30'), findsOneWidget);

    await tester.runAsync(() => tester.tap(undo));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('撤销上一段计时'), findsOneWidget);
    expect(find.textContaining('计时 00:00:29'), findsOneWidget);
    expect(find.textContaining('2026-10-17 12:01:01'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('00:01:30'), findsOneWidget);
    expect(
      harness.timer.lastSessionFor(taskId, '2026-10-17')!.id,
      latestSession.id,
    );

    await tester.runAsync(() => tester.tap(undo));
    await tester.pumpAndSettle();
    await _pressTimer(tester, harness.timer, '撤销这段');

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('00:01:01'), findsOneWidget);
    expect(find.text('上一段 00:01:01'), findsOneWidget);
    expect(
      harness.timer.lastSessionFor(taskId, '2026-10-17')!.id,
      firstSession.id,
    );
    expect(taskDayMinutes(harness.coordinator.data!, taskId, '2026-10-17'), 1);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('undo is disabled when the task cannot discard sessions', (
    tester,
  ) async {
    final clock = _Clock(DateTime.utc(2026, 10, 17, 4));
    final harness = await _mountTimer(tester, clock, canDiscard: false);
    await _pressTimer(tester, harness.timer, '开始计时');
    clock.elapsed = const Duration(seconds: 61);
    await _pressTimer(tester, harness.timer, '暂停计时');

    final taskId = harness.coordinator.data!.tasks.single.id;
    final undo = find.byKey(Key('undo-study-session-$taskId-2026-10-17'));
    expect(tester.widget<IconButton>(undo).onPressed, isNull);
    expect(find.text('00:01:01'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('legacy totals explain their limits before deleting the total', (
    tester,
  ) async {
    final clock = _Clock(DateTime.utc(2026, 10, 17, 4));
    final taskId = _planFor('2026-10-17').tasks.single.id;
    final harness = await _mountTimer(
      tester,
      clock,
      savedTimer: {
        'version': 1,
        'revision': 1,
        'buckets': [
          {
            'id': 'legacy-timer-log',
            'taskId': taskId,
            'date': '2026-10-17',
            'milliseconds': 90000,
            'startedAt': '2026-10-17T04:00:00Z',
            'endedAt': '2026-10-17T04:01:30Z',
          },
        ],
        'active': null,
      },
    );

    expect(find.text('历史计时累计 00:01:30'), findsOneWidget);
    expect(find.byTooltip('撤销上一段计时'), findsNothing);
    final discard = find.byTooltip('删除历史计时累计');
    await tester.runAsync(() => tester.tap(discard));
    await tester.pumpAndSettle();
    expect(find.text('删除历史计时累计'), findsOneWidget);
    expect(find.textContaining('无法拆分到每次开始和暂停'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('00:01:30'), findsOneWidget);

    await tester.runAsync(() => tester.tap(discard));
    await tester.pumpAndSettle();
    await _pressTimer(tester, harness.timer, '删除累计');
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('开始计时'), findsOneWidget);
    expect(find.byTooltip('删除历史计时累计'), findsNothing);
    expect(harness.timer.lastSessionFor(taskId, '2026-10-17'), isNull);
    expect(taskDayMinutes(harness.coordinator.data!, taskId, '2026-10-17'), 0);
  });

  testWidgets('today shows the read-only ring at mobile width', (tester) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = (await tester.runAsync(() async {
      final database = _database();
      await database.database;
      return database;
    }))!;
    final clock = _Clock(DateTime.now());
    final plan = _planFor(shanghaiToday(clock.now()));
    final client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) async {
          if (request.path.endsWith('/api/auth/login')) {
            return jsonResponse({
              'user': testUser,
              'accessToken': 'access',
              'refreshToken': 'refresh',
              'expiresIn': 900,
            });
          }
          if (request.path.endsWith('/api/onboarding/profile')) {
            return jsonResponse({
              'profile': {
                'goal_text': '准备计算机专业研究生考试',
                'goal_type': 'exam',
                'target_date': '2027-12-25',
                'plan_start_date': '2026-10-01',
                'plan_end_date': '2027-12-25',
                'weekly_minutes': {
                  for (var day = 0; day < 7; day++) '$day': 120,
                },
              },
            });
          }
          if (request.path.endsWith('/api/planner/sync')) {
            return jsonResponse({'data': plan.toJson(), 'revision': 1});
          }
          return jsonResponse({'error': 'Unexpected ${request.path}'}, 404);
        }),
    );
    final container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(database),
        storageRepositoryProvider.overrideWithValue(MemoryStorageRepository()),
        apiClientProvider.overrideWithValue(client),
        identityStoreProvider.overrideWithValue(MemoryIdentityStore()),
        syncRetryIntervalProvider.overrideWithValue(null),
        studyTimerProvider.overrideWith(
          (ref) => StudyTimer(
            coordinator: ref.watch(plannerSyncProvider.notifier),
            store: LocalStudyTimerStore(database),
            now: clock.now,
            monotonicNow: () => clock.elapsed,
            tickInterval: null,
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      client.close();
      await database.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PlannerApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'student@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Study4089');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.byType(TaskStudyTimer), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TaskStudyTimer),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('开始计时'), findsOneWidget);
    expect(find.text('今日已完成'), findsNothing);
    expect(find.text('记录用时'), findsNothing);
    expect(find.text('修改用时'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
