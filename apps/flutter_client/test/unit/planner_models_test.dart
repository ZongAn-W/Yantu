import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
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

  test('a goal without a target date survives export, validation and import', () {
    final json = readPlannerFixture();
    final profile = JsonMap.from(json['profile'] as Map)
      ..['goal_text'] = '长期阅读中国近现代史'
      ..['goal_type'] = 'self_study'
      ..['goal_subtype'] = ''
      ..['target_date'] = ''
      ..['target_date_confirmed'] = false
      ..['plan_start_date'] = '2026-10-17'
      ..['plan_end_date'] = '2026-11-13'
      // 新文档不再写旧镜像字段；客户端把缺失的镜像保留为空字符串。
      ..['exam_date'] = ''
      ..['exam_end_date'] = ''
      ..['weekly_minutes'] = {
        '0': 0,
        '1': 120,
        '2': 0,
        '3': 120,
        '4': 0,
        '5': 120,
        '6': 0,
      };
    final tasks = [
      for (final row in json['tasks'] as List)
        JsonMap.from(row as Map)..['deadline_kind'] = 'plan_end',
    ];
    final source = JsonMap.from(json)
      ..['profile'] = profile
      ..['tasks'] = tasks;
    final encoded = jsonEncode(source);
    final parsed = parsePlannerJson(encoded);
    expect(parsed.profile.resolvedTargetDate, isEmpty);
    expect(parsed.profile.goalType, GoalType.selfStudy);
    expect(parsed.profile.resolvedPlanEnd('2026-10-17'), '2026-11-13');
    expect(parsed.profile.weekMinutes['2'], 0);
    expect(parsed.tasks.single.deadlineKind, ItemDateKind.planEnd);
    expect(parsed.toJson(), source);
  });

  test('legacy plans without the new fields read as an unknown date and a real deadline', () {
    final source = readPlannerFixture();
    final profile = JsonMap.from(source['profile'] as Map)
      ..remove('goal_text')
      ..remove('goal_type')
      ..remove('target_date')
      ..remove('plan_start_date')
      ..remove('plan_end_date')
      ..remove('weekly_minutes');
    final task = JsonMap.from((source['tasks'] as List).single as Map)
      ..remove('deadline_kind');
    final parsed = PlannerData.fromJson(
      JsonMap.from(source)
        ..['profile'] = profile
        ..['tasks'] = [task],
    );
    expect(parsed.profile.goalType, GoalType.other);
    expect(parsed.profile.resolvedTargetDate, '2027-12-25');
    expect(parsed.profile.resolvedPlanEnd('2026-10-17'), '2027-12-26');
    expect(parsed.profile.weekMinutes['1'], parsed.profile.dailyLimitMinutes);
    expect(parsed.tasks.single.deadlineKind, ItemDateKind.deadline);
  });

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
