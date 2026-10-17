import '../errors/app_failure.dart';
import '../http/api_client.dart';
import '../storage/planner_json.dart';
import '../../shared/models/planner_models.dart';

class RemoteSnapshot {
  const RemoteSnapshot(this.data, this.revision, {this.conflict = false});
  final PlannerData? data;
  final int revision;
  final bool conflict;
}

abstract interface class SyncApi {
  Future<RemoteSnapshot> pull();
  Future<RemoteSnapshot> push(
    PlannerData data,
    PlannerData? base,
    int revision,
  );
}

class HttpSyncApi implements SyncApi {
  HttpSyncApi(this.client);
  final ApiClient client;

  /// Parses one sync response.
  ///
  /// A server document is validated with the same rules as local storage before it
  /// is handed to the coordinator: accepting a dangling task/subject/block
  /// reference here would persist an unusable plan instead of failing loudly.
  RemoteSnapshot _parse(dynamic value) {
    try {
      if (value is! Map || value['revision'] is! int || value['revision'] < 0) {
        throw const FormatException('同步版本号异常');
      }
      final PlannerData? data = value['data'] == null
          ? null
          : PlannerData.fromJson(JsonMap.from(value['data'] as Map));
      if (data != null) validatePlanner(data);
      return RemoteSnapshot(data, value['revision'] as int);
    } catch (_) {
      throw const ResponseFailure();
    }
  }

  @override
  Future<RemoteSnapshot> pull() async =>
      _parse((await client.get('/api/planner/sync')).data);
  @override
  Future<RemoteSnapshot> push(
    PlannerData data,
    PlannerData? base,
    int revision,
  ) async {
    try {
      return _parse(
        (await client.put(
          '/api/planner/sync',
          data: {
            'data': data.toJson(),
            'base': base?.toJson(),
            'expectedRevision': revision,
          },
        )).data,
      );
    } on ConflictFailure {
      final remote = await pull();
      return RemoteSnapshot(remote.data, remote.revision, conflict: true);
    }
  }
}
