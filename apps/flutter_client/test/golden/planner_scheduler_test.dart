import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

Object? jsonValue(Object? value) => jsonDecode(jsonEncode(value));

/// Remove additive legacy-default keys introduced by the unified model from actual
/// output before comparing with the pre-existing TypeScript oracle.
///
/// `planner-goldens.json` is a legacy-data oracle generated before the flexible
/// time/relations model existed, and the TypeScript engine intentionally does not
/// duplicate the Flutter model. These keys are therefore absent from the oracle but
/// are always serialized by Dart with a default value that means exactly the old
/// behaviour. Only the documented defaults are stripped; any non-default value
/// (`relation: scheduled|extra|ad_hoc`, `capacity_basis: net`, a non-empty
/// `ad_hoc_learnings` list) is preserved so real regressions still fail.
/// - `profile.capacity_basis == "gross_buffer"` (legacy total-budget semantics)
/// - `logs[].relation == "legacy_unknown"` (old logs without classification)
/// - empty top-level `ad_hoc_learnings` list
Object? stripLegacyModelDefaults(Object? value) {
  if (value is List) {
    return value.map(stripLegacyModelDefaults).toList();
  }
  if (value is Map) {
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      final key = entry.key;
      final item = entry.value;
      if (key == 'capacity_basis' && item == 'gross_buffer') continue;
      if (key == 'relation' && item == 'legacy_unknown') continue;
      if (key == 'ad_hoc_learnings' && item is List && item.isEmpty) continue;
      result[key as String] = stripLegacyModelDefaults(item);
    }
    return result;
  }
  return value;
}

/// Whether [value] still carries a non-default new-model field (used by tests that
/// prove the normalization above is not over-broad).
bool hasNonDefaultNewFields(Object? value) {
  if (value is List) return value.any(hasNonDefaultNewFields);
  if (value is Map) {
    if (value['capacity_basis'] != null &&
        value['capacity_basis'] != 'gross_buffer') {
      return true;
    }
    if (value['relation'] != null && value['relation'] != 'legacy_unknown') {
      return true;
    }
    if (value['ad_hoc_learnings'] is List &&
        (value['ad_hoc_learnings'] as List).isNotEmpty) {
      return true;
    }
    return value.values.any(hasNonDefaultNewFields);
  }
  return false;
}

