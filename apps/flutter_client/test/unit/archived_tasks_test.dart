import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/progress_metrics.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart'
    as scheduler;
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/task_editing.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

void main() {
  PlannerData archivedFixture() {
    final base = plannerFixture();
    return base.copyWith(
      tasks: [base.tasks.single.copyWith(status: TaskStatus.archived)],
    );
  }

  test(
    'archived tasks round-trip through canonical JSON and task snapshots',
    () {
      final data = archivedFixture();
      expect(data.toJson()['tasks'][0]['status'], 'archived');
      expect(PlannerData.fromJson(data.toJson()), data);
      final snapshot = TaskStatusSnapshot(
        id: data.tasks.single.id,
        status: TaskStatus.archived,
      );
      expect(TaskStatusSnapshot.fromJson(snapshot.toJson()), snapshot);
    },
  );

  test(
    'archived history remains in actual totals but leaves active progress',
    () {
      final data = archivedFixture();
      final metrics = progressMetrics(
        data,
        date: '2026-10-16',
        month: '2026-10',
      );
      expect(metrics.totalActual, 35);
      expect(metrics.weekStats.single.actual, 35);
      expect(metrics.weekStats.single.planned, 30);
      expect(metrics.subjectProgress.single.actual, 35);
      expect(metrics.subjectProgress.single.estimated, 0);
      expect(metrics.subjectProgress.single.completed, 0);
      expect(metrics.overallMinutes, 0);
      expect(metrics.remainingMinutes, 0);
      expect(metrics.burnValues, everyElement(0));
      expect(groupDailyBlocks(data.blocks, data.tasks), hasLength(1));
    },
  );

  test('recording and refreshing archived history never reactivates it', () {
    final data = archivedFixture();
    final taskId = data.tasks.single.id;
    final recorded = scheduler.recordTaskDayMinutes(
      data,
      taskId,
      '2026-10-16',
      60,
    );
    final corrected = scheduler.recordTaskDayMinutes(
      recorded,
      taskId,
      '2026-10-16',
      0,
    );
    expect(recorded.tasks.single.status, TaskStatus.archived);
    expect(recorded.tasks.single.completedMinutes, 60);
    expect(corrected.tasks.single.status, TaskStatus.archived);
    expect(corrected.tasks.single.completedMinutes, 0);
    expect(
      refreshTaskProgress(recorded).tasks.single.status,
      TaskStatus.archived,
    );
    expect(
      refreshTaskProgress(
        recorded,
        correctedTaskIds: [taskId],
      ).tasks.single.status,
      TaskStatus.archived,
    );
  });

  test('archived tasks reject manual scheduling, moves and completion', () {
    final data = archivedFixture();
    final task = data.tasks.single;
    expect(unscheduledTaskMinutes(data, task, from: '2026-10-16'), 0);
    expect(
      scheduler.validateBlockPlacement(
        data,
        data.blocks.single.copyWith(id: 'new'),
      ),
      '已归档事项不可安排',
    );
    expect(
      () => scheduleTaskDay(data, task.id, '2026-10-17', 30),
      throwsStateError,
    );
    expect(moveTaskDay(data, data.blocks, '2026-10-17').error, '已归档事项不可安排');
    expect(
      () => completeTask(data, task.id, date: '2026-10-16', actualMinutes: 0),
      throwsStateError,
    );
  });
}
