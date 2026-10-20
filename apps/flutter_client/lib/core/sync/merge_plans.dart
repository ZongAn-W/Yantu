import 'dart:convert';
import '../../shared/models/planner_models.dart';
import '../storage/planner_json.dart';

/// One (task, day) or (temporary learning, day) group whose accumulated study
/// time was changed on both sides.
///
/// The timer uses this scope to discard exactly the local records the user chose
/// to give up when resolving a conflict, without touching other days or owners.
class LogConflict {
  const LogConflict(this.taskId, this.date, {this.adHocId});

  /// 归属事项；全新临时学习的计时冲突时为 null。
  final String? taskId;

  /// 临时学习实体；正式事项的计时冲突时为 null。
  final String? adHocId;
  final String date;

  @override
  bool operator ==(Object other) =>
      other is LogConflict &&
      other.taskId == taskId &&
      other.adHocId == adHocId &&
      other.date == date;

  @override
  int get hashCode => Object.hash(taskId, adHocId, date);

  @override
  String toString() => '${taskId ?? adHocId ?? '?'}@$date';
}

class MergeResult {
  const MergeResult(this.data, this.conflicts, {this.logConflicts = const []});
  final PlannerData data;
  final List<String> conflicts;
  final List<LogConflict> logConflicts;
}

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys =
        value.keys
            .cast<String>()
            .where((key) => !['created_at', 'updated_at'].contains(key))
            .toList()
          ..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

bool semanticallyEqual(Object? a, Object? b) =>
    jsonEncode(_canonical(a)) == jsonEncode(_canonical(b));

Map<String, dynamic> _withoutNullValues(Map map) => {
  for (final entry in map.entries)
    if (entry.value != null) entry.key as String: entry.value,
};

/// 容量覆盖是“键存在即权威、删除键=恢复上层规则”的映射；三路合并会把删除
/// 表达成 null 值，这里重建一份不含 null 的映射，避免写出无法反序列化的
/// JSON，也避免修改 freezed 模型持有的只读集合。
void _sanitizeCapacityOverrides(Map<dynamic, dynamic> profile) {
  final dates = profile['date_capacity_overrides'];
  if (dates is Map) {
    profile['date_capacity_overrides'] = _withoutNullValues(dates);
  }
  final weeks = profile['week_capacity_overrides'];
  if (weeks is Map) {
    final cleanedWeeks = <String, dynamic>{};
    for (final entry in weeks.entries) {
      final week = entry.value;
      if (week is! Map) continue;
      final cleanedWeek = <String, dynamic>{};
      for (final field in week.entries) {
        final value = field.value;
        if (value == null) continue;
        final key = field.key as String;
        cleanedWeek[key] = key == 'days' && value is Map
            ? _withoutNullValues(value)
            : value;
      }
      cleanedWeeks[entry.key as String] = cleanedWeek;
    }
    profile['week_capacity_overrides'] = cleanedWeeks;
  }
}

