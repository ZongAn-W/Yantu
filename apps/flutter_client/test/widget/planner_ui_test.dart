import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/app.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/features/auth/application/auth_controller.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart'
    as day_ops;
import 'package:sjtu_study_planner_client/features/shell/app_shell.dart';
import 'package:sjtu_study_planner_client/router/app_router.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/http_adapter.dart';
import '../support/planner_fixture.dart';

/// The shared fixture with its block moved to today.
///
/// The committed fixture is pinned to 2026-10-16; the workbench only renders the
/// current Asia/Shanghai day, so tests that exercise the daily rows must move it.
PlannerData todayFixture() {
  final base = plannerFixture();
  return base.copyWith(
    blocks: [base.blocks.first.copyWith(date: shanghaiToday())],
    logs: const [],
  );
}

const _profile = {
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

/// Builds the app with a signed-in session and a plan served by the stub.
Future<ProviderContainer> signIn(
  WidgetTester tester, {
  required Respond respond,
  int? revision,
  DateTime Function()? timerNow,
  Duration Function()? monotonicNow,
  StudyTimerStore? timerStore,
  void Function(StudyTimer timer)? onTimerCreated,
}) async {
  final adapter = TestAdapter(respond);
  final client = ApiClient(
    config: const AppConfig(apiBaseUrl: 'http://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: Dio()..httpClientAdapter = adapter,
  );
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      identityStoreProvider.overrideWithValue(MemoryIdentityStore()),
      storageRepositoryProvider.overrideWithValue(MemoryStorageRepository()),
      syncRetryIntervalProvider.overrideWithValue(null),
      studyTimerProvider.overrideWith((ref) {
        final timer = StudyTimer(
          coordinator: ref.watch(plannerSyncProvider.notifier),
          store: timerStore ?? _MemoryStudyTimerStore(),
          now: timerNow,
          monotonicNow: monotonicNow,
          tickInterval: null,
        );
        // Mirror the production provider: sign-out and expiry persist the timer.
        final auth = ref.read(authControllerProvider.notifier);
        auth.addSessionEndHandler(timer.pauseForSessionEnd);
        ref.onDispose(
          () => auth.removeSessionEndHandler(timer.pauseForSessionEnd),
        );
        onTimerCreated?.call(timer);
        return timer;
      }),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const PlannerApp()),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextFormField).at(0),
    'student@example.com',
  );
  await tester.enterText(find.byType(TextFormField).at(1), 'Study4089');
  await tester.tap(find.widgetWithText(FilledButton, '登录'));
  await tester.pumpAndSettle();
  return container;
}

Respond plannerResponder({int? revision, bool today = false}) =>
    (request) async {
      if (request.path.endsWith('/api/auth/login')) {
        return jsonResponse({
          'user': testUser,
          'accessToken': 'access',
          'refreshToken': 'refresh',
          'expiresIn': 900,
        });
      }
      if (request.path.endsWith('/api/onboarding/profile')) {
        return jsonResponse({'profile': _profile});
      }
      if (request.path.endsWith('/api/planner/sync')) {
        final plan = today ? todayFixture() : plannerFixture();
        return jsonResponse({'data': plan.toJson(), 'revision': revision ?? 1});
      }
      return jsonResponse({'error': 'unexpected ${request.path}'}, 404);
    };

/// Finds the text field whose `InputDecoration` carries [label].
///
/// `find.byType(TextField).first` and label-ancestor lookups are both unsafe here:
/// the page behind a dialog also owns text fields and is mounted first, while the
/// decoration sits inside the field rather than above it in the widget tree.
Finder fieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
  description: 'TextField(labelText: $label)',
);

/// Pumps frames until [condition] holds.
///
/// A save goes through the coordinator's serialized write queue, so the plan changes
/// on a later microtask rather than during the tap.
Future<void> waitUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = '条件未在超时前满足',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail(reason);
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Finishes the background sync that a save starts.
///
/// `edit` schedules the upload without awaiting it, and `Dio` puts its timeout on the
/// fake clock. Awaiting the cycle while pumping frames lets it complete and leaves no
/// pending timer after the widget tree is disposed.
Future<void> drainSync(
  WidgetTester tester,
  PlannerCoordinator coordinator,
) async {
  final cycle = coordinator.sync();
  for (var turn = 0; turn < 40; turn++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (!coordinator.busy && !coordinator.pending) break;
  }
  await cycle;
  await tester.pump(const Duration(milliseconds: 250));
}

