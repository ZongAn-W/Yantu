import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/storage/database_factory_io.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/http_adapter.dart';

/// 基线测量产物目录（相对 apps/flutter_client，即 `flutter test` 的工作目录）。
const String perfArtifactDirectory = '../../.dsh-verify/optfix/perf';

void writePerfArtifact(String fileName, Map<String, Object?> payload) {
  final directory = Directory(perfArtifactDirectory)
    ..createSync(recursive: true);
  final file = File('${directory.path}/$fileName');
  file.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  debugPrint('perf artifact written: ${file.absolute.path}');
}

Map<String, Object?> perfEnvironment(String label) => {
  'label': label,
  'measuredAt': DateTime.now().toUtc().toIso8601String(),
  'runner': 'flutter test（Dart VM / flutter_tester 进程）',
  'platform': Platform.operatingSystem,
  'osVersion': Platform.operatingSystemVersion,
  'dartVersion': Platform.version.split(' ').first,
  'processors': Platform.numberOfProcessors,
  'notes': '合成数据；结构性计数为主要验收依据；耗时为单次观测，仅在同一环境内可比。',
};

Map<String, Object?> perfReportHeader(String label) => {
  'label': label,
  'environment': perfEnvironment(label),
};

double medianMilliseconds(List<int> microseconds) {
  if (microseconds.isEmpty) return 0;
  final sorted = [...microseconds]..sort();
  final middle = sorted.length ~/ 2;
  final value = sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
  return value / 1000;
}

