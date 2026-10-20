import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/onboarding_page.dart';
import '../support/http_adapter.dart';
import '../support/onboarding_fixture.dart';

void main() {
  testWidgets(
    'five answers keep the interview going, later answers advance, and failures retain input',
    (tester) async {
      var session = onboardingFixture();
      var failure = false;
      final actions = <Map>[];
      final api = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: Dio()
          ..httpClientAdapter = TestAdapter((request) async {
            if (request.method == 'POST') {
              final action = (request.data as Map)['action'] as Map;
              actions.add(action);
              if (failure) return jsonResponse({'error': 'AI暂时不可用，请重试'}, 502);
              if (action['type'] == 'answer') {
                final count = (session['answers'] as List).length + 1;
                session = onboardingFixture(answers: count);
              }
            }
            return jsonResponse({'session': session});
          }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: MaterialApp(
            theme: plannerTheme(),
            home: const OnboardingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('你的长期目标是什么？'), findsOneWidget);
      expect(find.text('根据当前回答生成事项'), findsNothing);
      final input = find.byKey(const ValueKey('interview-answer-input'));
      for (var i = 0; i < 5; i++) {
        await tester.enterText(input, '回答$i');
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
      }
      // 第五题之后不再暂停，直接显示第六题和生成入口。
      expect(find.text('信息已记录'), findsNothing);
      expect(find.text('继续完善信息'), findsNothing);
      expect(find.text('第 6 问'), findsOneWidget);
      expect(find.text('根据当前回答生成事项'), findsOneWidget);
      expect(
        actions.where((action) => action['type'] == 'answer'),
        hasLength(5),
      );

      // 继续回答后仍会生成下一题。
      await tester.enterText(input, '回答5');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.text('第 7 问'), findsOneWidget);
      expect(find.text('根据当前回答生成事项'), findsOneWidget);

      failure = true;
      await tester.enterText(input, '保留我的回答');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(input).controller!.text, '保留我的回答');
      expect(find.text('AI暂时不可用，请重试'), findsOneWidget);
      failure = false;
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已答 7 问'), findsOneWidget);
      expect(find.text('第 8 问'), findsOneWidget);
    },
  );

  testWidgets('manual item changes are included when asking AI to revise', (
    tester,
  ) async {
    var session = onboardingFixture(stage: 'items', answers: 5);
    session['items'] = [
      {
        'id': 'math-foundation',
        'title': '高数基础',
        'estimated_minutes': 120,
        'deadline': '2026-11-01',
        'tag_names': ['数学'],
      },
    ];
    Map? sent;
    final api = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()
        ..httpClientAdapter = TestAdapter((request) async {
          if (request.method == 'POST') {
            sent =
                jsonDecode(jsonEncode((request.data as Map)['action'])) as Map;
            session['revision'] = (session['revision'] as int) + 1;
            session['items'] = sent!['items'];
          }
          return jsonResponse({'session': session});
        }),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(theme: plannerTheme(), home: const OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认学习事项'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑 高数基础'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('draft-item-title')), '线性代数');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('线性代数'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '增加英语');
    await tester.tap(find.text('按要求修改'));
    await tester.pumpAndSettle();
    expect(sent!['type'], 'revise_items');
    expect(sent!['instruction'], '增加英语');
    expect((sent!['items'] as List).single['title'], '线性代数');
    expect((sent!['items'] as List).single['tag_names'], ['数学']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile renders long item details without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = onboardingFixture(stage: 'items', answers: 5);
    session['items'] = [
      {
        'id': 'task',
        'title': '一轮基础知识梳理与典型例题训练',
        'tag_names': ['数据结构', '薄弱项'],
        'description': '学习内容与完成标准需要完整显示，不能被操作按钮遮住。',
        'estimated_minutes': 600,
        'deadline': '2027-12-25',
      },
    ];
    final api = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()
        ..httpClientAdapter = TestAdapter(
          (_) async => jsonResponse({'session': session}),
        ),
    );
    addTearDown(api.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp(theme: plannerTheme(), home: const OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('确认学习事项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