/// A stub server that keeps the plan it was pushed, like the real sync endpoint.
///
/// A stateless stub that always answers with the initial revision makes a correct
/// client look broken: after a successful upload the client's revision is ahead, so
/// the next pull legitimately replaces the local copy. This double mirrors the real
/// contract (store the pushed document, advance the revision) so tests can assert on
/// uploads.
class FakeSyncServer {
  FakeSyncServer({PlannerData? plan, this.revision = 1})
    : document = plan ?? todayFixture();

  PlannerData document;
  int revision;
  int pushCount = 0;

  /// When set, every push is refused once and another device writes first.
  bool conflictOnNextPush = false;

  Respond get respond => (request) async {
    if (request.path.endsWith('/api/auth/login')) {
      return jsonResponse({
        'user': testUser,
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'expiresIn': 900,
      });
    }
    if (request.path.endsWith('/api/onboarding/profile')) {
      return jsonResponse({'profile': _profile});
    }
    if (request.path.endsWith('/api/planner/sync')) {
      if (request.method == 'PUT') return _push(request);
      return jsonResponse({'data': document.toJson(), 'revision': revision});
    }
    return jsonResponse({'error': 'unexpected ${request.path}'}, 404);
  };

  ResponseBody _push(RequestOptions request) {
    final body = request.data as Map;
    if (conflictOnNextPush) {
      conflictOnNextPush = false;
      // Another device wrote first, and it changed the same field.
      revision++;
      document = document.copyWith(
        profile: document.profile.copyWith(
          targetSchool: '其他设备的目标院校',
          targetProgram: '其他设备的目标方向',
        ),
      );
      return jsonResponse({'conflict': true}, 409);
    }
    if (body['expectedRevision'] != revision) {
      return jsonResponse({'conflict': true}, 409);
    }
    pushCount++;
    document = PlannerData.fromJson(JsonMap.from(body['data'] as Map));
    revision++;
    return jsonResponse({'data': document.toJson(), 'revision': revision});
  }
}

