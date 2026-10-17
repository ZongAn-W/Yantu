import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

JsonMap readPlannerFixture() => JsonMap.from(
  jsonDecode(File('test/fixtures/planner_v1.json').readAsStringSync()) as Map,
);

void main() {
  test(
    'TypeScript PlannerData including nullable references and replan history round-trips',
    () {
      final source = readPlannerFixture();
      final data = PlannerData.fromJson(source);
      expect(data.toJson(), source);
      expect(jsonDecode(data.toJsonString()), source);
      expect(data.tasks.single.subjectId, data.subjects.single.id);
      expect(data.logs.single.blockId, isNull);
      expect(data.replanRuns.single.changes.single.before, isNull);
      expect(data.replanRuns.single.changes.single.after, data.blocks.single);
      expect(() => data.tasks.clear(), throwsUnsupportedError);
      expect(data.copyWith(tasks: []).tasks, isEmpty);
      expect(data.tasks, hasLength(1));
    },
  );

  test(
    'optional legacy planning mode defaults daily; date-only strings stay unchanged',
    () {
      final source = readPlannerFixture();
      (source['profile'] as Map).remove('planning_mode');
      final data = PlannerData.fromJson(source);
      expect(data.profile.planningMode, PlanningMode.daily);
      expect(data.profile.toJson().containsKey('planning_mode'), isFalse);
      expect(
        data.tasks.single.deadline,
        (source['tasks'] as List).single['deadline'],
      );
      final block = JsonMap.from((source['blocks'] as List).single as Map)
        ..['advice_text'] = '完成一组练习';
      final parsed = ScheduleBlock.fromJson(block);
      expect(parsed.adviceText, '完成一组练习');
      expect(parsed.toJson(), block);
    },
  );

  test(
    'unknown future fields are tolerated but unsupported versions and invalid priority are rejected',
    () {
      final source = readPlannerFixture()..['future_readonly_hint'] = true;
      expect(PlannerData.fromJson(source).version, 1);
      expect(
        () => PlannerData.fromJson({...source, 'version': 2}),
        throwsA(isA<Exception>()),
      );
      (source['tasks'] as List).single['priority'] = 9;
      expect(() => PlannerData.fromJson(source), throwsA(isA<Exception>()));
    },
  );

  test(
    'sync metadata preserves revision, pending, base and camelCase updatedAt',
    () {
      final data = PlannerData.fromJson(readPlannerFixture());
      final metadata = SyncMetadata(
        revision: 7,
        pending: true,
        base: data,
        updatedAt: DateTime.utc(2026, 10, 16),
      );
      final json = metadata.toJson();
      expect(json.containsKey('updatedAt'), isTrue);
      expect(json.containsKey('updated_at'), isFalse);
      expect(SyncMetadata.fromJson(json), metadata);
      expect(metadata.copyWith(base: null).base, isNull);
      expect(
        () => SyncMetadata.fromJson({'revision': -1}),
        throwsA(isA<Exception>()),
      );
      expect(
        () => SyncMetadata.fromJson({'version': 2}),
        throwsA(isA<Exception>()),
      );
    },
  );
}
