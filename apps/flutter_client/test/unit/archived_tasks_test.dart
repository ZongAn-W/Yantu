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
      tasks: [base.tasks.single.copyWith(archived: true)],
    );
  }

  test('archived tasks round-trip through canonical JSON', () {
    final data = archivedFixture();
    expect(data.toJson()['tasks'][0]['archived'], isTrue);
    expect(PlannerData.fromJson(data.toJson()), data);
  });

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
      expect(metrics.weekProgress.actual, 35);
      expect(metrics.weekProgress.planned, 30);
      expect(metrics.goalActual, 0);
      expect(metrics.completedMinutes, 0);
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
    expect(recorded.tasks.single.archived, isTrue);
    expect(recorded.tasks.single.completedMinutes, 60);
    expect(corrected.tasks.single.archived, isTrue);
    expect(corrected.tasks.single.completedMinutes, 0);
    expect(
      refreshTaskProgress(recorded).tasks.single.archived,
      isTrue,
    );
    expect(
      refreshTaskProgress(
        recorded,
        correctedTaskIds: [taskId],
      ).tasks.single.archived,
      isTrue,
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
