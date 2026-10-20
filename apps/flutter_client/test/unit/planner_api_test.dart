import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/features/planner/data/planner_api.dart';
import 'package:sjtu_study_planner_client/shared/models/api_models.dart';

import '../support/http_adapter.dart';

/// 旧 TypeScript 导出没有新字段；统一模型序列化时会物化“可加性旧默认键”
/// （临时学习空列表、容量口径 gross_buffer、旧日志 relation=legacy_unknown）。
/// 期望值补齐这些文档化默认后做全等比较，而不是放宽成子集断言。
Map<String, dynamic> legacyExportWithModelDefaults(Map source) {
  final expected = Map<String, dynamic>.from(source);
  final subjects = expected.remove('subjects') as List? ?? const [];
  final tags = [
    for (final value in subjects)
      if (value is Map)
        {
          'id': value['id'],
          'user_id': value['user_id'] ?? value['userId'],
          'name': (value['name'] as String).trim(),
          if (value['color'] != null) 'color': value['color'],
          'created_at': value['created_at'] ?? value['createdAt'] ?? '',
          'updated_at': value['updated_at'] ?? value['updatedAt'] ?? '',
        },
  ];
  expected['tags'] = tags;
  final tagIds = {for (final tag in tags) tag['id']: tag['id']};
  expected['tasks'] = [
    for (final value in expected['tasks'] as List)
      if (value is Map)
        () {
          final task = Map<String, dynamic>.from(value);
          final subjectId =
              task.remove('subject_id') ?? task.remove('subjectId');
          task['tag_ids'] = subjectId is String && tagIds.containsKey(subjectId)
              ? [tagIds[subjectId]]
              : <String>[];
          return task;
        }(),
  ];
  expected.putIfAbsent('ad_hoc_learnings', () => <dynamic>[]);
  expected['profile'] = Map<String, dynamic>.from(expected['profile'] as Map)
    ..remove('subject_limit_minutes')
    ..putIfAbsent('capacity_basis', () => 'gross_buffer');
  expected['logs'] = [
    for (final row in expected['logs'] as List)
      Map<String, dynamic>.from(row as Map)
        ..putIfAbsent('relation', () => 'legacy_unknown'),
  ];
  return expected;
}

void main() {
  ApiClient client(Respond respond) => ApiClient(
    config: const AppConfig(apiBaseUrl: 'http://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: Dio()..httpClientAdapter = TestAdapter(respond),
  );

  test('snapshot parses a complete existing TypeScript export', () async {
    final json =
        jsonDecode(File('test/fixtures/planner_v1.json').readAsStringSync())
            as Map;
    final http = client((_) async => jsonResponse({'data': json}));
    addTearDown(http.close);
    final data = await PlannerApi(http).snapshot();
    expect(data!.toJson(), legacyExportWithModelDefaults(json));
  });

  test(
    'no confirmed plan returns null; malformed data produces a parse failure',
    () async {
      var missing = true;
      final http = client(
        (_) async => missing
            ? jsonResponse({'error': '请先完成学习目标设置和计划确认'}, 404)
            : jsonResponse({
                'data': {'version': 1},
              }),
      );
      addTearDown(http.close);
      final api = PlannerApi(http);
      expect(await api.snapshot(), isNull);
      missing = false;
      await expectLater(api.snapshot(), throwsA(isA<ResponseFailure>()));
    },
  );

  test(
    'AI requests retain idempotency key, extended timeout and onboarding field names',
    () async {
      final http = client((request) async {
        expect(request.headers['Idempotency-Key'], 'request-1');
        expect(request.receiveTimeout, const Duration(seconds: 240));
        expect((request.data as Map)['weekly_minutes'], {'0': 30});
        return jsonResponse({
          'id': 'draft-1',
          'draft': {
            'items': [
              {
                'id': 'item-1',
                'tag_names': ['数学', '薄弱项'],
                'title': '基础一轮',
                'estimated_minutes': 120,
                'deadline': '2027-12-25',
              },
            ],
            'analysis_summary': '按实际可用时间安排',
          },
        });
      });
      addTearDown(http.close);
      final draft = await PlannerApi(http).createDraft(
        const OnboardingProfile(
          goalText: '准备计算机专业研究生考试',
          goalType: 'exam',
          goalSubtype: '考研',
          planEndDate: '2027-12-25',
          weeklyMinutes: {'0': 30},
        ),
        requestId: 'request-1',
      );
      expect(draft.draft.items.single.tagNames, ['数学', '薄弱项']);
      expect(draft.draft.warnings, isEmpty);
    },
  );
}
