import '../errors/app_failure.dart';
import '../http/api_client.dart';
import '../storage/planner_json.dart';
import '../../shared/models/planner_models.dart';

/// 服务端要求升级客户端后才能同步时的提示。
///
/// 云端可能保存了旧版本无法表达的学习记录（例如没有正式事项的临时学习计时）。
/// 客户端必须保留本机 pending 数据、不把 426 当普通冲突，也不要用旧结构覆盖云端。
const String syncUpgradeRequiredMessage = '云端数据包含更新版本的学习记录，请升级客户端后再同步；本机数据已保留';

/// 把服务端的 426/升级信号映射为统一失败；其他失败原样返回。
AppFailure mapSyncFailure(Object error) {
  if (error is ValidationFailure && error.statusCode == 426) {
    return ValidationFailure(
      error.message.isEmpty
          ? syncUpgradeRequiredMessage
          : '${error.message}（本机数据已保留）',
      statusCode: 426,
    );
  }
  return error is AppFailure ? error : const ResponseFailure();
}

class RemoteSnapshot {
  const RemoteSnapshot(
    this.data,
    this.revision, {
    this.conflict = false,
    this.unchanged = false,
  });
  final PlannerData? data;
  final int revision;
  final bool conflict;

  /// 服务端确认自客户端已知 revision 起没有任何变化，因此没有返回完整文档。
  ///
  /// `unchanged == true` 时 [data] 必然为 null，但它**不表示云端计划被删除**；
  /// 调用方必须优先检查该标记，只有完整响应里的 null 才是“云端没有计划”。
  final bool unchanged;
}

abstract interface class SyncApi {
  /// 拉取云端快照。
  ///
  /// [revision] 是客户端已知的同步版本号。支持条件读取的服务端在版本一致时
  /// 返回 `{revision, unchanged: true}`（不生成完整文档）；老服务端会忽略该
  /// 参数并返回完整文档，调用方照常处理，因此该参数保持向前/向后兼容。
  Future<RemoteSnapshot> pull({int? revision});
  Future<RemoteSnapshot> push(
    PlannerData data,
    PlannerData? base,
    int revision,
  );
}

JsonMap plannerDocumentForSync(PlannerData data, PlannerData? base) {
  final result = data.toJson();
  if (data.planning == null && base?.planning != null) {
    result['planning'] = null;
  }
  // 新字段在全局 `include_if_null: false` 下会从 JSON 中消失，而服务端把
  // “键缺失”当作“旧写入方无法表达，保留云端旧值”。因此本机显式清空时必须
  // 补一个 null，否则清除容量覆盖/会话关联会被云端旧值悄悄复活。
  final profile = result['profile'] as JsonMap;
  final previousProfile = base?.profile;
  if (previousProfile != null) {
    if (!profile.containsKey('weekly_baseline_minutes') &&
        previousProfile.weeklyBaselineMinutes != null) {
      profile['weekly_baseline_minutes'] = null;
    }
    if (!profile.containsKey('weekly_range_min_minutes') &&
        previousProfile.weeklyRangeMinMinutes != null) {
      profile['weekly_range_min_minutes'] = null;
    }
    if (!profile.containsKey('weekly_range_max_minutes') &&
        previousProfile.weeklyRangeMaxMinutes != null) {
      profile['weekly_range_max_minutes'] = null;
    }
    if (!profile.containsKey('week_capacity_overrides') &&
        previousProfile.weekCapacityOverrides != null) {
      profile['week_capacity_overrides'] = null;
    }
    if (!profile.containsKey('date_capacity_overrides') &&
        previousProfile.dateCapacityOverrides != null) {
      profile['date_capacity_overrides'] = null;
    }
  }
  final tasks = {for (final task in base?.tasks ?? <Task>[]) task.id: task};
  for (final row in result['tasks'] as List) {
    if (!row.containsKey('planning') && tasks[row['id']]?.planning != null) {
      row['planning'] = null;
    }
  }
  final blocks = {
    for (final block in base?.blocks ?? <ScheduleBlock>[]) block.id: block,
  };
  for (final row in result['blocks'] as List) {
    if (!row.containsKey('activity_instance_id') &&
        blocks[row['id']]?.activityInstanceId != null) {
      row['activity_instance_id'] = null;
    }
  }
  final logs = {for (final log in base?.logs ?? <TimeLog>[]) log.id: log};
  for (final row in result['logs'] as List) {
    final previous = logs[row['id']];
    if (previous == null) continue;
    if (!row.containsKey('session_id') && previous.sessionId != null) {
      row['session_id'] = null;
    }
    if (!row.containsKey('ad_hoc_id') && previous.adHocId != null) {
      row['ad_hoc_id'] = null;
    }
    if (!row.containsKey('quota_minutes') && previous.quotaMinutes != null) {
      row['quota_minutes'] = null;
    }
  }
  return result;
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
      final revision = value['revision'] as int;
      if (value.containsKey('unchanged') && value['unchanged'] is! bool) {
        throw const FormatException('同步无变化标记异常');
      }
      if (value['unchanged'] == true) {
        if (value['data'] != null) throw const FormatException('同步响应内容异常');
        return RemoteSnapshot(null, revision, unchanged: true);
      }
      final PlannerData? data = value['data'] == null
          ? null
          : PlannerData.fromJson(JsonMap.from(value['data'] as Map));
      if (data != null) validatePlanner(data);
      return RemoteSnapshot(data, revision);
    } catch (_) {
      // 解码失败可能因为云端来自更新版本（旧结构无法表达新记录）。保留本机
      // 数据并给出明确升级提示，而不是让上层误以为需要重建本地数据。
      throw const ResponseFailure(
        '云端返回的数据无法被当前版本识别，可能来自更新版本；本机数据已保留，请升级后重试',
      );
    }
  }

  @override
  Future<RemoteSnapshot> pull({int? revision}) async {
    try {
      return _parse(
        (await client.get(
          '/api/planner/sync',
          query: revision == null ? null : {'revision': revision},
        )).data,
      );
    } catch (error) {
      throw mapSyncFailure(error);
    }
  }

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
            'data': plannerDocumentForSync(data, base),
            'base': base?.toJson(),
            'expectedRevision': revision,
            // 新客户端的写作能力声明：服务端据此区分“能表达 relation/临时学习/
            // 容量覆盖”的写入方与旧客户端，避免把缺失当成删除。
            'writer_planning_version': 1,
            'writer_learning_version': 1,
          },
        )).data,
      );
    } on ConflictFailure {
      // A conflict still needs the full current document for resolution.
      final remote = await pull();
      return RemoteSnapshot(remote.data, remote.revision, conflict: true);
    } on AppFailure catch (error) {
      throw mapSyncFailure(error);
    }
  }
}
