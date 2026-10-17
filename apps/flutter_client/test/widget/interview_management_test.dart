import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/app.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/onboarding_page.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/router/app_router.dart';
import '../support/http_adapter.dart';
import '../support/onboarding_fixture.dart';
import '../support/planner_fixture.dart';

class _CurrentPlanApi implements SyncApi {
  _CurrentPlanApi(this.data);
  final PlannerData data;
  @override
  Future<RemoteSnapshot> pull() async => RemoteSnapshot(data, 9);
  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async => RemoteSnapshot(next, 9);
}

void main() {
  testWidgets(
    'stale plan refresh preserves the reviewed draft and entered schedule',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var session = onboardingFixture(stage: 'schedule', answers: 5)
        ..['has_plan'] = true
        ..['replanning'] = true
        ..['plan_revision'] = 7;
      session['profile'] = {
        'goal_text': '准备计算机专业研究生考试',
        'goal_type': 'exam',
        'goal_subtype': '考研',
        'target_date': '2027-12-25',
        'plan_start_date': '2026-10-01',
        'plan_end_date': '2027-12-25',
        'weekly_minutes': {for (var i = 0; i < 7; i++) '$i': 120},
      };
      final actions = <Map>[];
      final data = forAccount(plannerFixture(), testUser['id']!);
      final coordinator =
          PlannerCoordinator(
              userId: testUser['id']!,
              scope: 'test',
              storage: MemoryStorageRepository(),
              api: _CurrentPlanApi(data),
              retryInterval: null,
            )
            ..ready = true
            ..data = data
            ..status = SyncStatus.connected;
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: Dio()
          ..httpClientAdapter = TestAdapter((request) async {
            if (request.method == 'POST') {
              final action = Map.from((request.data as Map)['action'] as Map);
              actions.add(action);
              if (action['type'] == 'finish') {
                return jsonResponse({'error': '当前计划已更新，请重新读取当前计划后再确认'}, 409);
              }
              if (action['type'] == 'refresh_plan') {
                session = {...session, 'revision': 6, 'plan_revision': 9};
              }
            }
            return jsonResponse({'session': session});
          }),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            plannerSyncProvider.overrideWith((_) => coordinator),
          ],
          child: MaterialApp(
            theme: plannerTheme(),
            home: const Scaffold(body: OnboardingPage(embedded: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('weekly-1-1')), '150');
      await tester.tap(find.text('确认并更新每日计划'));
      await tester.pumpAndSettle();
      expect(find.text('更新当前计划进度，保留草稿'), findsOneWidget);
      await tester.tap(find.text('更新当前计划进度，保留草稿'));
      await tester.pumpAndSettle();
      expect(actions.map((action) => action['type']), [
        'finish',
        'refresh_plan',
      ]);
      expect(find.text('150'), findsOneWidget);
      await tester.tap(find.text('确认并更新每日计划'));
      await tester.pumpAndSettle();
      expect((actions.last['weekly_minutes'] as Map)['1'], 150);
      expect(actions.last['end_date'], '2027-12-25');
      expect(actions.last['target_date'], '2027-12-25');
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'interview navigation resumes, preserves drafts and confirms restart at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var session = onboardingFixture(stage: 'complete', answers: 5)
          ..['has_plan'] = true
          ..['profile'] = {
            'goal_text': '准备计算机专业研究生考试',
            'goal_type': 'exam',
            'goal_subtype': '考研',
            'target_date': '2027-12-25',
          };
        final plan = forAccount(plannerFixture(), testUser['id']!).toJson();
        final original = jsonEncode(plan);
        final actions = <String>[];
        final client = ApiClient(
          config: const AppConfig(apiBaseUrl: 'http://api.test'),
          tokenStore: MemoryTokenStore(),
          dio: Dio()
            ..httpClientAdapter = TestAdapter((request) async {
              if (request.path == '/api/auth/login') {
                return jsonResponse({
                  'user': testUser,
                  'accessToken': 'access',
                  'refreshToken': 'refresh',
                  'expiresIn': 900,
                });
              }
              if (request.path == '/api/onboarding/profile') {
                return jsonResponse({'profile': session['profile']});
              }
              if (request.path == '/api/planner/sync') {
                return jsonResponse({'data': plan, 'revision': 7});
              }
              if (request.path == '/api/onboarding/session') {
                return jsonResponse({'session': session});
              }
              if (request.path == '/api/ai/onboarding/advance') {
                final action = (request.data as Map)['action'] as Map;
                actions.add(action['type'] as String);
                if (action['type'] == 'resume_interview') {
                  session['stage'] = 'interview';
                  session['replanning'] = true;
                  session['question'] = '最近有哪些准备情况需要补充？';
                } else if (action['type'] == 'restart_interview') {
                  session = onboardingFixture()
                    ..['has_plan'] = true
                    ..['replanning'] = true;
                }
                session['revision'] = (session['revision'] as int) + 1;
                return jsonResponse({'session': session});
              }
              return jsonResponse({'error': 'Unexpected ${request.path}'}, 404);
            }),
        );
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(client),
            identityStoreProvider.overrideWithValue(MemoryIdentityStore()),
            storageRepositoryProvider.overrideWithValue(
              MemoryStorageRepository(),
            ),
            syncRetryIntervalProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(client.close);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const PlannerApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'student@example.com',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'Study4089');
        await tester.tap(find.widgetWithText(FilledButton, '登录'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('访谈').last);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          '/interview',
        );
        expect(find.text('访谈与规划'), findsOneWidget);
        await tester.tap(find.text('继续访谈'));
        await tester.pumpAndSettle();
        expect(actions, ['resume_interview']);
        expect(find.text('已回答 5 个问题'), findsOneWidget);
        expect(find.text('最近有哪些准备情况需要补充？'), findsOneWidget);
        expect(find.text('新计划确认前，当前计划保持生效。'), findsOneWidget);
        await tester.tap(find.text('今日').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('访谈').last);
        await tester.pumpAndSettle();
        expect(find.text('最近有哪些准备情况需要补充？'), findsOneWidget);
        await tester.tap(find.text('重新访谈'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(actions, ['resume_interview']);
        await tester.tap(find.text('重新访谈'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重新开始'));
        await tester.pumpAndSettle();
        expect(actions, ['resume_interview', 'restart_interview']);
        expect(find.text('你的长期目标是什么？'), findsOneWidget);
        expect(jsonEncode(plan), original);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
