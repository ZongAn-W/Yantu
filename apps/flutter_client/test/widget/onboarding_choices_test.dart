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
import 'package:sjtu_study_planner_client/features/onboarding/presentation/onboarding_page.dart';
import '../support/http_adapter.dart';
import '../support/onboarding_fixture.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> session, {
    Respond? respond,
  }) async {
    final client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()
        ..httpClientAdapter = TestAdapter(
          respond ?? (_) async => jsonResponse({'session': session}),
        ),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: MaterialApp(theme: plannerTheme(), home: const OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('legacy sessions keep free text and default recommendation fields', () {
    final session = OnboardingSession.fromJson(onboardingFixture());
    expect(session.questionOptions, isEmpty);
    expect(session.questionMultiple, isFalse);
    expect(session.recommendations.targetDate, isEmpty);
    expect(session.recommendations.weeklyMinutes, isEmpty);
  });

  testWidgets(
    'single choice requires a selection and resets for the next question',
    (tester) async {
      var session = onboardingFixture()..['question_options'] = ['考研', '考公'];
      Map? action;
      await mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            action = (request.data as Map)['action'] as Map;
            session = onboardingFixture(answers: 1)
              ..['question_options'] = ['刚开始', '已完成一轮'];
          }
          return jsonResponse({'session': session});
        },
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('提交回答，继续'));
      await tester.pumpAndSettle();
      expect(action, isNull);
      expect(find.text('请选择一个选项或填写其他回答'), findsOneWidget);
      await tester.tap(find.text('考研'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交回答，继续'));
      await tester.pumpAndSettle();
      expect(action!['answer'], '考研');
      expect(find.text('刚开始'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        isNull,
      );
    },
  );

  testWidgets('other accepts text and retains it after a failed request', (
    tester,
  ) async {
    final session = onboardingFixture()..['question_options'] = ['考研', '考公'];
    Map? action;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          action = (request.data as Map)['action'] as Map;
          return jsonResponse({'error': '请稍后重试'}, 502);
        }
        return jsonResponse({'session': session});
      },
    );
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '备考雅思7分');
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(action!['answer'], '备考雅思7分');
    expect(find.text('备考雅思7分'), findsOneWidget);
    expect(find.text('请稍后重试'), findsOneWidget);
  });

  testWidgets('multiple choice submits selected options and additional text', (
    tester,
  ) async {
    final session = onboardingFixture(answers: 2)
      ..['question_multiple'] = true
      ..['question_options'] = ['数学基础较弱', '英语需要强化', '专业课刚开始'];
    Map? action;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          action = (request.data as Map)['action'] as Map;
        }
        return jsonResponse({'session': session});
      },
    );
    await tester.tap(find.text('数学基础较弱'));
    await tester.tap(find.text('英语需要强化'));
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '周三晚上有课');
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(action!['answer'], '数学基础较弱；英语需要强化；周三晚上有课');
  });

  testWidgets(
    'schedule prefills recommendations, restores them and submits user edits',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = onboardingFixture(stage: 'schedule', answers: 5);
      session['recommendations'] = {
        'target_date': '2027-12-18',
        'target_date_reason': '按2027年考研安排估计',
        'target_date_estimated': true,
        'plan_end_date': '2026-11-13',
        'plan_end_date_reason': '本次规划周期默认为从今天开始的未来28个自然日',
        'weekly_minutes': {
          for (var i = 0; i < 7; i++) '$i': i == 0 || i == 6 ? 240 : 120,
        },
        'weekly_minutes_reason': '在校期间工作日两小时，周末四小时',
      };
      Map? action;
      await mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            action = (request.data as Map)['action'] as Map;
            return jsonResponse({'error': '测试保留当前页面'}, 400);
          }
          return jsonResponse({'session': session});
        },
      );
      expect(find.text('2026-11-13'), findsOneWidget);
      expect(find.text('2027-12-18'), findsOneWidget);
      expect(find.text('以正式通知为准，你也可以清空目标日期。'), findsOneWidget);
      expect(find.text('建议依据：在校期间工作日两小时，周末四小时'), findsOneWidget);
      final monday = find.byKey(const ValueKey('weekly-1-1'));
      await tester.enterText(monday, '180');
      await tester.tap(find.text('恢复推荐时间'));
      await tester.pumpAndSettle();
      final restored = find.byKey(const ValueKey('weekly-2-1'));
      expect(tester.widget<TextFormField>(restored).initialValue, '120');
      await tester.enterText(restored, '150');
      await tester.tap(find.text('确认并生成每日计划'));
      await tester.pumpAndSettle();
      expect(action!['end_date'], '2026-11-13');
      expect(action!['target_date'], '2027-12-18');
      expect((action!['weekly_minutes'] as Map)['1'], 150);
      expect((action!['weekly_minutes'] as Map)['0'], 240);
    },
  );

  testWidgets('long options wrap on mobile without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = onboardingFixture()
      ..['question_options'] = [
        '准备上海交通大学计算机技术专业研究生考试并参加408统考',
        '在职备考公务员，工作日晚上有时间',
      ];
    await mount(tester, session);
    expect(find.text('其他'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
