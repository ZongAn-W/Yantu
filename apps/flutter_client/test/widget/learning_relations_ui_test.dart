import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_page.dart';
import 'package:sjtu_study_planner_client/features/dashboard/presentation/dashboard_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

var _databaseSequence = 0;

class _Clock {
  _Clock(this.wall);
  DateTime wall;
  Duration monotonic = Duration.zero;

  void advance(Duration duration) {
    wall = wall.add(duration);
    monotonic += duration;
  }
}

class _OfflineSync implements SyncApi {
  @override
  Future<RemoteSnapshot> pull({int? revision}) async =>
      throw const OfflineFailure();

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int revision,
  ) async => throw const OfflineFailure();
}

/// In-memory week preference store: the merged calendar page only needs the
/// wiring inside widget tests, while the Sembast store has its own unit tests.
class _MemoryWeekViewStore implements CalendarWeekViewPreferenceStore {
  CalendarWeekView value = CalendarWeekView.mirror;

  @override
  Future<CalendarWeekView> load() async => value;

  @override
  Future<void> save(CalendarWeekView view) async {
    value = view;
  }
}

/// The dashboard uses the real Shanghai "today", so tests must use the same day.
String get today => shanghaiToday();

PlannerData _plan(DateTime now) {
  final fixture = plannerFixture();
  final task = fixture.tasks.single;
  final future = task.copyWith(
    id: 'future-task',
    title: '线性代数第三章',
    earliestDate: '2026-12-01',
    deadline: '2027-03-01',
  );
  final completed = task.copyWith(
    id: 'completed-task',
    title: '已完成的章节',
    status: TaskStatus.completed,
    completedMinutes: task.estimatedMinutes,
  );
  return fixture.copyWith(
    planning: {'version': 1, 'mode': 'full', 'rolling': false},
    tasks: [task, future, completed],
    blocks: [
      fixture.blocks.single.copyWith(
        date: shanghaiToday(now),
        durationMinutes: 30,
      ),
    ],
    logs: const [],
    fixedEvents: const [],
  );
}

class _Harness {
  _Harness(this.tester, this.clock, this.timer, this.coordinator);

  final WidgetTester tester;
  final _Clock clock;
  final StudyTimer timer;
  final PlannerCoordinator coordinator;

