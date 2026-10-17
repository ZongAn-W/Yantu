import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/features/auth/data/auth_repository.dart';

import '../support/http_adapter.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';

void main() {
  late MemoryTokenStore store;
  late ApiClient client;
  late TestAdapter adapter;
  var expired = 0;

  void setup(Respond respond, {bool bearer = true}) {
    adapter = TestAdapter(respond);
    final dio = Dio()..httpClientAdapter = adapter;
    client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: store,
      dio: dio,
      usesBearer: bearer,
      onSessionExpired: () async {
        expired++;
      },
    );
  }

  Future<void> seed({bool isExpired = false}) => store.write(
    TokenPair(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      expiresAt: DateTime.now().add(Duration(minutes: isExpired ? -1 : 10)),
    ),
  );

  setUp(() {
    store = MemoryTokenStore();
    expired = 0;
  });
  tearDown(() {
    client.close();
  });

  test(
    'native login saves tokens before returning; bad credentials never refresh',
    () async {
      setup((request) async {
        expect(request.headers['X-Client-Auth'], 'bearer');
        if ((request.data as Map)['password'] == 'wrong') {
          return jsonResponse({'error': '邮箱或密码错误'}, 401);
        }
        return jsonResponse({
          'user': testUser,
          'accessToken': 'access',
          'refreshToken': 'refresh',
          'expiresIn': 900,
        });
      });
      final repository = AuthRepository(client, MemoryIdentityStore());
      final user = await repository.login('student@example.com', 'Study4089');
      expect(user.id, 'user-1');
      expect((await store.read())?.refreshToken, 'refresh');
      await expectLater(
        repository.login('student@example.com', 'wrong'),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'concurrent expired requests share one refresh, then use the new access token',
    () async {
      await seed(isExpired: true);
      final refresh = Completer<ResponseBody>();
      setup((request) async {
        if (request.path == '/api/auth/token/refresh') {
          expect(request.data, {'refreshToken': 'old-refresh'});
          return refresh.future;
        }
        expect(request.headers['Authorization'], 'Bearer new-access');
        return jsonResponse({'user': testUser});
      });
      final requests = [client.get('/api/me'), client.get('/api/items')];
      await Future<void>.delayed(Duration.zero);
      refresh.complete(
        jsonResponse({
          'accessToken': 'new-access',
          'refreshToken': 'new-refresh',
          'expiresIn': 900,
        }),
      );
      await Future.wait(requests);
      expect(
        adapter.requests.where((r) => r.path.endsWith('/refresh')),
        hasLength(1),
      );
      expect((await store.read())?.refreshToken, 'new-refresh');
    },
  );

  test(
    '401 refresh rejection clears credentials and notifies the session controller',
    () async {
      await seed();
      setup((request) async => jsonResponse({'error': '登录已过期'}, 401));
      await expectLater(
        client.get('/api/me'),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(await store.read(), isNull);
      expect(expired, 1);
      expect(adapter.requests, hasLength(2));
    },
  );

  test('malformed refresh response clears the unusable session', () async {
    await seed(isExpired: true);
    setup((request) async => jsonResponse({'accessToken': 'incomplete'}));
    await expectLater(client.get('/api/me'), throwsA(isA<ResponseFailure>()));
    expect(await store.read(), isNull);
    expect(expired, 1);
  });

  test(
    'network failure during refresh preserves credentials for retry',
    () async {
      await seed(isExpired: true);
      setup(
        (request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(client.get('/api/me'), throwsA(isA<OfflineFailure>()));
      expect((await store.read())?.refreshToken, 'old-refresh');
      expect(expired, 0);
    },
  );

  test('Web uses Cookie refresh and never sends native credentials', () async {
    var attempts = 0;
    setup((request) async {
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('X-Client-Auth'), isFalse);
      if (request.path == '/api/auth/refresh') {
        return jsonResponse({'user': testUser});
      }
      return ++attempts == 1
          ? jsonResponse({'error': '请先登录'}, 401)
          : jsonResponse({'user': testUser});
    }, bearer: false);
    await client.get('/api/me');
    expect(adapter.requests.map((r) => r.path), [
      '/api/me',
      '/api/auth/refresh',
      '/api/me',
    ]);
    expect(await store.read(), isNull);
  });

  test('logout invalidates a refresh response already in flight', () async {
    await seed(isExpired: true);
    final refresh = Completer<ResponseBody>();
    final started = Completer<void>();
    setup((request) {
      started.complete();
      return refresh.future;
    });
    final request = client.get('/api/me');
    final assertion = expectLater(request, throwsA(isA<UnauthorizedFailure>()));
    await started.future;
    await client.clearSession();
    refresh.complete(
      jsonResponse({
        'accessToken': 'late',
        'refreshToken': 'late',
        'expiresIn': 900,
      }),
    );
    await assertion;
    expect(await store.read(), isNull);
  });

  test('a second 401 after refresh cannot loop forever', () async {
    await seed();
    setup(
      (request) async => request.path.endsWith('/refresh')
          ? jsonResponse({
              'accessToken': 'new',
              'refreshToken': 'new',
              'expiresIn': 900,
            })
          : jsonResponse({'error': '失效'}, 401),
    );
    await expectLater(
      client.get('/api/me'),
      throwsA(isA<UnauthorizedFailure>()),
    );
    expect(adapter.requests, hasLength(3));
    expect(await store.read(), isNull);
  });
}
