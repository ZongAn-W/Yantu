import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:sjtu_study_planner_client/app.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/router/app_router.dart';
import 'package:sjtu_study_planner_client/features/adjust/presentation/adjust_plan_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/features/auth/application/auth_controller.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/onboarding_page.dart';
import 'package:sjtu_study_planner_client/features/planner/application/onboarding_controller.dart';

import '../support/http_adapter.dart';
import '../support/planner_fixture.dart';
import '../support/onboarding_fixture.dart';

/// A finished profile for flows that also open the optional planning pages.
const testProfile = {
  'goal_text': '准备计算机专业研究生考试',
  'goal_type': 'exam',
  'goal_subtype': '考研',
  'target_date': '2027-12-25',
  'plan_start_date': '2026-10-01',
  'plan_end_date': '2027-12-25',
  'target_school': '上海交通大学',
  'target_program': '计算机技术',
  'current_progress': '高数基础一轮',
  'weekly_minutes': {
    '0': 0,
    '1': 120,
    '2': 120,
    '3': 120,
    '4': 120,
    '5': 120,
    '6': 180,
  },
  'constraints_text': '周三晚上有课',
};

Future<ResponseBody> Function(RequestOptions) plannerAdapter() =>
    (options) async {
      if (options.path.endsWith('/api/auth/login')) {
        return jsonResponse({
          'user': testUser,
          'accessToken': 'access',
          'refreshToken': 'refresh',
          'expiresIn': 900,
        });
      }
      if (options.path.endsWith('/api/onboarding/profile')) {
        return jsonResponse({'profile': testProfile});
      }
      if (options.path.endsWith('/api/onboarding/session')) {
        return jsonResponse({
          'session': onboardingFixture(stage: 'complete', answers: 5)
            ..['has_plan'] = true,
        });
      }
      if (options.path.endsWith('/api/planner/sync')) {
        return jsonResponse({'data': null, 'revision': 0});
      }
      return jsonResponse({'error': 'unexpected ${options.path}'}, 404);
    };

/// Shared overrides: an in-memory API client, identity store and plan storage.
List<Override> testOverrides(ApiClient client) => [
  apiClientProvider.overrideWithValue(client),
  identityStoreProvider.overrideWithValue(MemoryIdentityStore()),
  storageRepositoryProvider.overrideWithValue(MemoryStorageRepository()),
  // No periodic retry timer may outlive a widget test.
  syncRetryIntervalProvider.overrideWithValue(null),
];

