import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/errors/app_failure.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/http_adapter.dart';
import '../support/planner_fixture.dart';

void main() {
  late TestAdapter adapter;
  late ApiClient client;
  late HttpSyncApi api;

  void setup(Respond respond) {
    adapter = TestAdapter(respond);
    client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()..httpClientAdapter = adapter,
      usesBearer: false,
    );
    api = HttpSyncApi(client);
  }

  setUp(() {});
  tearDown(() => client.close());

  group('pull', () {
    test('a document and revision are parsed into the domain model', () async {
      final data = plannerFixture();
      setup(
        (request) async =>
            jsonResponse({'data': data.toJson(), 'revision': 12}),
      );
      final remote = await api.pull();
      expect(remote.revision, 12);
      expect(remote.conflict, isFalse);
      expect(remote.data, data);
      expect(adapter.requests.single.path, '/api/planner/sync');
    });

    test('a document with new learning fields is parsed without stripping', () async {
      final fixture = plannerFixture();
      final json = fixture.toJson();
      json['profile'] = {
        ...(json['profile'] as Map),
        'capacity_basis': 'net',
        'weekly_baseline_minutes': 300,
        'date_capacity_overrides': {'2026-10-22': 0},
      };
      json['ad_hoc_learnings'] = [
        {
          'id': 'adhoc-photo',
          'user_id': fixture.profile.userId,
          'title': '摄影构图',
          'created_at': '2026-10-18T01:00:00.000Z',
          'updated_at': '2026-10-18T01:00:00.000Z',
        },
      ];
      final log = (json['logs'] as List).single as Map;
      log['task_id'] = null;
      log['relation'] = 'ad_hoc';
      log['ad_hoc_id'] = 'adhoc-photo';
      log['session_id'] = 'session-1';
      setup((request) async => jsonResponse({'data': json, 'revision': 3}));
      final remote = await api.pull();
      final data = remote.data!;
      expect(data.adHocLearnings.single.id, 'adhoc-photo');
      expect(data.profile.capacityBasis, CapacityBasis.net);
      expect(data.profile.weeklyBaselineMinutes, 300);
      expect(data.profile.dateCapacityOverrides, {'2026-10-22': 0});
      final parsed = data.logs.single;
      expect(parsed.taskId, isNull);
      expect(parsed.adHocId, 'adhoc-photo');
      expect(parsed.relation, TimeLogRelation.adHoc);
      expect(parsed.sessionId, 'session-1');
    });

    test('a null document means the account has no server plan yet', () async {
      setup((request) async => jsonResponse({'data': null, 'revision': 0}));
      final remote = await api.pull();
      expect(remote.data, isNull);
      expect(remote.revision, 0);
    });

    test('a negative revision is rejected as a malformed response', () async {
      setup(
        (request) async =>
            jsonResponse({'data': null, 'revision': -1}),
      );
      await expectLater(api.pull(), throwsA(isA<ResponseFailure>()));
    });

    test('a missing revision is rejected', () async {
      setup((request) async => jsonResponse({'data': null}));
      await expectLater(api.pull(), throwsA(isA<ResponseFailure>()));
    });

    test('a string revision is rejected instead of coerced', () async {
      setup(
        (request) async =>
            jsonResponse({'data': null, 'revision': '12'}),
      );
      await expectLater(api.pull(), throwsA(isA<ResponseFailure>()));
    });

    test('a document that fails domain validation is rejected', () async {
      final broken = plannerFixture().toJson();
      (broken['blocks'] as List).single['task_id'] = 'missing-task';
      setup(
        (request) async => jsonResponse({'data': broken, 'revision': 3}),
      );
      await expectLater(api.pull(), throwsA(isA<ResponseFailure>()));
    });

    test('a future document version is rejected', () async {
      final broken = plannerFixture().toJson()..['version'] = 2;
      setup(
        (request) async => jsonResponse({'data': broken, 'revision': 3}),
      );
      await expectLater(api.pull(), throwsA(isA<ResponseFailure>()));
    });

    test(
      'a document with unknown learning relations fails with an upgrade hint',
      () async {
        final broken = plannerFixture().toJson();
        ((broken['logs'] as List).single as Map)['relation'] = 'future_relation';
        setup(
          (request) async => jsonResponse({'data': broken, 'revision': 3}),
        );
        await expectLater(
          api.pull(),
          throwsA(
            isA<ResponseFailure>().having(
              (error) => error.message,
              'message',
              contains('更新版本'),
            ),
          ),
        );
      },
    );

    test('a non-object payload is rejected', () async {
      setup((request) async => jsonResponse([1, 2, 3]));
      await expectLater(api.pull(), throwsA(isA<ResponseFailure>()));
    });

    test('an offline server surfaces as an offline failure', () async {
      setup(
        (request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(api.pull(), throwsA(isA<OfflineFailure>()));
    });

    test('a 5xx surfaces as a server failure so the client can retry later', () async {
      setup((request) async => jsonResponse({'error': '维护中'}, 503));
      await expectLater(api.pull(), throwsA(isA<ServerFailure>()));
    });

    test('an unauthenticated account surfaces as unauthorized', () async {
      setup((request) async => jsonResponse({'error': '请先登录'}, 401));
      await expectLater(api.pull(), throwsA(isA<UnauthorizedFailure>()));
    });

    test('a known revision is sent as a query parameter', () async {
      final data = plannerFixture();
      setup(
        (request) async =>
            jsonResponse({'data': data.toJson(), 'revision': 12}),
      );
      await api.pull(revision: 12);
      expect(adapter.requests.single.queryParameters, {'revision': 12});
    });

    test(
      'an unchanged response is not mistaken for a deleted cloud plan',
      () async {
        setup(
          (request) async =>
              jsonResponse({'revision': 12, 'unchanged': true}),
        );
        final remote = await api.pull(revision: 12);
        expect(remote.unchanged, isTrue);
        expect(remote.data, isNull);
        expect(remote.revision, 12);
        expect(remote.conflict, isFalse);
        expect(adapter.requests.single.queryParameters, {'revision': 12});
      },
    );

    test(
      'an old server that ignores the revision argument returns a full document',
      () async {
        final data = plannerFixture();
        setup(
          (request) async =>
              jsonResponse({'data': data.toJson(), 'revision': 12}),
        );
        final remote = await api.pull(revision: 12);
        expect(remote.unchanged, isFalse);
        expect(remote.data, data);
      },
    );

    test('unchanged with a full document is rejected as malformed', () async {
      setup(
        (request) async => jsonResponse({
          'data': plannerFixture().toJson(),
          'revision': 12,
          'unchanged': true,
        }),
      );
      await expectLater(
        api.pull(revision: 12),
        throwsA(isA<ResponseFailure>()),
      );
    });

    test('a non-boolean unchanged flag is rejected', () async {
      setup(
        (request) async =>
            jsonResponse({'data': null, 'revision': 12, 'unchanged': 'true'}),
      );
      await expectLater(
        api.pull(revision: 12),
        throwsA(isA<ResponseFailure>()),
      );
    });

    test('unchanged without a valid revision is rejected', () async {
      setup((request) async => jsonResponse({'unchanged': true}));
      await expectLater(
        api.pull(revision: 12),
        throwsA(isA<ResponseFailure>()),
      );
    });
  });

  group('push', () {
    test('the body carries data, base, expected revision and writer capability', () async {
      final data = plannerFixture();
      setup(
        (request) async =>
            jsonResponse({'data': data.toJson(), 'revision': 13}),
      );
      final response = await api.push(data, data, 12);
      expect(response.revision, 13);
      expect(response.data, data);
      final body = adapter.requests.single.data as Map;
      expect(body['expectedRevision'], 12);
      expect(body['base'], isNotNull);
      expect((body['data'] as Map)['version'], 1);
      // 新客户端同时声明新版规划与学习记录表达能力；服务端据此判断“缺失=保留”。
      expect(body['writer_planning_version'], 1);
      expect(body['writer_learning_version'], 1);
      expect(adapter.requests.single.method, 'PUT');
    });

    test('a null base is sent as null for a never-synced account', () async {
      final data = plannerFixture();
      setup(
        (request) async =>
            jsonResponse({'data': data.toJson(), 'revision': 1}),
      );
      await api.push(data, null, 0);
      final body = adapter.requests.single.data as Map;
      expect(body.containsKey('base'), isTrue);
      expect(body['base'], isNull);
      expect(body['expectedRevision'], 0);
    });

    test('a 409 conflict triggers a fresh pull and reports the conflict', () async {
      final remote = plannerFixture().copyWith(
        profile: plannerFixture().profile.copyWith(targetSchool: '远端院校'),
      );
      final local = plannerFixture();
      setup((request) async {
        if (request.method == 'PUT') {
          return jsonResponse({'conflict': true}, 409);
        }
        return jsonResponse({'data': remote.toJson(), 'revision': 20});
      });
      final response = await api.push(local, local, 12);
      expect(response.conflict, isTrue);
      expect(response.revision, 20);
      expect(response.data?.profile.targetSchool, '远端院校');
      expect(adapter.requests.map((r) => r.method), ['PUT', 'GET']);
    });

    test('a conflict whose follow-up pull fails is still an error', () async {
      final local = plannerFixture();
      var calls = 0;
      setup((request) async {
        calls++;
        if (calls == 1) return jsonResponse({'conflict': true}, 409);
        return jsonResponse({'error': '维护中'}, 503);
      });
      await expectLater(
        api.push(local, local, 12),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a rejected body surfaces its validation message', () async {
      final local = plannerFixture();
      setup(
        (request) async => jsonResponse({'error': '数据格式不正确'}, 400),
      );
      await expectLater(
        api.push(local, local, 1),
        throwsA(
          isA<ValidationFailure>().having(
            (error) => error.message,
            'message',
            '数据格式不正确',
          ),
        ),
      );
    });

    test('an offline push keeps the local change for a later retry', () async {
      final local = plannerFixture();
      setup(
        (request) async => throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(
        api.push(local, null, 0),
        throwsA(isA<OfflineFailure>()),
      );
    });

    test('a push response with a malformed document is rejected', () async {
      final local = plannerFixture();
      setup((request) async => jsonResponse({'data': 'nope', 'revision': 2}));
      await expectLater(
        api.push(local, local, 1),
        throwsA(isA<ResponseFailure>()),
      );
    });

    test(
      'a 426 writer upgrade requirement is a clear upgrade failure, not a conflict',
      () async {
        final local = plannerFixture();
        setup(
          (request) async => jsonResponse({
            'upgradeRequired': true,
            'error': '当前计划包含临时学习/加学计时记录，请升级客户端后再同步',
            'code': 'learning_writer_upgrade_required',
          }, 426),
        );
        await expectLater(
          api.push(local, local, 1),
          throwsA(
            isA<ValidationFailure>()
                .having((error) => error.statusCode, 'statusCode', 426)
                .having((error) => error.message, 'message', contains('升级'))
                .having((error) => error.message, 'message', contains('本机数据已保留')),
          ),
        );
        // 升级信号不应触发冲突后的完整拉取：服务端明确拒绝了这次写入。
        expect(adapter.requests.map((request) => request.method), ['PUT']);
      },
    );
  });

  group('round trip compatibility', () {
    test('a pushed document survives a JSON encode/decode cycle unchanged', () async {
      final data = plannerFixture();
      Map<String, dynamic>? received;
      setup((request) async {
        received = jsonDecode(jsonEncode(request.data)) as Map<String, dynamic>;
        return jsonResponse({'data': received!['data'], 'revision': 5});
      });
      final response = await api.push(data, data, 4);
      expect(response.data, data);
      // The wire body must be the same JSON the old TypeScript client writes.
      expect(received!['data'], data.toJson());
    });
  });
}
