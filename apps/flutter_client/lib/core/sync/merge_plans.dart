import 'dart:convert';
import '../../shared/models/planner_models.dart';
import '../storage/planner_json.dart';

class MergeResult {
  const MergeResult(this.data, this.conflicts);
  final PlannerData data;
  final List<String> conflicts;
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
    if (old is Map && left is Map && right is Map) {
      final result = <String, dynamic>{};
      for (final key in {...old.keys, ...left.keys, ...right.keys}) {
        if ([
          'completed_minutes',
          'actual_minutes',
          'created_at',
          'updated_at',
        ].contains(key)) {
          result[key as String] = left[key] ?? right[key];
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
    for (final id in {...right.keys, ...left.keys, ...old.keys}) {
      final row = merge(old[id], left[id], right[id], label);
      if (row != null) result.add(row);
    }
    return result;
  }

  final result = <String, dynamic>{
    'version': 1,
    'profile': merge(
      before['profile'],
      here['profile'],
      there['profile'],
      '学习目标设置',
    ),
    'phases': merge(before['phases'], here['phases'], there['phases'], '学习阶段'),
  };
  if ([before, here, there].any((json) => json['daily_feedback'] != null)) {
    result['daily_feedback'] = merge(
      before['daily_feedback'] ?? {},
      here['daily_feedback'] ?? {},
      there['daily_feedback'] ?? {},
      '每日反馈',
    );
  }
  for (final entry in {
    'subjects': '课程',
    'tasks': '事项',
    'blocks': '日程安排',
    'fixed_events': '固定事件',
    'replan_runs': '重排历史',
  }.entries) {
    result[entry.key] = rows(entry.key, entry.value);
  }
  String group(dynamic row) => '${row['task_id']}:${row['date']}';
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
  for (final key in {...oldLogs.keys, ...localLogs.keys, ...remoteLogs.keys}) {
    final old = oldLogs[key] ?? [],
        left = localLogs[key] ?? [],
        right = remoteLogs[key] ?? [];
    final changedLeft = !semanticallyEqual(left, old),
        changedRight = !semanticallyEqual(right, old);
    if (changedLeft && changedRight && !semanticallyEqual(left, right)) {
      conflicts.add('同一事项当天的累计用时');
    }
    logs.addAll(
      changedLeft ? ((changedRight && !preferLocal) ? right : left) : right,
    );
  }
  final taskRows = (result['tasks'] as List).cast<Map>();
  final subjectRows = (result['subjects'] as List).cast<Map>();
  final blockRows = (result['blocks'] as List).cast<Map>();
  // Preserve locally changed children when another device removed their parent.
  for (final row in [...blockRows, ...logs.cast<Map>()]) {
    if (taskRows.any((task) => task['id'] == row['task_id'])) continue;
    final localTask = local.tasks
        .where((task) => task.id == row['task_id'])
        .firstOrNull;
    final localChildren = [
      ...(here['blocks'] as List),
      ...(here['logs'] as List),
    ].where((child) => child['task_id'] == row['task_id']).toList();
    final baseChildren = [
      ...(before['blocks'] as List),
      ...(before['logs'] as List),
    ].where((child) => child['task_id'] == row['task_id']).toList();
    if (localTask != null && !semanticallyEqual(localChildren, baseChildren)) {
      conflicts.add('云端删除的事项仍有本机修改');
      if (preferLocal) taskRows.add(localTask.toJson());
    } else if (localTask == null) {
      final remoteTask = remote.tasks
          .where((task) => task.id == row['task_id'])
          .firstOrNull;
      final remoteChildren = [
        ...(there['blocks'] as List),
        ...(there['logs'] as List),
      ].where((child) => child['task_id'] == row['task_id']).toList();
      if (remoteTask != null &&
          !semanticallyEqual(remoteChildren, baseChildren)) {
        conflicts.add('本机删除的事项有云端学习记录');
        if (!preferLocal) taskRows.add(remoteTask.toJson());
      }
    }
  }
  for (final task in taskRows) {
    if (subjectRows.any((subject) => subject['id'] == task['subject_id'])) {
      continue;
    }
    final subject =
        local.subjects.where((s) => s.id == task['subject_id']).firstOrNull ??
        remote.subjects.where((s) => s.id == task['subject_id']).firstOrNull;
    if (subject != null) {
      conflicts.add('事项所属课程被云端删除');
      subjectRows.add(subject.toJson());
    }
  }
  final tasks = taskRows.map((row) => row['id']).toSet();
  result['tasks'] = taskRows;
  result['subjects'] = subjectRows;
  result['blocks'] = blockRows
      .where((row) => tasks.contains(row['task_id']))
      .toList();
  final blocks = (result['blocks'] as List).map((row) => row['id']).toSet();
  result['logs'] = logs
      .where((row) => tasks.contains(row['task_id']))
      .map(
        (row) => <String, dynamic>{
          ...JsonMap.from(row as Map),
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
      task['completed_minutes'] = total > (task['estimated_minutes'] as int)
          ? task['estimated_minutes']
          : total;
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
  return MergeResult(data, conflicts.toSet().toList());
}