void main() {
  testWidgets('archived items stay visible in the course directory', (
    tester,
  ) async {
    final base = todayFixture();
    final server = FakeSyncServer(
      plan: base.copyWith(
        tasks: [
          base.tasks.single.copyWith(
            title: '旧规划归档事项',
            status: TaskStatus.archived,
            earliestDate: addDate(shanghaiToday(), 1),
          ),
        ],
      ),
    );
    final container = await signIn(tester, respond: server.respond);
    container.read(appRouterProvider).go('/tasks');
    await tester.pumpAndSettle();
    expect(find.text('旧规划归档事项'), findsOneWidget);

    await tester.tap(find.byTooltip('编辑或删除事项'));
    await tester.pumpAndSettle();
    expect(find.text('编辑事项'), findsOneWidget);
    expect(find.text('删除事项'), findsOneWidget);
  });

  testWidgets('the login form validates before sending anything', (
    tester,
  ) async {
    final adapter = TestAdapter(plannerResponder());
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

    // Empty submit is refused by the form, not by the server.
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的邮箱'), findsOneWidget);
    expect(adapter.requests, isEmpty);

    // A malformed address is refused too.
    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'Study4089');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的邮箱'), findsOneWidget);
    expect(adapter.requests, isEmpty);

    // Registration requires both password fields to agree.
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '小明');
    await tester.enterText(fields.at(1), 'student@example.com');
    await tester.enterText(fields.at(2), '123456');
    await tester.enterText(fields.at(3), 'Study4089');
    await tester.enterText(fields.at(4), 'Different9');
    await tester.ensureVisible(find.text('注册并登录'));
    await tester.tap(find.text('注册并登录'));
    await tester.pumpAndSettle();
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('a server error is shown with the server message', (
    tester,
  ) async {
    final adapter = TestAdapter(
      (request) async => jsonResponse({'error': '邮箱或密码错误'}, 401),
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
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'student@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Wrong1234');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(find.text('邮箱或密码错误'), findsOneWidget);
    // The form stays usable for a retry.
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
  });

  testWidgets('a failed plan load offers a retry that reaches the data', (
    tester,
  ) async {
    var syncCalls = 0;
    final container = await signIn(
      tester,
      respond: (request) async {
        if (request.path.endsWith('/api/auth/login')) {
          return jsonResponse({
            'user': testUser,
            'accessToken': 'access',
            'refreshToken': 'refresh',
            'expiresIn': 900,
          });
        }
        if (request.path.endsWith('/api/onboarding/profile')) {
          return jsonResponse({'profile': _profile});
        }
        if (request.path.endsWith('/api/planner/sync')) {
          syncCalls++;
          // The first pull fails, the retry succeeds.
          if (syncCalls == 1) {
            return jsonResponse({'error': '服务端暂时不可用'}, 503);
          }
          return jsonResponse({'data': todayFixture().toJson(), 'revision': 3});
        }
        return jsonResponse({'error': 'unexpected'}, 404);
      },
    );

    final coordinator = container.read(plannerSyncProvider);
    expect(coordinator.status, SyncStatus.error);
    // The failure state explains itself and offers a retry.
    expect(find.text('重试加载'), findsOneWidget);
    expect(find.textContaining('服务端暂时不可用'), findsWidgets);

    await tester.tap(find.text('重试加载'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(coordinator.status, SyncStatus.connected);
    expect(find.byKey(const Key('dashboard-quick-start')), findsOneWidget);
    expect(find.text('基础一轮'), findsWidgets);
  });

  testWidgets('the new-task form rejects bad input before editing the plan', (
    tester,
  ) async {
    final server = FakeSyncServer();
    final container = await signIn(tester, respond: server.respond);
    final coordinator = container.read(plannerSyncProvider);
    final tasksBefore = coordinator.data!.tasks.length;
    final router = container.read(appRouterProvider);
    router.go('/tasks');
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final addButton = find.byKey(const Key('course-add-calculus'));
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    // The dialog animates in; a bounded settle avoids depending on its exact frames.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('新建事项'), findsOneWidget);
    expect(find.byKey(const Key('task-save-button')), findsOneWidget);

    // An empty title is refused.
    await tester.tap(find.byKey(const Key('task-save-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('请填写事项名称'), findsOneWidget);
    expect(coordinator.data!.tasks.length, tasksBefore);

    // A valid title saves and the plan grows by exactly one task.
    await tester.enterText(
      find.byKey(const Key('task-title-field')),
      '阶段七验收事项',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('task-save-button')));
    await waitUntil(
      tester,
      () => coordinator.data!.tasks.length == tasksBefore + 1,
      reason: '保存事项后计划没有新增事项',
    );
    await drainSync(tester, coordinator);
    // The new task survives the sync cycle locally and reaches the server.
    expect(
      coordinator.data!.tasks.any((task) => task.title == '阶段七验收事项'),
      isTrue,
      reason: '同步后本机计划不应丢失新增事项',
    );
    expect(server.pushCount, greaterThan(0), reason: '新增事项应上传到服务端');
    expect(
      server.document.tasks.any((task) => task.title == '阶段七验收事项'),
      isTrue,
      reason: '服务端应保存新增事项',
    );
  });

  testWidgets('the new-course dialog creates an empty folder and syncs it', (
    tester,
  ) async {
    final server = FakeSyncServer();
    final container = await signIn(tester, respond: server.respond);
    final coordinator = container.read(plannerSyncProvider);
    final subjectsBefore = coordinator.data!.subjects.length;
    container.read(appRouterProvider).go('/tasks');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('new-course-button')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('新建课程'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('course-name-field')),
      '概率论与数理统计',
    );
    await tester.tap(find.byKey(const Key('course-save-button')));
    await waitUntil(
      tester,
      () => coordinator.data!.subjects.length == subjectsBefore + 1,
      reason: '创建课程后计划没有新增课程',
    );
    await drainSync(tester, coordinator);
    final created = coordinator.data!.subjects.last;
    expect(created.name, '概率论与数理统计');
    expect(
      coordinator.data!.tasks.where((task) => task.subjectId == created.id),
      isEmpty,
    );
    expect(server.pushCount, greaterThan(0), reason: '新增课程应上传到服务端');
    expect(
      server.document.subjects.any((subject) => subject.name == '概率论与数理统计'),
      isTrue,
    );
  });

  testWidgets(
    'the task directory is name-only with independent desktop columns',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = todayFixture();
      final source = base.tasks.single;
      final english = base.subjects.first.copyWith(
        id: 'english',
        name: '英语',
        color: '#1f7a5a',
      );
      final dataStructures = base.subjects.first.copyWith(
        id: 'data-structure',
        name: '数据结构',
        color: '#c2761f',
      );
      final server = FakeSyncServer(
        plan: base.copyWith(
          subjects: [base.subjects.first, english, dataStructures],
          tasks: [
            source,
            source.copyWith(
              id: 'task-english',
              subjectId: english.id,
              title: '真题精读',
            ),
            source.copyWith(
              id: 'task-ds',
              subjectId: dataStructures.id,
              title: '树与二叉树',
            ),
          ],
        ),
      );
      final container = await signIn(tester, respond: server.respond);
      container.read(appRouterProvider).go('/tasks');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tasks-two-columns')), findsOneWidget);
      expect(find.byKey(const Key('tasks-single-column')), findsNothing);
      expect(find.text('真题精读'), findsOneWidget);
      expect(find.text(source.description!), findsNothing);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tasks-single-column')), findsOneWidget);
      expect(find.byKey(const Key('tasks-two-columns')), findsNothing);
      expect(tester.takeException(), isNull, reason: '手机宽度下目录不能溢出');
    },
  );

  testWidgets('search and course filter narrow the directory', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final base = todayFixture();
    final source = base.tasks.single;
    final english = base.subjects.first.copyWith(
      id: 'english',
      name: '英语',
      color: '#1f7a5a',
    );
    final server = FakeSyncServer(
      plan: base.copyWith(
        subjects: [base.subjects.first, english],
        tasks: [
          source,
          source.copyWith(
            id: 'task-english',
            subjectId: english.id,
            title: '真题精读',
          ),
        ],
      ),
    );
    final container = await signIn(tester, respond: server.respond);
    container.read(appRouterProvider).go('/tasks');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tasks-search-field')), '真题');
    await tester.pumpAndSettle();
    expect(find.text('真题精读'), findsOneWidget);
    expect(find.text('基础一轮'), findsNothing);

    await tester.tap(find.byKey(const Key('clear-search-button')));
    await tester.pumpAndSettle();
    expect(find.text('基础一轮'), findsOneWidget);

    await tester.tap(find.byKey(const Key('course-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('英语').last);
    await tester.pumpAndSettle();
    expect(find.text('真题精读'), findsOneWidget);
    expect(find.text('基础一轮'), findsNothing);
  });

  testWidgets('study time comes from the inline timer and cannot be edited', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final now = DateTime.now();
    final server = FakeSyncServer();
    final container = await signIn(
      tester,
      respond: server.respond,
      timerNow: () => now.add(elapsed),
      monotonicNow: () => elapsed,
    );
    final coordinator = container.read(plannerSyncProvider);
    final taskId = coordinator.data!.tasks.first.id;
    final date = coordinator.data!.blocks.first.date;
    final action = find.byKey(Key('study-timer-action-$taskId-$date'));
    final clock = find.byKey(Key('study-clock-$taskId-$date'));

    expect(find.text('今日已完成'), findsNothing);
    expect(find.text('记录用时'), findsNothing);
    expect(find.text('修改用时'), findsNothing);
    expect(tester.widget<Text>(clock).data, '00:00:00');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('暂停计时'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    elapsed = const Duration(minutes: 2, seconds: 7);
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 100));
    await drainSync(tester, coordinator);
    expect(tester.widget<Text>(clock).data, '00:02:07');
    expect(day_ops.taskDayMinutes(server.document, taskId, date), 2);

    container.read(appRouterProvider).go('/calendar');
    await tester.pumpAndSettle();
    expect(find.text('记录用时'), findsNothing);
    expect(find.text('修改用时'), findsNothing);
    expect(tester.widget<Text>(clock).data, '00:02:07');

    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 100));
    elapsed += const Duration(seconds: 30);
    await tester.tap(action);
    await tester.pump(const Duration(milliseconds: 100));
    await drainSync(tester, coordinator);
    expect(tester.widget<Text>(clock).data, '00:02:37');
    expect(day_ops.taskDayMinutes(server.document, taskId, date), 2);
  });

  testWidgets('the shell is responsive and reports sync state', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await signIn(
      tester,
      respond: plannerResponder(revision: 9, today: true),
    );

    // Desktop shows the sidebar and the exam card.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('学习执行台'), findsOneWidget);
    expect(find.textContaining('2027-12-25'), findsWidgets);
    expect(container.read(plannerSyncProvider).metadata.revision, 9);

    // Narrow: bottom navigation, no overflow, all five destinations reachable.
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final label in const ['今日', '日历', '事项', '进度', '设置']) {
      expect(
        find.widgetWithText(NavigationDestination, label),
        findsOneWidget,
        reason: '底部导航缺少「$label」',
      );
    }

    // Very narrow: the layout still renders without an overflow exception.
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a blocked local store stops editing and explains recovery', (
    tester,
  ) async {
    final storage = MemoryStorageRepository();
    await storage.save(
      'sjtu-study-planner:items-v2:http%3A%2F%2Fapi.test:cloud:user-1',
      plannerFixture(),
      const StorageMetadata(),
    );
    final adapter = TestAdapter(plannerResponder());
    final client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        identityStoreProvider.overrideWithValue(MemoryIdentityStore()),
        storageRepositoryProvider.overrideWithValue(_BlockedStorage()),
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

    final coordinator = container.read(plannerSyncProvider);
    expect(coordinator.blocked, isTrue);
    expect(
      find.textContaining('本地数据读取失败'),
      findsWidgets,
      reason: '阻断状态必须向用户说明',
    );
    expect(find.text('重新读取本机数据'), findsOneWidget);
  });

  testWidgets(
    'a failed timer checkpoint keeps the account dialog open with an error',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = _FailingTimerStore();
      final server = FakeSyncServer();
      final container = await signIn(
        tester,
        respond: server.respond,
        timerStore: store,
      );
      final coordinator = container.read(plannerSyncProvider);
      final taskId = coordinator.data!.tasks.first.id;
      final date = coordinator.data!.blocks.first.date;
      final action = find.byKey(Key('study-timer-action-$taskId-$date'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('暂停计时'), findsOneWidget);

      store.fail = true;
      await tester.tap(find.byTooltip('账号与同步'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
      await tester.pumpAndSettle();
      expect(
        find.byType(AccountDialog),
        findsOneWidget,
        reason: '计时保存失败时不能伪装成已成功退出',
      );
      expect(find.textContaining('无法保存本机计时记录'), findsOneWidget);
      expect(container.read(authControllerProvider).user, isNotNull);
      expect(
        container.read(authControllerProvider).loading,
        isFalse,
        reason: '失败后按钮应恢复可用以便重试',
      );

      store.fail = false;
      await tester.tap(find.widgetWithText(FilledButton, '退出登录'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountDialog), findsNothing);
      expect(container.read(authControllerProvider).user, isNull);
    },
  );

  testWidgets('the account dialog and sign-out controls fit a phone layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await signIn(tester, respond: plannerResponder(revision: 1, today: true));

    await tester.tap(find.byTooltip('账号与同步'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountDialog), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '手机宽度下账号对话框不能溢出');
    final signOut = find.widgetWithText(FilledButton, '退出登录');
    expect(signOut, findsOneWidget);
    expect(tester.widget<FilledButton>(signOut).onPressed, isNotNull);

    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the delete confirmation keeps the item', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = FakeSyncServer(plan: todayFixture());
    final container = await signIn(tester, respond: server.respond);
    container.read(appRouterProvider).go('/tasks');
    await tester.pumpAndSettle();
    expect(find.text('基础一轮'), findsOneWidget);

    final coordinator = container.read(plannerSyncProvider);
    final taskId = coordinator.data!.tasks.single.id;
    final menu = find.byKey(Key('task-menu-$taskId'));
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除事项').last);
    await tester.pumpAndSettle();
    expect(find.text('删除事项'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(coordinator.data!.tasks, hasLength(1), reason: '取消删除不改变计划');
    expect(server.pushCount, 0, reason: '取消删除不产生同步写入');
  });

  testWidgets(
    'deleting an item other items depend on is refused with a reason',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = todayFixture();
      final first = base.tasks.single;
      final dependent = first.copyWith(
        id: 'task-dependent',
        title: '依赖演练',
        deadline: '2027-06-30',
        earliestDate: '2026-10-01',
        planning: <String, dynamic>{
          'dependencies': [
            {'task_id': first.id, 'mode': 'planned'},
          ],
        },
      );
      final server = FakeSyncServer(
        plan: base.copyWith(
          tasks: [first, dependent],
          blocks: [
            ...base.blocks,
            base.blocks.single.copyWith(
              id: 'block-dependent',
              taskId: dependent.id,
            ),
          ],
          planning: <String, dynamic>{
            'version': 1,
            'route': [
              {
                'id': 'stage',
                'title': '阶段',
                'item_ids': [first.id, dependent.id],
                'outcome': '完成',
                'check': '自检',
              },
            ],
            'quality': <String, dynamic>{'status': 'pass'},
            'needs_review': false,
          },
        ),
      );
      final container = await signIn(tester, respond: server.respond);
      container.read(appRouterProvider).go('/tasks');
      await tester.pumpAndSettle();
      expect(find.text('依赖演练'), findsOneWidget);

      final coordinator = container.read(plannerSyncProvider);
      final menu = find.byKey(Key('task-menu-${first.id}'));
      await tester.ensureVisible(menu);
      await tester.pumpAndSettle();
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除事项').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining('前置'),
        findsOneWidget,
        reason: '有依赖时必须明确阻止并说明原因',
      );
      expect(coordinator.data!.tasks, hasLength(2));
      expect(server.pushCount, 0);
      expect(
        (coordinator.data!.planning!['route'] as List).single['item_ids'],
        [first.id, dependent.id],
      );
    },
  );
}

