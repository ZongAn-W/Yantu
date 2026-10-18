import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/dashboard/presentation/task_time_pie.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const _date = '2026-10-17';
const _taskIds = ['math', 'english', 'data-structures', 'not-started'];
const _titles = ['高数基础一轮', '英语词汇与长难句', '数据结构基础', '尚未开始的事项'];
var _databaseSequence = 0;

class _Clock {
  Duration elapsed = Duration.zero;

  DateTime now() => DateTime.utc(2026, 10, 17, 4).add(elapsed);
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

PlannerData _plan({List<int> minutes = const [0, 0, 0, 0]}) {
  final fixture = plannerFixture();
  final task = fixture.tasks.single;
  final block = fixture.blocks.single;
  final log = fixture.logs.single;
  return fixture.copyWith(
    tasks: [
      for (var index = 0; index < _taskIds.length; index++)
        task.copyWith(id: _taskIds[index], title: _titles[index]),
    ],
    blocks: [
      for (var index = 0; index < _taskIds.length; index++)
        block.copyWith(
          id: 'block-$index',
          taskId: _taskIds[index],
          date: _date,
          durationMinutes: 90,
        ),
    ],
    logs: [
      for (var index = 0; index < minutes.length; index++)
        if (minutes[index] > 0)
          log.copyWith(
            id: 'manual-$index',
            taskId: _taskIds[index],
            date: _date,
            minutes: minutes[index],
          ),
      log.copyWith(
        id: 'yesterday',
        taskId: _taskIds.last,
        date: '2026-10-16',
        minutes: 300,
      ),
    ],
  );
}

Future<({StudyTimer timer, PlannerCoordinator coordinator})> _mountPie(
  WidgetTester tester,
  PlannerData plan, {
  _Clock? clock,
  double width = 400,
  double textScale = 1,
}) async {
  clock ??= _Clock();
  final taskClock = clock;
  final setup = (await tester.runAsync(() async {
    final database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase(
        'task-time-pie-widget-${_databaseSequence++}',
      ),
    );
    final coordinator = PlannerCoordinator(
      userId: plan.profile.userId,
      scope: 'widget-test',
      storage: SembastStorageRepository(database: database),
      api: _FixtureSync(plan),
      retryInterval: null,
    );
    await coordinator.initialize();
    final timer = StudyTimer(
      coordinator: coordinator,
      store: LocalStudyTimerStore(database),
      now: taskClock.now,
      monotonicNow: () => taskClock.elapsed,
      tickInterval: null,
    );
    await timer.initialize();
    return (database: database, coordinator: coordinator, timer: timer);
  }))!;
  final container = ProviderContainer(
    overrides: [studyTimerProvider.overrideWith((ref) => setup.timer)],
  );
  addTearDown(() async {
    container.dispose();
    setup.coordinator.dispose();
    await setup.database.close();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: TaskTimePiePanel(data: plan, date: _date),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (timer: setup.timer, coordinator: setup.coordinator);
}

Future<void> _timerAction(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  await tester.runAsync(action);
  await tester.pumpAndSettle();
}

Finder _entry(String taskId) => find.byKey(Key('task-time-pie-entry-$taskId'));

String _value(WidgetTester tester, String taskId) =>
    tester.widget<Text>(find.byKey(Key('task-time-pie-value-$taskId'))).data!;

void main() {
  testWidgets('many untimed tasks keep the empty chart responsive', (
    tester,
  ) async {
    final base = _plan(minutes: [0, 0, 0, 0]);
    await _mountPie(
      tester,
      base.copyWith(
        tasks: [
          for (var index = 0; index < 400; index++)
            base.tasks.first.copyWith(
              id: 'future-$index',
              title: '未来事项 $index',
            ),
        ],
        blocks: const [],
      ),
    );
    expect(find.byKey(const Key('task-time-pie-empty')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no actual time shows an empty state despite planned tasks', (
    tester,
  ) async {
    await _mountPie(tester, _plan());

    expect(find.text('今日事项用时'), findsOneWidget);
    expect(find.text('合计 0秒'), findsOneWidget);
    expect(find.text('今天还没有学习用时'), findsOneWidget);
    expect(find.byKey(const Key('task-time-pie-chart')), findsNothing);
    for (final taskId in _taskIds) {
      expect(_entry(taskId), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('actual time determines shares and each task has its own color', (
    tester,
  ) async {
    await _mountPie(tester, _plan(minutes: [90, 45, 15, 0]));

    expect(find.text('合计 2小时30分'), findsOneWidget);
    expect(_value(tester, 'math'), '1小时30分  ·  60%');
    expect(_value(tester, 'english'), '45分  ·  30%');
    expect(_value(tester, 'data-structures'), '15分  ·  10%');
    expect(_entry('not-started'), findsNothing);
    expect(find.text(_titles.last), findsNothing);
    expect(find.byKey(const Key('task-time-pie-chart')), findsOneWidget);

    final colors = <Color>{};
    for (final taskId in _taskIds.take(3)) {
      final swatch = tester.widget<Container>(
        find.byKey(Key('task-time-pie-swatch-$taskId')),
      );
      colors.add((swatch.decoration! as BoxDecoration).color!);
    }
    expect(colors, hasLength(3));
    expect(
      tester.getTopLeft(_entry('math')).dy,
      lessThan(tester.getTopLeft(_entry('english')).dy),
    );
    expect(
      tester.getTopLeft(_entry('english')).dy,
      lessThan(tester.getTopLeft(_entry('data-structures')).dy),
    );
  });

  testWidgets('legend and chart selection expose the chosen task', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _mountPie(tester, _plan(minutes: [90, 45, 15, 0]));

    final englishEntry = _entry('english');
    expect(tester.getSemantics(englishEntry).label, '英语词汇与长难句，45分，30%');
    expect(
      tester.getSemantics(englishEntry).flagsCollection.isSelected ==
          Tristate.isTrue,
      isFalse,
    );
    await tester.tap(englishEntry);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(englishEntry).flagsCollection.isSelected ==
          Tristate.isTrue,
      isTrue,
    );

    final chart = tester.getRect(find.byKey(const Key('task-time-pie-chart')));
    await tester.tapAt(chart.center + Offset(chart.width / 4, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(_entry('math')).flagsCollection.isSelected ==
          Tristate.isTrue,
      isTrue,
    );
    expect(
      tester.getSemantics(englishEntry).flagsCollection.isSelected ==
          Tristate.isTrue,
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets('subminute timer time appears and undo preserves prior logs', (
    tester,
  ) async {
    final clock = _Clock();
    final plan = _plan(minutes: [90, 0, 0, 0]);
    final harness = await _mountPie(tester, plan, clock: clock);
    final originalLogs = [...harness.coordinator.data!.logs];
    expect(_entry('english'), findsNothing);

    await _timerAction(tester, () => harness.timer.start('english', _date));
    clock.elapsed = const Duration(seconds: 37);
    await _timerAction(tester, harness.timer.checkpoint);

    expect(find.text('合计 1小时30分37秒'), findsOneWidget);
    expect(_value(tester, 'english'), '37秒  ·  0.7%');
    expect(_value(tester, 'math'), '1小时30分  ·  99.3%');
    expect(harness.coordinator.data!.logs, originalLogs);

    await _timerAction(tester, harness.timer.pause);
    final session = harness.timer.lastSessionFor('english', _date)!;
    await _timerAction(
      tester,
      () => harness.timer.discardLastSession(
        'english',
        _date,
        expectedSessionId: session.id,
      ),
    );

    expect(_entry('english'), findsNothing);
    expect(find.text('合计 1小时30分'), findsOneWidget);
    expect(_value(tester, 'math'), '1小时30分  ·  100%');
    expect(harness.coordinator.data!.logs, originalLogs);
  });

  testWidgets('long task names fit a narrow panel with enlarged text', (
    tester,
  ) async {
    final plan = _plan(minutes: [90, 45, 15, 0]);
    final longTitle = '${_titles.first}：概念梳理与基础题、错题复习和阶段总结' * 4;
    await _mountPie(
      tester,
      plan.copyWith(
        tasks: [
          plan.tasks.first.copyWith(title: longTitle),
          ...plan.tasks.skip(1),
        ],
      ),
      width: 220,
      textScale: 1.5,
    );

    expect(find.text(longTitle), findsOneWidget);
    expect(_entry('math'), findsOneWidget);
    final panel = tester.getRect(find.byType(TaskTimePiePanel));
    final chart = tester.getRect(find.byKey(const Key('task-time-pie-chart')));
    expect(chart.left, greaterThanOrEqualTo(panel.left));
    expect(chart.right, lessThanOrEqualTo(panel.right));
    expect(tester.takeException(), isNull);
  });
}
