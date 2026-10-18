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
/// make an edit while a sync cycle is in flight. [returnUnchanged] models a server
/// with the conditional-read fast path: when the client's known revision matches,
/// only `{revision, unchanged: true}` is returned (no full document).
class ScriptedSync implements SyncApi {
  ScriptedSync(this.data);
  PlannerData? data;
  int revision = 1;
  int pushes = 0;
  int pulls = 0;
  bool returnUnchanged = false;
  final List<int?> pullRevisions = [];
  final List<Object> pullFailures = [];
  final List<Object> pushFailures = [];
  Completer<void>? pullGate;

  @override
  Future<RemoteSnapshot> pull({int? revision}) async {
    pulls++;
    pullRevisions.add(revision);
    final gate = pullGate;
    if (gate != null) {
      pullGate = null;
      await gate.future;
    }
    if (pullFailures.isNotEmpty) throw pullFailures.removeAt(0);
    if (returnUnchanged && revision != null && revision == this.revision) {
      return RemoteSnapshot(null, this.revision, unchanged: true);
    }
    return RemoteSnapshot(data, this.revision);
  }

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    pushes++;
    if (pushFailures.isNotEmpty) throw pushFailures.removeAt(0);
    if (expected != revision) {
      return RemoteSnapshot(data, revision, conflict: true);
    }
    data = next;
    revision++;
    return RemoteSnapshot(data, revision);
  }
}

/// Counts real local saves so fast-path tests can prove no rebuild/persist happens.
class CountingStorage implements StorageRepository {
  CountingStorage(this.inner);
  final StorageRepository inner;
  int saves = 0;

  @override
  Future<StorageSnapshot> load(String userKey) => inner.load(userKey);

  @override
  Future<void> save(
    String userKey,
    PlannerData data,
    StorageMetadata metadata, {
    bool recovery = false,
  }) {
    saves++;
    return inner.save(userKey, data, metadata, recovery: recovery);
  }

  @override
  Future<String?> exportJson(PlannerData data) => inner.exportJson(data);

  @override
  Future<PlannerData?> importJson() => inner.importJson();

  @override
  Future<void> restore(String userKey, PlannerData data) =>
      inner.restore(userKey, data);

  @override
  Future<void> markPending(String userKey, bool pending) =>
      inner.markPending(userKey, pending);

  @override
  Future<StorageSnapshot> recoverFromBackup(String userKey) =>
      inner.recoverFromBackup(userKey);
}