MergeResult mergePlans(
  PlannerData? base,
  PlannerData local,
  PlannerData? remote, {
  bool preferLocal = true,
}) {
  if (base == null || remote == null) {
    if (remote == null && base == null) return MergeResult(local, []);
    if (local == remote) return MergeResult(local, []);
    return MergeResult(preferLocal ? local : remote ?? local, ['学习计划缺少共同同步基线']);
  }
  final before = base.toJson(), here = local.toJson(), there = remote.toJson();
  final conflicts = <String>[];
  dynamic merge(dynamic old, dynamic left, dynamic right, String label) {
    if (semanticallyEqual(left, old)) return right;
    if (semanticallyEqual(right, old) || semanticallyEqual(left, right)) {
      return left;
    }
    if (old is List && left is List && right is List && label == '标签关联') {
      final beforeIds = old.whereType<String>().toSet();
      final leftIds = left.whereType<String>().toSet();
      final rightIds = right.whereType<String>().toSet();
      final removed = (beforeIds.difference(
        leftIds,
      )).union(beforeIds.difference(rightIds));
      final added = leftIds
          .difference(beforeIds)
          .union(rightIds.difference(beforeIds));
      return [...beforeIds.difference(removed).union(added)];
    }
    if (old is Map && left is Map && right is Map) {
      final result = <String, dynamic>{};
      // 以本机键顺序为主：没有实际变化时合并结果与原文档同序，乐观编辑的
      // jsonEncode 守卫不会因为键重排而误报“数据已变化”。
      for (final key in {...left.keys, ...old.keys, ...right.keys}) {
        if ([
          'completed_minutes',
          'actual_minutes',
          'created_at',
          'updated_at',
        ].contains(key)) {
          result[key as String] = left[key] ?? right[key];
          continue;
        }
        if (key == 'tag_ids') {
          result[key as String] = merge(
            old[key] ?? const [],
            left[key] ?? const [],
            right[key] ?? const [],
            '标签关联',
          );
          continue;
        }
        final next = merge(old[key], left[key], right[key], label);
        if (next != null || left.containsKey(key) || right.containsKey(key)) {
          result[key as String] = next;
        }
      }
      return result;
    }
    conflicts.add(label);
    return preferLocal ? left : right;
  }

  List<dynamic> rows(String key, String label) {
    final old = {for (final row in before[key] as List) row['id']: row},
        left = {for (final row in here[key] as List) row['id']: row},
        right = {for (final row in there[key] as List) row['id']: row};
    final result = <dynamic>[];
    for (final id in {...left.keys, ...old.keys, ...right.keys}) {
      final row = merge(old[id], left[id], right[id], label);
      if (row != null) result.add(row);
    }
    return result;
  }

  final profile = merge(
    before['profile'],
    here['profile'],
    there['profile'],
    '学习目标设置',
  );
  if (profile is Map) _sanitizeCapacityOverrides(profile);
  final result = <String, dynamic>{
    'version': 1,
    'profile': profile,
    'phases': merge(before['phases'], here['phases'], there['phases'], '学习阶段'),
  };
  if ([before, here, there].any((json) => json.containsKey('planning'))) {
    result['planning'] = merge(
      before['planning'],
      here['planning'],
      there['planning'],
      '学习路线与策略',
    );
  }
  if ([before, here, there].any((json) => json['daily_feedback'] != null)) {
    result['daily_feedback'] = merge(
      before['daily_feedback'] ?? {},
      here['daily_feedback'] ?? {},
      there['daily_feedback'] ?? {},
      '每日反馈',
    );
  }
  for (final entry in {
    'tags': '标签',
    'tasks': '事项',
    'blocks': '日程安排',
    'ad_hoc_learnings': '临时学习',
    'fixed_events': '固定事件',
    'replan_runs': '重排历史',
  }.entries) {
    result[entry.key] = rows(entry.key, entry.value);
  }
  // 同一归属（正式事项或临时学习实体）同一天的累计用时一起合并：scheduled 与
  // extra 段共享冲突范围，但不同临时学习实体的同名日期不会互相覆盖。
  String group(dynamic row) {
    final taskId = row['task_id'];
    if (taskId is String && taskId.isNotEmpty) {
      return 'task:$taskId:${row['date']}';
    }
    final adHocId = row['ad_hoc_id'];
    return 'ad_hoc:${adHocId is String ? adHocId : ''}:${row['date']}';
  }

  Map<String, List<dynamic>> groups(dynamic values) {
    final map = <String, List<dynamic>>{};
    for (final row in values as List) {
      map.putIfAbsent(group(row), () => []).add(row);
    }
    return map;
  }

  final oldLogs = groups(before['logs']),
      localLogs = groups(here['logs']),
      remoteLogs = groups(there['logs']);
  final logs = <dynamic>[];
  final logConflicts = <LogConflict>{};
  for (final key in {...localLogs.keys, ...oldLogs.keys, ...remoteLogs.keys}) {
    final old = oldLogs[key] ?? [],
        left = localLogs[key] ?? [],
        right = remoteLogs[key] ?? [];
    final changedLeft = !semanticallyEqual(left, old),
        changedRight = !semanticallyEqual(right, old);
    if (changedLeft && changedRight && !semanticallyEqual(left, right)) {
      conflicts.add(
        key.startsWith('ad_hoc:') ? '同一临时学习当天的累计用时' : '同一事项当天的累计用时',
      );
      final sample = (left.isNotEmpty ? left : right).first as Map;
      final taskId = sample['task_id'],
          adHocId = sample['ad_hoc_id'],
          date = sample['date'];
      if (date is String) {
        if (taskId is String && taskId.isNotEmpty) {
          logConflicts.add(LogConflict(taskId, date));
        } else if (adHocId is String && adHocId.isNotEmpty) {
          logConflicts.add(LogConflict(null, date, adHocId: adHocId));
        }
      }
    }
    logs.addAll(
      changedLeft ? ((changedRight && !preferLocal) ? right : left) : right,
    );
  }
  final taskRows = (result['tasks'] as List).cast<Map>();
  final tagRows = (result['tags'] as List).cast<Map>();
  final blockRows = (result['blocks'] as List).cast<Map>();
  final adHocRows = (result['ad_hoc_learnings'] as List).cast<Map>();
  // Preserve locally changed children when another device removed their parent.
  for (final row in [...blockRows, ...logs.cast<Map>()]) {
    final ownerTask = row['task_id'];
    if (ownerTask == null) continue;
    if (taskRows.any((task) => task['id'] == ownerTask)) continue;
    final localTask = local.tasks
        .where((task) => task.id == ownerTask)
        .firstOrNull;
    final localChildren = [
      ...(here['blocks'] as List),
      ...(here['logs'] as List),
    ].where((child) => child['task_id'] == ownerTask).toList();
    final baseChildren = [
      ...(before['blocks'] as List),
      ...(before['logs'] as List),
    ].where((child) => child['task_id'] == ownerTask).toList();
    if (localTask != null && !semanticallyEqual(localChildren, baseChildren)) {
      conflicts.add('云端删除的事项仍有本机修改');
      if (preferLocal) taskRows.add(localTask.toJson());
    } else if (localTask == null) {
      final remoteTask = remote.tasks
          .where((task) => task.id == ownerTask)
          .firstOrNull;
      final remoteChildren = [
        ...(there['blocks'] as List),
        ...(there['logs'] as List),
      ].where((child) => child['task_id'] == ownerTask).toList();
      if (remoteTask != null &&
          !semanticallyEqual(remoteChildren, baseChildren)) {
        conflicts.add('本机删除的事项有云端学习记录');
        if (!preferLocal) taskRows.add(remoteTask.toJson());
      }
    }
  }
  // Resolve same-name tags created concurrently on different devices, then drop
  // references to deleted definitions without disturbing unrelated associations.
  final canonicalByName = <String, String>{};
  final canonicalById = <String, String>{};
  final uniqueTags = <Map>[];
  for (final tag in tagRows) {
    final name = (tag['name'] as String? ?? '').trim();
    final key = name.toLowerCase();
    final id = tag['id'] as String;
    final canonical = canonicalByName.putIfAbsent(key, () => id);
    canonicalById[id] = canonical;
    if (canonical == id) {
      tag['name'] = name;
      uniqueTags.add(tag);
    } else {
      conflicts.add('同名标签已合并');
    }
  }
  final validTags = uniqueTags.map((tag) => tag['id']).toSet();
  for (final task in taskRows) {
    final ids = (task['tag_ids'] as List? ?? const [])
        .whereType<String>()
        .map((id) => canonicalById[id] ?? id)
        .where(validTags.contains)
        .toSet()
        .toList(growable: false);
    task['tag_ids'] = ids;
  }
  // 临时学习实体与其历史记录必须成对存在：实体被另一台设备删除时恢复该实体，
  // 否则保留可归属的记录并退回 unknown 关系，避免整份合并结果不可读。
  final adHocIds = adHocRows.map((row) => row['id']).toSet();
  final droppedLogs = <Map>{};
  for (final row in logs.cast<Map>()) {
    final adHocId = row['ad_hoc_id'];
    if (adHocId is! String || adHocId.isEmpty || adHocIds.contains(adHocId)) {
      continue;
    }
    final candidates = preferLocal
        ? [...local.adHocLearnings, ...remote.adHocLearnings]
        : [...remote.adHocLearnings, ...local.adHocLearnings];
    final entity = candidates.where((item) => item.id == adHocId).firstOrNull;
    if (entity != null) {
      adHocRows.add(entity.toJson());
      adHocIds.add(adHocId);
      conflicts.add('临时学习关联被另一设备删除，历史记录已保留');
      continue;
    }
    row['ad_hoc_id'] = null;
    if (row['task_id'] == null) {
      droppedLogs.add(row);
      conflicts.add('临时学习记录失去归属，已跳过');
    } else if (row['relation'] == 'ad_hoc') {
      row['relation'] = 'legacy_unknown';
    }
  }
  final tasks = taskRows.map((row) => row['id']).toSet();
  result['tasks'] = taskRows;
  result['tags'] = uniqueTags;
  result['ad_hoc_learnings'] = adHocRows;
  result['blocks'] = blockRows
      .where((row) => tasks.contains(row['task_id']))
      .toList();
  final blocks = (result['blocks'] as List).map((row) => row['id']).toSet();
  final validAdHoc = adHocRows.map((row) => row['id']).toSet();
  result['logs'] = logs
      .cast<Map>()
      .where((row) {
        if (droppedLogs.contains(row)) return false;
        final taskId = row['task_id'];
        if (taskId != null && !tasks.contains(taskId)) return false;
        final adHocId = row['ad_hoc_id'];
        return adHocId == null || validAdHoc.contains(adHocId);
      })
      .map(
        (row) => <String, dynamic>{
          ...JsonMap.from(row),
          'block_id': blocks.contains(row['block_id']) ? row['block_id'] : null,
        },
      )
      .toList();
  for (final task in taskRows) {
    final records = (result['logs'] as List)
        .where((log) => log['task_id'] == task['id'])
        .toList();
    if (records.isNotEmpty ||
        [
          ...base.logs,
          ...local.logs,
          ...remote.logs,
        ].any((log) => log.taskId == task['id'])) {
      final total = records.fold<int>(
        0,
        (sum, log) => sum + (log['minutes'] as int),
      );
      task['completed_minutes'] = total;
    }
  }
  for (final block in result['blocks'] as List) {
    final records = (result['logs'] as List)
        .where((log) => log['block_id'] == block['id'])
        .toList();
    if (records.isNotEmpty ||
        [
          ...base.logs,
          ...local.logs,
          ...remote.logs,
        ].any((log) => log.blockId == block['id'])) {
      block['actual_minutes'] = records.fold<int>(
        0,
        (sum, log) => sum + (log['minutes'] as int),
      );
    }
  }
  final data = PlannerData.fromJson(result);
  validatePlanner(data);
  return MergeResult(
    data,
    conflicts.toSet().toList(),
    logConflicts: logConflicts.toList(),
  );
}