/// 让协调器内部的 fire-and-forget 同步/计时写队列跑完，不依赖随机 sleep。
Future<void> settle([int turns = 24]) async {
  for (var turn = 0; turn < turns; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 等待协调器内部由 edit 触发的同步循环自然结束（不额外发起请求）。
///
/// 以条件（同步不再 busy）为结束依据，配合明确超时；不依赖固定的 sleep 次数。
Future<void> waitUntilSyncIdle(
  PlannerCoordinator coordinator, {
  String label = '',
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (coordinator.busy) {
    if (DateTime.now().isAfter(deadline)) {
      debugPrint(
        'perf waitUntilSyncIdle timeout ($label): status=${coordinator.status} '
        'busy=${coordinator.busy} pending=${coordinator.pending} '
        'conflicts=${coordinator.conflicts.length}',
      );
      throw StateError('同步循环未在超时前结束');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<int> fileBytes(String path) async {
  final file = File(path);
  return await file.exists() ? file.length() : 0;
}

/// 记录写入次数并按当前生产实现执行真实物理备份（导出全库 + 原子替换）。
class CountingLocalDatabase extends LocalDatabase {
  CountingLocalDatabase({super.name, super.open, super.backup});

  int writeCalls = 0;

  @override
  Future<T> write<T>(
    Future<T> Function(Database) action, {
    bool recovery = false,
  }) {
    writeCalls++;
    return super.write(action, recovery: recovery);
  }
}

/// 模拟 `/api/planner/sync` 服务端契约。
///
/// [supportsUnchanged] 为 false 时模拟优化前/老服务端：忽略 `?revision` 并总是
/// 返回完整文档；为 true 时模拟问题七后的条件读取：revision 相等返回
/// `{revision, unchanged: true}`（不返回文档）。PUT 校验 expectedRevision 后
/// 递增 revision 并返回完整文档。
///
/// 计数在 HTTP 边界进行：请求数、请求体字节数、响应体字节数。
class PerfSyncServer {
  PerfSyncServer(
    this.document, {
    this.revision = 1,
    this.supportsUnchanged = false,
  });

  PlannerData? document;
  int revision;
  bool supportsUnchanged;
  bool offline = false;
  int getRequests = 0;
  int putRequests = 0;
  int requestBytes = 0;
  int responseBytes = 0;
  int failedRequests = 0;
  final List<int> statuses = [];

  int get requests => getRequests + putRequests + failedRequests;

  void resetCounters() {
    getRequests = 0;
    putRequests = 0;
    requestBytes = 0;
    responseBytes = 0;
    failedRequests = 0;
    statuses.clear();
  }

  Future<ResponseBody> handle(RequestOptions options) async {
    if (offline) {
      failedRequests++;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    if (options.method == 'GET') {
      getRequests++;
      requestBytes += utf8.encode(options.path).length;
      final query = options.queryParameters;
      if (query.isNotEmpty) {
        requestBytes += utf8.encode(
          Uri(queryParameters: query.map((k, v) => MapEntry(k, '$v'))).query,
        ).length;
      }
      final knownRevision = query['revision'];
      if (supportsUnchanged &&
          knownRevision is int &&
          knownRevision == revision) {
        return _respond({'revision': revision, 'unchanged': true});
      }
      return _respond({'data': document?.toJson(), 'revision': revision});
    }
    putRequests++;
    final body = options.data as Map;
    final payload = jsonEncode(body);
    requestBytes += utf8.encode(payload).length;
    final expected = body['expectedRevision'] as int;
    if (expected != revision) {
      statuses.add(409);
      return _respond(
        {'conflict': true, 'data': document?.toJson(), 'revision': revision},
        409,
      );
    }
    document = PlannerData.fromJson(JsonMap.from(body['data'] as Map));
    revision++;
    statuses.add(200);
    return _respond({'data': document!.toJson(), 'revision': revision});
  }

  ResponseBody _respond(Object body, [int status = 200]) {
    final encoded = jsonEncode(body);
    responseBytes += utf8.encode(encoded).length;
    return ResponseBody.fromString(
      encoded,
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }
}

/// 一份真实 IO Sembast 数据库 + 计数包装的物理备份 + 假同步服务端。
class PerfHarness {
  PerfHarness._({
    required this.directory,
    required this.databasePath,
    required this.database,
    required this.storage,
    required this.server,
    required this.adapter,
    required this.client,
    required this.coordinator,
  });

  final Directory directory;
  final String databasePath;
  final CountingLocalDatabase database;
  final SembastStorageRepository storage;
  final PerfSyncServer server;
  final TestAdapter adapter;
  final ApiClient client;
  final PlannerCoordinator coordinator;

  int physicalBackups = 0;
  final List<int> backupMicroseconds = [];

  String get key => coordinator.key;
  String get recoveryPath => '$databasePath.recovery.json';

  static Future<PerfHarness> create({
    required PlannerData remote,
    bool seedLocal = true,
    bool supportsUnchanged = false,
    Duration uploadDebounce = const Duration(milliseconds: 500),
    Duration uploadMaxWait = const Duration(seconds: 1),
  }) async {
    final directory = await Directory.systemTemp.createTemp('planner-perf-');
    final databasePath = '${directory.path}/planner.db';
    late PerfHarness harness;
    final database = CountingLocalDatabase(
      open: () => openPlannerDatabase(databasePath),
      backup: (db) async {
        final watch = Stopwatch()..start();
        await backupPlannerDatabase(db);
        watch.stop();
        harness.physicalBackups++;
        harness.backupMicroseconds.add(watch.elapsedMicroseconds);
      },
    );
    final storage = SembastStorageRepository(database: database);
    final server = PerfSyncServer(remote, supportsUnchanged: supportsUnchanged);
    final adapter = TestAdapter(server.handle);
    final client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://perf.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()..httpClientAdapter = adapter,
      usesBearer: false,
    );
    final coordinator = PlannerCoordinator(
      userId: remote.profile.userId,
      scope: 'perf',
      storage: storage,
      api: HttpSyncApi(client),
      retryInterval: null,
      uploadDebounce: uploadDebounce,
      uploadMaxWait: uploadMaxWait,
    );
    harness = PerfHarness._(
      directory: directory,
      databasePath: databasePath,
      database: database,
      storage: storage,
      server: server,
      adapter: adapter,
      client: client,
      coordinator: coordinator,
    );
    if (seedLocal) {
      // 模拟“本机与云端已一致”的稳定状态，不计入后续测量。
      await storage.save(
        coordinator.key,
        remote,
        StorageMetadata(
          revision: server.revision,
          base: remote,
          updatedAt: DateTime.utc(2026, 10, 16),
        ),
      );
      harness.resetCounters();
    }
    return harness;
  }

  void resetCounters() {
    server.resetCounters();
    physicalBackups = 0;
    backupMicroseconds.clear();
    database.writeCalls = 0;
  }

  Map<String, Object?> counters({required int elapsedMilliseconds}) => {
    'requests': server.requests,
    'getRequests': server.getRequests,
    'putRequests': server.putRequests,
    'failedRequests': server.failedRequests,
    'requestBytes': server.requestBytes,
    'responseBytes': server.responseBytes,
    'localWrites': database.writeCalls,
    'physicalBackups': physicalBackups,
    'backupElapsedMs': backupMicroseconds.fold<int>(
      0,
      (sum, value) => sum + value,
    ) /
        1000,
    'elapsedMs': elapsedMilliseconds,
  };

  Future<Map<String, Object?>> storageSizes() async => {
    'databaseBytes': await fileBytes(databasePath),
    'recoveryBytes': await fileBytes(recoveryPath),
  };

  /// 等待合并上传窗口触发的同步把 pending 清空（不依赖固定 sleep 次数）。
  Future<void> waitUntilUploaded({Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while ((coordinator.busy || coordinator.pending) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (coordinator.busy || coordinator.pending) {
      throw StateError(
        '上传未在超时前完成: busy=${coordinator.busy} '
        'pending=${coordinator.pending} status=${coordinator.status} '
        'message=${coordinator.message} requests=${server.requests} '
        'pushes=${server.putRequests}',
      );
    }
  }

  Future<void> dispose() async {
    coordinator.dispose();
    client.close();
    await database.close();
  }
}
