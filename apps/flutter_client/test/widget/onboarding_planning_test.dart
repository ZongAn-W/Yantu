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

Future<void> mount(
  WidgetTester tester,
  Map<String, dynamic> session,
  void Function(Map action) onAction,
) async {
  final api = ApiClient(
    config: const AppConfig(apiBaseUrl: 'http://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: Dio()
      ..httpClientAdapter = TestAdapter((request) async {
        if (request.method == 'POST') {
          onAction((request.data as Map)['action'] as Map);
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
}

void main() {
  test(
    'editing items invalidates restored quality result but research does not',
    () {
      final json = onboardingFixture(stage: 'schedule')
        ..['preview'] = {'token': 'saved'};
      final session = OnboardingSession.fromJson(json);
      expect(
        session.edit(research: {'status': 'pending'}).preview!['token'],
        'saved',
      );
      expect(session.edit(items: []).preview, isNull);
    },
  );

  testWidgets(
    'constraints are confirmed before item generation, including rest days',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = onboardingFixture(stage: 'constraints');
      Map? action;
      await mount(tester, session, (value) => action = value);
      await tester.enterText(find.byKey(const ValueKey('weekly-1-0')), '0');
      final submit = find.text('确认条件，生成事项');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(action!['type'], 'set_constraints');
      expect((action!['weekly_minutes'] as Map)['0'], 0);
      // 新计划使用净容量口径；旧的 detail_days 主流程字段不再发送。
      expect(action!['capacity_basis'], 'net');
      expect(action!.containsKey('detail_days'), isFalse);
      expect(action!['end_date'], isNotEmpty);
    },
  );

  testWidgets(
    'weekly capacity range requires confirming the adopted conservative baseline',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = onboardingFixture(stage: 'constraints');
      Map? action;
      await mount(tester, session, (value) => action = value);
      await tester.ensureVisible(find.text('大致周容量范围'));
      await tester.tap(find.text('大致周容量范围'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('weekly-range-min')), findsOneWidget);
      expect(find.byKey(const ValueKey('weekly-baseline-confirm')), findsOneWidget);
      // 未确认保守基线时不能提交。
      final submit = find.text('确认条件，生成事项');
      await tester.ensureVisible(submit);
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '确认条件，生成事项')).onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('weekly-baseline-confirm')),
      );
      await tester.tap(find.byKey(const ValueKey('weekly-baseline-confirm')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(action!['type'], 'set_constraints');
      expect(action!['capacity_basis'], 'net');
      expect(action!['weekly_baseline_minutes'], isNotNull);
      expect(action!['weekly_range_min_minutes'], isNotNull);
      expect(action!['weekly_range_max_minutes'], isNotNull);
    },
  );

  testWidgets(
    'preview is required, shows gaps, and expires after capacity changes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = onboardingFixture(stage: 'schedule');
      final actions = <Map>[];
      await mount(tester, session, (action) {
        actions.add(action);
        if (action['type'] == 'preview_schedule') {
          session['revision'] = (session['revision'] as int) + 1;
          session['preview'] = {
            'token': 'preview-1',
            'mode': 'full',
            'detailed_until': '2026-11-13',
            'scheduled_minutes': 120,
            'unscheduled_minutes': 60,
            'forecast_minutes': 0,
            'capacity_minutes': 240,
            'protected_blocks': 2,
            'status': 'ready',
            'days': [],
            'issues': [
              {
                'code': 'shortfall',
                'severity': 'warning',
                'message': '阅读练习尚缺 1 次',
              },
            ],
            'capacity': {
              'basis': 'net',
              'adopted_weekly_minutes': 600,
              'source': 'baseline',
              'weekly_range_minutes': {'min': 300, 'max': 900},
              'estimated_weeks': 2,
              'assumptions': ['按净学习时间计算'],
            },
            'capacity_impact': {
              'kept_blocks': 2,
              'kept_minutes': 120,
              'released_blocks': 1,
              'released_minutes': 60,
              'added_blocks': 3,
              'added_minutes': 90,
              'unscheduled_minutes': 0,
              'deadline_at_risk': [],
            },
          };
        }
      });
      FilledButton confirm() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '确认并生成每日计划'),
      );
      expect(confirm().onPressed, isNull);
      await tester.ensureVisible(find.text('试排并检查'));
      await tester.tap(find.text('试排并检查'));
      await tester.pumpAndSettle();
      expect(find.text('阅读练习尚缺 1 次'), findsOneWidget);
      // 全周期预览：显示覆盖范围、容量假设与排程影响，不再出现“远期待细化”。
      expect(find.textContaining('全周期覆盖'), findsOneWidget);
      expect(find.text('容量假设'), findsOneWidget);
      expect(find.text('排程影响'), findsOneWidget);
      expect(find.textContaining('远期待细化'), findsNothing);
      expect(confirm().onPressed, isNotNull);
      final monday = find.byKey(const ValueKey('weekly-1-1'));
      await tester.ensureVisible(monday);
      await tester.enterText(monday, '60');
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNull);
      expect(find.text('时间条件已修改，请重新试排后确认。'), findsOneWidget);
      expect(actions.single['type'], 'preview_schedule');
      await tester.ensureVisible(find.text('试排并检查'));
      await tester.tap(find.text('试排并检查'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('确认并生成每日计划'));
      await tester.tap(find.text('确认并生成每日计划'));
      await tester.pumpAndSettle();
      expect(actions.last['type'], 'finish');
      expect(actions.last['preview_token'], 'preview-1');
      expect((actions.last['weekly_minutes'] as Map)['1'], 60);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile constraints and quality warnings have no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mount(tester, onboardingFixture(stage: 'constraints'), (_) {});
    expect(find.text('确认本次规划条件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
