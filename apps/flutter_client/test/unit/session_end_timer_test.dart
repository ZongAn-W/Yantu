import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/auth/application/auth_controller.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/async_wait.dart';
import '../support/http_adapter.dart';
import '../support/planner_fixture.dart';

/// 退出账号、会话失效与普通重启必须有不同的计时边界。
void main() {
  const date = '2026-10-17';
  final fixture = plannerFixture();

  late _Clock clock;
  late _TimerStore timerStore;
  late MemoryStorageRepository plannerStore;
  late _RemoteApi remote;
  late PlannerCoordinator coordinator;
  late StudyTimer timer;
  late MemoryIdentityStore identity;
  late MemoryTokenStore tokenStore;
  late ApiClient client;
  late ProviderContainer container;
  late int revokeCalls;
  late bool networkDown;
  var sequence = 0;

  AuthController auth() => container.read(authControllerProvider.notifier);
  AuthState authState() => container.read(authControllerProvider);

  PlannerData plan() => fixture.copyWith(
    logs: [],
    blocks: [fixture.blocks.single.copyWith(date: date, durationMinutes: 120)],
  );

  StudyTimer createTimer() => StudyTimer(
    coordinator: coordinator,
    store: timerStore,
    now: () => clock.wall,
    monotonicNow: () => clock.monotonic,
    nextId: () => 'timer-${sequence++}',
    tickInterval: null,
  );

  setUp(() async {
    clock = _Clock();
    timerStore = _TimerStore();
    plannerStore = MemoryStorageRepository();
    remote = _RemoteApi(plan());
    revokeCalls = 0;
    networkDown = false;
    identity = MemoryIdentityStore();
    await identity.save(testUser);
    tokenStore = MemoryTokenStore();
    await tokenStore.write(
      TokenPair(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final adapter = TestAdapter((request) async {
      if (request.path.endsWith('/api/me')) {
        return jsonResponse({'user': testUser});
      }
      if (request.path.endsWith('/api/auth/token/revoke')) {
        revokeCalls++;
        if (networkDown) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
          );
        }
        return jsonResponse({});
      }
      return jsonResponse({'error': 'unexpected ${request.path}'}, 404);
    });
    client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: tokenStore,
      usesBearer: true,
      dio: Dio()..httpClientAdapter = adapter,
    );
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        identityStoreProvider.overrideWithValue(identity),
      ],
    );
    container.read(authControllerProvider);
    await waitUntil(
      () => authState().user != null,
      reason: '会话没有在超时前恢复',
    );

    coordinator = PlannerCoordinator(
      userId: testUser['id'] as String,
      scope: 'session-end-tests',
      storage: plannerStore,
      api: remote,
      retryInterval: null,
    )..data = plan();
    coordinator.ready = true;
    timer = createTimer();
    auth().addSessionEndHandler(timer.pauseForSessionEnd);
    await timer.initialize();
  });

  tearDown(() {
    timer.dispose();
    coordinator.dispose();
    container.dispose();
    client.close();
  });

  String taskId() => coordinator.data!.tasks.single.id;
  int minutesFor(String day) => taskDayMinutes(coordinator.data!, taskId(), day);

  test(
    'sign-out persists a paused timer and an overnight sign-in does not bill the gap',
    () async {
      await timer.start(taskId(), date);
      clock.advance(const Duration(minutes: 2));
      await auth().signOut();

      expect(authState().user, isNull);
      expect(timer.activeTaskId, isNull);
      expect((await timerStore.load(timer.storageKey))!['active'], isNull);
      expect(await tokenStore.read(), isNull);
      expect(await identity.load(), isNull);
      expect(minutesFor(date), 2);

      clock.advance(const Duration(hours: 9));
      timer.dispose();
      timer = createTimer();
      await timer.initialize();
      expect(timer.activeTaskId, isNull);
      expect(timer.elapsedFor(taskId(), date), const Duration(minutes: 2));
      expect(minutesFor(date), 2);
    },
  );

  test('an offline sign-out still signs out after the timer is saved', () async {
    networkDown = true;
    await timer.start(taskId(), date);
    clock.advance(const Duration(minutes: 4));
    await auth().signOut();

    expect(revokeCalls, 1);
    expect(authState().user, isNull);
    expect(timer.activeTaskId, isNull);
    expect(await tokenStore.read(), isNull);
    expect(minutesFor(date), 4);
  });

  test('a failed timer save aborts sign-out and keeps the session', () async {
    await timer.start(taskId(), date);
    clock.advance(const Duration(minutes: 3));
    timerStore.fail = true;

    await auth().signOut();

    expect(authState().user, isNotNull);
    expect(authState().error, contains('无法保存本机计时记录'));
    expect(await tokenStore.read(), isNotNull);
    expect(timer.activeTaskId, isNotNull);
    expect((await timerStore.load(timer.storageKey))!['active'], isNotNull);

    timerStore.fail = false;
    await auth().signOut();
    expect(authState().user, isNull);
    expect(timer.activeTaskId, isNull);
    expect(minutesFor(date), 3);
  });

  test('repeated sign-out clicks settle once', () async {
    await timer.start(taskId(), date);
    clock.advance(const Duration(minutes: 1));

    await Future.wait([auth().signOut(), auth().signOut()]);

    expect(revokeCalls, 1);
    expect(authState().user, isNull);
    expect(timer.activeTaskId, isNull);
    expect(await tokenStore.read(), isNull);
  });

  test('an expired session stops the timer at the expiry moment', () async {
    await timer.start(taskId(), date);
    clock.advance(const Duration(minutes: 3));

    await auth().expire();

    expect(authState().user, isNull);
    expect(timer.activeTaskId, isNull);
    expect((await timerStore.load(timer.storageKey))!['active'], isNull);
    expect(await identity.load(), isNull);

    clock.advance(const Duration(hours: 5));
    timer.dispose();
    timer = createTimer();
    await timer.initialize();
    expect(timer.elapsedFor(taskId(), date), const Duration(minutes: 3));
    expect(minutesFor(date), 3);
  });

  test('an expiry whose checkpoint cannot be stored reports the error', () async {
    await timer.start(taskId(), date);
    clock.advance(const Duration(minutes: 3));
    timerStore.fail = true;

    await auth().expire();

    expect(authState().user, isNull);
    expect(authState().error, contains('未能保存'));
  });

  test('an ordinary restart still resumes a running timer', () async {
    await timer.start(taskId(), date);
    clock.advance(const Duration(minutes: 1));
    timer.dispose();
    clock.advance(const Duration(minutes: 5));

    timer = createTimer();
    await timer.initialize();
    expect(timer.activeTaskId, taskId());
    expect(timer.elapsedFor(taskId(), date), const Duration(minutes: 6));
    expect(minutesFor(date), 6);
  });

  test('account A timer state is stored under its own key before B signs in', () async {
    await timer.start(taskId(), date);
    clock.advance(const Duration(minutes: 2));
    await auth().signOut();
    final aKey = timer.storageKey;

    final coordinatorB = PlannerCoordinator(
      userId: 'user-b',
      scope: 'session-end-tests',
      storage: plannerStore,
      api: remote,
      retryInterval: null,
    )..data = plan().copyWith(profile: plan().profile.copyWith(userId: 'user-b'));
    addTearDown(coordinatorB.dispose);
    final timerB = StudyTimer(
      coordinator: coordinatorB,
      store: timerStore,
      now: () => clock.wall,
      monotonicNow: () => clock.monotonic,
      nextId: () => 'timer-b-${sequence++}',
      tickInterval: null,
    );
    addTearDown(timerB.dispose);
    await timerB.initialize();
    expect(timerB.activeTaskId, isNull);
    expect(timerB.elapsedFor(taskId(), date), Duration.zero);
    expect(aKey, isNot(timerB.storageKey));
    expect((await timerStore.load(aKey))!['active'], isNull);
    expect(await timerStore.load(timerB.storageKey), isNull);

    timer.dispose();
    timer = createTimer();
    await timer.initialize();
    expect(timer.elapsedFor(taskId(), date), const Duration(minutes: 2));
  });
}

class _Clock {
  DateTime wall = DateTime.parse('2026-10-17T02:00:00Z');
  Duration monotonic = Duration.zero;

  void advance(Duration duration) {
    wall = wall.add(duration);
    monotonic += duration;
  }
}

class _TimerStore implements StudyTimerStore {
  final values = <String, JsonMap>{};
  bool fail = false;

  @override
  Future<JsonMap?> load(String key) async => values[key];

  @override
  Future<void> save(String key, JsonMap value) async {
    if (fail) throw StateError('timer disk unavailable');
    final current = values[key];
    final revision = (current?['revision'] as int?) ?? 0;
    if (value['revision'] != revision + 1) {
      throw StudyTimerConflict(current);
    }
    values[key] = JsonMap.from(jsonDecode(jsonEncode(value)) as Map);
  }
}

class _RemoteApi implements SyncApi {
  _RemoteApi(this.data);
  PlannerData? data;
  int revision = 1;

  @override
  Future<RemoteSnapshot> pull({int? revision}) async => throw const OfflineFailure();

  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async => throw const OfflineFailure();
}