/// Waits until the coordinator has no in-flight cycle and nothing left to upload.
Future<void> waitForSyncIdle(
  PlannerCoordinator coordinator, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while ((coordinator.busy || coordinator.pending) &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(
    coordinator.busy || coordinator.pending,
    isFalse,
    reason: '同步未在超时前完成',
  );
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
    StorageRepository? storageOverride,
    Duration uploadDebounce = const Duration(milliseconds: 500),
    Duration uploadMaxWait = const Duration(seconds: 1),
  }) => PlannerCoordinator(
    userId: userId ?? plannerFixture().profile.userId,
    scope: scope,
    storage: storageOverride ?? storage,
    api: api ?? remote,
    retryInterval: null,
    uploadDebounce: uploadDebounce,
    uploadMaxWait: uploadMaxWait,
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

  test(
    'an unchanged poll with a known revision skips merge, persistence and rebuild',
    () async {
      final counting = CountingStorage(storage);
      final coordinator = create(storageOverride: counting);
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      final dataBefore = coordinator.data;
      final savesBefore = counting.saves;
      final pullsBefore = remote.pulls;
      remote.returnUnchanged = true;
      await coordinator.sync();
      expect(remote.pulls - pullsBefore, 1);
      expect(remote.pullRevisions.last, remote.revision);
      expect(counting.saves, savesBefore);
      expect(identical(coordinator.data, dataBefore), isTrue);
      expect(coordinator.pending, isFalse);
      expect(coordinator.status, SyncStatus.connected);
    },
  );

  test(
    'pending edits upload directly when the server revision is unchanged',
    () async {
      final counting = CountingStorage(storage);
      final coordinator = create(storageOverride: counting);
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      remote.returnUnchanged = true;
      counting.saves = 0;
      final knownRevision = remote.revision;
      final pullsBefore = remote.pulls;
      final pushesBefore = remote.pushes;
      final started = DateTime.now();
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetSchool: '快速上传'),
        ),
      );
      await coordinator.sync();
      final elapsed = DateTime.now().difference(started);
      expect(remote.pulls - pullsBefore, 1);
      expect(remote.pullRevisions.last, knownRevision);
      expect(remote.pushes - pushesBefore, 1);
      expect(remote.data!.profile.targetSchool, '快速上传');
      // 本机编辑 1 次落盘 + 上传响应 1 次落盘；unchanged 路径没有 merge 中间落盘。
      expect(counting.saves, 2);
      expect(coordinator.pending, isFalse);
      expect(coordinator.status, SyncStatus.connected);
      // 手动 sync() 立即发出，不受合并窗口阻塞。
      expect(elapsed, lessThan(const Duration(seconds: 2)));
    },
  );

  test('a revision change after the fast path is never missed', () async {
    final coordinator = create();
    addTearDown(coordinator.dispose);
    await coordinator.initialize();
    remote.returnUnchanged = true;
    await coordinator.sync();
    expect(coordinator.status, SyncStatus.connected);
    // 关系表写入导致 revision 递增后，服务端回退到完整文档路径。
    remote.returnUnchanged = false;
    remote.data = remote.data!.copyWith(
      profile: remote.data!.profile.copyWith(targetSchool: '云端新变化'),
    );
    remote.revision++;
    final staleRevision = coordinator.metadata.revision;
    await coordinator.sync();
    expect(remote.pullRevisions.last, staleRevision);
    expect(coordinator.data!.profile.targetSchool, '云端新变化');
    expect(coordinator.pending, isFalse);
    expect(coordinator.status, SyncStatus.connected);
  });

  test('an old server that ignores the revision parameter still works', () async {
    final coordinator = create();
    addTearDown(coordinator.dispose);
    await coordinator.initialize();
    // returnUnchanged 保持 false：模拟老服务端忽略 ?revision，返回完整文档。
    remote.data = remote.data!.copyWith(
      profile: remote.data!.profile.copyWith(targetSchool: '老服务端完整文档'),
    );
    remote.revision++;
    await coordinator.sync();
    expect(remote.pullRevisions.last, isNot(isNull));
    expect(coordinator.data!.profile.targetSchool, '老服务端完整文档');
    expect(coordinator.status, SyncStatus.connected);
  });

  test(
    'a remote change during a pending edit still surfaces a conflict',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetSchool: '本机修改'),
        ),
      );
      final pushesBefore = remote.pushes;
      // 服务端 revision 变了（完整文档路径），同一字段的并发修改必须冲突。
      remote.data = remote.data!.copyWith(
        profile: remote.data!.profile.copyWith(targetSchool: '云端修改'),
      );
      remote.revision++;
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.conflict);
      expect(coordinator.conflicts, isNotEmpty);
      expect(remote.pushes, pushesBefore);
      expect(coordinator.pending, isTrue);
    },
  );

  test('rapid local edits are coalesced into one upload cycle', () async {
    final counting = CountingStorage(storage);
    final coordinator = create(
      storageOverride: counting,
      uploadDebounce: const Duration(milliseconds: 40),
      uploadMaxWait: const Duration(milliseconds: 300),
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize();
    remote.returnUnchanged = true;
    counting.saves = 0;
    final pullsBefore = remote.pulls;
    final pushesBefore = remote.pushes;
    for (var index = 0; index < 5; index++) {
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetSchool: '合并-$index'),
        ),
      );
    }
    await waitForSyncIdle(coordinator);
    // 5 次编辑合并成一次条件读取 + 一次上传，而不是逐次完整上传。
    expect(remote.pulls - pullsBefore, 1);
    expect(remote.pushes - pushesBefore, 1);
    expect(remote.data!.profile.targetSchool, '合并-4');
    expect(coordinator.pending, isFalse);
    expect(coordinator.status, SyncStatus.connected);
    // 5 次本机落盘 + 1 次上传响应落盘。
    expect(counting.saves, 6);
  });

  test('the upload max wait bounds a continuous edit stream', () async {
    final coordinator = create(
      uploadDebounce: const Duration(seconds: 5),
      uploadMaxWait: const Duration(milliseconds: 80),
    );
    addTearDown(coordinator.dispose);
    await coordinator.initialize();
    remote.returnUnchanged = true;
    final pushesBefore = remote.pushes;
    final started = DateTime.now();
    await coordinator.edit(
      (data) => data.copyWith(
        profile: data.profile.copyWith(targetSchool: '最长等待'),
      ),
    );
    await waitForSyncIdle(coordinator);
    final elapsed = DateTime.now().difference(started);
    expect(remote.pushes - pushesBefore, 1);
    // 合并窗口 5s，但最长等待 80ms：上传不能被窗口拖到 5s。
    expect(elapsed, lessThan(const Duration(seconds: 2)));
  });

  test(
    'pending new fields survive merging with an old-format cloud document',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      final owner = coordinator.data!.profile.userId;
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(
            capacityBasis: CapacityBasis.net,
            dateCapacityOverrides: {'2026-10-22': 0},
          ),
          adHocLearnings: [
            AdHocLearning(
              id: 'adhoc-photo',
              userId: owner,
              title: '摄影构图',
              createdAt: '2026-10-18T01:00:00.000Z',
              updatedAt: '2026-10-18T01:00:00.000Z',
            ),
          ],
          logs: [
            ...data.logs,
            TimeLog(
              id: 'log-adhoc',
              userId: owner,
              taskId: null,
              blockId: null,
              date: '2026-10-17',
              minutes: 20,
              startedAt: '2026-10-18T01:00:00.000Z',
              endedAt: '2026-10-18T01:00:00.000Z',
              source: LogSource.timer,
              relation: TimeLogRelation.adHoc,
              sessionId: 'session-x',
              adHocId: 'adhoc-photo',
            ),
          ],
        ),
      );
      // 旧客户端/旧服务端只写入了旧字段：它修改了无关设置并推进 revision。
      // 合并与上传都不能把本机的新字段当成“云端已删除”而清掉。
      remote.data = remote.data!.copyWith(
        profile: remote.data!.profile.copyWith(targetSchool: '云端旧格式修改'),
      );
      remote.revision++;
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.connected);
      expect(coordinator.conflicts, isEmpty);
      expect(coordinator.pending, isFalse);
      expect(coordinator.data!.adHocLearnings.single.id, 'adhoc-photo');
      expect(coordinator.data!.profile.dateCapacityOverrides, {'2026-10-22': 0});
      expect(
        coordinator.data!.logs.any((log) => log.id == 'log-adhoc'),
        isTrue,
      );
      expect(remote.data!.adHocLearnings.single.id, 'adhoc-photo');
      expect(remote.data!.profile.dateCapacityOverrides, {'2026-10-22': 0});
      expect(remote.data!.profile.capacityBasis, CapacityBasis.net);
      expect(remote.data!.profile.targetSchool, '云端旧格式修改');
      final uploaded = remote.data!.logs.firstWhere(
        (log) => log.id == 'log-adhoc',
      );
      expect(uploaded.taskId, isNull);
      expect(uploaded.adHocId, 'adhoc-photo');
      expect(uploaded.sessionId, 'session-x');
      expect(uploaded.relation, TimeLogRelation.adHoc);
    },
  );

  test(
    'a 426 writer upgrade keeps local data pending and stops overwrite retries',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      final owner = coordinator.data!.profile.userId;
      // 本机有待上传的临时学习记录与正在使用的容量覆盖（模拟计时器已 flush 的
      // ad-hoc 记录仍在 coordinator 的 pending 文档里）。
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetSchool: '本机修改'),
          adHocLearnings: [
            AdHocLearning(
              id: 'adhoc-photo',
              userId: owner,
              title: '摄影构图',
              createdAt: '2026-10-18T01:00:00.000Z',
              updatedAt: '2026-10-18T01:00:00.000Z',
            ),
          ],
          logs: [
            ...data.logs,
            TimeLog(
              id: 'log-adhoc',
              userId: owner,
              taskId: null,
              blockId: null,
              date: '2026-10-17',
              minutes: 20,
              startedAt: '2026-10-18T01:00:00.000Z',
              endedAt: '2026-10-18T01:00:00.000Z',
              source: LogSource.timer,
              relation: TimeLogRelation.adHoc,
              sessionId: 'session-x',
              adHocId: 'adhoc-photo',
            ),
          ],
        ),
      );
      remote.pushFailures.add(
        const ValidationFailure(
          '当前计划包含临时学习/加学计时记录，请升级客户端后再同步',
          statusCode: 426,
        ),
      );
      final pushesBefore = remote.pushes;
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.error);
      expect(coordinator.upgradeRequired, isTrue);
      expect(coordinator.message, contains('升级'));
      // pending 与计时记录都保留：升级后可以继续同步同一份数据。
      expect(coordinator.pending, isTrue);
      expect(coordinator.blocked, isFalse);
      expect(coordinator.conflicts, isEmpty);
      expect(coordinator.data!.profile.targetSchool, '本机修改');
      expect(coordinator.data!.adHocLearnings.single.id, 'adhoc-photo');
      expect(
        coordinator.data!.logs.firstWhere((log) => log.id == 'log-adhoc').sessionId,
        'session-x',
      );
      expect(remote.pushes - pushesBefore, 1);
      // 同一份旧结构不会自动重试覆盖云端；用户升级后重新启动即可继续。
      await coordinator.sync();
      expect(remote.pushes - pushesBefore, 1);
      expect(coordinator.data!.logs.any((log) => log.id == 'log-adhoc'), isTrue);
    },
  );

  test(
    'explicit conflict resolution keeps new fields and pending ad-hoc records',
    () async {
      final coordinator = create();
      addTearDown(coordinator.dispose);
      await coordinator.initialize();
      final owner = coordinator.data!.profile.userId;
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(
            targetSchool: '本机目标',
            capacityBasis: CapacityBasis.net,
            dateCapacityOverrides: {'2026-10-22': 0},
          ),
          adHocLearnings: [
            AdHocLearning(
              id: 'adhoc-photo',
              userId: owner,
              title: '摄影构图',
              createdAt: '2026-10-18T01:00:00.000Z',
              updatedAt: '2026-10-18T01:00:00.000Z',
            ),
          ],
          logs: [
            ...data.logs,
            TimeLog(
              id: 'log-adhoc',
              userId: owner,
              taskId: null,
              blockId: null,
              date: '2026-10-17',
              minutes: 20,
              startedAt: '2026-10-18T01:00:00.000Z',
              endedAt: '2026-10-18T01:00:00.000Z',
              source: LogSource.timer,
              relation: TimeLogRelation.adHoc,
              sessionId: 'session-x',
              adHocId: 'adhoc-photo',
            ),
          ],
        ),
      );
      // 云端同时修改同一字段：产生冲突，随后选择“采用云端”。
      final original = plannerFixture();
      remote.data = original.copyWith(
        profile: original.profile.copyWith(targetSchool: '云端目标'),
      );
      remote.revision++;
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.conflict);
      expect(coordinator.conflicts, isNotEmpty);
      await coordinator.resolve(useLocal: false);
      expect(coordinator.status, SyncStatus.connected);
      expect(coordinator.conflicts, isEmpty);
      expect(coordinator.pending, isFalse);
      expect(coordinator.data!.profile.targetSchool, '云端目标');
      // 与本机新字段无关的云端变化不得丢掉临时学习和容量覆盖。
      expect(coordinator.data!.adHocLearnings.single.id, 'adhoc-photo');
      expect(coordinator.data!.profile.capacityBasis, CapacityBasis.net);
      expect(coordinator.data!.profile.dateCapacityOverrides, {'2026-10-22': 0});
      final adhoc = coordinator.data!.logs.firstWhere(
        (log) => log.id == 'log-adhoc',
      );
      expect(adhoc.taskId, isNull);
      expect(adhoc.adHocId, 'adhoc-photo');
      expect(adhoc.sessionId, 'session-x');
      expect(remote.data!.adHocLearnings.single.id, 'adhoc-photo');
      expect(remote.data!.profile.dateCapacityOverrides, {'2026-10-22': 0});
    },
  );
}
