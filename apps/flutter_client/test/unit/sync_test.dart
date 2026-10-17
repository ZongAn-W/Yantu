import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/merge_plans.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_edits.dart';
import '../support/planner_fixture.dart';

class FakeSync implements SyncApi {
  FakeSync(this.data);
  PlannerData? data;
  int revision = 1, pushes = 0;
  bool offline = false;
  Future<void> Function()? duringPush;
  @override
  Future<RemoteSnapshot> pull() async {
    if (offline) throw const OfflineFailure();
    return RemoteSnapshot(data, revision);
  }

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    if (offline) throw const OfflineFailure();
    pushes++;
    await duringPush?.call();
    if (expected != revision) {
      return RemoteSnapshot(data, revision, conflict: true);
    }
    data = next;
    revision++;
    return RemoteSnapshot(data, revision);
  }
}

void main() {
  final base = plannerFixture();
  test(
    'different-day totals merge without a derived completed_minutes conflict',
    () {
      final local = recordDayMinutes(
        base,
        base.tasks.single.id,
        '2026-10-16',
        80,
      );
      final remote = recordDayMinutes(
        base,
        base.tasks.single.id,
        '2026-10-17',
        110,
      );
      final result = mergePlans(base, local, remote);
      expect(result.conflicts, isEmpty);
      expect(
        result.data.logs.fold<int>(0, (sum, log) => sum + log.minutes),
        190,
      );
      expect(result.data.tasks.single.completedMinutes, 190);
    },
  );
  test(
    'independent fields merge; simultaneous field edits keep local and surface conflict',
    () {
      final local = base.copyWith(
        profile: base.profile.copyWith(targetSchool: '本机目标'),
      );
      final remote = base.copyWith(
        tasks: [base.tasks.single.copyWith(title: '云端事项')],
      );
      final merged = mergePlans(base, local, remote);
      expect(merged.conflicts, isEmpty);
      expect(merged.data.profile.targetSchool, '本机目标');
      expect(merged.data.tasks.single.title, '云端事项');
      final conflict = mergePlans(
        base,
        local,
        base.copyWith(profile: base.profile.copyWith(targetSchool: '云端目标')),
      );
      expect(conflict.conflicts, isNotEmpty);
      expect(conflict.data.profile.targetSchool, '本机目标');
    },
  );
  test(
    'same-day corrections do not add; deletion cannot discard locally edited child logs',
    () {
      final local = recordDayMinutes(
            base,
            base.tasks.single.id,
            '2026-10-16',
            80,
          ),
          remote = recordDayMinutes(
            base,
            base.tasks.single.id,
            '2026-10-16',
            110,
          );
      final merged = mergePlans(base, local, remote);
      expect(merged.conflicts, isNotEmpty);
      expect(
        merged.data.logs
            .where((l) => l.date == '2026-10-16')
            .fold<int>(0, (s, l) => s + l.minutes),
        80,
      );
      final deleted = base.copyWith(tasks: [], blocks: [], logs: []);
      final preserved = mergePlans(base, local, deleted);
      expect(preserved.conflicts, isNotEmpty);
      expect(preserved.data.tasks, hasLength(1));
      expect(preserved.data.logs, isNotEmpty);
    },
  );

  var index = 0;
  late LocalDatabase database;
  late SembastStorageRepository storage;
  late FakeSync remote;
  late PlannerCoordinator coordinator;
  PlannerCoordinator create() => PlannerCoordinator(
    userId: base.profile.userId,
    scope: 'test',
    storage: storage,
    api: remote,
    retryInterval: null,
  );
  setUp(() {
    database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase('sync-${index++}'),
    );
    storage = SembastStorageRepository(database: database);
    remote = FakeSync(base);
    coordinator = create();
  });
  tearDown(() async {
    coordinator.dispose();
    await database.close();
  });
  test(
    'offline edit survives coordinator restart then syncs with baseline and pending intact',
    () async {
      await coordinator.initialize();
      remote.offline = true;
      await coordinator.edit(
        (data) =>
            data.copyWith(tasks: [data.tasks.single.copyWith(title: '离线修改')]),
      );
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.offline);
      expect(coordinator.pending, isTrue);
      coordinator.dispose();
      coordinator = create();
      await coordinator.initialize();
      expect(coordinator.data!.tasks.single.title, '离线修改');
      expect(coordinator.metadata.base, base);
      remote.offline = false;
      await coordinator.sync();
      expect(remote.data!.tasks.single.title, '离线修改');
      expect(coordinator.pending, isFalse);
    },
  );
  test(
    'conflict pauses upload and explicit resolution preserves independent cloud changes',
    () async {
      await coordinator.initialize();
      remote.offline = true;
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetSchool: 'local'),
        ),
      );
      await coordinator.sync();
      remote.data = base.copyWith(
        profile: base.profile.copyWith(targetSchool: 'remote'),
        tasks: [base.tasks.single.copyWith(title: 'remote item')],
      );
      remote.revision++;
      remote.offline = false;
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.conflict);
      expect(remote.pushes, 0);
      expect(coordinator.data!.profile.targetSchool, 'local');
      await coordinator.resolve(useLocal: true);
      expect(remote.data!.profile.targetSchool, 'local');
      expect(remote.data!.tasks.single.title, 'remote item');
      expect(coordinator.pending, isFalse);
    },
  );
  test(
    'edits made while upload is in flight remain pending and eventually sync',
    () async {
      await coordinator.initialize();
      remote.offline = true;
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetSchool: 'first'),
        ),
      );
      await coordinator.sync();
      remote.offline = false;
      final started = Completer<void>(), release = Completer<void>();
      remote.duringPush = () async {
        remote.duringPush = null;
        started.complete();
        await release.future;
      };
      final syncing = coordinator.sync();
      await started.future;
      await coordinator.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetProgram: 'second'),
        ),
      );
      release.complete();
      await syncing;
      expect(remote.data!.profile.targetSchool, 'first');
      expect(remote.data!.profile.targetProgram, 'second');
      expect(coordinator.pending, isFalse);
    },
  );
  test(
    'storage failure prevents network write and keeps the current display',
    () async {
      await coordinator.initialize();
      final db = await database.database;
      await storage.store.record(coordinator.key).put(db, 'broken');
      await storage.store.record('${coordinator.key}:backup').put(db, 'broken');
      await expectLater(
        coordinator.edit((data) => data.copyWith(phases: [])),
        throwsA(anything),
      );
      expect(remote.pushes, 0);
      expect(coordinator.data, base);
    },
  );
}
