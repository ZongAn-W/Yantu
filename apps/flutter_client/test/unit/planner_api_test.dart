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

void main() {
  ApiClient client(Respond respond) => ApiClient(
    config: const AppConfig(apiBaseUrl: 'http://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: Dio()..httpClientAdapter = TestAdapter(respond),
  );

  test('snapshot parses a complete existing TypeScript export', () async {
    final json = jsonDecode(
      File('test/fixtures/planner_v1.json').readAsStringSync(),
    );
    final http = client((_) async => jsonResponse({'data': json}));
    addTearDown(http.close);
    final data = await PlannerApi(http).snapshot();
    expect(data!.toJson(), json);
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
            'courses': [
              {'id': 'math', 'name': '数学'},
            ],
            'items': [
              {
                'id': 'item-1',
                'course_id': 'math',
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
      expect(draft.draft.items.single.courseId, 'math');
      expect(draft.draft.warnings, isEmpty);
    },
  );
}
