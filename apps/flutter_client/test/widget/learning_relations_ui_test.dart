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
import 'package:sjtu_study_planner_client/features/dashboard/presentation/dashboard_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/progress/presentation/progress_page.dart';
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
  final clock = _Clock(DateTime.now());
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
  testWidgets('dashboard offers the three study relations', (tester) async {
    final harness = await _mount(tester);
    expect(find.byType(DashboardPage), findsOneWidget);
    await harness.tap(find.text('开始学习').first);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('今日原定学习'), findsOneWidget);
    expect(find.text('已有事项加学'), findsOneWidget);
    expect(find.text('全新临时学习'), findsOneWidget);
    expect(find.byKey(const Key('start-study-scheduled')), findsOneWidget);
    expect(find.byKey(const Key('start-study-extra')), findsOneWidget);
    expect(find.byKey(const Key('start-study-adhoc')), findsOneWidget);
  });

  testWidgets(
    'temporary learning starts by name and pauses into a history row',
    (tester) async {
      final harness = await _mount(tester);
      await harness.tap(find.text('开始学习').first);
      await harness.tap(find.byKey(const Key('start-study-adhoc')));
      // The ad-hoc dialog is stacked above the still-open start dialog.
      expect(find.byType(AlertDialog), findsNWidgets(2));
      expect(find.text('临时学习'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('ad-hoc-title')),
        '摄影构图',
      );
      await harness.tap(find.byKey(const Key('ad-hoc-start')));

      final entity = harness.coordinator.data!.adHocLearnings.single;
      expect(entity.title, '摄影构图');
      expect(harness.timer.activeAdHocId, entity.id);
      expect(find.text('今日临时学习'), findsOneWidget);
      expect(find.byKey(Key('ad-hoc-minutes-${entity.id}')), findsOneWidget);

      harness.clock.advance(const Duration(minutes: 20));
      await harness.tap(find.text('暂停计时'));
      final log = harness.coordinator.data!.logs.single;
      expect(log.taskId, isNull);
      expect(log.adHocId, entity.id);
      expect(log.relation, TimeLogRelation.adHoc);
      expect(log.minutes, 20);
      expect(find.textContaining('临时学习已保存'), findsOneWidget);
      expect(find.text('转为正式事项'), findsOneWidget);
    },
  );

  testWidgets(
    'extra study of an item without a today block records without a new block',
    (tester) async {
      final harness = await _mount(tester);
      await harness.tap(find.text('开始学习').first);
      await harness.tap(find.byKey(const Key('start-study-extra')));
      expect(find.text('选择要加学的事项'), findsOneWidget);
      expect(find.byKey(const Key('task-picker-search')), findsOneWidget);
      // Completed items are reviewable but hidden from the default filter.
      expect(
        find.byKey(const Key('task-picker-item-future-task')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('task-picker-item-completed-task')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('task-picker-search')),
        '线性代数',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const Key('task-picker-item-future-task')),
        findsOneWidget,
      );
      await harness.tap(find.byKey(const Key('task-picker-item-future-task')));

      expect(harness.timer.activeTaskId, 'future-task');
      expect(harness.timer.activeRelation, TimeLogRelation.extra);
      harness.clock.advance(const Duration(minutes: 30));
      await harness.tap(find.text('暂停计时'));

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
      expect(find.byKey(const Key('extra-minutes-future-task')), findsOneWidget);
      expect(find.textContaining('加学时间已保存'), findsOneWidget);
      await harness.tap(find.text('记录内容进度'));
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
      // Timing alone never completes content or unlocks dependencies.
      expect(future.status, isNot(TaskStatus.completed));
    },
  );

  testWidgets(
    'scheduled overflow shows the extra badge without inflating execution',
    (tester) async {
      final harness = await _mount(tester);
      final taskId = harness.coordinator.data!.tasks.first.id;
      await harness.tap(find.text('开始计时').first);
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
        logs.singleWhere((log) => log.relation == TimeLogRelation.extra).minutes,
        10,
      );
      expect(find.byKey(Key('task-extra-chip-$taskId')), findsOneWidget);
      expect(find.text('+加学 10分钟'), findsOneWidget);
      expect(find.textContaining('原定完成 30分钟'), findsOneWidget);
    },
  );

  testWidgets('capacity breakdown bills every minute once', (tester) async {
    final fixture = plannerFixture();
    final task = fixture.tasks.single;
    final plan = fixture.copyWith(
      profile: fixture.profile.copyWith(
        weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 150},
        bufferMinutes: 30,
      ),
      fixedEvents: const [],
      blocks: [
        fixture.blocks.single.copyWith(date: today, durationMinutes: 60),
      ],
      logs: [
        fixture.logs.single.copyWith(
          minutes: 30,
          relation: TimeLogRelation.scheduled,
          blockId: null,
          taskId: task.id,
          date: today,
          startedAt: '${today}T00:00:00.000Z',
          endedAt: '${today}T01:00:00.000Z',
        ),
        TimeLog(
          id: 'photo-log',
          userId: fixture.profile.userId,
          taskId: null,
          blockId: null,
          date: today,
          minutes: 20,
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
    await _mount(tester, plan: (now) => plan);
    final text = tester
        .widget<Text>(find.byKey(const Key('today-capacity-breakdown')))
        .data!;
    expect(text, contains('今日净容量 2小时'));
    expect(text, contains('实际投入 50分钟'));
    expect(text, contains('有效预留 30分钟'));
    expect(text, contains('新增可安排 40分钟'));
    expect(find.text('今日临时学习'), findsOneWidget);
    expect(find.textContaining('原定完成 30分钟'), findsOneWidget);
  });

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

  testWidgets('full period plans show coverage instead of an upgrade button', (
    tester,
  ) async {
    final fixture = plannerFixture();
    final full = fixture.copyWith(
      planning: {'version': 1, 'mode': 'full', 'rolling': false},
      blocks: [fixture.blocks.single.copyWith(date: today)],
      logs: const [],
    );
    await _mount(tester, plan: (now) => full);
    expect(find.byKey(const Key('dashboard-complete-cycle')), findsNothing);
    final coverage = tester
        .widget<Text>(find.byKey(const Key('dashboard-full-plan-coverage')))
        .data!;
    expect(coverage, contains('覆盖整个规划周期'));
  });

  testWidgets('temporary learning history is visible on the progress page', (
    tester,
  ) async {
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
    await _mount(tester, page: const ProgressPage(), plan: (now) => plan);
    expect(find.text('临时学习记录'), findsOneWidget);
    expect(find.byKey(const Key('ad-hoc-history-title-photo')), findsOneWidget);
    expect(find.text('摄影构图'), findsOneWidget);
    expect(
      find.byKey(const Key('progress-relation-breakdown')),
      findsOneWidget,
    );
    final breakdown = tester
        .widget<Text>(find.byKey(const Key('progress-relation-breakdown')))
        .data!;
    expect(breakdown, contains('临时学习 25分钟'));
  });

  testWidgets('ad-hoc conversion keeps the recorded minutes', (tester) async {
    final harness = await _mount(tester);
    await harness.tap(find.text('开始学习').first);
    await harness.tap(find.byKey(const Key('start-study-adhoc')));
    await tester.enterText(find.byKey(const Key('ad-hoc-title')), '摄影构图');
    await harness.tap(find.byKey(const Key('ad-hoc-start')));
    harness.clock.advance(const Duration(minutes: 15));
    await harness.tap(find.text('暂停计时'));
    final entity = harness.coordinator.data!.adHocLearnings.single;
    final before = harness.coordinator.data!.logs.single;

    await harness.tap(find.byTooltip('临时学习后续操作'));
    await harness.tap(
      find.widgetWithText(PopupMenuItem<String>, '转为正式事项'),
    );
    expect(find.byKey(const Key('ad-hoc-convert-title')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('ad-hoc-convert-title')),
      '摄影构图基础',
    );
    await harness.tap(find.byKey(const Key('ad-hoc-convert-save')));
    // The existing schedule dialog previews the remaining-cycle impact.
    expect(find.text('安排时间块'), findsOneWidget);
    await harness.tap(find.text('取消'));

    final converted = harness.coordinator.data!;
    final log = converted.logs.singleWhere((item) => item.id == before.id);
    expect(log.minutes, 15);
    expect(log.taskId, isNotNull);
    expect(log.adHocId, entity.id);
    expect(log.relation, TimeLogRelation.adHoc);
    expect(
      converted.logs.fold<int>(0, (sum, item) => sum + item.minutes),
      15,
    );
    expect(converted.adHocLearnings.single.archived, isTrue);
    expect(converted.adHocLearnings.single.convertedTaskId, log.taskId);
    expect(converted.tasks.any((task) => task.title == '摄影构图基础'), isTrue);
    // A later checkpoint must not revert the adopted attribution.
    await harness.checkpoint();
    expect(
      harness.coordinator.data!.logs
          .singleWhere((item) => item.id == before.id)
          .taskId,
      log.taskId,
    );
  });
}
