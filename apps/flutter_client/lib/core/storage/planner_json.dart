import 'dart:convert';
import '../../shared/models/planner_models.dart';

PlannerData parsePlannerJson(String source) {
  final raw = jsonDecode(source);
  if (raw is! Map) throw const FormatException('请选择有效的计划 JSON 文件');
  final json = JsonMap.from(raw);
  final value = json.containsKey('data') ? json['data'] : json;
  if (json['version'] != 1 || value is! Map) {
    throw const FormatException('本地数据版本不兼容');
  }
  final data = PlannerData.fromJson(JsonMap.from(value));
  validatePlanner(data);
  return data;
}

void validatePlanner(PlannerData data) {
  if (data.version != 1) throw const FormatException('本地数据版本不兼容');
  void ids(Iterable<String> values) {
    final rows = values.toList();
    if (rows.any((id) => id.isEmpty) || rows.toSet().length != rows.length) {
      throw const FormatException('计划包含重复或空标识');
    }
  }

  void date(String value) {
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw const FormatException('计划日期无效');
    }
  }

  ids(data.subjects.map((row) => row.id));
  ids(data.tasks.map((row) => row.id));
  ids(data.blocks.map((row) => row.id));
  ids(data.logs.map((row) => row.id));
  ids(data.fixedEvents.map((row) => row.id));
  ids(data.replanRuns.map((row) => row.id));
  final owner = data.profile.userId,
      subjects = data.subjects.map((row) => row.id).toSet(),
      tasks = data.tasks.map((row) => row.id).toSet(),
      blocks = {for (final row in data.blocks) row.id: row};
  if (data.planning != null && data.planning!['version'] != 1) {
    throw const FormatException('学习策略版本不兼容');
  }
  if (owner.isEmpty) throw const FormatException('计划缺少账号标识');
  for (final row in data.subjects) {
    if (row.userId != owner) throw const FormatException('计划账号不一致');
  }
  for (final row in data.tasks) {
    final workload = row.planning?['workload'];
    if (data.planning != null && workload is Map) {
      final components = workload['components'];
      if (components is! List || components.isEmpty) {
        throw const FormatException('工作量组成不能为空');
      }
      var total = 0.0;
      for (final component in components) {
        if (component is! Map ||
            component['quantity'] is! num ||
            component['minutes_per_unit'] is! num) {
          throw const FormatException('工作量数量或单位时长无效');
        }
        final quantity = (component['quantity'] as num).toDouble();
        final price = (component['minutes_per_unit'] as num).toDouble();
        if (!quantity.isFinite ||
            !price.isFinite ||
            quantity <= 0 ||
            price <= 0) {
          throw const FormatException('工作量数量或单位时长无效');
        }
        if (component['selected'] != false) total += quantity * price;
      }
      final activity = row.planning?['activity'];
      final expected = activity is Map && activity['kind'] == 'recurring'
          ? activity['session_minutes']
          : row.estimatedMinutes;
      if (total.ceil() != expected) {
        throw const FormatException('预算与工作量不一致，请在访谈中调整学习范围后重新预览');
      }
    }
    if (row.userId != owner ||
        !subjects.contains(row.subjectId) ||
        row.estimatedMinutes <= 0 ||
        row.completedMinutes < 0) {
      throw const FormatException('事项内容或课程引用无效');
    }
    date(row.deadline);
    final dependencies = row.planning?['dependencies'];
    if (dependencies != null &&
        (dependencies is! List ||
            dependencies.any(
              (dependency) =>
                  dependency is! Map ||
                  !tasks.contains(dependency['task_id']) ||
                  dependency['task_id'] == row.id,
            ))) {
      throw const FormatException('前置事项引用无效');
    }
    if (row.earliestDate != null) {
      date(row.earliestDate!);
      if (row.earliestDate!.compareTo(row.deadline) > 0) {
        throw const FormatException('事项开始日期晚于截止日期');
      }
    }
  }
  final byTask = {for (final task in data.tasks) task.id: task};
  final visiting = <String>{}, visited = <String>{};
  bool hasCycle(String id) {
    if (visiting.contains(id)) return true;
    if (visited.contains(id)) return false;
    visiting.add(id);
    final dependencies = byTask[id]?.planning?['dependencies'] as List? ?? [];
    if (dependencies.any(
      (dependency) => hasCycle(dependency['task_id'] as String),
    )) {
      return true;
    }
    visiting.remove(id);
    visited.add(id);
    return false;
  }

  if (data.tasks.any((task) => hasCycle(task.id))) {
    throw const FormatException('前置事项存在循环依赖');
  }
  final route = data.planning?['route'];
  if (route != null) {
    if (route is! List) throw const FormatException('学习路线格式无效');
    for (final stage in route) {
      if (stage is! Map ||
          stage['item_ids'] is! List ||
          (stage['item_ids'] as List).any((id) => !tasks.contains(id))) {
        throw const FormatException('学习路线引用无效');
      }
    }
  }
  final instances = <String, String>{};
  for (final row in data.blocks) {
    date(row.date);
    if (row.userId != owner ||
        !tasks.contains(row.taskId) ||
        row.durationMinutes <= 0 ||
        row.actualMinutes < 0) {
      throw const FormatException('日程内容或事项引用无效');
    }
    if (row.activityInstanceId != null) {
      final identity = '${row.taskId}:${row.activityInstanceId}';
      if (instances.containsKey(identity) && instances[identity] != row.date) {
        throw const FormatException('同一活动实例不能重复安排到不同日期');
      }
      instances[identity] = row.date;
    }
  }
  for (final row in data.logs) {
    date(row.date);
    if (row.userId != owner ||
        !tasks.contains(row.taskId) ||
        row.minutes < 0 ||
        (row.blockId != null && blocks[row.blockId]?.taskId != row.taskId)) {
      throw const FormatException('学习日志引用无效');
    }
  }
  for (final row in data.fixedEvents) {
    date(row.date);
    if (row.userId != owner ||
        row.startMinute < 0 ||
        row.startMinute > 1440 ||
        row.durationMinutes <= 0) {
      throw const FormatException('固定事件格式无效');
    }
  }
  for (final row in data.replanRuns) {
    if (row.userId != owner) throw const FormatException('重排历史账号不一致');
  }
  // 可选日期：空字符串表示“没有这个日期”，不再用占位日期冒充。
  for (final value in [
    data.profile.targetDate,
    data.profile.examDate,
    data.profile.planStartDate,
    data.profile.planEndDate,
    data.profile.examEndDate,
  ]) {
    if (value.isNotEmpty) date(value);
  }
  for (final value in data.dailyFeedback?.keys ?? <String>[]) {
    date(value);
  }
}

PlannerData forAccount(PlannerData data, String userId) {
  if (data.profile.userId == userId) return data;
  String mapped(String id) => '$userId::$id';
  dynamic retag(dynamic value) {
    if (value is List) return value.map(retag).toList();
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map(
          (key, item) => MapEntry(
            key,
            key == 'user_id'
                ? userId
                : [
                        'id',
                        'task_id',
                        'block_id',
                        'subject_id',
                        'run_id',
                      ].contains(key) &&
                      item is String
                ? mapped(item)
                : ['postponed', 'advanced', 'item_ids'].contains(key) &&
                      item is List
                ? item.map((id) => mapped(id as String)).toList()
                : retag(item),
          ),
        ),
      );
    }
    return value;
  }

  return PlannerData.fromJson(JsonMap.from(retag(data.toJson()) as Map));
}
