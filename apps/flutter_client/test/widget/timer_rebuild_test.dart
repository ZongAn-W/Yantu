import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/presentation/task_study_timer.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

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
  Future<RemoteSnapshot> pull({int? revision}) async =>
      RemoteSnapshot(data, this.revision);

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
    planning: {'version': 1, 'mode': 'full', 'rolling': false},
    blocks: [fixture.blocks.single.copyWith(date: date)],
    logs: const [],
  );
}

LocalDatabase _database() => LocalDatabase(
  open: () => databaseFactoryMemory.openDatabase(
    'timer-rebuild-widget-${_databaseSequence++}',
  ),
);

Future<({StudyTimer timer, PlannerCoordinator coordinator})> _mountTimer(
  WidgetTester tester,
  _Clock clock,
) async {
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
              width: 500,
              child: TaskStudyTimer(
                taskId: plan.tasks.single.id,
                date: shanghaiToday(clock.now()),
                plannedMinutes: 90,
                color: Colors.blue,
                canStart: true,
                heading: const Text('高数基础一轮：概念梳理与基础题'),
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
  testWidgets('a tick refreshes only the clock, not the card controls', (
    tester,
  ) async {
    final clock = _Clock(DateTime.utc(2026, 10, 17, 4));
    final harness = await _mountTimer(tester, clock);
    final taskId = harness.coordinator.data!.tasks.single.id;
    final date = shanghaiToday(clock.now());
    final actionFinder = find.byKey(Key('study-timer-action-$taskId-$date'));
    final clockFinder = find.byKey(Key('study-clock-$taskId-$date'));

    await _pressTimer(tester, harness.timer, '开始计时');
    expect(find.text('暂停计时'), findsOneWidget);

    // Simulate the first one-second tick: the card now sees elapsed > 0.
    clock.elapsed = const Duration(seconds: 2);
    // A tick is a ChangeNotifier notification; notify it directly instead of
    // waiting a real second in the test's fake clock.
    // ignore: invalid_use_of_protected_member
    harness.timer.notifyListeners();
    await tester.pump();
    expect(find.text('00:00:02'), findsOneWidget);

    final cardAction = tester.widget(actionFinder);
    final cardClock = tester.widget(clockFinder);

    // A later tick changes only the elapsed time.
    clock.elapsed = const Duration(seconds: 5);
    // ignore: invalid_use_of_protected_member
    harness.timer.notifyListeners();
    await tester.pump();

    expect(find.text('00:00:05'), findsOneWidget);
    expect(
      identical(tester.widget(actionFinder), cardAction),
      isTrue,
      reason: 'a tick must not rebuild the card controls',
    );
    expect(
      identical(tester.widget(clockFinder), cardClock),
      isFalse,
      reason: 'the clock must rebuild on a tick',
    );
    expect(find.text('暂停计时'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pausing keeps the previous interval local to the clock dock', (
    tester,
  ) async {
    final clock = _Clock(DateTime.utc(2026, 10, 17, 4));
    final harness = await _mountTimer(tester, clock);
    final taskId = harness.coordinator.data!.tasks.single.id;
    final date = shanghaiToday(clock.now());

    await _pressTimer(tester, harness.timer, '开始计时');
    clock.elapsed = const Duration(seconds: 37);
    await _pressTimer(tester, harness.timer, '暂停计时');

    expect(find.text('00:00:37'), findsOneWidget);
    expect(find.text('继续计时'), findsOneWidget);
    expect(find.text('上一段 00:00:37'), findsOneWidget);
    expect(find.byKey(Key('undo-study-session-$taskId-$date')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
