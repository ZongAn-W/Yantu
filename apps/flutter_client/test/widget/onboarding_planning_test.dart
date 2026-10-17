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
      expect(action!['detail_days'], 14);
      expect(action!['end_date'], isNotEmpty);
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
            'scheduled_minutes': 120,
            'unscheduled_minutes': 60,
            'deferred_minutes': 180,
            'capacity_minutes': 240,
            'protected_blocks': 2,
            'detailed_until': '2026-10-30',
            'days': [],
            'issues': [
              {
                'code': 'shortfall',
                'severity': 'warning',
                'message': '阅读练习尚缺 1 次',
              },
            ],
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
      expect(find.text('远期待细化 3小时，未计入近期每日任务。'), findsOneWidget);
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
