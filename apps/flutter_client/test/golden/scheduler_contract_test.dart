import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/strategy_scheduler.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

Object? jsonValue(Object? value) => jsonDecode(jsonEncode(value));

/// Cross-entry scheduling contract. The same fixture is executed by the API strategy
/// scheduler (apps/api/src/planning-scheduler.test.ts) and by the TypeScript reference
/// engine (packages/planner-engine/src/scheduler-contract.test.ts), so the Flutter
/// mirror cannot silently diverge from either entry point.
void main() {
  final fixture =
      jsonDecode(
            File(
              '../../packages/planner-engine/fixtures/scheduler-contract-cases.json',
            ).readAsStringSync(),
          )
          as JsonMap;
  final clock = fixture['clock'] as String;
  final baseProfile = JsonMap.from(fixture['base_profile'] as Map);

  PlannerData buildData(JsonMap row) {
    final profile = {
      ...baseProfile,
      ...JsonMap.from(row['profile'] as Map? ?? const {}),
    };
    final from = row['from'] as String;
    final to = row['to'] as String;
    return PlannerData.fromJson({
      'version': 1,
      'profile': profile,
      'tags': <Object?>[],
      'tasks': [
        for (final task in row['tasks'] as List? ?? const [])
          {
            'user_id': 'fixture-user',
            'tag_ids': <String>[],
            'title': (task as Map)['id'],
            'estimated_minutes': 30,
            'completed_minutes': 0,
            'priority': 2,
            'deadline': to,
            'is_fixed': false,
            'status': 'not_started',
            'created_at': clock,
            'updated_at': clock,
            ...JsonMap.from(task),
          },
      ],
      'blocks': [
        for (final block in row['blocks'] as List? ?? const [])
          {
            'user_id': 'fixture-user',
            'start_minute': 0,
            'duration_minutes': 30,
            'actual_minutes': 0,
            'is_fixed': false,
            'status': 'planned',
            'created_at': clock,
            'updated_at': clock,
            ...JsonMap.from(block as Map),
          },
      ],
      'logs': [
        for (final log in row['logs'] as List? ?? const [])
          {
            'user_id': 'fixture-user',
            'block_id': null,
            'started_at': clock,
            'ended_at': clock,
            'source': 'manual',
            ...JsonMap.from(log as Map),
          },
      ],
      'fixed_events': [
        for (final event in row['fixed_events'] as List? ?? const [])
          {
            'user_id': 'fixture-user',
            'title': (event as Map)['id'],
            'date': from,
            'kind': 'course',
            'repeat': 'none',
            'created_at': clock,
            'updated_at': clock,
            ...JsonMap.from(event),
          },
      ],
      'replan_runs': <Object?>[],
      'phases': <Object?>[],
    });
  }

  ScheduleBlock candidateBlock(JsonMap placement) {
    final candidate = JsonMap.from(placement['candidate'] as Map);
    return ScheduleBlock.fromJson({
      'id': 'candidate',
      'user_id': 'fixture-user',
      'start_minute': 0,
      'duration_minutes': 30,
      'actual_minutes': 0,
      'is_fixed': false,
      'status': 'planned',
      'created_at': clock,
      'updated_at': clock,
      ...candidate,
    });
  }

  List<JsonMap> blockSummary(List<ScheduleBlock> blocks) => [
    for (final block in blocks)
      {
        'task_id': block.taskId,
        'date': block.date,
        'start_minute': block.startMinute,
        'duration_minutes': block.durationMinutes,
      },
  ];

  List<JsonMap> newBlockSummary(
    List<ScheduleBlock> blocks,
    List<ScheduleBlock> originals,
  ) => blockSummary([
    for (final block in blocks)
      if (!originals.any((original) => original.id == block.id)) block,
  ]);

  for (final raw in fixture['cases'] as List) {
    final row = JsonMap.from(raw as Map);
    test(row['name'] as String, () {
      final data = buildData(row);
      final snapshot = data.toJsonString();
      final from = row['from'] as String;
      final to = row['to'] as String;
      var nextId = 0;
      SchedulerRuntime runtime() => SchedulerRuntime(
        now: DateTime.parse(clock),
        nextId: () => 'contract-${++nextId}',
      );

      var state = data;
      final expectedAuto = row['expected_auto'] as JsonMap?;
      if (expectedAuto != null) {
        final result = scheduleStrategy(data, from, to, runtime: runtime());
        expect(data.toJsonString(), snapshot);
        expect(
          jsonValue({
            'scheduled': result.scheduledMinutes,
            'unscheduled': result.unscheduledMinutes,
            'issues': (result.issues.map((issue) => issue.code).toList()
              ..sort()),
          }),
          {
            'scheduled': expectedAuto['scheduled'],
            'unscheduled': expectedAuto['unscheduled'],
            'issues': expectedAuto['issues'],
          },
        );
        expect(
          jsonValue(newBlockSummary(result.blocks, data.blocks)),
          expectedAuto['new_blocks'],
        );
        state = data.copyWith(blocks: result.blocks);
        // Every legal automatically generated block must pass manual placement in the
        // same occupancy state; the candidate itself is excluded so it is not counted twice.
        for (final block in result.blocks) {
          if (data.blocks.any((original) => original.id == block.id)) continue;
          expect(
            validateBlockPlacement(state, block, ignoreId: block.id),
            isNull,
          );
        }
      }

      for (final placement in row['placements'] as List? ?? const []) {
        final check = JsonMap.from(placement as Map);
        expect(
          jsonValue(validateBlockPlacement(data, candidateBlock(check))),
          check['expected'],
        );
      }
      for (final placement
          in row['post_schedule_placements'] as List? ?? const []) {
        final check = JsonMap.from(placement as Map);
        expect(
          jsonValue(validateBlockPlacement(state, candidateBlock(check))),
          check['expected'],
        );
      }

      final replan = row['replan'] as JsonMap?;
      if (replan != null) {
        final preview = generateReplanPreview(
          ReplanInput.fromJson({
            ...data.toJson(),
            'today': replan['today'],
            'mode': replan['mode'],
          }),
          runtime: runtime(),
        );
        final expected = replan['expected'] as JsonMap;
        expect(jsonValue(blockSummary(preview.after)), expected['after']);
        expect(preview.after.length, (expected['after'] as List).length);
        for (final id in expected['protected_block_ids'] as List) {
          final original = data.blocks.firstWhere((block) => block.id == id);
          expect(preview.after.firstWhere((block) => block.id == id), original);
        }
        expect(
          jsonValue(
            (preview.conflicts
                .map(
                  (conflict) => {
                    'task_id': conflict.taskId,
                    'minutes': conflict.minutes,
                  },
                )
                .toList()
              ..sort(
                (a, b) =>
                    (a['task_id'] as String).compareTo(b['task_id'] as String),
              )),
          ),
          expected['conflicts'],
        );
        final replanned = data.copyWith(blocks: preview.after);
        for (final block in preview.after) {
          if (data.blocks.any((original) => original.id == block.id)) continue;
          expect(
            validateBlockPlacement(replanned, block, ignoreId: block.id),
            isNull,
          );
        }
      }

      expect(data.toJsonString(), snapshot);
    });
  }
}
