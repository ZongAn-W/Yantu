import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

class _Clock {
  DateTime wall = DateTime.parse('2026-10-17T02:00:00Z');
  Duration monotonic = Duration.zero;

  void advance(Duration duration) {
    wall = wall.add(duration);
    monotonic += duration;
  }
}

class _TimerStore implements StudyTimerStore {
  final values = <String, JsonMap>{};
  bool fail = false;
  Completer<void>? saveGate;

  @override
  Future<JsonMap?> load(String key) async => values[key];

  @override
  Future<void> save(String key, JsonMap value) async {
    final gate = saveGate;
    if (gate != null) {
      saveGate = null;
      await gate.future;
    }
    if (fail) throw StateError('timer disk unavailable');
    final current = values[key];
    final revision = (current?['revision'] as int?) ?? 0;
    if (value['revision'] != revision + 1) {
      throw StudyTimerConflict(current);
    }
    values[key] = JsonMap.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _PlannerStore extends MemoryStorageRepository {
  bool fail = false;

  @override
  Future<void> save(
    String userKey,
    PlannerData data,
    StorageMetadata metadata, {
    bool recovery = false,
  }) async {
    if (fail) throw StateError('planner disk unavailable');
    await super.save(userKey, data, metadata, recovery: recovery);
  }
}

class _OfflineApi implements SyncApi {
  @override
  Future<RemoteSnapshot> pull() async => throw const OfflineFailure();

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int revision,
  ) => throw const OfflineFailure();
}

void main() {
  late _Clock clock;
  late _TimerStore timerStore;
  late _PlannerStore plannerStore;
  late PlannerCoordinator coordinator;
  late StudyTimer timer;
  var sequence = 0;
  const date = '2026-10-17';

  StudyTimer createTimer() => StudyTimer(
    coordinator: coordinator,
    store: timerStore,
    now: () => clock.wall,
    monotonicNow: () => clock.monotonic,
    nextId: () => 'timer-${sequence++}',
    tickInterval: null,
  );

  setUp(() async {
    clock = _Clock();
    timerStore = _TimerStore();
    plannerStore = _PlannerStore();
    final fixture = plannerFixture();
    coordinator = PlannerCoordinator(
      userId: fixture.profile.userId,
      scope: 'timer-tests',
      storage: plannerStore,
      api: _OfflineApi(),
      retryInterval: null,
    );
    coordinator.data = fixture.copyWith(
      logs: [],
      blocks: [fixture.blocks.single.copyWith(date: date, durationMinutes: 1)],
    );
    coordinator.ready = true;
    timer = createTimer();
    await timer.initialize();
  });

  tearDown(() async {
    timer.dispose();
    await coordinator.sync();
    coordinator.dispose();
  });

  String taskId() => coordinator.data!.tasks.first.id;

  test(
    'planned dependencies require actual content confirmation before timing',
    () async {
      final original = coordinator.data!.tasks.first;
      final dependent = original.copyWith(
        id: 'dependent',
        planning: {
          'dependencies': [
            {'task_id': original.id, 'mode': 'planned'},
          ],
        },
      );
      await coordinator.edit(
        (data) => data.copyWith(
          tasks: [
            original.copyWith(
              completedMinutes: original.estimatedMinutes,
              status: TaskStatus.inProgress,
            ),
            dependent,
          ],
        ),
      );
      await expectLater(timer.start(dependent.id, date), throwsStateError);
      expect(timer.activeTaskId, isNull);
      expect(coordinator.data!.logs, isEmpty);
      await coordinator.edit(
        (data) => data.copyWith(
          tasks: [
            data.tasks.first.copyWith(status: TaskStatus.completed),
            dependent,
          ],
        ),
      );
      await timer.start(dependent.id, date);
      expect(timer.activeTaskId, dependent.id);
      await timer.pause();
    },
  );

  test('paused recurring activity cannot start a new timer session', () async {
    final id = taskId();
    await coordinator.edit(
      (data) => data.copyWith(
        tasks: [
          data.tasks.first.copyWith(
            planning: {
              'activity': {
                'kind': 'recurring',
                'state': 'paused',
                'starts_on': date,
                'ends_on': '2026-11-01',
                'sessions_per_week': 2,
                'session_minutes': 30,
              },
            },
          ),
        ],
      ),
    );
    await expectLater(timer.start(id, date), throwsStateError);
    expect(timer.activeTaskId, isNull);
    expect(timer.lastSessionFor(id, date), isNull);
  });

  test(
    'real seconds survive pause, reload and resume without rounding up',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 37));
      await timer.pause();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 37));
      expect(taskDayMinutes(coordinator.data!, id, date), 0);

      timer.dispose();
      clock.advance(const Duration(minutes: 10));
      timer = createTimer();
      await timer.initialize();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 37));
      expect(timer.activeTaskId, isNull);

      await timer.start(id, date);
      clock.advance(const Duration(seconds: 28));
      await timer.pause();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 65));
      expect(taskDayMinutes(coordinator.data!, id, date), 1);
      expect(coordinator.data!.logs.single.source, LogSource.timer);
    },
  );

  test(
    'reopening a running timer includes the time since its durable start',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 12));
      timer.dispose();
      clock.advance(const Duration(seconds: 58));
      timer = createTimer();
      await timer.initialize();
      expect(timer.isRunning(id, date), isTrue);
      expect(timer.elapsedFor(id, date), const Duration(seconds: 70));
      expect(taskDayMinutes(coordinator.data!, id, date), 1);
      clock.advance(const Duration(seconds: 5));
      await timer.pause();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 75));
    },
  );

  test(
    'the live clock uses monotonic elapsed even when system time changes',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 15));
      clock.wall = clock.wall.add(const Duration(hours: 2));
      expect(timer.elapsedFor(id, date), const Duration(seconds: 15));
      await timer.pause();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 15));
    },
  );

  test(
    'starting another task pauses the first and retains both actual totals',
    () async {
      final first = taskId();
      final original = coordinator.data!.tasks.single;
      coordinator.data = coordinator.data!.copyWith(
        tasks: [
          original,
          original.copyWith(id: 'second-task'),
        ],
      );
      await timer.start(first, date);
      clock.advance(const Duration(seconds: 40));
      await timer.start('second-task', date);
      clock.advance(const Duration(seconds: 80));
      await timer.pause();
      expect(timer.elapsedFor(first, date), const Duration(seconds: 40));
      expect(
        timer.elapsedFor('second-task', date),
        const Duration(seconds: 80),
      );
      expect(timer.activeTaskId, isNull);
    },
  );

  test(
    'a reached day goal completes its blocks and keeps timing beyond the goal',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 90));
      await timer.checkpoint();
      expect(coordinator.data!.blocks.single.status, BlockStatus.completed);
      expect(coordinator.data!.tasks.single.status, TaskStatus.inProgress);
      expect(timer.isRunning(id, date), isTrue);
      clock.advance(const Duration(seconds: 40));
      await timer.pause();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 130));
      expect(taskDayMinutes(coordinator.data!, id, date), 2);
    },
  );

  test(
    'Shanghai midnight splits one running session into the correct dates',
    () async {
      final id = taskId();
      clock.wall = DateTime.parse('2026-10-17T15:59:20Z');
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 110));
      await timer.pause();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 40));
      expect(timer.elapsedFor(id, '2026-10-18'), const Duration(seconds: 70));
      expect(taskDayMinutes(coordinator.data!, id, date), 0);
      expect(taskDayMinutes(coordinator.data!, id, '2026-10-18'), 1);
    },
  );

  test(
    'old manual logs remain unchanged when timed minutes are appended',
    () async {
      final id = taskId();
      final manual = plannerFixture().logs.single.copyWith(date: date);
      coordinator.data = coordinator.data!.copyWith(logs: [manual]);
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 70));
      await timer.pause();
      expect(coordinator.data!.logs.first, manual);
      expect(coordinator.data!.logs, hasLength(2));
      expect(
        timer.elapsedFor(id, date),
        const Duration(minutes: 36, seconds: 10),
      );
    },
  );

  test(
    'failed checkpoint keeps all active elapsed and can be retried',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 45));
      timerStore.fail = true;
      await expectLater(timer.pause(), throwsStateError);
      expect(timer.error, isNotNull);
      expect(timer.isRunning(id, date), isTrue);
      clock.advance(const Duration(seconds: 25));
      timerStore.fail = false;
      await timer.pause();
      expect(timer.elapsedFor(id, date), const Duration(seconds: 70));
      expect(taskDayMinutes(coordinator.data!, id, date), 1);
    },
  );

  test(
    'a failed planner write replays its stable timer log exactly once',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 75));
      plannerStore.fail = true;
      await expectLater(timer.pause(), throwsStateError);
      expect(timer.activeTaskId, isNull);
      expect(timer.elapsedFor(id, date), const Duration(seconds: 75));
      expect(coordinator.data!.logs, isEmpty);
      plannerStore.fail = false;
      await timer.checkpoint();
      await timer.checkpoint();
      expect(coordinator.data!.logs, hasLength(1));
      expect(coordinator.data!.logs.single.minutes, 1);
      expect(timer.elapsedFor(id, date), const Duration(seconds: 75));
    },
  );

  test('pause boundaries create removable sessions, not checkpoints', () async {
    final id = taskId();
    await timer.start(id, date);
    final startedAt = clock.wall;
    clock.advance(const Duration(seconds: 37));
    await timer.checkpoint();
    expect(timer.lastSessionFor(id, date), isNull);
    clock.advance(const Duration(seconds: 28));
    await timer.pause();
    final first = timer.lastSessionFor(id, date)!;
    expect(first.startedAt, startedAt);
    expect(first.endedAt, clock.wall);
    expect(first.elapsed, const Duration(seconds: 65));
    expect(first.isLegacy, isFalse);

    await timer.start(id, date);
    clock.advance(const Duration(seconds: 55));
    await timer.pause();
    final second = timer.lastSessionFor(id, date)!;
    expect(second.id, isNot(first.id));
    expect(second.elapsed, const Duration(seconds: 55));
    expect(taskDayMinutes(coordinator.data!, id, date), 2);

    timer.dispose();
    timer = createTimer();
    await timer.initialize();
    expect(timer.lastSessionFor(id, date)!.id, second.id);
    expect(timer.lastSessionFor(id, date)!.elapsed, second.elapsed);
    await timer.discardLastSession(id, date, expectedSessionId: second.id);
    expect(timer.elapsedFor(id, date), const Duration(seconds: 65));
    expect(taskDayMinutes(coordinator.data!, id, date), 1);
    expect(timer.lastSessionFor(id, date)!.id, first.id);
    await timer.discardLastSession(id, date, expectedSessionId: second.id);
    expect(timer.elapsedFor(id, date), const Duration(seconds: 65));
  });

  test(
    'discard persists and resets day progress while preserving manual time',
    () async {
      final id = taskId();
      final manual = plannerFixture().logs.single.copyWith(
        date: date,
        minutes: 90,
      );
      coordinator.data = coordinator.data!.copyWith(
        logs: [manual],
        blocks: [coordinator.data!.blocks.single.copyWith(durationMinutes: 91)],
      );
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 62));
      await timer.pause();
      final session = timer.lastSessionFor(id, date)!;
      expect(coordinator.data!.blocks.single.status, BlockStatus.completed);
      await timer.discardLastSession(id, date, expectedSessionId: session.id);
      expect(coordinator.data!.logs, [manual]);
      expect(coordinator.data!.blocks.single.actualMinutes, 90);
      expect(coordinator.data!.blocks.single.status, BlockStatus.planned);
      expect(
        coordinator.data!.blocks.single.completionStatus,
        CompletionStatus.partial,
      );
      expect(coordinator.data!.tasks.single.completedMinutes, 90);
      timer.dispose();
      timer = createTimer();
      await timer.initialize();
      expect(timer.lastSessionFor(id, date), isNull);
      expect(timer.elapsedFor(id, date), const Duration(minutes: 90));
      await timer.checkpoint();
      expect(coordinator.data!.logs, [manual]);
    },
  );

  test(
    'discard requires a paused timer and the expected latest session',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 10));
      await timer.pause();
      final first = timer.lastSessionFor(id, date)!;
      await timer.start(id, date);
      await expectLater(
        timer.discardLastSession(id, date, expectedSessionId: first.id),
        throwsStateError,
      );
      clock.advance(const Duration(seconds: 15));
      await timer.pause();
      await expectLater(
        timer.discardLastSession(id, date, expectedSessionId: first.id),
        throwsStateError,
      );
      expect(timer.elapsedFor(id, date), const Duration(seconds: 25));
    },
  );

  test(
    'failed discard storage keeps the session available for retry',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 75));
      await timer.pause();
      final session = timer.lastSessionFor(id, date)!;
      timerStore.fail = true;
      await expectLater(
        timer.discardLastSession(id, date, expectedSessionId: session.id),
        throwsStateError,
      );
      expect(timer.elapsedFor(id, date), const Duration(seconds: 75));
      expect(timer.lastSessionFor(id, date)!.id, session.id);
      timerStore.fail = false;
      await timer.discardLastSession(id, date, expectedSessionId: session.id);
      expect(timer.elapsedFor(id, date), Duration.zero);
      expect(coordinator.data!.logs, isEmpty);
      expect(coordinator.data!.blocks.single.status, BlockStatus.planned);
      expect(
        coordinator.data!.blocks.single.completionStatus,
        CompletionStatus.notStarted,
      );
      expect(coordinator.data!.tasks.single.completedMinutes, 0);
    },
  );

  test(
    'failed planner deletion retries without removing the previous session',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 65));
      await timer.pause();
      final first = timer.lastSessionFor(id, date)!;
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 60));
      await timer.pause();
      final second = timer.lastSessionFor(id, date)!;
      plannerStore.fail = true;
      await expectLater(
        timer.discardLastSession(id, date, expectedSessionId: second.id),
        throwsStateError,
      );
      expect(timer.elapsedFor(id, date), const Duration(seconds: 65));
      expect(coordinator.data!.logs.single.minutes, 2);
      expect(timer.lastSessionFor(id, date)!.id, first.id);
      plannerStore.fail = false;
      await timer.discardLastSession(id, date, expectedSessionId: second.id);
      expect(timer.elapsedFor(id, date), const Duration(seconds: 65));
      expect(coordinator.data!.logs.single.minutes, 1);
      await timer.checkpoint();
      expect(coordinator.data!.logs.single.minutes, 1);
    },
  );

  test(
    'legacy daily aggregates are labeled and kept separate from new intervals',
    () async {
      final id = taskId();
      final manual = plannerFixture().logs.single.copyWith(
        date: date,
        minutes: 90,
      );
      coordinator.data = coordinator.data!.copyWith(logs: [manual]);
      timerStore.values[timer.storageKey] = {
        'version': 1,
        'revision': 0,
        'active': null,
        'buckets': [
          {
            'id': 'legacy-log',
            'taskId': id,
            'date': date,
            'milliseconds': 61000,
            'startedAt': '2026-10-17T00:00:00Z',
            'endedAt': '2026-10-17T01:00:00Z',
          },
        ],
      };
      timer.dispose();
      timer = createTimer();
      await timer.initialize();
      final legacy = timer.lastSessionFor(id, date)!;
      expect(legacy.isLegacy, isTrue);
      expect(legacy.elapsed, const Duration(seconds: 61));
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 2));
      await timer.pause();
      final newSession = timer.lastSessionFor(id, date)!;
      expect(newSession.isLegacy, isFalse);
      expect(newSession.elapsed, const Duration(seconds: 2));
      await timer.discardLastSession(
        id,
        date,
        expectedSessionId: newSession.id,
      );
      expect(
        timer.elapsedFor(id, date),
        const Duration(minutes: 91, seconds: 1),
      );
      expect(timer.lastSessionFor(id, date)!.id, legacy.id);
      expect(timerStore.values[timer.storageKey]!['version'], 2);
      await timer.discardLastSession(id, date, expectedSessionId: legacy.id);
      expect(timer.elapsedFor(id, date), const Duration(minutes: 90));
      expect(coordinator.data!.logs, [manual]);
    },
  );

  test(
    'deleting a midnight session removes its time from both dates',
    () async {
      final id = taskId();
      clock.wall = DateTime.parse('2026-10-17T15:59:20Z');
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 110));
      await timer.pause();
      final session = timer.lastSessionFor(id, '2026-10-18')!;
      expect(session.elapsed, const Duration(seconds: 110));
      expect(timer.lastSessionFor(id, date)!.id, session.id);
      await timer.discardLastSession(
        id,
        '2026-10-18',
        expectedSessionId: session.id,
      );
      expect(timer.elapsedFor(id, date), Duration.zero);
      expect(timer.elapsedFor(id, '2026-10-18'), Duration.zero);
      expect(coordinator.data!.logs, isEmpty);
    },
  );

  test(
    'deleting another task session preserves the currently running interval',
    () async {
      final first = taskId();
      final task = coordinator.data!.tasks.single;
      coordinator.data = coordinator.data!.copyWith(
        tasks: [
          task,
          task.copyWith(id: 'second-task'),
        ],
      );
      await timer.start(first, date);
      clock.advance(const Duration(seconds: 40));
      await timer.start('second-task', date);
      final firstSession = timer.lastSessionFor(first, date)!;
      clock.advance(const Duration(seconds: 20));
      await timer.discardLastSession(
        first,
        date,
        expectedSessionId: firstSession.id,
      );
      clock.advance(const Duration(seconds: 25));
      await timer.pause();
      expect(timer.elapsedFor(first, date), Duration.zero);
      expect(
        timer.elapsedFor('second-task', date),
        const Duration(seconds: 45),
      );
    },
  );

  test(
    'a stale tab cannot delete a session added after its confirmation',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 40));
      await timer.pause();
      final first = timer.lastSessionFor(id, date)!;
      final otherCoordinator = PlannerCoordinator(
        userId: coordinator.userId,
        scope: coordinator.scope,
        storage: _PlannerStore(),
        api: _OfflineApi(),
        retryInterval: null,
      )..data = coordinator.data;
      addTearDown(otherCoordinator.dispose);
      final other = StudyTimer(
        coordinator: otherCoordinator,
        store: timerStore,
        now: () => clock.wall,
        monotonicNow: () => clock.monotonic,
        nextId: () => 'timer-${sequence++}',
        tickInterval: null,
      );
      addTearDown(other.dispose);
      await other.initialize();
      await other.start(id, date);
      clock.advance(const Duration(seconds: 30));
      await other.pause();
      final latest = other.lastSessionFor(id, date)!;
      await expectLater(
        timer.discardLastSession(id, date, expectedSessionId: first.id),
        throwsA(isA<StudyTimerConflict>()),
      );
      expect(timer.elapsedFor(id, date), const Duration(seconds: 70));
      expect(timer.lastSessionFor(id, date)!.id, latest.id);
      await expectLater(
        timer.discardLastSession(id, date, expectedSessionId: first.id),
        throwsStateError,
      );
      expect(other.elapsedFor(id, date), const Duration(seconds: 70));
    },
  );

  test(
    'restored planner snapshots cannot resurrect discarded timer minutes',
    () async {
      final id = taskId();
      await timer.start(id, date);
      clock.advance(const Duration(seconds: 75));
      await timer.pause();
      final oldLogs = coordinator.data!.logs;
      final session = timer.lastSessionFor(id, date)!;
      await timer.discardLastSession(id, date, expectedSessionId: session.id);
      await coordinator.edit((data) => data.copyWith(logs: oldLogs));
      await timer.checkpoint();
      expect(coordinator.data!.logs, isEmpty);
      expect(timer.elapsedFor(id, date), Duration.zero);
    },
  );

  test('the timer refuses dates other than today', () async {
    await expectLater(timer.start(taskId(), '2026-10-16'), throwsStateError);
    expect(timer.activeTaskId, isNull);
  });

  test('a stale tab cannot restart a timer paused in another tab', () async {
    final database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase('timer-tabs'),
    );
    addTearDown(database.close);
    StudyTimer tab() => StudyTimer(
      coordinator: coordinator,
      store: LocalStudyTimerStore(database),
      now: () => clock.wall,
      monotonicNow: () => clock.monotonic,
      nextId: () => 'tab-timer-${sequence++}',
      tickInterval: null,
    );
    timer.dispose();
    timer = tab();
    await timer.initialize();
    final id = taskId();
    await timer.start(id, date);
    clock.advance(const Duration(seconds: 30));
    final otherTab = tab();
    addTearDown(otherTab.dispose);
    await otherTab.initialize();
    clock.advance(const Duration(seconds: 10));
    await otherTab.pause();
    clock.advance(const Duration(seconds: 40));

    await expectLater(timer.checkpoint(), throwsA(isA<StudyTimerConflict>()));
    expect(timer.activeTaskId, isNull);
    expect(timer.elapsedFor(id, date), const Duration(seconds: 40));
    expect(
      (await LocalStudyTimerStore(database).load(timer.storageKey))!['active'],
      isNull,
    );
    await timer.checkpoint();
    expect(timer.activeTaskId, isNull);
    expect(timer.elapsedFor(id, date), const Duration(seconds: 40));
  });

  for (final change in ['archived', 'completed', 'deleted']) {
    test(
      'a task $change during a checkpoint is paused after that write',
      () async {
        final id = taskId();
        await timer.start(id, date);
        clock.advance(const Duration(seconds: 15));
        final gate = Completer<void>();
        timerStore.saveGate = gate;
        final checkpoint = timer.checkpoint();
        await Future<void>.delayed(Duration.zero);
        expect(timer.busy, isTrue);
        await coordinator.edit(
          (data) => data.copyWith(
            tasks: change == 'deleted'
                ? []
                : [
                    data.tasks.single.copyWith(
                      status: change == 'archived'
                          ? TaskStatus.archived
                          : TaskStatus.completed,
                    ),
                  ],
            blocks: change == 'deleted' ? [] : data.blocks,
          ),
        );
        gate.complete();
        await checkpoint;
        for (
          var attempt = 0;
          attempt < 10 && timer.activeTaskId != null;
          attempt++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(timer.activeTaskId, isNull);
        expect(timerStore.values[timer.storageKey]!['active'], isNull);
      },
    );
  }

  test(
    'atomic checkpoint revisions admit only one concurrent writer',
    () async {
      final database = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase('timer-atomic'),
      );
      addTearDown(database.close);
      final first = LocalStudyTimerStore(database);
      final second = LocalStudyTimerStore(database);
      await first.save('shared', {'version': 1, 'revision': 1});
      final outcomes = await Future.wait([
        first
            .save('shared', {'version': 1, 'revision': 2, 'active': 'first'})
            .then<Object?>((_) => null, onError: (Object error) => error),
        second
            .save('shared', {'version': 1, 'revision': 2, 'active': 'second'})
            .then<Object?>((_) => null, onError: (Object error) => error),
      ]);
      expect(outcomes.whereType<StudyTimerConflict>(), hasLength(1));
      expect(outcomes.where((outcome) => outcome == null), hasLength(1));
      expect((await first.load('shared'))!['revision'], 2);
    },
  );

  test('Sembast checkpoints are isolated by account and API scope', () async {
    final database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase('timer-scopes'),
    );
    addTearDown(database.close);
    final store = LocalStudyTimerStore(database);
    await store.save('api-one:user-a', {'version': 1, 'elapsed': 12345});
    await store.save('api-one:user-b', {'version': 1, 'elapsed': 9000});
    expect((await store.load('api-one:user-a'))!['elapsed'], 12345);
    expect((await store.load('api-one:user-b'))!['elapsed'], 9000);
    expect(await store.load('api-two:user-a'), isNull);
  });
}
