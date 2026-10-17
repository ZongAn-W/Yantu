import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/onboarding/domain/onboarding_session.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/learning_context_view.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/onboarding_page.dart';
import '../support/http_adapter.dart';
import '../support/onboarding_fixture.dart';

void main() {
  testWidgets(
    'the inferred exam year can be changed without adding an interview answer',
    (tester) async {
      final current = DateTime.now().year;
      final data = onboardingFixture()
        ..['learning_context'] = {
          'facts': {
            'identity': {'value': '本科大三', 'answer_index': 0, 'quote': '本科大三'},
          },
          'timing': {
            'exam_year': current + 1,
            'admission_year': current + 2,
            'estimated': true,
            'reason': '按四年制本科应届升学推算',
          },
        };
      Map<String, dynamic>? action;
      await tester.pumpWidget(
        MaterialApp(
          theme: plannerTheme(),
          home: Scaffold(
            body: LearningContextView(
              session: OnboardingSession.fromJson(data),
              busy: false,
              onAction: (value) async {
                action = value;
                return true;
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('预计'), findsOneWidget);
      await tester.tap(find.byTooltip('修改初试年份'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(action, {'type': 'set_exam_year', 'year': current + 1});
      expect(data['answers'], isEmpty);
    },
  );

  testWidgets(
    'official facts keep their scope, quote and source link on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = onboardingFixture()
        ..['research'] = {
          'key': 'same-goal',
          'status': 'reference',
          'message': '目标年度要求仍待核实',
          'facts': [
            {
              'statement': '计算机技术专硕初试含英语一',
              'reference_only': true,
              'applicable_year': 2027,
              'quote': '2027年计算机技术专硕考试科目：英语一。',
            },
          ],
          'sources': [
            {
              'title': '上海交通大学硕士研究生招生专业目录',
              'url': 'https://yzb.sjtu.edu.cn/catalogue',
            },
          ],
        };
      Map<String, dynamic>? action;
      await tester.pumpWidget(
        MaterialApp(
          theme: plannerTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LearningContextView(
                session: OnboardingSession.fromJson(data),
                busy: false,
                onAction: (value) async {
                  action = value;
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('官方资料（1）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('参考：'), findsOneWidget);
      expect(find.text('https://yzb.sjtu.edu.cn/catalogue'), findsOneWidget);
      expect(find.byTooltip('打开官方来源'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('重新核实官方资料'));
      expect(action, {'type': 'retry_research'});
    },
  );

  testWidgets(
    'background research completion preserves the in-progress answer and question',
    (tester) async {
      var loads = 0;
      final data = onboardingFixture(answers: 5)
        ..['research'] = {
          'key': 'same-goal',
          'status': 'pending',
          'message': '正在核对官方考试资料…',
          'facts': [],
          'sources': [],
        };
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: Dio()
          ..httpClientAdapter = TestAdapter((request) async {
            loads++;
            return jsonResponse({
              'session': {
                ...data,
                if (loads > 1)
                  'research': {
                    'key': 'same-goal',
                    'status': 'not_found',
                    'message': '暂未核实目标年度要求',
                    'facts': [],
                    'sources': [],
                  },
              },
            });
          }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(client)],
          child: MaterialApp(
            theme: plannerTheme(),
            home: const OnboardingPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextFormField), '我还在填写这段回答');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('我还在填写这段回答'), findsOneWidget);
      expect(find.text(data['question'] as String), findsOneWidget);
      expect(find.text('暂未核实目标年度要求'), findsOneWidget);
      expect(find.text('第 6 问'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
