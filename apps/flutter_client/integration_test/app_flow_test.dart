import 'dart:convert' as convert;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:sjtu_study_planner_client/app.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/storage/database_factory_io.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart'
    as day_ops;
import 'package:sjtu_study_planner_client/router/app_router.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import 'support/fake_server.dart';
import 'support/plan.dart';

/// End-to-end checks against a real HTTP socket and a real on-disk database.
///
/// Everything except the server and the OS file picker is production code: the Dio
/// client, the auth guard, the router, the sync coordinator, Sembast storage with
/// file backup and the widgets. The stub server never reaches the production API or
/// database.
/// Taps one workbench destination in whichever navigation the shell is showing.
///
/// The shell renders a sidebar above 900 logical pixels and a bottom bar below it, so
/// the same assertion has to work in both layouts.
Future<void> goto(WidgetTester tester, String label) async {
  final bottom = find.widgetWithText(NavigationDestination, label);
  final rail = find.widgetWithText(NavigationRailDestination, label);
  final finder = bottom.evaluate().isNotEmpty ? bottom : rail;
  expect(finder, findsWidgets, reason: '找不到导航目标「$label」，当前布局既没有底部导航也没有侧栏');
  await tester.tap(finder.first);
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

/// Opens a workbench route through the real router.
///
/// Navigation affordances are covered by the layout test; the data-consistency
/// checks below drive the routes directly so they stay independent of the shell.
Future<void> openRoute(WidgetTester tester, Harness app, String path) async {
  app.router.go(path);
  await tester.pumpAndSettle(const Duration(seconds: 5));
}

/// Pumps frames until [condition] holds.
///
/// Real network and file I/O complete on their own schedule, so `pumpAndSettle`
/// alone can observe a coordinator that has not finished its first cycle yet.
Future<void> waitFor(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  String reason = '条件未在超时前满足',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late FakePlannerServer server;
  late FakeFileTransfer transfer;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('planner-integration-');
    server = await FakePlannerServer.start();
    transfer = FakeFileTransfer()
      ..exportPath = path.join(temp.path, 'export.json');
  });

  tearDown(() async {
    await server.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// One app instance with its own database file, so a restart can reopen it.
  Harness harness({
    TokenStore? tokenStore,
    IdentityStore? identity,
    bool bearer = false,
  }) => Harness(
    temp: temp,
    server: server,
    transfer: transfer,
    tokenStore: tokenStore,
    identity: identity,
    bearer: bearer,
  );

  Future<void> login(WidgetTester tester, Harness app) async {
    await app.pump(tester);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'student@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Study4089');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  testWidgets('login loads the cloud plan and every page shows the same data', (
    tester,
  ) async {
    server.document = seededPlan();
    server.revision = 4;
    final app = harness();
    addTearDown(app.dispose);
    await login(tester, app);

    expect(app.router.state.uri.path, '/');
    expect(find.text('今日学习'), findsOneWidget);
    expect(find.text('高数'), findsWidgets);
    expect(find.text('基础一轮'), findsWidgets);
    // The seeded plan has one 90 minute block and one 60 minute block today.
    expect(find.text('2小时30分'), findsWidgets);
    expect(app.coordinator.data!.tasks, hasLength(2));
    expect(app.coordinator.metadata.revision, 4);
    expect(app.coordinator.pending, isFalse);

    // 事项目录已合并进今日页下方；旧的 /tasks 链接重定向到今日。
    await openRoute(tester, app, '/tasks');
    expect(app.router.state.uri.path, '/');
    expect(find.text('全部事项'), findsOneWidget);
    expect(find.text('基础一轮'), findsWidgets);
    expect(find.text('真题精读'), findsWidgets);
    expect(find.text('高数'), findsWidgets);

    // 日历 page: the read-only merged day/week/month windows.
    await openRoute(tester, app, '/calendar');
    expect(app.router.state.uri.path, '/calendar');
    expect(find.byKey(const ValueKey('calendar-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-day-chart')), findsNWidgets(2));

    // 进度 has been merged into 日历; the old link redirects to the calendar,
    // which keeps only the compact status strip of the former progress page.
    await openRoute(tester, app, '/progress');
    expect(app.router.state.uri.path, '/calendar');
    expect(find.textContaining('累计实际学习'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-learning-overview')),
      findsNothing,
    );
  });

  testWidgets('an offline edit survives a restart and uploads when back online', (
    tester,
  ) async {
    server.document = seededPlan();
    server.revision = 7;
    // Native platforms use bearer tokens, so a stored refresh token is what lets a
    // restart restore the session without reaching the API.
    final tokens = MemoryTokenStore();
    final identity = MemoryIdentityStore();
    final first = harness(tokenStore: tokens, identity: identity, bearer: true);
    await login(tester, first);
    debugPrint('Offline recovery: signed in');
    expect(first.coordinator.metadata.revision, 7);

    // The API stops listening: the edit is recorded locally only.
    await server.goOffline();
    debugPrint('Offline recovery: API stopped');
    final taskId = first.coordinator.data!.tasks.first.id;
    await first.session.recordDayMinutes(taskId, shanghaiToday(), 105);
    await first.coordinator.sync();
    debugPrint('Offline recovery: local edit saved');
    expect(first.coordinator.status, SyncStatus.offline);
    expect(first.coordinator.metadata.pending, isTrue);
    expect(
      day_ops.taskDayMinutes(first.coordinator.data!, taskId, shanghaiToday()),
      105,
    );
    expect(server.pushCount, 0);
    final pendingRevision = first.coordinator.metadata.revision;
    // The session survives, so a restart can reuse it without the API.
    expect((await tokens.read())?.refreshToken, isNotNull);
    await first.dispose();
    debugPrint('Offline recovery: first app closed');

    // Restart against the same database file while the API is still down. The stored
    // refresh token lets the session restore, so the queued upload is visible without
    // ever reaching the network.
    final second = harness(
      tokenStore: tokens,
      identity: identity,
      bearer: true,
    );
    addTearDown(second.dispose);
    await second.pump(tester);
    debugPrint('Offline recovery: second app started');
    await waitFor(
      tester,
      () => second.coordinator.status == SyncStatus.offline,
      reason: '离线重启后协调器未进入离线状态',
    );
    expect(second.router.state.uri.path, '/');
    expect(find.text('今日学习'), findsOneWidget);
    await openRoute(tester, second, '/tasks');
    expect(find.text('全部事项'), findsOneWidget);
    await openRoute(tester, second, '/');
    debugPrint('Offline recovery: workbench routes available');
    expect(second.coordinator.metadata.pending, isTrue);
    expect(second.coordinator.metadata.revision, pendingRevision);
    expect(
      day_ops.taskDayMinutes(second.coordinator.data!, taskId, shanghaiToday()),
      105,
    );
    expect(server.pushCount, 0);

    // The API returns on the same address: the queued change is uploaded.
    await server.goOnline();
    debugPrint('Offline recovery: API restarted');
    await second.coordinator.sync();
    await waitFor(
      tester,
      () => second.coordinator.status == SyncStatus.connected,
      reason: '恢复联网后未回到已同步状态',
    );
    expect(second.coordinator.pending, isFalse);
    expect(server.pushCount, greaterThan(0));
    expect(
      day_ops.taskDayMinutes(server.document!, taskId, shanghaiToday()),
      105,
    );
  });

  testWidgets(
    'a revision conflict pauses and an explicit choice merges both sides',
    (tester) async {
      server.document = seededPlan();
      server.revision = 3;
      final app = harness();
      addTearDown(app.dispose);
      await login(tester, app);

      // Both devices change the same profile field, so the merge cannot be
      // resolved silently; the other device also changes an independent field.
      await app.session.edit(
        (data) => data.copyWith(
          profile: data.profile.copyWith(targetProgram: '本机目标方向'),
        ),
      );
      server.conflictOnNextPush = true;
      await app.coordinator.sync();
      await app.coordinator.sync();

      expect(app.coordinator.status, SyncStatus.conflict);
      expect(app.coordinator.conflicts, isNotEmpty);
      // Nothing is silently discarded while the conflict is unresolved.
      expect(app.coordinator.data!.profile.targetProgram, '本机目标方向');
      expect(server.document!.profile.targetProgram, '其他设备的目标方向');

      await app.coordinator.resolve(useLocal: true);
      await app.coordinator.sync();
      expect(app.coordinator.conflicts, isEmpty);
      expect(app.coordinator.pending, isFalse);
      // The independent remote field survives; the clashing field takes the choice.
      expect(server.document!.profile.targetProgram, '本机目标方向');
      expect(server.document!.profile.targetSchool, '其他设备的目标院校');
    },
  );

  testWidgets(
    'recording minutes updates today, progress and the server together',
    (tester) async {
      server.document = seededPlan();
      server.revision = 1;
      final app = harness();
      addTearDown(app.dispose);
      await login(tester, app);

      final taskId = app.coordinator.data!.tasks.first.id;
      final before = day_ops.taskDayMinutes(
        app.coordinator.data!,
        taskId,
        shanghaiToday(),
      );
      await app.session.recordDayMinutes(taskId, shanghaiToday(), 150);
      await app.coordinator.sync();
      await tester.pumpAndSettle();

      // Today reflects the new value.
      await openRoute(tester, app, '/');
      expect(find.textContaining('2小时30分'), findsWidgets);

      // The merged calendar derives the same totals from the same logs.
      await openRoute(tester, app, '/progress');
      expect(app.router.state.uri.path, '/calendar');
      expect(find.textContaining('累计实际学习'), findsOneWidget);

      // The server received exactly the corrected total, not a delta.
      expect(
        day_ops.taskDayMinutes(server.document!, taskId, shanghaiToday()),
        150,
      );
      expect(
        day_ops.taskDayMinutes(server.document!, taskId, shanghaiToday()),
        greaterThan(before),
      );
    },
  );

  testWidgets('the layout switches between the sidebar and the bottom bar', (
    tester,
  ) async {
    server.document = seededPlan();
    final app = harness();
    addTearDown(app.dispose);

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await login(tester, app);

    // Desktop: sidebar navigation, no bottom bar.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('学习执行台'), findsOneWidget);
    expect(find.text('今日'), findsOneWidget);

    // Phone: bottom navigation, and no horizontal overflow.
    tester.view.physicalSize = const Size(414, 896);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    final overflow = tester.takeException();
    expect(overflow, isNull);
    await goto(tester, '设置');
    expect(find.text('学习目标与规划'), findsOneWidget);
  });

  testWidgets('importing a JSON export replaces the plan and re-syncs', (
    tester,
  ) async {
    server.document = seededPlan();
    final app = harness();
    addTearDown(app.dispose);
    await login(tester, app);

    // Export the current plan through the production serializer + file write.
    await app.session.exportJson();
    expect(await File(transfer.exportPath!).exists(), isTrue);
    final exported = PlannerData.fromJson(
      await _readJson(transfer.exportPath!),
    );
    expect(exported.profile.userId, app.coordinator.data!.profile.userId);

    // Modify the file, then import it back on this account.
    final modified = exported.copyWith(
      tasks: [
        exported.tasks.first.copyWith(title: '导入后的事项'),
        exported.tasks.last,
      ],
    );
    await File(
      transfer.exportPath!,
    ).writeAsString(modified.toJsonString(), flush: true);
    await app.session.importJson();
    await app.coordinator.sync();
    await tester.pumpAndSettle();

    expect(app.coordinator.data!.tasks.first.title, '导入后的事项');
    expect(server.document!.tasks.first.title, '导入后的事项');
    expect(app.coordinator.pending, isFalse);

    // The restored plan is visible in the 全部事项 directory after the import.
    await openRoute(tester, app, '/tasks');
    expect(find.text('全部事项'), findsOneWidget);
    expect(find.text('导入后的事项'), findsWidgets);
  });
}

Future<JsonMap> _readJson(String file) async {
  final raw = await File(file).readAsString();
  return JsonMap.from(convert.jsonDecode(raw) as Map);
}

/// A single app instance with its own database file inside the temp directory.
///
/// `tokenStore` and `identity` are injected so two instances can share one session,
/// which is what "restart the app" means for the offline-recovery test.
class Harness {
  Harness({
    required this.temp,
    required this.server,
    required this.transfer,
    TokenStore? tokenStore,
    IdentityStore? identity,
    this.bearer = false,
  }) : tokenStore = tokenStore ?? MemoryTokenStore(),
       identity = identity ?? MemoryIdentityStore();

  final Directory temp;
  final FakePlannerServer server;
  final FakeFileTransfer transfer;
  final TokenStore tokenStore;
  final IdentityStore identity;
  final bool bearer;

  late final LocalDatabase database = LocalDatabase(
    open: () => openPlannerDatabase(path.join(temp.path, 'planner.db')),
  );
  late final StorageRepository storage = SembastStorageRepository(
    database: database,
    transfer: transfer,
  );
  late final ProviderContainer container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig(apiBaseUrl: server.baseUrl),
      ),
      storageRepositoryProvider.overrideWithValue(storage),
      identityStoreProvider.overrideWithValue(identity),
      // The real store persists into the OS keychain, so a previous run would make
      // the app skip the login page. `SecureTokenStore` has its own unit tests; the
      // integration run needs a clean, per-test session.
      tokenStoreProvider.overrideWithValue(tokenStore),
      if (bearer)
        apiClientProvider.overrideWith((ref) {
          final client = ApiClient(
            config: ref.watch(appConfigProvider),
            tokenStore: ref.watch(tokenStoreProvider),
            usesBearer: true,
          );
          ref.onDispose(client.close);
          return client;
        }),
      // The periodic retry is production behaviour, but a shorter interval keeps
      // the integration run quick; the manual `sync()` calls remain explicit.
      syncRetryIntervalProvider.overrideWithValue(const Duration(seconds: 2)),
    ],
  );

  PlannerCoordinator get coordinator => container.read(plannerSyncProvider);
  PlannerSession get session => container.read(plannerSessionProvider);
  GoRouter get router => container.read(appRouterProvider);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PlannerApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  }

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}
