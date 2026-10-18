import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// 冲突解决必须与计时器的持久化状态共同生效。
///
/// 场景：两台设备在同一基线下离线计时，同一事项同一天分别产生本机 10 分钟和
/// 云端 20 分钟。用户显式选择「采用云端」后，本机计时桶不能在下一次 checkpoint
/// 或应用重建时把被舍弃的 10 分钟写回计划。
void main() {
  const date = '2026-10-17';
  final fixture = plannerFixture();

  late _Clock clock;
  late _TimerStore timerStore;
  late _PlannerStore plannerStore;
  late _RemoteSync remote;
  late PlannerCoordinator coordinator;
  late StudyTimer timer;
  var sequence = 0;

  PlannerData basePlan() {
    final task = fixture.tasks.single;
    final second = task.copyWith(id: 'second-task', title: '第二项');
    return fixture.copyWith(
      logs: [],
      tasks: [task, second],
      blocks: [
        fixture.blocks.single.copyWith(date: date, durationMinutes: 120),
        fixture.blocks.single.copyWith(
          id: 'block-second',
          taskId: second.id,
          date: date,
          durationMinutes: 120,
        ),
      ],
    );
  }

  TimeLog remoteLog(String taskId, String date, int minutes) => TimeLog(
    id: 'remote-log',
    userId: fixture.profile.userId,
    taskId: taskId,
    blockId: null,
    date: date,
    minutes: minutes,
    startedAt: '2026-10-17T00:00:00.000Z',
    endedAt: '2026-10-17T00:20:00.000Z',
    source: LogSource.manual,
  );

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
    remote = _RemoteSync(basePlan())..offline = true;
    coordinator = PlannerCoordinator(
      userId: fixture.profile.userId,
      scope: 'timer-conflict-tests',
      storage: plannerStore,
      api: remote,
      retryInterval: null,
    );
    final plan = basePlan();
    coordinator.data = plan;
    coordinator.metadata = SyncMetadata(base: plan, revision: 1);
    coordinator.ready = true;
    timer = createTimer();
    await timer.initialize();
  });

  tearDown(() {
    timer.dispose();
    coordinator.dispose();
  });

  Future<void> raisePendingConflict(String taskId) async {
    // Drain the offline attempt queued by the last local edit before pointing the
    // fake server at the conflicting document.
    await coordinator.sync();
    remote.data = basePlan().copyWith(logs: [remoteLog(taskId, date, 20)]);
    remote.revision = 2;
    remote.offline = false;
    await coordinator.sync();
    expect(coordinator.conflicts, isNotEmpty);
  }

  int minutesFor(String taskId, String day) =>
      taskDayMinutes(coordinator.data!, taskId, day);

  test(
    'adopting cloud discards local timer minutes across checkpoint and rebuild',
    () async {
      final id = coordinator.data!.tasks.first.id;
      await timer.start(id, date);
      clock.advance(const Duration(minutes: 10));
      await timer.pause();
      expect(minutesFor(id, date), 10);

      await raisePendingConflict(id);
      await coordinator.resolve(useLocal: false);

      expect(minutesFor(id, date), 20);
      expect(timer.elapsedFor(id, date), const Duration(minutes: 20));

      await timer.checkpoint();
      expect(minutesFor(id, date), 20);

      timer.dispose();
      timer = createTimer();
      await timer.initialize();
      await timer.checkpoint();
      expect(minutesFor(id, date), 20);
      expect(timer.elapsedFor(id, date), const Duration(minutes: 20));
    },
  );

  test(
    'adopting cloud while running only counts time after the resolution',
    () async {
      final id = coordinator.data!.tasks.first.id;
      await timer.start(id, date);
      clock.advance(const Duration(minutes: 10));
      await timer.checkpoint();
      expect(minutesFor(id, date), 10);

      await raisePendingConflict(id);
      await coordinator.resolve(useLocal: false);

      expect(timer.activeTaskId, id, reason: '计时器应保持运行');
      expect(minutesFor(id, date), 20);

      clock.advance(const Duration(minutes: 5));
      await timer.pause();
      expect(minutesFor(id, date), 25);
      expect(timer.elapsedFor(id, date), const Duration(minutes: 25));
    },
  );

  test('adopting local keeps the local minutes stable and idempotent', () async {
    final id = coordinator.data!.tasks.first.id;
    await timer.start(id, date);
    clock.advance(const Duration(minutes: 10));
    await timer.pause();

    await raisePendingConflict(id);
    await coordinator.resolve(useLocal: true);

    expect(minutesFor(id, date), 10);
    await timer.checkpoint();
    expect(minutesFor(id, date), 10);
    await timer.checkpoint();
    expect(coordinator.data!.logs.where((log) => log.taskId == id), hasLength(1));

    timer.dispose();
    timer = createTimer();
    await timer.initialize();
    await timer.checkpoint();
    expect(minutesFor(id, date), 10);
  });

  test('other dates keep their local timer records after a cloud resolution', () async {
    final id = coordinator.data!.tasks.first.id;
    clock.wall = DateTime.parse('2026-10-17T15:59:00Z');
    await timer.start(id, date);
    clock.advance(const Duration(seconds: 180));
    await timer.pause();
    expect(minutesFor(id, date), 1);
    expect(minutesFor(id, '2026-10-18'), 2);

    await raisePendingConflict(id);
    await coordinator.resolve(useLocal: false);

    expect(minutesFor(id, date), 20);
    expect(minutesFor(id, '2026-10-18'), 2);

    await timer.checkpoint();
    expect(minutesFor(id, date), 20);
    expect(minutesFor(id, '2026-10-18'), 2);
  });

  test(
    'failed local replay is retried once without resurrecting discarded minutes',
    () async {
      final first = coordinator.data!.tasks.first.id;
      const second = 'second-task';
      await timer.start(first, date);
      clock.advance(const Duration(minutes: 10));
      await timer.pause();

      // The second task's local write fails: its timer bucket is pending replay,
      // not a user-discarded record.
      plannerStore.fail = true;
      await timer.start(second, date);
      clock.advance(const Duration(minutes: 7));
      await expectLater(timer.pause(), throwsStateError);
      expect(coordinator.data!.logs.where((log) => log.taskId == second), isEmpty);

      await raisePendingConflict(first);
      plannerStore.fail = false;
      await coordinator.resolve(useLocal: false);
      await timer.checkpoint();

      expect(minutesFor(first, date), 20);
      expect(minutesFor(second, date), 7);
      expect(
        coordinator.data!.logs.where((log) => log.taskId == second),
        hasLength(1),
      );

      await timer.checkpoint();
      await timer.checkpoint();
      expect(minutesFor(first, date), 20);
      expect(minutesFor(second, date), 7);
      expect(
        coordinator.data!.logs.where((log) => log.taskId == second),
        hasLength(1),
      );
    },
  );

  test('a failed resolution keeps the conflict and can be retried', () async {
    final id = coordinator.data!.tasks.first.id;
    await timer.start(id, date);
    clock.advance(const Duration(minutes: 10));
    await timer.pause();

    await raisePendingConflict(id);
    plannerStore.fail = true;
    await expectLater(
      coordinator.resolve(useLocal: false),
      throwsA(isA<StateError>()),
    );
    expect(coordinator.conflicts, isNotEmpty);

    plannerStore.fail = false;
    await coordinator.resolve(useLocal: false);
    await timer.checkpoint();
    expect(minutesFor(id, date), 20);
    expect(coordinator.conflicts, isEmpty);
  });

  test(
    'a checkpoint already queued when the decision is made cannot overwrite it',
    () async {
      final id = coordinator.data!.tasks.first.id;
      await timer.start(id, date);
      clock.advance(const Duration(minutes: 10));
      await timer.pause();
      await raisePendingConflict(id);

      final gate = Completer<void>();
      timerStore.saveGate = gate;
      final checkpoint = timer.checkpoint();
      await Future<void>.delayed(Duration.zero);

      final resolution = coordinator.resolve(useLocal: false);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await checkpoint;
      await resolution;

      await timer.checkpoint();
      expect(minutesFor(id, date), 20);
    },
  );
}

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

class _RemoteSync implements SyncApi {
  _RemoteSync(this.data);

  PlannerData? data;
  int revision = 1;
  bool offline = false;
  int pushes = 0;

  @override
  Future<RemoteSnapshot> pull({int? revision}) async {
    if (offline) throw const OfflineFailure();
    return RemoteSnapshot(data, this.revision);
  }

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    if (offline) throw const OfflineFailure();
    if (expected != revision) {
      return RemoteSnapshot(data, revision, conflict: true);
    }
    pushes++;
    data = next;
    revision++;
    return RemoteSnapshot(data, revision);
  }
}
