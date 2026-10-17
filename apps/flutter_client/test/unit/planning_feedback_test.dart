import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planning_feedback.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

void main() {
  final fixture = plannerFixture();
  final task = fixture.tasks.first.copyWith(
    planning: {
      'workload': {
        'components': [
          {
            'id': 'chapter',
            'quantity': 10,
            'unit': '章',
            'minutes_per_unit': 30,
          },
        ],
      },
      'feedback': {'content_units': 3, 'sampled_at': '2026-10-17T10:00:00Z'},
    },
  );
  final logs = [
    for (var i = 0; i < 3; i++)
      fixture.logs.first.copyWith(
        id: 'timer-$i',
        taskId: task.id,
        minutes: 60,
        source: LogSource.timer,
        startedAt: '2026-10-17T0${i + 1}:00:00Z',
        endedAt: '2026-10-17T0${i + 2}:00:00Z',
      ),
  ];

  test('one timer cannot infer long-term speed; third valid sample can', () {
    expect(calibratePace(task, logs.take(1)).deviates, isFalse);
    final pace = calibratePace(task, logs);
    expect(pace.samples, 3);
    expect(pace.observedMinutesPerUnit, 60);
    expect(pace.expectedMinutesPerUnit, 30);
    expect(pace.deviates, isTrue);
  });

  test(
    'undo recomputes evidence; manual and later logs cannot backfill sample',
    () {
      final surviving = [
        logs[0],
        logs[1],
        logs[2].copyWith(source: LogSource.manual),
        logs[2].copyWith(endedAt: '2026-10-18T00:00:00Z'),
      ];
      final pace = calibratePace(task, surviving);
      expect(pace.samples, 2);
      expect(pace.minutes, 120);
      expect(pace.deviates, isFalse);
    },
  );

  test(
    'feedback preserves budget, actual minutes, status, history and strategy',
    () {
      final data = fixture.copyWith(tasks: [task]);
      final updated = recordPlanningFeedback(
        data,
        task.id,
        contentUnits: 10,
        contentCompleted: true,
        difficulty: 'hard',
        sampledAt: '2026-10-17T10:00:00Z',
      );
      final changed = updated.tasks.single;
      expect(changed.estimatedMinutes, task.estimatedMinutes);
      expect(changed.completedMinutes, task.completedMinutes);
      expect(changed.status, task.status);
      expect(changed.planning!['workload'], task.planning!['workload']);
      expect(
        (changed.planning!['content_progress'] as Map)['confirmed'],
        isTrue,
      );
      expect(updated.logs, data.logs);
      expect(updated.blocks, data.blocks);
    },
  );
}
