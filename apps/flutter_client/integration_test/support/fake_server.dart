import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sjtu_study_planner_client/core/storage/file_transfer_repository.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

/// A real localhost HTTP server that speaks the same contract as the Node API.
///
/// The integration tests drive the production `Dio` client over a real socket, so
/// status codes, headers, JSON encoding and connection failures are real; only the
/// server is a double. It never contacts the production API or database.
///
/// "Offline" is modelled by closing the listening socket, so the client gets a
/// genuine connection refusal instead of a stub response.
class FakePlannerServer {
  FakePlannerServer._(this._server)
    : _port = _server.port,
      _baseUrl = 'http://127.0.0.1:${_server.port}';

  HttpServer _server;
  final List<String> received = [];

  /// Captured at bind time: the server cannot report its port once it is closed, and
  /// the app keeps using this address across an offline/online cycle.
  final int _port;
  final String _baseUrl;

  /// Server-side plan document: exactly what `/api/planner/sync` would store.
  PlannerData? document;
  int revision = 1;

  /// When set, every `/api/planner/sync` call fails with this status.
  int? forcedStatus;

  /// When true, the next `PUT` answers 409 after another writer moved the revision,
  /// which is what a second device writing first looks like.
  bool conflictOnNextPush = false;

  String email = 'student@example.com';
  String password = 'Study4089';

  int pushCount = 0;
  int pullCount = 0;
  bool get offline => _closed;

  bool _closed = false;
  bool _serving = false;

  String get baseUrl => _baseUrl;

  /// Binds a fresh port. The URL is stable across offline/online because the same
  /// port is reused, which is what an API restart looks like to the client.
  static Future<FakePlannerServer> start() async =>
      FakePlannerServer._(await _bind()).._listen();

  static Future<HttpServer> _bind({int? port}) async {
    Object? lastError;
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        return await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          port ?? 0,
          shared: false,
        );
      } on SocketException catch (error) {
        // A just-released port can linger in TIME_WAIT; retry briefly.
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError('无法绑定本地测试端口：$lastError');
  }

  /// Stops listening; connecting clients get `connection refused`.
  Future<void> goOffline() async {
    if (_closed) return;
    _closed = true;
    _serving = false;
    await _server.close(force: true);
  }

  /// Serves again on the same port, keeping [baseUrl] valid.
  Future<void> goOnline() async {
    if (!_closed) return;
    _server = await _bind(port: _port);
    _closed = false;
    _listen();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _serving = false;
    await _server.close(force: true);
  }

  void _listen() {
    if (_serving) return;
    _serving = true;
    _server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object _) {},
      cancelOnError: false,
    );
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    received.add('${request.method} $path');
    lastAuthHeader = request.headers.value('authorization');
    try {
      final response = await _route(request, path);
      request.response.statusCode = response.status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(response.body));
    } catch (error) {
      request.response.statusCode = 500;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': '$error'}));
    }
    await request.response.close();
  }

  String? lastAuthHeader;

  Future<_Stub> _route(HttpRequest request, String path) async {
    if (path == '/api/auth/login') {
      final body = await _json(request);
      if (body['email'] != email || body['password'] != password) {
        return _Stub(401, {'error': '邮箱或密码错误'});
      }
      return _Stub(200, {
        'user': _user,
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'expiresIn': 900,
      });
    }
    if (path == '/api/auth/registration-code') {
      return _Stub(200, {'ok': true, 'expiresIn': 600, 'retryAfter': 60});
    }
    if (path == '/api/auth/register') {
      return _Stub(201, {
        'user': _user,
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'expiresIn': 900,
      });
    }
    if (path == '/api/auth/token/refresh' || path == '/api/auth/refresh') {
      return _Stub(200, {
        'user': _user,
        'accessToken': 'access-2',
        'refreshToken': 'refresh-2',
        'expiresIn': 900,
      });
    }
    if (path == '/api/auth/logout' || path == '/api/auth/token/revoke') {
      return _Stub(200, {'ok': true});
    }
    if (path == '/api/me') return _Stub(200, {'user': _user});
    if (path == '/api/onboarding/profile') {
      return _Stub(200, {'profile': _profile});
    }
    if (path == '/api/planner/sync') {
      if (forcedStatus != null) {
        return _Stub(forcedStatus!, {'error': '服务端暂时不可用'});
      }
      if (request.method == 'PUT') return _push(request);
      pullCount++;
      return _Stub(200, {'data': document?.toJson(), 'revision': revision});
    }
    if (path == '/api/planner/snapshot') {
      return document == null
          ? _Stub(404, {'error': '尚无计划'})
          : _Stub(200, {'data': document!.toJson()});
    }
    if (path == '/api/study-logs') {
      return _Stub(200, {
        'log': {'id': 'log-stub'},
      });
    }
    if (path.startsWith('/api/daily-reviews/')) {
      return _Stub(200, {'runId': 'run-stub'});
    }
    return _Stub(404, {'error': '未实现：$path'});
  }

  Future<_Stub> _push(HttpRequest request) async {
    final body = await _json(request);
    final data = body['data'];
    if (data is! Map) return _Stub(400, {'error': '缺少 data'});
    if (conflictOnNextPush) {
      conflictOnNextPush = false;
      // Another device wrote first: the revision moves on without our document, and
      // it changes the same profile field so the merge cannot be silent.
      revision++;
      document = document?.copyWith(
        profile: document!.profile.copyWith(
          targetSchool: '其他设备的目标院校',
          targetProgram: '其他设备的目标方向',
        ),
      );
      return _Stub(409, {'conflict': true});
    }
    if (body['expectedRevision'] != revision) {
      return _Stub(409, {'conflict': true});
    }
    pushCount++;
    document = PlannerData.fromJson(JsonMap.from(data));
    revision++;
    return _Stub(200, {'data': document!.toJson(), 'revision': revision});
  }

  Future<Map<String, dynamic>> _json(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.isEmpty) return {};
    final value = jsonDecode(raw);
    return value is Map<String, dynamic> ? value : {'value': value};
  }

  static const _user = {
    'id': 'integration-user',
    'email': 'student@example.com',
    'username': '集成验收',
  };

  static const _profile = {
    'exam_type': '考研',
    'exam_date': '2027-12-25',
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
}

class _Stub {
  const _Stub(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

/// Stand-in for the OS file picker.
///
/// The real picker needs a human. The bytes still travel through production code:
/// the export is serialized by the client and written to a real file, and the import
/// re-reads and re-validates that file.
class FakeFileTransfer implements FileTransferRepository {
  String? exportPath;
  PlannerData? importValue;
  PlannerData? exported;
  bool exportCancelled = false;

  @override
  Future<bool> exportJson(PlannerData data) async {
    if (exportCancelled) return false;
    exported = data;
    final path = exportPath;
    if (path != null) {
      await File(path).writeAsString(data.toJsonString(), flush: true);
    }
    return true;
  }

  @override
  Future<PlannerData?> importJson() async {
    if (importValue != null) return importValue;
    final path = exportPath;
    if (path == null) return null;
    return PlannerData.fromJson(
      JsonMap.from(jsonDecode(await File(path).readAsString()) as Map),
    );
  }
}