class _MemoryStudyTimerStore implements StudyTimerStore {
  final _values = <String, JsonMap>{};

  @override
  Future<JsonMap?> load(String key) async => _values[key];

  @override
  Future<void> save(String key, JsonMap value) async => _values[key] = value;
}

/// A timer store that can fail on demand, to prove sign-out is not faked.
class _FailingTimerStore implements StudyTimerStore {
  final _values = <String, JsonMap>{};
  bool fail = false;

  @override
  Future<JsonMap?> load(String key) async => _values[key];

  @override
  Future<void> save(String key, JsonMap value) async {
    if (fail) throw StateError('timer disk unavailable');
    _values[key] = value;
  }
}

/// A storage repository whose main record cannot be decoded.
class _BlockedStorage implements StorageRepository {
  static const _error = '主数据和备份都无法读取，已停止编辑和同步：测试注入';

  @override
  Future<StorageSnapshot> load(String userKey) async => const StorageSnapshot(
    data: null,
    metadata: StorageMetadata(),
    error: _error,
  );

  @override
  Future<void> save(
    String userKey,
    PlannerData data,
    StorageMetadata metadata, {
    bool recovery = false,
  }) async => throw StateError(_error);

  @override
  Future<String?> exportJson(PlannerData data) async => null;

  @override
  Future<PlannerData?> importJson() async => null;

  @override
  Future<void> restore(String userKey, PlannerData data) async {}

  @override
  Future<void> markPending(String userKey, bool pending) async {}

  @override
  Future<StorageSnapshot> recoverFromBackup(String userKey) async =>
      const StorageSnapshot(
        data: null,
        metadata: StorageMetadata(),
        error: _error,
      );
}
