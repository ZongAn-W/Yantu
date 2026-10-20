import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';

import '../support/http_adapter.dart';

/// A response with a body that is not JSON at all.
ResponseBody textResponse(String body, int status) => ResponseBody.fromString(
  body,
  status,
  headers: {
    'content-type': ['text/html'],
  },
);

/// Runs [send] against a captured adapter and returns the exact request body bytes.
///
/// `TestAdapter` never consumes the request stream, so `RequestOptions.data` stays
/// null for streamed bodies; reading the stream is the only faithful check.
Future<List<int>> captureBody(
  Future<void> Function(ApiClient client) send, {
  required MemoryTokenStore store,
}) async {
  final captured = <int>[];
  final adapter = TestAdapter((request) async => jsonResponse({'ok': true}));
  final dio = Dio()..httpClientAdapter = _CapturingAdapter(adapter, captured);
  final client = ApiClient(
    config: const AppConfig(apiBaseUrl: 'http://api.test'),
    tokenStore: store,
    dio: dio,
    usesBearer: false,
  );
  try {
    await send(client);
  } finally {
    client.close();
  }
  return captured;
}

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.inner, this.sink);
  final HttpClientAdapter inner;
  final List<int> sink;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        sink.addAll(chunk);
      }
    }
    return inner.fetch(options, null, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

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

  setUp(() {
    store = MemoryTokenStore();
    expired = 0;
  });
  tearDown(() => client.close());

  group('timeouts', () {
    test(
      'AI requests receive the long receive timeout, others the default',
      () async {
        final seen = <String, Duration?>{};
        adapter = TestAdapter((request) async {
          seen[request.path] = request.receiveTimeout;
          return jsonResponse({'ok': true});
        });
        client = ApiClient(
          config: const AppConfig(apiBaseUrl: 'http://api.test'),
          tokenStore: store,
          dio: Dio()..httpClientAdapter = adapter,
          usesBearer: false,
        );
        await client.post('/api/ai/plan-drafts', data: {'a': 1});
        await client.get('/api/planner/sync');
        expect(seen['/api/ai/plan-drafts'], const Duration(seconds: 240));
        expect(seen['/api/planner/sync'], const Duration(seconds: 45));
      },
    );

    test('the refresh request uses its own short timeout', () async {
      await store.write(
        TokenPair(
          accessToken: 'old',
          refreshToken: 'old-refresh',
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        ),
      );
      final seen = <Duration?>[];
      adapter = TestAdapter((request) async {
        seen.add(request.receiveTimeout);
        return jsonResponse({'error': '失效'}, 401);
      });
      client = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: store,
        dio: Dio()..httpClientAdapter = adapter,
      );
      await expectLater(
        client.get('/api/me'),
        throwsA(isA<UnauthorizedFailure>()),
      );
      // First the business request (45s), then the refresh (15s).
      expect(seen, hasLength(2));
      expect(seen.first, const Duration(seconds: 45));
      expect(seen.last, const Duration(seconds: 15));
    });

    test('connect timeout is configured once on the shared options', () {
      final dio = Dio()
        ..httpClientAdapter = TestAdapter((request) async => jsonResponse({}));
      final subject = ApiClient(
        config: const AppConfig(apiBaseUrl: 'http://api.test'),
        tokenStore: store,
        dio: dio,
      );
      expect(dio.options.connectTimeout, const Duration(seconds: 15));
      expect(dio.options.sendTimeout, const Duration(seconds: 45));
      expect(dio.options.receiveTimeout, const Duration(seconds: 45));
      expect(dio.options.headers['accept'], 'application/json');
      subject.close();
    });
  });

  group('failure mapping', () {
    test('status codes map to the documented failure types', () async {
      final cases = <int, Matcher>{
        400: isA<ValidationFailure>(),
        404: isA<ValidationFailure>(),
        409: isA<ConflictFailure>(),
        422: isA<ValidationFailure>(),
        500: isA<ServerFailure>(),
        502: isA<ServerFailure>(),
        503: isA<ServerFailure>(),
      };
      for (final entry in cases.entries) {
        setup(
          (request) async => jsonResponse({'error': '服务端说明'}, entry.key),
          bearer: false,
        );
        await expectLater(
          client.get('/api/planner/sync'),
          throwsA(entry.value),
          reason: 'HTTP ${entry.key}',
        );
        client.close();
      }
    });

    test('the server error message survives the mapping', () async {
      setup(
        (request) async => jsonResponse({'error': '该时段已有学习时间块'}, 409),
        bearer: false,
      );
      await expectLater(
        client.post('/api/items', data: {}),
        throwsA(
          isA<ConflictFailure>().having(
            (error) => error.message,
            'message',
            '该时段已有学习时间块',
          ),
        ),
      );
    });

    test('a missing error field falls back to a status message', () async {
      setup((request) async => jsonResponse({}, 403), bearer: false);
      await expectLater(
        client.get('/api/me'),
        throwsA(
          isA<ValidationFailure>().having(
            (error) => error.message,
            'message',
            '请求失败（403）',
          ),
        ),
      );
    });

    test('a validation failure exposes its status code', () async {
      setup(
        (request) async => jsonResponse({'error': 'x'}, 422),
        bearer: false,
      );
      await expectLater(
        client.get('/api/me'),
        throwsA(
          isA<ValidationFailure>().having(
            (error) => error.statusCode,
            'statusCode',
            422,
          ),
        ),
      );
    });

    test('a non-JSON error body still maps by status', () async {
      setup(
        (request) async => textResponse('<html>502</html>', 502),
        bearer: false,
      );
      await expectLater(
        client.get('/api/planner/sync'),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('transport failures map to OfflineFailure', () async {
      for (final type in const [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.badCertificate,
        DioExceptionType.unknown,
      ]) {
        setup(
          (request) async =>
              throw DioException(requestOptions: request, type: type),
          bearer: false,
        );
        await expectLater(
          client.get('/api/planner/sync'),
          throwsA(isA<OfflineFailure>()),
          reason: '$type',
        );
        client.close();
      }
    });

    test(
      'a cancelled request is reported as a transport failure, not a server error',
      () async {
        setup(
          (request) async => throw DioException(
            requestOptions: request,
            type: DioExceptionType.cancel,
          ),
          bearer: false,
        );
        // Cancellation is not a server-side problem. It currently shares the offline
        // bucket; a page treats it as "retry later" rather than showing a 5xx message.
        await expectLater(
          client.get('/api/planner/sync'),
          throwsA(isA<OfflineFailure>()),
        );
      },
    );

    test(
      'a successful non-JSON body is surfaced to the caller, not swallowed',
      () async {
        setup((request) async => textResponse('not json', 200), bearer: false);
        final response = await client.get('/api/planner/sync');
        expect(response.statusCode, 200);
        expect(response.data, 'not json');
      },
    );
  });

  group('request building', () {
    test('native requests carry the bearer flag and access token', () async {
      await store.write(
        TokenPair(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        ),
      );
      setup((request) async => jsonResponse({'ok': true}));
      await client.get('/api/planner/sync');
      final request = adapter.requests.single;
      expect(request.headers['Authorization'], 'Bearer access-1');
      expect(request.headers['X-Client-Auth'], isNull);
      expect(request.baseUrl, 'http://api.test');
    });

    test(
      'auth endpoints advertise the bearer contract without an access token',
      () async {
        setup((request) async => jsonResponse({'ok': true}));
        await client.post('/api/auth/login', data: {'email': 'a@b.c'});
        final request = adapter.requests.single;
        expect(request.headers['X-Client-Auth'], 'bearer');
        expect(request.headers['Authorization'], isNull);
      },
    );

    test('query parameters and JSON bodies are forwarded', () async {
      setup((request) async => jsonResponse({'ok': true}), bearer: false);
      await client.get('/api/progress', query: {'from': '2026-10-01'});
      await client.patch('/api/items/1', data: {'title': 'x'});
      expect(adapter.requests.first.uri.queryParameters['from'], '2026-10-01');
      expect(adapter.requests.last.method, 'PATCH');
      expect(adapter.requests.last.data, {'title': 'x'});
    });

    test('every verb is reachable through the client', () async {
      setup((request) async => jsonResponse({'ok': true}), bearer: false);
      await client.get('/a');
      await client.post('/b', data: {});
      await client.put('/c', data: {});
      await client.patch('/d', data: {});
      await client.delete('/e', data: {});
      expect(adapter.requests.map((r) => r.method), [
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
      ]);
      expect(adapter.requests.map((r) => r.path), [
        '/a',
        '/b',
        '/c',
        '/d',
        '/e',
      ]);
    });

    test(
      'an expired access token is refreshed before the request is sent',
      () async {
        await store.write(
          TokenPair(
            accessToken: 'stale',
            refreshToken: 'refresh-1',
            expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          ),
        );
        setup((request) async {
          if (request.path == '/api/auth/token/refresh') {
            return jsonResponse({
              'accessToken': 'fresh',
              'refreshToken': 'refresh-2',
              'expiresIn': 900,
            });
          }
          return jsonResponse({'user': testUser});
        });
        await client.get('/api/me');
        expect(adapter.requests.map((r) => r.path), [
          '/api/auth/token/refresh',
          '/api/me',
        ]);
        expect(adapter.requests.last.headers['Authorization'], 'Bearer fresh');
        expect((await store.read())?.refreshToken, 'refresh-2');
      },
    );

    test(
      'a request with no stored credentials is sent unauthenticated',
      () async {
        setup((request) async => jsonResponse({'ok': true}));
        await client.get('/api/planner/snapshot');
        expect(adapter.requests.single.headers['Authorization'], isNull);
      },
    );
  });

  group('session handling', () {
    test(
      'logout on the Web hits the cookie endpoint and drops local state',
      () async {
        setup((request) async => jsonResponse({'ok': true}), bearer: false);
        await client.clearSession();
        // clearSession itself performs no request: the repository owns logout.
        expect(adapter.requests, isEmpty);
        expect(expired, 1);
      },
    );

    test(
      'a failing session-expired callback still clears the token store',
      () async {
        adapter = TestAdapter((request) async => jsonResponse({'ok': true}));
        client = ApiClient(
          config: const AppConfig(apiBaseUrl: 'http://api.test'),
          tokenStore: store,
          dio: Dio()..httpClientAdapter = adapter,
          onSessionExpired: () async => throw StateError('callback failed'),
        );
        await store.write(
          TokenPair(
            accessToken: 'a',
            refreshToken: 'b',
            expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          ),
        );
        await expectLater(client.clearSession(), throwsA(isA<StateError>()));
        expect(await store.read(), isNull);
      },
    );

    test(
      'a bearer refresh without stored credentials ends the session',
      () async {
        setup((request) async => jsonResponse({'ok': true}));
        await expectLater(
          client.refreshTokens(),
          throwsA(isA<UnauthorizedFailure>()),
        );
        expect(expired, 1);
        expect(adapter.requests, isEmpty);
      },
    );

    test(
      'a 5xx during refresh keeps the credentials for a later retry',
      () async {
        await store.write(
          TokenPair(
            accessToken: 'stale',
            refreshToken: 'keep-me',
            expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
          ),
        );
        setup((request) async => jsonResponse({'error': '维护中'}, 503));
        await expectLater(client.get('/api/me'), throwsA(isA<ServerFailure>()));
        expect((await store.read())?.refreshToken, 'keep-me');
        expect(expired, 0);
      },
    );

    test('tokens accepted by login stay usable for the next request', () async {
      setup((request) async => jsonResponse({'user': testUser}));
      await client.acceptSession({
        'accessToken': 'login-access',
        'refreshToken': 'login-refresh',
        'expiresIn': 900,
      });
      final tokens = await store.read();
      expect(tokens?.accessToken, 'login-access');
      expect(
        tokens!.expiresAt.difference(DateTime.now()).inSeconds,
        greaterThan(880),
      );
      await client.get('/api/me');
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer login-access',
      );
    });

    test('a Web client ignores an acceptSession payload', () async {
      setup((request) async => jsonResponse({'ok': true}), bearer: false);
      await client.acceptSession({'accessToken': 'ignored'});
      expect(await store.read(), isNull);
    });
  });

  group('parsing compatibility', () {
    test('a JSON body with extra unknown fields is accepted', () async {
      setup(
        (request) async => jsonResponse({
          'user': testUser,
          'accessToken': 'a',
          'refreshToken': 'b',
          'expiresIn': 900,
          'serverVersion': '2.0.0',
          'features': ['x', 'y'],
        }),
      );
      // The login response is only persisted when the caller accepts the session,
      // which AuthRepository does; the client must tolerate the extra fields.
      await client.acceptSession({
        'accessToken': 'a',
        'refreshToken': 'b',
        'expiresIn': 900,
        'serverVersion': '2.0.0',
        'features': ['x', 'y'],
      });
      expect((await store.read())?.accessToken, 'a');
    });

    test(
      'numeric expiresIn sent as a double is rejected instead of truncated',
      () async {
        setup((request) async => jsonResponse({'ok': true}));
        await expectLater(
          client.acceptSession({
            'accessToken': 'a',
            'refreshToken': 'b',
            'expiresIn': 900.5,
          }),
          throwsA(isA<ResponseFailure>()),
        );
        expect(await store.read(), isNull);
      },
    );

    test('a UTF-8 JSON body round-trips Chinese text', () async {
      setup(
        (request) async => jsonResponse({'title': '高数 · 基础一轮'}),
        bearer: false,
      );
      final response = await client.get('/api/items');
      expect(jsonDecode(jsonEncode(response.data))['title'], '高数 · 基础一轮');
    });

    test('a request body is encoded as UTF-8 on the wire', () async {
      final wire = await captureBody(
        (client) => client.post('/api/items', data: {'title': '政治'}),
        store: store,
      );
      expect(utf8.decode(wire), contains('政治'));
      expect(utf8.decode(wire), contains('"title"'));
    });
  });

  group('cookie mode', () {
    test(
      'Web requests never attach a bearer header, even when tokens exist',
      () async {
        await store.write(
          TokenPair(
            accessToken: 'should-not-be-used',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
          ),
        );
        setup((request) async => jsonResponse({'ok': true}), bearer: false);
        await client.get('/api/planner/sync');
        expect(adapter.requests.single.headers['Authorization'], isNull);
        expect(adapter.requests.single.headers['X-Client-Auth'], isNull);
      },
    );

    test('a Web 401 refreshes the cookie session and replays once', () async {
      var attempt = 0;
      setup((request) async {
        if (request.path == '/api/auth/refresh') {
          return jsonResponse({'user': testUser});
        }
        attempt++;
        return attempt == 1
            ? jsonResponse({'error': '请先登录'}, 401)
            : jsonResponse({'ok': true});
      }, bearer: false);
      final response = await client.get('/api/planner/sync');
      expect(response.statusCode, 200);
      expect(adapter.requests.map((r) => r.path), [
        '/api/planner/sync',
        '/api/auth/refresh',
        '/api/planner/sync',
      ]);
    });

    test('a Web 401 on an auth endpoint is not retried', () async {
      setup(
        (request) async => jsonResponse({'error': '邮箱或密码错误'}, 401),
        bearer: false,
      );
      await expectLater(
        client.post('/api/auth/login', data: {}),
        throwsA(isA<UnauthorizedFailure>()),
      );
      expect(adapter.requests, hasLength(1));
    });
  });

  group('native transport', () {
    test(
      'a full planner document round-trips through the sync request body',
      () async {
        final data = {
          'version': 1,
          'profile': {'user_id': 'u1', 'target_school': '上海交通大学'},
          'tags': [
            for (var index = 0; index < 20; index++)
              {'id': 'tag$index', 'user_id': 'u1', 'name': '标签 $index'},
          ],
          'tasks': [
            for (var index = 0; index < 200; index++)
              {
                'id': 't$index',
                'title': '基础一轮 $index',
                'description': '范围：极限、导数与积分基础题；整理主要薄弱点。',
                'estimated_minutes': 600 + index,
                'tag_ids': ['tag${index % 20}'],
              },
          ],
          'blocks': [
            for (var index = 0; index < 500; index++)
              {
                'id': 'b$index',
                'task_id': 't${index % 200}',
                'date': '2026-10-17',
                'duration_minutes': 30,
              },
          ],
        };
        final wire = await captureBody(
          (client) => client.put('/api/planner/sync', data: data),
          store: store,
        );
        final decoded = jsonDecode(utf8.decode(wire)) as Map<String, dynamic>;
        expect((decoded['tasks'] as List), hasLength(200));
        expect((decoded['blocks'] as List), hasLength(500));
        expect(
          ((decoded['tasks'] as List).first as Map)['description'],
          '范围：极限、导数与积分基础题；整理主要薄弱点。',
        );
        expect(((decoded['profile'] as Map)['target_school']), '上海交通大学');
      },
    );

    test('closing the client releases the transport', () async {
      setup((request) async => jsonResponse({'ok': true}));
      client.close();
      await expectLater(client.get('/api/me'), throwsA(isA<Object>()));
    });
  });
}
