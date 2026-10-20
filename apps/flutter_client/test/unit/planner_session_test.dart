import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart'
    as day_ops;
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// Storage that can hold the next [save] until the test releases it.
///
/// The coordinator serializes edits on a future chain, so holding one persist
/// lets a test interleave a second edit between a stale snapshot computation and
/// the queued edit that must not overwrite it.
class GatedStorage implements StorageRepository {
  GatedStorage(this._inner);

  final MemoryStorageRepository _inner;
  Completer<void>? _nextSave;
  Completer<void>? _started;
  Completer<void>? _holding;

  void holdNextSave() {
    _nextSave = Completer<void>();
    _started = Completer<void>();
  }

  Future<void> waitForHeldSave() => _started!.future;

  void releaseHeldSave() {
    final holding = _holding;
    _holding = null;
    _nextSave = null;
    holding?.complete();
  }

  @override
  Future<StorageSnapshot> load(String userKey) => _inner.load(userKey);

  @override
  Future<void> save(
    String userKey,
    PlannerData data,
    StorageMetadata metadata, {
    bool recovery = false,
  }) async {
    final gate = _nextSave;
    if (gate != null) {
      _nextSave = null;
      _holding = gate;
      _started!.complete();
      await gate.future;
    }
    await _inner.save(userKey, data, metadata, recovery: recovery);
  }

  @override
  Future<String?> exportJson(PlannerData data) => _inner.exportJson(data);

  @override
  Future<PlannerData?> importJson() => _inner.importJson();

  @override
  Future<void> restore(String userKey, PlannerData data) =>
      _inner.restore(userKey, data);

  @override
  Future<void> markPending(String userKey, bool pending) =>
      _inner.markPending(userKey, pending);

  @override
  Future<StorageSnapshot> recoverFromBackup(String userKey) =>
      _inner.recoverFromBackup(userKey);
}

/// Remote that stops answering background pulls once [hold] is set.
///
/// The coordinator schedules an upload after every edit; keeping that pull
/// pending leaves the persisted plan untouched so a test can assert on it
/// without a background merge racing the assertions.
class HoldingSync implements SyncApi {
  HoldingSync(this.data);
  PlannerData? data;
  int revision = 1;
  bool hold = false;

  @override
  Future<RemoteSnapshot> pull({int? revision}) async {
    if (hold) await Completer<void>().future;
    return RemoteSnapshot(data, this.revision);
  }

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    if (expected != revision) {
      return RemoteSnapshot(data, revision, conflict: true);
    }
    data = next;
    revision++;
    return RemoteSnapshot(data, revision);
  }
}

Future<PlannerCoordinator> openCoordinator(
  StorageRepository storage,
  SyncApi api,
) async {
  final coordinator = PlannerCoordinator(
    userId: plannerFixture().profile.userId,
    scope: 'move-concurrency',
    storage: storage,
    api: api,
    retryInterval: null,
  );
  await coordinator.initialize();
  return coordinator;
}

/// In-memory remote that keeps whatever the session pushes.
class RecordingSync implements SyncApi {
  RecordingSync(this.data);
  PlannerData? data;
  int revision = 1;
  int pushes = 0;

  @override
  Future<RemoteSnapshot> pull({int? revision}) async =>
      RemoteSnapshot(data, this.revision);

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    if (expected != revision) {
      return RemoteSnapshot(data, revision, conflict: true);
    }
    pushes++;
    data = next;
    revision++;
    return RemoteSnapshot(data, revision);
  }
}

