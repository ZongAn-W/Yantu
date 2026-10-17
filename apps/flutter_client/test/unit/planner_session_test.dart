import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart' as day_ops;
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// In-memory remote that keeps whatever the session pushes.
class RecordingSync implements SyncApi {
  RecordingSync(this.data);
  PlannerData? data;
  int revision = 1;
  int pushes = 0;

  @override
  Future<RemoteSnapshot> pull() async => RemoteSnapshot(data, revision);

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

  test('create, update and delete run through the local-first edit path', () async {
    final draft = TaskDraft.blank(local(), '2026-10-16').copyWith(
      title: '线代强化',
      subjectId: 'linear-algebra',
      estimatedMinutes: 900,
    );
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
  });

  test('recording minutes corrects the day total instead of adding to it', () async {
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
  });

  test('day completion toggles only the given blocks', () async {
    final blocks = local()
        .blocks
        .where((block) => block.date == '2026-10-16')
        .toList();
    await session.setTaskDayCompletion(blocks, true);
    expect(
      local().blocks.every((block) => block.status == BlockStatus.completed),
      isTrue,
    );
    await session.setTaskDayCompletion(blocks, false);
    expect(
      local().blocks.every((block) => block.status == BlockStatus.planned),
      isTrue,
    );
  });

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

  test('an overlapping fixed event is refused in timed mode', () async {
    final timed = local().copyWith(
      profile: local().profile.copyWith(storedPlanningMode: PlanningMode.timed),
      blocks: [local().blocks.first.copyWith(startMinute: 600)],
    );
    await coordinator.edit((_) => timed);
    await expectLater(
      session.createFixedEvent(
        FixedEvent(
          id: 'event-x',
          userId: local().profile.userId,
          title: '晚课',
          date: '2026-10-16',
          startMinute: 620,
          durationMinutes: 60,
          kind: FixedEventKind.course,
          repeat: EventRepeat.none,
          createdAt: '2026-10-16T00:00:00.000Z',
          updatedAt: '2026-10-16T00:00:00.000Z',
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('preview, confirm and undo move the plan through the coordinator', () async {
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
  });

  test('cancelling a preview leaves the plan and pending flag untouched', () async {
    await session.previewReplan(today: '2026-10-16');
    expect(coordinator.replanProposal, isNotNull);
    session.cancelReplan();
    expect(coordinator.replanProposal, isNull);
    expect(coordinator.pending, isFalse);
  });

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
}