  Future<void> settle() async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tap(Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      while (timer.busy) {
        await Future<void>.delayed(Duration.zero);
      }
    });
    await settle();
  }

  Future<void> checkpoint() async {
    await tester.runAsync(() async {
      await timer.checkpoint();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await settle();
  }
}

Future<_Harness> _mount(
  WidgetTester tester, {
  Widget page = const DashboardPage(),
  PlannerData Function(DateTime now)? plan,
}) async {
  final now = DateTime.now();
  // Pin the simulated wall clock to midday: a 40-minute session started near
  // Shanghai midnight would be split across two dates, while these widget tests
  // assert same-day minute splits. Cross-midnight splitting has its own unit tests.
  final clock = _Clock(DateTime(now.year, now.month, now.day, 12));
  final data = (plan ?? _plan)(clock.wall);
  final setup = (await tester.runAsync(() async {
    final database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase(
        'learning-relations-widget-${_databaseSequence++}',
      ),
    );
    final coordinator = PlannerCoordinator(
      userId: data.profile.userId,
      scope: 'learning-relations-widget',
      storage: SembastStorageRepository(database: database),
      api: _OfflineSync(),
      retryInterval: null,
    );
    coordinator.data = data;
    coordinator.ready = true;
    final timer = StudyTimer(
      coordinator: coordinator,
      store: LocalStudyTimerStore(database),
      now: () => clock.wall,
      monotonicNow: () => clock.monotonic,
      tickInterval: null,
    );
    await timer.initialize();
    return (database: database, coordinator: coordinator, timer: timer);
  }))!;
  final container = ProviderContainer(
    overrides: [
      plannerSyncProvider.overrideWith((ref) => setup.coordinator),
      studyTimerProvider.overrideWith((ref) => setup.timer),
      calendarWeekViewPreferenceStoreProvider.overrideWithValue(
        _MemoryWeekViewStore(),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await setup.database.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return _Harness(tester, clock, setup.timer, setup.coordinator);
}

void main() {
  testWidgets(
    'dashboard uses inline extra-study alarms instead of a start dialog',
    (tester) async {
      final harness = await _mount(tester);
      expect(find.byType(DashboardPage), findsOneWidget);
      // 「开始计时」快捷入口与三类学习关系选择器已下线。
      expect(find.byKey(const Key('dashboard-quick-start')), findsNothing);
      expect(find.text('今天想学什么？'), findsNothing);
      // 每个事项行都有加学计时闹钟；已完成事项以复习计时呈现。
      for (final task in harness.coordinator.data!.tasks) {
        expect(find.byKey(Key('task-extra-timer-${task.id}')), findsOneWidget);
      }
      expect(find.byTooltip('复习计时'), findsOneWidget);
      // 今日净容量拆分与临时学习区块都已从合并页移除。
      expect(find.byKey(const Key('today-capacity-breakdown')), findsNothing);
      expect(find.text('今日临时学习'), findsNothing);
      expect(find.text('今日加学'), findsNothing);
    },
  );

  testWidgets(
    'alarm starts and pauses extra study for an item without a today block',
    (tester) async {
      final harness = await _mount(tester);
      final alarm = find.byKey(const Key('task-extra-timer-future-task'));
      expect(
        find.descendant(of: alarm, matching: find.byIcon(Icons.alarm)),
        findsOneWidget,
      );

      await harness.tap(alarm);
      expect(harness.timer.activeTaskId, 'future-task');
      expect(harness.timer.activeRelation, TimeLogRelation.extra);
      expect(
        find.descendant(of: alarm, matching: find.byIcon(Icons.pause)),
        findsOneWidget,
      );
      // 计时中的事项同步出现在「今日加学」，即使今天没有它的原定安排；
      // 区块标题和加学卡的零秒目标标签都会显示这条文案。
      expect(find.text('今日加学'), findsWidgets);
      expect(
        find.byKey(const Key('extra-minutes-future-task')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('study-timer-action-future-task-$today')),
        findsOneWidget,
      );

      harness.clock.advance(const Duration(minutes: 30));
      await harness.tap(alarm);

      // 暂停后闹钟回到 ⏰，计时保存为加学记录且不新增安排。
      expect(
        find.descendant(of: alarm, matching: find.byIcon(Icons.alarm)),
        findsOneWidget,
      );
      expect(harness.timer.activeTaskId, isNull);
      final log = harness.coordinator.data!.logs.single;
      expect(log.taskId, 'future-task');
      expect(log.relation, TimeLogRelation.extra);
      expect(log.minutes, 30);
      expect(
        harness.coordinator.data!.blocks.any(
          (block) => block.taskId == 'future-task',
        ),
        isFalse,
      );
      expect(
        find.byKey(const Key('extra-minutes-future-task')),
        findsOneWidget,
      );
      expect(find.textContaining('加学时间已保存'), findsOneWidget);

      // 可选的后续只记录内容进度，绝不自动完成内容。
      await tester.tap(find.text('记录内容进度'));
      await tester.pumpAndSettle();
      expect(find.text('记录内容进度与困难'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('content-feedback-units')),
        '2',
      );
      await harness.tap(find.byKey(const Key('content-feedback-save')));
      final future = harness.coordinator.data!.tasks
          .where((task) => task.id == 'future-task')
          .single;
      expect((future.planning!['feedback'] as Map)['content_units'], 2);
      expect(future.status, isNot(TaskStatus.completed));
    },
  );

  testWidgets(
    'scheduled overflow shows the extra badge and the extra-study card together',
    (tester) async {
      final harness = await _mount(tester);
      final taskId = harness.coordinator.data!.tasks.first.id;
      await harness.tap(find.byKey(Key('study-timer-action-$taskId-$today')));
      expect(harness.timer.activeRelation, TimeLogRelation.scheduled);
      harness.clock.advance(const Duration(minutes: 40));
      await harness.tap(find.text('暂停计时'));

      final logs = harness.coordinator.data!.logs;
      expect(logs, hasLength(2));
      expect(
        logs
            .singleWhere((log) => log.relation == TimeLogRelation.scheduled)
            .minutes,
        30,
      );
      expect(
        logs
            .singleWhere((log) => log.relation == TimeLogRelation.extra)
            .minutes,
        10,
      );
      // 计划内事项的加学同时出现在计划卡的 chip 和「今日加学」卡里。
      expect(find.byKey(Key('task-extra-chip-$taskId')), findsOneWidget);
      expect(find.text('+加学 10分钟'), findsOneWidget);
      expect(find.textContaining('原定完成 30分钟'), findsOneWidget);
      expect(find.text('今日加学'), findsOneWidget);
      expect(find.byKey(Key('extra-minutes-$taskId')), findsOneWidget);
    },
  );

  testWidgets('rolling plans offer completion entry', (tester) async {
    final fixture = plannerFixture();
    final rolling = fixture.copyWith(
      planning: {'version': 1, 'rolling': true},
      blocks: [fixture.blocks.single.copyWith(date: today)],
      logs: const [],
    );
    await _mount(tester, plan: (now) => rolling);
    expect(find.byKey(const Key('dashboard-complete-cycle')), findsOneWidget);
    expect(find.text('补全本周期安排'), findsOneWidget);
    expect(find.text('细化近期安排'), findsNothing);
  });

  testWidgets(
    'merged calendar excludes temporary-learning history and breakdown',
    (tester) async {
      final fixture = plannerFixture();
      final plan = fixture.copyWith(
        logs: [
          TimeLog(
            id: 'photo-log',
            userId: fixture.profile.userId,
            taskId: null,
            blockId: null,
            date: today,
            minutes: 25,
            startedAt: '${today}T04:00:00.000Z',
            endedAt: '${today}T05:00:00.000Z',
            source: LogSource.timer,
            relation: TimeLogRelation.adHoc,
            adHocId: 'photo',
          ),
        ],
        adHocLearnings: [
          AdHocLearning(
            id: 'photo',
            userId: fixture.profile.userId,
            title: '摄影构图',
            createdAt: '2026-10-01T00:00:00.000Z',
            updatedAt: '2026-10-01T00:00:00.000Z',
          ),
        ],
      );
      await _mount(tester, page: const CalendarPage(), plan: (now) => plan);
      // 临时学习已下线，合并后的日历不再展示历史面板，也不把它计入累计。
      expect(find.textContaining('临时学习'), findsNothing);
      expect(
        find.byKey(const Key('progress-relation-breakdown')),
        findsOneWidget,
      );
      final breakdown = tester
          .widget<Text>(find.byKey(const Key('progress-relation-breakdown')))
          .data!;
      expect(breakdown, contains('原定执行'));
      expect(breakdown, contains('加学'));
      expect(breakdown, isNot(contains('临时学习')));
    },
  );
}
