import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/strategy_scheduler.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              '../../packages/planner-engine/fixtures/strategy-cases.json',
            ).readAsStringSync(),
          )
          as JsonMap;
  for (final raw in fixture['cases'] as List) {
    final row = JsonMap.from(raw as Map);
    test(row['name'] as String, () {
      final data = PlannerData.fromJson({
        'version': 1,
        'profile': {
          'user_id': 'fixture-user',
          'planning_mode': 'daily',
          'daily_limit_minutes': 120,
          'buffer_minutes': 30,
          'granularity_minutes': 30,
          'study_start_minute': 480,
          'study_end_minute': 1320,
          'foundation': '',
          'plan_start_date': row['plan_start_date'] ?? row['from'],
          'plan_end_date': row['plan_end_date'] ?? row['to'],
          'weekly_minutes':
              row['weekly_minutes'] ??
              {
                '0': 0,
                '1': 120,
                '2': 120,
                '3': 120,
                '4': 120,
                '5': 120,
                '6': 0,
              },
          ...JsonMap.from(row['profile'] as Map? ?? const {}),
        },
        'tags': <Object?>[],
        'tasks': [
          for (final task in row['tasks'] as List)
            {
              'user_id': 'fixture-user',
              'tag_ids': <String>[],
              'title': task['id'],
              'estimated_minutes': 30,
              'completed_minutes': 0,
              'priority': 2,
              'deadline': row['to'],
              'is_fixed': false,
              'status': 'not_started',
              'created_at': fixture['clock'],
              'updated_at': fixture['clock'],
              ...JsonMap.from(task as Map),
            },
        ],
        'blocks': row['blocks'] ?? <Object?>[],
        'logs': row['logs'] ?? <Object?>[],
        'fixed_events': [
          for (final event in row['fixed_events'] as List? ?? <Object?>[])
            {
              'date': row['from'],
              'repeat': 'none',
              'kind': 'course',
              'title': 'fixed',
              'user_id': 'fixture-user',
              'created_at': fixture['clock'],
              'updated_at': fixture['clock'],
              ...JsonMap.from(event as Map),
            },
        ],
        'replan_runs': <Object?>[],
        'phases': <Object?>[],
      });
      final before = data.toJsonString();
      var id = 0;
      final runtime = SchedulerRuntime(
        now: DateTime.parse(fixture['clock'] as String),
        nextId: () => 'strategy-${++id}',
      );
      final from = row['from'] as String, to = row['to'] as String;
      final result = scheduleStrategy(data, from, to, runtime: runtime);
      final dates = result.blocks.map((block) => block.date).toList()..sort();
      final issues = result.issues.map((issue) => issue.code).toList()..sort();
      expect({
        'scheduled': result.scheduledMinutes,
        'unscheduled': result.unscheduledMinutes,
        'instances': result.blocks
            .where((block) => block.activityInstanceId != null)
            .length,
        'last_date': dates.lastOrNull,
        'issues': issues,
      }, row['expected']);
      expect(data.toJsonString(), before);
      for (final original in data.blocks) {
        expect(
          result.blocks.firstWhere((block) => block.id == original.id),
          original,
        );
      }
      if (row['expected_new_starts'] != null) {
        final starts =
            result.blocks
                .where((block) => !data.blocks.any((old) => old.id == block.id))
                .map((block) => block.startMinute)
                .toList()
              ..sort();
        expect(starts, row['expected_new_starts']);
      }
      final again = scheduleStrategy(
        data.copyWith(blocks: result.blocks),
        from,
        to,
        runtime: runtime,
      );
      expect(again.added, 0);
      expect(again.blocks, result.blocks);
      for (final block in result.blocks) {
        expect(
          block.date.compareTo(from) >= 0 && block.date.compareTo(to) <= 0,
          isTrue,
        );
        expect(
          data.profile.weekMinutes['${weekdayIndex(block.date)}'],
          greaterThan(0),
        );
      }
      if ((row['name'] as String).contains('planned prerequisites')) {
        expect(
          result.blocks.firstWhere((block) => block.taskId == 'chapter').date,
          '2026-10-12',
        );
        expect(
          result.blocks
              .firstWhere((block) => block.taskId == 'assessment')
              .date,
          '2026-10-13',
        );
      }
    });
  }
}
