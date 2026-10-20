import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/storage/file_transfer_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/merge_plans.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_edits.dart';
import '../support/planner_fixture.dart';

const String _newFieldStamp = '2026-10-18T01:00:00.000Z';

/// 给任意文档加上全部新字段（容量覆盖、临时学习实体与三类学习记录）。
PlannerData withNewLearningFields(PlannerData data) {
  final owner = data.profile.userId;
  return data.copyWith(
    profile: data.profile.copyWith(
      capacityBasis: CapacityBasis.net,
      weeklyBaselineMinutes: 300,
      dateCapacityOverrides: {'2026-10-22': 0},
      weekCapacityOverrides: {
        '2026-10-19': const WeekCapacityOverride(
          totalMinutes: 240,
          days: {'2': 0},
        ),
      },
    ),
    adHocLearnings: [
      AdHocLearning(
        id: 'adhoc-photo',
        userId: owner,
        title: '摄影构图',
        createdAt: _newFieldStamp,
        updatedAt: _newFieldStamp,
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
        startedAt: _newFieldStamp,
        endedAt: _newFieldStamp,
        source: LogSource.timer,
        relation: TimeLogRelation.adHoc,
        sessionId: 'session-x',
        adHocId: 'adhoc-photo',
      ),
    ],
  );
}

class FakeTransfer implements FileTransferRepository {
  PlannerData? imported;
  PlannerData? exported;

  @override
  Future<PlannerData?> importJson() async => imported;

  @override
  Future<bool> exportJson(PlannerData data) async {
    exported = data;
    return true;
  }
}

class FakeSync implements SyncApi {
  FakeSync(this.data);
  PlannerData? data;
  int revision = 1, pushes = 0;
  bool offline = false;
  Future<void> Function()? duringPush;
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
  test(
    'new fields survive an offline edit, coordinator restart and upload, '
    'while legacy ad-hoc records are removed',
    () async {
      await coordinator.initialize();
      remote.offline = true;
      await coordinator.edit(withNewLearningFields);
      await coordinator.sync();
      expect(coordinator.status, SyncStatus.offline);
      expect(coordinator.pending, isTrue);
      coordinator.dispose();
      coordinator = create();
      await coordinator.initialize();
      // 重启后本机保存的新字段完整保留；临时学习记录已被清理。
      expect(coordinator.data!.adHocLearnings, isEmpty);
      expect(coordinator.data!.profile.dateCapacityOverrides, {'2026-10-22': 0});
      expect(coordinator.data!.logs.any((log) => log.id == 'log-adhoc'), isFalse);
      remote.offline = false;
      await coordinator.sync();
      expect(coordinator.pending, isFalse);
      expect(coordinator.status, SyncStatus.connected);
      expect(remote.data!.adHocLearnings, isEmpty);
      expect(remote.data!.profile.capacityBasis, CapacityBasis.net);
      expect(
        remote.data!.profile.weekCapacityOverrides!.keys.single,
        '2026-10-19',
      );
      expect(remote.data!.logs.any((log) => log.id == 'log-adhoc'), isFalse);
    },
  );
  test(
    'JSON export and import keep new fields, re-tag them for the account '
    'and drop ad-hoc records',
    () async {
      final transfer = FakeTransfer();
      final transferStorage = SembastStorageRepository(
        database: database,
        transfer: transfer,
      );
      final exportCoordinator = PlannerCoordinator(
        userId: base.profile.userId,
        scope: 'transfer',
        storage: transferStorage,
        api: remote,
        retryInterval: null,
      );
      addTearDown(exportCoordinator.dispose);
      await exportCoordinator.initialize();
      await exportCoordinator.edit(withNewLearningFields);
      await exportCoordinator.exportJson();
      expect(transfer.exported, isNotNull);
      expect(transfer.exported!.adHocLearnings, isEmpty);
      expect(
        transfer.exported!.logs.any((log) => log.id == 'log-adhoc'),
        isFalse,
      );
      // 另一账号的导出被导入当前账号：id 重新映射，新字段保留，临时学习被清理。
      transfer.imported = forAccount(
        withNewLearningFields(plannerFixture()),
        'other-account',
      );
      await exportCoordinator.importJson();
      expect(exportCoordinator.pending, isFalse);
      expect(exportCoordinator.data!.adHocLearnings, isEmpty);
      expect(
        exportCoordinator.data!.logs.every((log) => log.taskId != null),
        isTrue,
      );
      expect(exportCoordinator.data!.profile.dateCapacityOverrides, {
        '2026-10-22': 0,
      });
      expect(remote.data!.adHocLearnings, isEmpty);
      expect(
        remote.data!.profile.weekCapacityOverrides!.keys.single,
        '2026-10-19',
      );
    },
  );
  test('explicit backup recovery keeps the new fields and drops ad-hoc records', () async {
    await coordinator.initialize();
    final rich = withNewLearningFields(base);
    await coordinator.edit((_) => rich);
    await coordinator.edit((data) => data.copyWith(phases: []));
    await coordinator.recover();
    expect(coordinator.data!.adHocLearnings, isEmpty);
    expect(coordinator.data!.profile.dateCapacityOverrides, {'2026-10-22': 0});
    expect(coordinator.data!.logs.any((log) => log.id == 'log-adhoc'), isFalse);
    expect(remote.data!.adHocLearnings, isEmpty);
  });
}