void main() {
  final fixture =
      jsonDecode(
            File(
              '../../packages/planner-engine/fixtures/planner-goldens.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test('legacy-default normalization keeps non-default new model values', () {
    final normalized =
        stripLegacyModelDefaults({
              'profile': {'capacity_basis': 'net', 'daily_limit_minutes': 480},
              'logs': [
                {'relation': 'extra'},
                {'relation': 'legacy_unknown'},
              ],
              'ad_hoc_learnings': [
                {'id': 'ad-1'},
              ],
            })
            as Map;
    expect(normalized['profile'], {
      'capacity_basis': 'net',
      'daily_limit_minutes': 480,
    });
    expect((normalized['logs'] as List)[0], {'relation': 'extra'});
    expect((normalized['logs'] as List)[1], <String, dynamic>{});
    expect((normalized['ad_hoc_learnings'] as List).length, 1);
    expect(hasNonDefaultNewFields(normalized), isTrue);
    expect(
      stripLegacyModelDefaults({
        'profile': {'capacity_basis': 'gross_buffer'},
        'logs': [
          {'relation': 'legacy_unknown'},
        ],
        'ad_hoc_learnings': [],
      }),
      {'profile': <String, dynamic>{}, 'logs': [<String, dynamic>{}]},
    );
  });
  for (final raw in fixture['cases'] as List) {
    final row = JsonMap.from(raw as Map);
    test(row['name'] as String, () {
      final args = JsonMap.from(row['args'] as Map);
      var id = 0;
      final runtime = SchedulerRuntime(
        now: DateTime.parse(fixture['clock'] as String),
        nextId: () => 'gold-${(++id).toString().padLeft(4, '0')}',
      );
      final data = args['data'] == null
          ? null
          : PlannerData.fromJson(JsonMap.from(args['data'] as Map));
      final original = data?.toJsonString();
      String? error(void Function() operation) {
        try {
          operation();
          return null;
        } on StateError catch (error) {
          return error.message;
        } on FormatException catch (error) {
          return error.message;
        }
      }

      Object? run() {
        switch (row['operation']) {
          case 'date':
            return addDays(args['date'] as String, args['days'] as int);
          case 'capacity':
            final events = (args['events'] as List)
                .map((value) => FixedEvent.fromJson(JsonMap.from(value as Map)))
                .toList();
            final date = args['date'] as String;
            return {
              'occurs': events
                  .map((event) => eventOccursOn(event, date))
                  .toList(),
              'union': fixedEventMinutesForDate(events, date),
              'without_rest': fixedEventMinutesForDate(
                events,
                date,
                includeRest: false,
              ),
              'available': availableDailyMinutes(
                Profile.fromJson(JsonMap.from(args['profile'] as Map)),
                events,
                date,
              ),
            };
          case 'totals':
            final task = Task.fromJson(JsonMap.from(args['task'] as Map));
            final logs = (args['logs'] as List)
                .map((value) => TimeLog.fromJson(JsonMap.from(value as Map)))
                .toList();
            return {
              'completed': taskCompletedMinutes(task, logs),
              'remaining': remainingTaskMinutes(task, logs),
            };
          case 'placement':
            return validateBlockPlacement(
              data!,
              ScheduleBlock.fromJson(JsonMap.from(args['candidate'] as Map)),
              ignoreId: args['ignoreId'] as String?,
            );
          case 'record':
            return recordTaskDayMinutes(
              data!,
              args['taskId'] as String,
              args['date'] as String,
              args['minutes'] as int,
              runtime: runtime,
            );
          case 'records':
            return (args['entries'] as List).fold<PlannerData>(
              data!,
              (state, entry) => recordTaskDayMinutes(
                state,
                entry['taskId'] as String,
                entry['date'] as String,
                entry['minutes'] as int,
                runtime: runtime,
              ),
            );
          case 'merge':
            List<TimeLog> logs(String key) => (args[key] as List)
                .map((value) => TimeLog.fromJson(JsonMap.from(value as Map)))
                .toList();
            return mergeTaskDayLogs(
              logs('base'),
              logs('local'),
              logs('remote'),
            );
          case 'lifecycle':
            final preview = generateReplanPreview(
              ReplanInput.fromJson({
                ...data!.toJson(),
                'today': args['today'],
                'mode': args['mode'],
                'excess_minutes': args['excess_minutes'],
              }),
              runtime: runtime,
            );
            expect(data.toJsonString(), original);
            final confirmed = confirmReplan(data, preview);
            final undone = undoLastReplan(confirmed);
            return {
              'preview': preview,
              'confirmed': confirmed,
              'undone': undone,
              'errors': {
                'foreign': error(
                  () => confirmReplan(data, preview.copyWith(userId: 'other')),
                ),
                'duplicate': error(() => confirmReplan(confirmed, preview)),
                'stale': error(
                  () => confirmReplan(
                    data.copyWith(
                      blocks: [
                        ...data.blocks,
                        data.blocks.first.copyWith(id: 'new'),
                      ],
                    ),
                    preview,
                  ),
                ),
                'changed_undo': error(
                  () => undoLastReplan(
                    confirmed.copyWith(
                      blocks: [
                        ...confirmed.blocks,
                        data.blocks.first.copyWith(id: 'new'),
                      ],
                    ),
                  ),
                ),
                'empty_undo': error(
                  () => undoLastReplan(data.copyWith(replanRuns: [])),
                ),
              },
            };
          default:
            throw StateError('unknown operation ${row['operation']}');
        }
      }

      Object? actual;
      try {
        actual = jsonValue(run());
      } on StateError catch (error) {
        actual = {'error': error.message};
      } on FormatException catch (error) {
        actual = {'error': error.message};
      }
      expect(data?.toJsonString(), original);
      // Map keys may be emitted in either order; arrays, presence, nulls and every field are exact.
      expect(stripLegacyModelDefaults(actual), row['expected']);
    });
  }
}
