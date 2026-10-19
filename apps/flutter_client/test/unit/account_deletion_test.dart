import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/storage/account_data_store.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/features/auth/application/auth_controller.dart';

import '../support/async_wait.dart';
import '../support/http_adapter.dart';

class _AccountStore implements AccountDataStore {
  final purged = <String>[];
  Object? failure;

  @override
  Future<void> purge({required String scope, required String userId}) async {
    purged.add('$scope/$userId');
    if (failure != null) throw failure!;
  }
}

void main() {
  late ProviderContainer container;
  late ApiClient client;
  late MemoryIdentityStore identity;
  late MemoryTokenStore tokens;
  late _AccountStore store;
  late TestAdapter adapter;
  final events = <String>[];
  late Future<ResponseBody> Function(RequestOptions) deletion;
  var deleted = false;

  setUp(() async {
    events.clear();
    deleted = false;
    identity = MemoryIdentityStore();
    tokens = MemoryTokenStore();
    store = _AccountStore();
    deletion = (_) async => jsonResponse({'ok': true});
    adapter = TestAdapter((request) async {
      if (request.path == '/api/auth/delete-account') {
        events.add('request');
        return deletion(request);
      }
      if (deleted) {
        return jsonResponse({'code': 'ACCOUNT_DELETED', 'error': '账号已注销'}, 410);
      }
      return jsonResponse({'user': testUser});
    });
    client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: tokens,
      usesBearer: true,
      dio: Dio()..httpClientAdapter = adapter,
    );
    await tokens.write(
      TokenPair(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(client),
        appConfigProvider.overrideWithValue(
          const AppConfig(apiBaseUrl: 'http://api.test'),
        ),
        identityStoreProvider.overrideWithValue(identity),
        accountDataStoreProvider.overrideWithValue(store),
      ],
    );
    container.read(authControllerProvider);
    await waitUntil(() => container.read(authControllerProvider).user != null);
    final auth = container.read(authControllerProvider.notifier);
    auth.addSessionEndHandler(() async => events.add('pause'));
    auth.addDeletionParticipant(
      AccountDeletionParticipant(
        suspend: () async => events.add('suspend'),
        resume: () => events.add('resume'),
      ),
    );
  });

  tearDown(() {
    container.dispose();
    client.close();
  });

  test(
    'confirmed deletion drains state, authenticates request and clears only this account',
    () async {
      expect(
        await container
            .read(authControllerProvider.notifier)
            .deleteAccount(' secret '),
        isTrue,
      );
      expect(events, ['pause', 'suspend', 'request']);
      final request = adapter.requests.last;
      expect(request.headers['Authorization'], 'Bearer access');
      expect(request.data, {'password': ' secret '});
      expect(store.purged, ['http://api.test/user-1']);
      expect(await identity.load(), isNull);
      expect(await tokens.read(), isNull);
      expect(container.read(authControllerProvider).user, isNull);
      expect(container.read(authControllerProvider).notice, contains('账号已注销'));
    },
  );

  test('password rejection preserves session and resumes work', () async {
    deletion = (_) async => jsonResponse({'error': '当前密码错误'}, 403);
    expect(
      await container
          .read(authControllerProvider.notifier)
          .deleteAccount('wrong'),
      isFalse,
    );
    expect(events.last, 'resume');
    expect(store.purged, isEmpty);
    expect(await tokens.read(), isNotNull);
    expect(container.read(authControllerProvider).user?.id, 'user-1');
    expect(container.read(authControllerProvider).deletionPending, isFalse);
  });

  test(
    'lost response keeps data suspended and a confirmed retry purges it',
    () async {
      deletion = (request) async => throw DioException(
        requestOptions: request,
        type: DioExceptionType.receiveTimeout,
      );
      final auth = container.read(authControllerProvider.notifier);
      expect(await auth.deleteAccount('secret'), isFalse);
      expect(store.purged, isEmpty);
      expect(events, isNot(contains('resume')));
      expect(await identity.load(), isNotNull);
      expect(container.read(authControllerProvider).deletionPending, isTrue);
      deletion = (_) async => jsonResponse({'ok': true});
      expect(await auth.deleteAccount('secret'), isTrue);
      expect(store.purged, hasLength(1));
    },
  );

  test('failed local checkpoint prevents a deletion request', () async {
    container
        .read(authControllerProvider.notifier)
        .addSessionEndHandler(() async => throw StateError('disk full'));
    expect(
      await container
          .read(authControllerProvider.notifier)
          .deleteAccount('secret'),
      isFalse,
    );
    expect(events, isNot(contains('request')));
    expect(store.purged, isEmpty);
    expect(container.read(authControllerProvider).user, isNotNull);
  });

  test(
    'remote deletion closes the session and cleans cached account on restore',
    () async {
      deleted = true;
      await container.read(authControllerProvider.notifier).restoreSession();
      await waitUntil(
        () =>
            container.read(authControllerProvider).user == null &&
            !container.read(authControllerProvider).loading,
      );
      expect(store.purged, ['http://api.test/user-1']);
      expect(await tokens.read(), isNull);
      expect(await identity.load(), isNull);
    },
  );

  test('duplicate submit uses one server operation', () async {
    final response = Completer<ResponseBody>();
    deletion = (_) => response.future;
    final auth = container.read(authControllerProvider.notifier);
    final first = auth.deleteAccount('secret');
    await waitUntil(() => events.contains('request'));
    expect(await auth.deleteAccount('secret'), isFalse);
    response.complete(jsonResponse({'ok': true}));
    expect(await first, isTrue);
    expect(events.where((event) => event == 'request'), hasLength(1));
  });

  test(
    'server deletion still ends credentials when local cleanup fails',
    () async {
      store.failure = StateError('disk unavailable');
      expect(
        await container
            .read(authControllerProvider.notifier)
            .deleteAccount('secret'),
        isTrue,
      );
      expect(container.read(authControllerProvider).user, isNull);
      expect(await tokens.read(), isNull);
      expect(
        container.read(authControllerProvider).error,
        contains('本机缓存未能完整清理'),
      );
    },
  );

  test('historical corrupt files give explicit manual cleanup paths', () async {
    store.failure = LocalAccountCleanupIncomplete([
      'D:/cache/planner.db.corrupt-1',
    ]);
    expect(
      await container
          .read(authControllerProvider.notifier)
          .deleteAccount('secret'),
      isTrue,
    );
    expect(
      container.read(authControllerProvider).error,
      contains('D:/cache/planner.db.corrupt-1'),
    );
    expect(container.read(authControllerProvider).notice, isNull);
  });
}