void main() {
  testWidgets(
    'a new account reaches quick start without finishing planning first',
    (tester) async {
      final lookup = Completer<ResponseBody>();
      final adapter = TestAdapter((request) async {
        if (request.path == '/api/auth/login') {
          return jsonResponse({
            'user': testUser,
            'accessToken': 'access',
            'refreshToken': 'refresh',
            'expiresIn': 900,
          });
        }
        if (request.path == '/api/onboarding/session') {
          return jsonResponse({'session': onboardingFixture()});
        }
        if (request.path == '/api/onboarding/profile') return lookup.future;
        if (request.path == '/api/planner/sync') {
          return jsonResponse({'data': null, 'revision': 0});
        }
        return jsonResponse({'error': 'expired'}, 401);
      });
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      final container = ProviderContainer(overrides: testOverrides(client));
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
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/',
      );
      expect(
        adapter.requests.where(
          (request) => request.path == '/api/planner/sync',
        ),
        isNotEmpty,
      );
      expect(container.read(onboardingStatusProvider).isLoading, isTrue);
      expect(find.byKey(const Key('dashboard-quick-start')), findsOneWidget);
      expect(find.text('正在读取学习目标…'), findsNothing);
      final router = container.read(appRouterProvider);
      router.go('/login');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      lookup.complete(jsonResponse({'profile': null}));
      await tester.pumpAndSettle();
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/',
      );
      expect(
        adapter.requests.where(
          (request) => request.path == '/api/planner/sync',
        ),
        isNotEmpty,
      );
      expect(container.read(onboardingStatusProvider).valueOrNull, isNull);
      expect(find.text('还没有长期计划，也没关系'), findsOneWidget);
      expect(find.byKey(const Key('dashboard-quick-start')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-ai-planning')), findsOneWidget);
      expect(find.text('开始计时'), findsOneWidget);
      expect(find.text('AI 长期规划'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dashboard-quick-start')));
      await tester.pumpAndSettle();
      expect(find.text('今天想学什么？'), findsOneWidget);
      expect(find.byKey(const Key('ad-hoc-title')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      final beforePlanning = container.read(plannerSyncProvider).data;
      await tester.tap(find.byKey(const Key('dashboard-ai-planning')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/interview');
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(container.read(plannerSyncProvider).data, beforePlanning);
      expect(
        adapter.requests.where(
          (request) => request.path.startsWith('/api/ai/'),
        ),
        isEmpty,
      );
      for (final path in ['/onboarding', '/interview']) {
        router.go(path);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, path);
        expect(find.byType(OnboardingPage), findsOneWidget);
      }
    },
  );
  testWidgets(
    'offline restart keeps cached workbench accessible and recovers online',
    (tester) async {
      final plan = forAccount(plannerFixture(), testUser['id']!);
      final tokens = MemoryTokenStore();
      await tokens.write(
        TokenPair(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final identity = MemoryIdentityStore();
      await identity.save(testUser);
      final storage = MemoryStorageRepository();
      const apiUrl = 'http://api.test';
      await storage.save(
        'sjtu-study-planner:items-v2:${Uri.encodeComponent(apiUrl)}:cloud:${testUser['id']}',
        plan,
        StorageMetadata(base: plan, revision: 1),
      );
      var offline = true;
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: apiUrl),
        tokenStore: tokens,
        usesBearer: true,
        dio: Dio()
          ..httpClientAdapter = TestAdapter((request) async {
            if (offline) {
              throw DioException.connectionError(
                requestOptions: request,
                reason: 'offline',
              );
            }
            if (request.path == '/api/onboarding/profile') {
              return jsonResponse({'profile': testProfile});
            }
            if (request.path == '/api/planner/sync') {
              return jsonResponse({'data': plan.toJson(), 'revision': 1});
            }
            return jsonResponse({'user': testUser});
          }),
      );
      final container = ProviderContainer(
        overrides: [
          ...testOverrides(client),
          appConfigProvider.overrideWithValue(
            const AppConfig(apiBaseUrl: apiUrl),
          ),
          identityStoreProvider.overrideWithValue(identity),
          storageRepositoryProvider.overrideWithValue(storage),
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
      expect(container.read(authControllerProvider).user?.id, testUser['id']);
      final router = container.read(appRouterProvider);
      expect(router.routeInformationProvider.value.uri.path, '/');
      router.go('/tasks');
      await tester.pumpAndSettle();
      expect(find.text('事项管理'), findsOneWidget);
      expect(container.read(plannerSyncProvider).data, plan);
      offline = false;
      final refresh = container
          .read(onboardingStatusProvider.notifier)
          .refresh();
      await tester.pumpAndSettle();
      await refresh;
      expect(router.routeInformationProvider.value.uri.path, '/tasks');
    },
  );

  testWidgets(
    'profile lookup errors do not block direct entry or optional planning',
    (tester) async {
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: Dio()
          ..httpClientAdapter = TestAdapter((request) async {
            if (request.path == '/api/onboarding/session') {
              return jsonResponse({'session': onboardingFixture()});
            }
            if (request.path == '/api/onboarding/profile') {
              return jsonResponse({'error': 'unavailable'}, 503);
            }
            if (request.path == '/api/planner/sync') {
              return jsonResponse({'data': null, 'revision': 0});
            }
            if (request.path == '/api/auth/login') {
              return jsonResponse({
                'user': testUser,
                'accessToken': 'access',
                'refreshToken': 'refresh',
                'expiresIn': 900,
              });
            }
            return jsonResponse({'error': 'expired'}, 401);
          }),
      );
      final container = ProviderContainer(overrides: testOverrides(client));
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
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/',
      );
      // A profile lookup failure no longer traps the account on a loading page:
      // the workbench bootstraps an editable plan and offers the quick actions.
      expect(container.read(onboardingStatusProvider).hasError, isTrue);
      expect(find.byKey(const Key('dashboard-quick-start')), findsOneWidget);
      expect(find.text('重试读取学习目标'), findsNothing);
      // Optional planning stays reachable through the workbench.
      await tester.tap(find.byKey(const Key('dashboard-ai-planning')));
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
    },
  );
  testWidgets(
    'guards protected routes, loads the profile, logs in and returns to login on expiry',
    (tester) async {
      final adapter = TestAdapter(plannerAdapter());
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      final container = ProviderContainer(overrides: testOverrides(client));
      addTearDown(container.dispose);
      addTearDown(client.close);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PlannerApp(),
        ),
      );
      await tester.pumpAndSettle();

      // The authentication guard keeps every workbench route behind the login page.
      final router = container.read(appRouterProvider);
      router.go('/');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      router.go('/settings');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'student@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'Study4089');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle();

      // A finished profile also goes straight to the workbench.
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(find.text('开始计时'), findsOneWidget);

      await client.clearSession();
      await tester.pumpAndSettle();
      expect(find.text('登录不白学 · 学习执行台'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/login');
    },
  );

  testWidgets('bottom navigation and sidebar reach every workbench route', (
    tester,
  ) async {
    final adapter = TestAdapter(plannerAdapter());
    final client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    final container = ProviderContainer(overrides: testOverrides(client));
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

    final router = container.read(appRouterProvider);
    // Narrow layout: every workbench destination remains available.
    await tester.tap(find.widgetWithText(NavigationDestination, '事项'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/tasks');
    expect(find.text('事项管理'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '日历'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/calendar');
    expect(find.text('学习日历'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '进度'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/progress');
    expect(find.text('学习进度'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '调整'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/adjust');
    expect(find.byType(AdjustPlanPage), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/settings');
    expect(find.text('学习目标与规划'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, '访谈'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/interview');
    expect(find.text('继续访谈'), findsOneWidget);
    expect(find.text('重新访谈'), findsOneWidget);

    // Wide layout: the sidebar replaces the bottom bar on Web and Windows.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('学习执行台'), findsOneWidget);
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets(
    'registration shows verification fields and validates before sending',
    (tester) async {
      final adapter = TestAdapter(
        (request) async => jsonResponse({'retryAfter': 60}),
      );
      final client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: MemoryTokenStore(),
        dio: Dio()..httpClientAdapter = adapter,
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          identityStoreProvider.overrideWithValue(MemoryIdentityStore()),
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
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();
      expect(find.text('邮箱验证码'), findsOneWidget);
      expect(find.text('确认密码'), findsOneWidget);
      await tester.ensureVisible(find.text('注册并登录'));
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      expect(find.text('请输入有效的邮箱'), findsOneWidget);
      expect(adapter.requests, isEmpty);
    },
  );
}
