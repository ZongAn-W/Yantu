import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// Remote double whose failures are scripted per call.
///
/// [pullFailures] is consumed one entry per `pull`; once empty a normal snapshot is
/// returned. [pullGate] puts a caller-controlled delay inside a pull so a test can
/// make an edit while a sync cycle is in flight.
class ScriptedSync implements SyncApi {
  ScriptedSync(this.data);
  PlannerData? data;
  int revision = 1;
  int pushes = 0;
  int pulls = 0;
  final List<Object> pullFailures = [];
  Completer<void>? pullGate;

  @override
  Future<RemoteSnapshot> pull() async {
    pulls++;
    final gate = pullGate;
    if (gate != null) {
      pullGate = null;
      await gate.future;
    }
    if (pullFailures.isNotEmpty) throw pullFailures.removeAt(0);
    return RemoteSnapshot(data, revision);
  }

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    pushes++;
    if (expected != revision) {
      return RemoteSnapshot(data, revision, conflict: true);
    }
    data = next;
    revision++;
    return RemoteSnapshot(data, revision);
  }
}

/// Lets the coordinator's fire-and-forget sync cycle finish before the next step.
Future<void> settle() async {
  for (var turn = 0; turn < 8; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  var sequence = 0;
  late LocalDatabase database;
  late SembastStorageRepository storage;
  late ScriptedSync remote;

  setUp(() {
    database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase('coord-${sequence++}'),
    );
    storage = SembastStorageRepository(database: database);
    remote = ScriptedSync(plannerFixture());
  });
  tearDown(() => database.close());

  PlannerCoordinator create({
    String? userId,
    String scope = 'test',
    SyncApi? api,
  }) => PlannerCoordinator(
    userId: userId ?? plannerFixture().profile.userId,
    scope: scope,
    storage: storage,
    api: api ?? remote,
    retryInterval: null,
  );

  test(
    'an offline start keeps the cached local plan and reports offline',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      // Simulate a device that synced before and is now offline.
      final cached = plannerFixture().copyWith(
        tasks: [plannerFixture().tasks.single.copyWith(title: '离线缓存事项')],
      );
      await storage.save(
        coordinator.key,
        cached,
        const StorageMetadata(revision: 1),
      );
      remote.pullFailures.add(const OfflineFailure());
      await coordinator.initialize();
      expect(coordinator.data!.tasks.single.title, '离线缓存事项');
      expect(coordinator.status, SyncStatus.offline);
      expect(coordinator.blocked, isFalse);
      expect(coordinator.conflicts, isEmpty);
    },
  );

  test(
    'a brand new account that is offline stays unblocked with no plan',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      remote.data = null;
      remote.pullFailures.add(const OfflineFailure());
      await coordinator.initialize();
      // Nothing to show yet, but the workspace must stay usable and editable later.
      expect(coordinator.data, isNull);
      expect(coordinator.status, SyncStatus.offline);
      expect(coordinator.blocked, isFalse);

      remote.pullFailures.clear();
      await coordinator.sync();
      expect(coordinator.data, isNotNull);
      expect(coordinator.status, SyncStatus.connected);
    },
  );

  test(
    'a retry after a transient failure reaches connected without losing edits',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      expect(coordinator.status, SyncStatus.connected);

      // A later pull fails: the local plan stays editable and marked pending.
      remote.pullFailures.add(const ServerFailure('维护中'));
      await coordinator.edit(
        (data) =>
            data.copyWith(tasks: [data.tasks.single.copyWith(title: '离线期间修改')]),
      );
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.error);
      expect(coordinator.pending, isTrue);
      expect(coordinator.data!.tasks.single.title, '离线期间修改');

      remote.pullFailures.clear();
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.connected);
      expect(coordinator.pending, isFalse);
      expect(coordinator.data!.tasks.single.title, '离线期间修改');
      expect(remote.data!.tasks.single.title, '离线期间修改');
    },
  );

  test(
    'a pending local edit survives a failing pull and uploads on retry',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      await coordinator.edit(
        (data) =>
            data.copyWith(profile: data.profile.copyWith(targetSchool: '待上传')),
      );
      // `edit` schedules its own sync; let that cycle finish before injecting the
      // failure so the assertion observes the failure we intended.
      await settle();

      remote.pullFailures.add(const OfflineFailure());
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.offline);
      expect(coordinator.data!.profile.targetSchool, '待上传');

      remote.pullFailures.clear();
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.connected);
      expect(coordinator.pending, isFalse);
      expect(remote.data!.profile.targetSchool, '待上传');
    },
  );

  test('concurrent sync calls share a single in-flight cycle', () async {
    final coordinator = create();
    addTearDown(coordinator.dispose);
    remote.data = null;
    await coordinator.initialize();
    final gate = Completer<void>();
    remote.pullGate = gate;
    final first = coordinator.sync();
    final second = coordinator.sync();
    expect(identical(first, second), isTrue);
    gate.complete();
    await first;
    expect(coordinator.status, SyncStatus.connected);
  });

  test(
    'a local save failure is reported and the network is never used',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      final db = await database.database;
      await storage.store.record(coordinator.key).put(db, 'broken');
      await storage.store.record('${coordinator.key}:backup').put(db, 'broken');
      await expectLater(
        coordinator.edit((data) => data.copyWith(phases: const [])),
        throwsA(anything),
      );
      expect(remote.pushes, 0);
    },
  );

  test('two accounts on one device never share plan rows', () async {
    final remoteA = ScriptedSync(forAccount(plannerFixture(), 'user-a'));
    final remoteB = ScriptedSync(forAccount(plannerFixture(), 'user-b'));
    final first = create(userId: 'user-a', api: remoteA);
    addTearDown(first.dispose);
    await first.initialize();
    await first.edit(
      (data) =>
          data.copyWith(tasks: [data.tasks.single.copyWith(title: 'A 的事项')]),
    );

    await first.sync();
    final second = create(userId: 'user-b', api: remoteB);
    addTearDown(second.dispose);
    await second.initialize();
    expect(second.key, isNot(first.key));
    // A fresh account must not inherit the other account's local plan.
    expect(second.data?.tasks.any((task) => task.title == 'A 的事项'), isFalse);

    await second.edit(
      (data) =>
          data.copyWith(tasks: [data.tasks.single.copyWith(title: 'B 的事项')]),
    );

    await second.sync();
    final reloadedFirst = create(userId: 'user-a', api: remoteA);
    addTearDown(reloadedFirst.dispose);
    await reloadedFirst.initialize();
    expect(reloadedFirst.data!.tasks.single.title, 'A 的事项');
  });

  test(
    'the storage key includes the API scope so two servers stay separate',
    () async {
      final local = create(scope: 'http%3A%2F%2F127.0.0.1%3A8787');
      addTearDown(local.dispose);
      final remoteApi = create(scope: 'https%3A%2F%2Fapi.example.com');
      addTearDown(remoteApi.dispose);
      expect(local.key, isNot(remoteApi.key));
      expect(local.key, contains('127.0.0.1%3A8787'));
      expect(remoteApi.key, contains('api.example.com'));
    },
  );

  test(
    'a remote-only change is adopted when there is nothing pending',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      remote.data = remote.data!.copyWith(
        profile: remote.data!.profile.copyWith(targetSchool: '云端新目标'),
      );
      remote.revision++;
      await coordinator.sync();
      expect(coordinator.data!.profile.targetSchool, '云端新目标');
      expect(coordinator.pending, isFalse);
      expect(coordinator.status, SyncStatus.connected);
    },
  );

  test(
    'a deleted server plan pauses instead of silently wiping local data',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      final localTitle = coordinator.data!.tasks.single.title;
      remote.data = null;
      remote.revision++;
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.conflict);
      expect(coordinator.conflicts, isNotEmpty);
      expect(coordinator.data!.tasks.single.title, localTitle);
    },
  );

  test('a pending plan is uploaded even when the server is untouched', () async {
    final coordinator = create();
    addTearDown(coordinator.dispose);
    remote.data = null;
    await coordinator.initialize();
    // No server plan and no local plan: the coordinator bootstraps a minimal one.
    expect(coordinator.data, isNotNull);
    await coordinator.sync();
    expect(remote.data, isNotNull);
    expect(coordinator.pending, isFalse);
  });

  test('disposing a coordinator cancels its periodic retry timer', () async {
    final coordinator = PlannerCoordinator(
      userId: plannerFixture().profile.userId,
      scope: 'timer-test',
      storage: storage,
      api: remote,
      retryInterval: const Duration(milliseconds: 20),
    );
    await coordinator.initialize();
    coordinator.dispose();
    var pushesBefore = remote.pushes;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(remote.pushes, pushesBefore);
  });

  test('an edit made while a pull is in flight is not lost', () async {
    final coordinator = create();
    addTearDown(coordinator.dispose);
    await coordinator.initialize();
    final gate = Completer<void>();
    remote.pullGate = gate;
    final syncing = coordinator.sync();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await coordinator.edit(
      (data) => data.copyWith(
        profile: data.profile.copyWith(targetProgram: '排队中的修改'),
      ),
    );
    gate.complete();
    await syncing;
    // The cycle that was already running must carry the queued edit to the server
    // instead of finishing with the snapshot it started from.
    expect(coordinator.data!.profile.targetProgram, '排队中的修改');
    expect(remote.data!.profile.targetProgram, '排队中的修改');
    expect(coordinator.pending, isFalse);
  });

  test('two edits queued during one pull are both uploaded', () async {
    final coordinator = create();
    addTearDown(coordinator.dispose);
    await coordinator.initialize();
    final gate = Completer<void>();
    remote.pullGate = gate;
    final syncing = coordinator.sync();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await coordinator.edit(
      (data) =>
          data.copyWith(profile: data.profile.copyWith(targetSchool: '第一个')),
    );
    await coordinator.edit(
      (data) =>
          data.copyWith(profile: data.profile.copyWith(targetProgram: '第二个')),
    );
    gate.complete();
    await syncing;
    expect(remote.data!.profile.targetSchool, '第一个');
    expect(remote.data!.profile.targetProgram, '第二个');
    expect(coordinator.pending, isFalse);
  });
}
