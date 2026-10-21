import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/features/planner/application/local_replanning.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import 'sync_test.dart' show FakeSync;

void main() {
  final fixture =
      jsonDecode(
            File(
              '../../packages/planner-engine/fixtures/planner-goldens.json',
            ).readAsStringSync(),
          )
          as JsonMap;
  final sample = (fixture['cases'] as List).firstWhere(
    (row) => row['name'] == 'daily partial completion',
  );
  final data = PlannerData.fromJson(
    JsonMap.from(sample['args']['data'] as Map),
  );
  final service = LocalReplanning(
    runtime: SchedulerRuntime(
      now: DateTime.utc(2026, 10, 16, 8),
      nextId: () => 'unused',
    ),
  );
  LocalReplanning freshService() {
    var id = 0;
    return LocalReplanning(
      runtime: SchedulerRuntime(
        now: DateTime.utc(2026, 10, 16, 8),
        nextId: () => 'local-${++id}',
      ),
    );
  }

  test('pure runtime emits UUID v4 and JS millisecond timestamps', () {
    final runtime = SchedulerRuntime(
      now: DateTime.parse('2026-10-16T00:00:00.123456Z'),
    );
    expect(runtime.timestamp(), '2026-10-16T00:00:00.123Z');
    expect(
      runtime.ids(),
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
  });
  test('local preview does not mutate data and cancel needs no write', () {
    final original = data.toJsonString();
    final preview = freshService().preview(data, today: '2026-10-16');
    expect(data.toJsonString(), original);
    expect(preview.preview.after, data.blocks);
    expect(preview.preview.changes, isEmpty);
  });
  final changes = <String, PlannerData Function(PlannerData)>{
    'profile': (state) =>
        state.copyWith(profile: state.profile.copyWith(bufferMinutes: 60)),
    'task': (state) => state.copyWith(
      tasks: [state.tasks.single.copyWith(deadline: '2026-10-17')],
    ),
    'task status': (state) => state.copyWith(
      tasks: [state.tasks.single.copyWith(completedAt: '2026-10-16T00:00:00.000Z')],
    ),
    'unlinked logs': (state) => state.copyWith(
      logs: [
        ...state.logs,
        state.logs.single.copyWith(id: 'orphan', blockId: null, minutes: 10),
      ],
    ),
    'fixed events': (state) => state.copyWith(
      fixedEvents: [
        FixedEvent(
          id: 'event',
          userId: state.profile.userId,
          title: '考试',
          date: '2026-10-17',
          startMinute: 480,
          durationMinutes: 60,
          kind: FixedEventKind.exam,
          repeat: EventRepeat.none,
          createdAt: 'original',
          updatedAt: 'original',
        ),
      ],
    ),
    'guidance': (state) => state.copyWith(
      blocks: [
        state.blocks.first.copyWith(adviceText: 'changed'),
        ...state.blocks.skip(1),
      ],
    ),
  };
  for (final change in changes.entries) {
    test('confirm rejects stale ${change.key} without touching data', () {
      final local = freshService();
      final preview = local.preview(data, today: '2026-10-16');
      final newer = change.value(data);
      final original = newer.toJsonString();
      expect(() => local.confirm(newer, preview), throwsStateError);
      expect(newer.toJsonString(), original);
    });
    test('undo rejects changed ${change.key}, including after JSON reload', () {
      final local = freshService();
      final confirmed = local.confirm(
        data,
        local.preview(data, today: '2026-10-16'),
      );
      final newer = PlannerData.fromJson(
        jsonDecode(change.value(confirmed).toJsonString()) as JsonMap,
      );
      expect(() => service.undo(newer), throwsStateError);
    });
  }
  test(
    'local undo restores blocks and prior task status after JSON roundtrip',
    () {
      final local = freshService();
      final confirmed = local.confirm(
        data,
        local.preview(data, today: '2026-10-16'),
      );
      expect(confirmed.tasks.single.archived, data.tasks.single.archived);
      final restored = local.undo(
        PlannerData.fromJson(jsonDecode(confirmed.toJsonString()) as JsonMap),
      );
      expect(restored.blocks, data.blocks);
      expect(restored.logs, data.logs);
      expect(restored.tasks.single.archived, data.tasks.single.archived);
      expect(restored.replanRuns.single.status, ReplanStatus.undone);
    },
  );
  test('legacy TS run without local guard still restores task snapshots', () {
    final confirmed = PlannerData.fromJson(
      JsonMap.from(sample['expected']['confirmed'] as Map),
    );
    final restored = service.undo(confirmed);
    expect(restored.tasks.single.archived, data.tasks.single.archived);
    expect(restored.blocks, data.blocks);
  });

  late LocalDatabase database;
  late SembastStorageRepository storage;
  late FakeSync api;
  late PlannerCoordinator coordinator;
  var sequence = 0;
  PlannerCoordinator create() => PlannerCoordinator(
    userId: data.profile.userId,
    scope: 'local-replan',
    storage: storage,
    api: api,
    retryInterval: null,
    replanning: freshService(),
  );
  setUp(() {
    database = LocalDatabase(
      open: () =>
          databaseFactoryMemory.openDatabase('local-replan-${sequence++}'),
    );
    storage = SembastStorageRepository(database: database);
    api = FakeSync(data);
    coordinator = create();
  });
  tearDown(() async {
    coordinator.dispose();
    await database.close();
  });
  test(
    'offline preview/cancel never persists; confirmation and undo survive restart then sync',
    () async {
      await coordinator.initialize();
      api.offline = true;
      final before = coordinator.data!;
      final metadata = coordinator.metadata;
      await coordinator.previewReplan(today: '2026-10-16');
      expect(coordinator.data, before);
      expect(coordinator.metadata, metadata);
      expect((await storage.load(coordinator.key)).data, before);
      expect(api.pushes, 0);
      coordinator.cancelReplan();
      expect(coordinator.replanProposal, isNull);
      await expectLater(coordinator.confirmReplan(), throwsStateError);
      await coordinator.previewReplan(today: '2026-10-16');
      await coordinator.confirmReplan();
      await coordinator.sync();
      expect(coordinator.pending, isTrue);
      expect(coordinator.status, SyncStatus.offline);
      expect(
        coordinator.data!.replanRuns.single.status,
        ReplanStatus.confirmed,
      );
      coordinator.dispose();
      coordinator = create();
      await coordinator.initialize();
      expect(coordinator.data!.replanRuns.single.localUndoGuard, isNotNull);
      await coordinator.undoReplan();
      expect(coordinator.data!.blocks, before.blocks);
      expect(coordinator.data!.tasks.single.archived, before.tasks.single.archived);
      await coordinator.sync();
      api.offline = false;
      await coordinator.sync();
      expect(coordinator.pending, isFalse);
      expect(api.data!.replanRuns.single.status, ReplanStatus.undone);
      expect(api.data!.blocks, before.blocks);
    },
  );
  test(
    'serialized edit invalidates preview before queued confirmation',
    () async {
      await coordinator.initialize();
      api.offline = true;
      await coordinator.previewReplan(today: '2026-10-16');
      final editing = coordinator.edit(changes['profile']!);
      final confirming = coordinator.confirmReplan();
      await editing;
      await expectLater(confirming, throwsStateError);
      expect(coordinator.data!.replanRuns, isEmpty);
      expect(coordinator.data!.profile.bufferMinutes, 60);
    },
  );
  test('cloud change invalidates local preview', () async {
    await coordinator.initialize();
    await coordinator.previewReplan(today: '2026-10-16');
    api.data = changes['task']!(data);
    api.revision++;
    await coordinator.sync();
    await expectLater(coordinator.confirmReplan(), throwsStateError);
    expect(coordinator.data!.tasks.single.deadline, '2026-10-17');
  });
  test('storage failure cannot publish a local confirmation', () async {
    await coordinator.initialize();
    api.offline = true;
    await coordinator.previewReplan(today: '2026-10-16');
    final db = await database.database;
    await storage.store.record(coordinator.key).put(db, 'broken');
    await storage.store.record('${coordinator.key}:backup').put(db, 'broken');
    await expectLater(coordinator.confirmReplan(), throwsA(anything));
    expect(coordinator.data, data);
    expect(api.pushes, 0);
  });
}