void main() {
  var index = 0;
  late LocalDatabase database;
  late RecordingSync remote;
  late PlannerCoordinator coordinator;
  late PlannerSession session;

  setUp(() async {
    final fixture = plannerFixture();
    database = LocalDatabase(
      open: () => databaseFactoryMemory.openDatabase('session-${index++}'),
    );
    remote = RecordingSync(fixture);
    coordinator = PlannerCoordinator(
      userId: fixture.profile.userId,
      scope: 'session',
      storage: SembastStorageRepository(database: database),
      api: remote,
      retryInterval: null,
    );
    session = PlannerSession(coordinator);
    await coordinator.initialize();
  });

  tearDown(() async {
    coordinator.dispose();
    await database.close();
  });

  PlannerData local() => coordinator.data!;

  test(
    'create, update and delete run through the local-first edit path',
    () async {
      final draft = TaskDraft.blank(
        local(),
        '2026-10-16',
      ).copyWith(title: '线代强化', estimatedMinutes: 900);
      await session.createTask(draft);
      final created = local().tasks.last;
      expect(created.title, '线代强化');
      expect(coordinator.pending, isTrue);
      // `edit` schedules the upload instead of awaiting it; flush before asserting.
      await coordinator.sync();
      expect(remote.data!.tasks, hasLength(2), reason: '完成后已推送到云端');

      await session.updateTask(
        created.id,
        TaskDraft.from(created).copyWith(title: '线代真题', priority: 1),
      );
      final updated = local().tasks.firstWhere((task) => task.id == created.id);
      expect(updated.title, '线代真题');
      expect(updated.priority, 1);

      await session.deleteTask(created.id);
      await coordinator.sync();
      expect(local().tasks.any((task) => task.id == created.id), isFalse);
      expect(remote.data!.tasks.any((task) => task.id == created.id), isFalse);
    },
  );

  test(
    'multi-tag edits sync as associations and deleting a tag preserves records',
    () async {
      final task = local().tasks.single;
      final blockCount = local().blocks.length;
      final logCount = local().logs.length;
      final first = await session.createTag(name: '数学', color: '#4565c7');
      final second = await session.createTag(name: '薄弱项');
      await session.setTaskTags(task.id, [first, second]);
      await coordinator.sync();
      expect(remote.data!.tasks.single.tagIds, [first, second]);

      await session.renameTag(second, '重点');
      await coordinator.sync();
      expect(
        remote.data!.tags.singleWhere((tag) => tag.id == second).name,
        '重点',
      );

      await session.deleteTag(first);
      await coordinator.sync();
      expect(local().tasks.single.tagIds, [second]);
      expect(local().blocks, hasLength(blockCount));
      expect(local().logs, hasLength(logCount));
    },
  );

  test(
    'recording minutes corrects the day total instead of adding to it',
    () async {
      final taskId = local().tasks.first.id;
      await session.recordDayMinutes(taskId, '2026-10-16', 90);
      expect(day_ops.taskDayMinutes(local(), taskId, '2026-10-16'), 90);
      await session.recordDayMinutes(taskId, '2026-10-16', 40);
      expect(day_ops.taskDayMinutes(local(), taskId, '2026-10-16'), 40);
      expect(
        local().tasks.first.completedMinutes,
        40,
        reason: 'recordTaskDayMinutes 同步刷新事项累计值',
      );
      // A second day is additive, not a correction.
      await session.recordDayMinutes(taskId, '2026-10-17', 30);
      expect(day_ops.taskTotalMinutes(local(), taskId), 70);
    },
  );

  test('completing a task records minutes and marks it completed', () async {
    final taskId = local().tasks.first.id;
    await session.completeTask(taskId, actualMinutes: 60, date: '2026-10-16');
    final task = local().tasks.first;
    expect(task.status, TaskStatus.completed);
    expect(task.completedMinutes, 60);
  });

  test('an edit is refused while the plan is blocked', () async {
    coordinator.blocked = true;
    await expectLater(
      session.deleteTask(local().tasks.first.id),
      throwsA(isA<StateError>()),
    );
  });

  test('scheduling reports the outcome the dialog shows', () async {
    final taskId = local().tasks.first.id;
    final outcome = await session.scheduleTask(
      taskId: taskId,
      date: '2026-10-18',
      minutes: 60,
    );
    expect(outcome.placed, 60);
    expect(outcome.conflict, isFalse);
    expect(outcome.message, contains('2026-10-18'));
    expect(
      local().blocks.where((block) => block.date == '2026-10-18'),
      hasLength(2),
    );

    final impossible = await session.scheduleTask(
      taskId: taskId,
      date: '2027-05-01',
      minutes: 60,
    );
    expect(impossible.placed, 0);
    expect(impossible.conflict, isTrue);
  });

  test('moving a recorded day is refused with the Web message', () async {
    await expectLater(
      session.moveTaskDay(local().blocks, '2026-10-18'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('已记录用时'),
        ),
      ),
    );
  });

  test(
    'preview, confirm and undo move the plan through the coordinator',
    () async {
      final preview = await session.previewReplan(today: '2026-10-16');
      expect(coordinator.replanProposal?.preview.id, preview.id);
      // Preview alone must not persist anything.
      expect(coordinator.pending, isFalse);
      await session.confirmReplan();
      expect(local().replanRuns, hasLength(2));
      expect(local().replanRuns.last.status, ReplanStatus.confirmed);
      expect(coordinator.replanProposal, isNull);
      await session.undoReplan();
      expect(local().replanRuns.last.status, ReplanStatus.undone);
    },
  );

  test(
    'cancelling a preview leaves the plan and pending flag untouched',
    () async {
      await session.previewReplan(today: '2026-10-16');
      expect(coordinator.replanProposal, isNotNull);
      session.cancelReplan();
      expect(coordinator.replanProposal, isNull);
      expect(coordinator.pending, isFalse);
    },
  );

  test('the snapshot value object changes when the plan changes', () async {
    PlannerSnapshot build() => PlannerSnapshot(
      data: coordinator.data,
      revision: coordinator.metadata.revision,
      pending: coordinator.metadata.pending,
      status: coordinator.status,
      message: coordinator.message,
      blocked: coordinator.blocked,
      ready: coordinator.ready,
      busy: coordinator.busy,
      conflicts: coordinator.conflicts,
    );
    final before = build();
    expect(before.editable, isTrue);
    await session.recordDayMinutes(local().tasks.first.id, '2026-10-18', 15);
    expect(before, isNot(equals(build())));
    expect(build().pending, isTrue);
  });

  test('a blocked plan is not editable through the snapshot', () async {
    coordinator.blocked = true;
    final snapshot = PlannerSnapshot(
      data: coordinator.data,
      revision: coordinator.metadata.revision,
      pending: coordinator.metadata.pending,
      status: coordinator.status,
      message: coordinator.message,
      blocked: coordinator.blocked,
      ready: coordinator.ready,
      busy: coordinator.busy,
      conflicts: coordinator.conflicts,
    );
    expect(snapshot.editable, isFalse);
  });

  test(
    'deleting a route-referenced item saves the cleaned plan locally',
    () async {
      final taskId = local().tasks.first.id;
      await coordinator.edit(
        (current) => current.copyWith(
          planning: <String, dynamic>{
            'version': 1,
            'route': [
              {
                'id': 'stage',
                'title': '阶段',
                'item_ids': [taskId],
                'outcome': '完成',
                'check': '自检',
              },
            ],
            'quality': <String, dynamic>{'status': 'pass'},
            'needs_review': false,
          },
        ),
      );

      await session.deleteTask(taskId);

      expect(local().tasks.any((task) => task.id == taskId), isFalse);
      expect(local().planning!['route'], isEmpty);
      expect(local().planning!['needs_review'], isTrue);
      expect(local().planning!['quality'], isNull);
      expect(coordinator.pending, isTrue, reason: '本机先可靠落盘并等待同步');
      await coordinator.sync();
      expect(remote.data!.tasks.any((task) => task.id == taskId), isFalse);
      expect(remote.data!.planning!['route'], isEmpty);
    },
  );

  group('moveTaskDay keeps the latest plan', () {
    late GatedStorage storage;
    late HoldingSync remote;
    late PlannerCoordinator gated;
    late PlannerSession gatedSession;

    setUp(() async {
      storage = GatedStorage(MemoryStorageRepository());
      remote = HoldingSync(plannerFixture());
      gated = await openCoordinator(storage, remote);
      addTearDown(gated.dispose);
      gatedSession = PlannerSession(gated);
      // Stop the background uploads triggered by edits so assertions only see
      // the local edit path under test.
      remote.hold = true;
      // The fixture day already has a study log, which makes the day immovable.
      await gated.edit((current) => current.copyWith(logs: []));
    });

    PlannerData localPlan() => gated.data!;

    List<ScheduleBlock> sourceBlocks() => localPlan().blocks
        .where((block) => block.date == '2026-10-16')
        .toList();

    test('an edit persisted first is not overwritten by the move', () async {
      final source = sourceBlocks();
      final extra = source.first.copyWith(
        id: 'extra-block',
        date: '2026-10-17',
      );
      storage.holdNextSave();
      final otherEdit = gated.edit(
        (current) => current.copyWith(blocks: [...current.blocks, extra]),
      );
      await storage.waitForHeldSave();

      // The move is computed from the snapshot read above, before the queued
      // edit below has persisted.
      final move = gatedSession.moveTaskDay(source, '2026-10-18');

      storage.releaseHeldSave();
      await otherEdit;
      await move;

      final blocks = localPlan().blocks;
      expect(
        blocks.any((block) => block.id == 'extra-block'),
        isTrue,
        reason: '期间新增的其他日期安排不能被移动时的旧快照整表覆盖',
      );
      expect(
        blocks.firstWhere((block) => block.id == source.first.id).date,
        '2026-10-18',
      );
      expect(blocks.where((block) => block.date == '2026-10-16'), isEmpty);
    });

    test('a plan change pulled by sync first is not overwritten', () async {
      final syncStorage = GatedStorage(MemoryStorageRepository());
      final syncRemote = RecordingSync(plannerFixture());
      final synced = await openCoordinator(syncStorage, syncRemote);
      addTearDown(synced.dispose);
      final syncedSession = PlannerSession(synced);
      await synced.edit((current) => current.copyWith(logs: []));
      await synced.sync();
      final source = synced.data!.blocks
          .where((block) => block.date == '2026-10-16')
          .toList();
      final cloudBlock = source.first.copyWith(
        id: 'cloud-block',
        date: '2026-10-17',
        updatedAt: '2026-10-17T00:00:00.000Z',
      );
      // Another device adds a block; the next pull delivers it.
      syncRemote.data = synced.data!.copyWith(
        blocks: [...synced.data!.blocks, cloudBlock],
      );
      syncRemote.revision += 1;

      syncStorage.holdNextSave();
      final syncing = synced.sync();
      await syncStorage.waitForHeldSave();

      final move = syncedSession.moveTaskDay(source, '2026-10-18');

      syncStorage.releaseHeldSave();
      await syncing;
      await move;
      await synced.sync();

      final blocks = synced.data!.blocks;
      expect(
        blocks.any((block) => block.id == 'cloud-block'),
        isTrue,
        reason: '同步先更新的安排不能被旧快照覆盖',
      );
      expect(
        blocks.firstWhere((block) => block.id == source.first.id).date,
        '2026-10-18',
      );
    });

    test('a record completed while the dialog is open is refused', () async {
      final source = sourceBlocks();
      storage.holdNextSave();
      final otherEdit = gated.edit(
        (current) => current.copyWith(
          blocks: [
            for (final block in current.blocks)
              block.id == source.first.id
                  ? block.copyWith(status: BlockStatus.completed)
                  : block,
          ],
        ),
      );
      await storage.waitForHeldSave();

      final move = gatedSession.moveTaskDay(source, '2026-10-18');
      final refused = expectLater(
        move,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('不可移动'),
          ),
        ),
      );
      storage.releaseHeldSave();
      await otherEdit;
      await refused;

      final block = localPlan().blocks.firstWhere(
        (item) => item.id == source.first.id,
      );
      expect(block.status, BlockStatus.completed);
      expect(block.date, '2026-10-16');
    });

    test(
      'a record deleted while the dialog is open is not resurrected',
      () async {
        final source = sourceBlocks();
        storage.holdNextSave();
        final otherEdit = gated.edit(
          (current) => current.copyWith(
            blocks: current.blocks
                .where((block) => block.id != source.first.id)
                .toList(),
          ),
        );
        await storage.waitForHeldSave();

        final move = gatedSession.moveTaskDay(source, '2026-10-18');
        final refused = expectLater(
          move,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('不存在'),
            ),
          ),
        );
        storage.releaseHeldSave();
        await otherEdit;
        await refused;

        expect(
          localPlan().blocks.any((block) => block.id == source.first.id),
          isFalse,
        );
        expect(
          localPlan().blocks.where((block) => block.date == '2026-10-18'),
          isEmpty,
        );
      },
    );

    test(
      'a record moved while the dialog is open is not moved twice',
      () async {
        final source = sourceBlocks();
        storage.holdNextSave();
        final otherEdit = gated.edit(
          (current) => current.copyWith(
            blocks: [
              for (final block in current.blocks)
                block.id == source.first.id
                    ? block.copyWith(date: '2026-10-17')
                    : block,
            ],
          ),
        );
        await storage.waitForHeldSave();

        final move = gatedSession.moveTaskDay(source, '2026-10-18');
        final refused = expectLater(
          move,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('已变化'),
            ),
          ),
        );
        storage.releaseHeldSave();
        await otherEdit;
        await refused;

        expect(
          localPlan().blocks
              .firstWhere((block) => block.id == source.first.id)
              .date,
          '2026-10-17',
        );
      },
    );

    test('a normal move keeps unrelated tasks and dates', () async {
      final base = localPlan();
      final secondTask = base.tasks.first.copyWith(
        id: 'task-two',
        title: '第二事项',
      );
      final secondBlock = base.blocks.first.copyWith(
        id: 'second-block',
        taskId: 'task-two',
        date: '2026-10-17',
      );
      await gated.edit(
        (current) => current.copyWith(
          tasks: [...current.tasks, secondTask],
          blocks: [...current.blocks, secondBlock],
        ),
      );
      final source = sourceBlocks();

      await gatedSession.moveTaskDay(source, '2026-10-18');

      final blocks = localPlan().blocks;
      expect(
        blocks.firstWhere((block) => block.id == source.first.id).date,
        '2026-10-18',
      );
      expect(
        blocks.firstWhere((block) => block.id == 'second-block').date,
        '2026-10-17',
      );
      expect(
        blocks.where(
          (block) =>
              block.date == '2026-10-16' && block.taskId == source.first.taskId,
        ),
        isEmpty,
      );
    });

    test('a capacity failure writes nothing', () async {
      final base = localPlan();
      final secondTask = base.tasks.first.copyWith(
        id: 'task-two',
        title: '第二事项',
      );
      final filler = base.blocks.first.copyWith(
        id: 'filler-block',
        taskId: 'task-two',
        date: '2026-10-18',
        durationMinutes: 450,
      );
      await gated.edit(
        (current) => current.copyWith(
          tasks: [...current.tasks, secondTask],
          blocks: [...current.blocks, filler],
        ),
      );
      final before = jsonEncode(localPlan().toJson());

      await expectLater(
        gatedSession.moveTaskDay(sourceBlocks(), '2026-10-18'),
        throwsA(isA<StateError>()),
      );

      expect(jsonEncode(localPlan().toJson()), before);
    });

    test(
      'generating a schedule does not roll back edits persisted first',
      () async {
        final extra = localPlan().blocks.first.copyWith(
          id: 'extra-block',
          date: '2026-10-17',
        );
        storage.holdNextSave();
        final otherEdit = gated.edit(
          (current) => current.copyWith(blocks: [...current.blocks, extra]),
        );
        await storage.waitForHeldSave();

        final generated = gatedSession.generateSchedule(
          from: '2026-10-19',
          to: '2026-10-20',
        );

        storage.releaseHeldSave();
        await otherEdit;
        await generated;

        expect(
          localPlan().blocks.any((block) => block.id == 'extra-block'),
          isTrue,
          reason: '生成安排不能把期间已落盘的其他安排覆盖掉',
        );
      },
    );
  });
}
