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
  ids(data.adHocLearnings.map((row) => row.id));
  final owner = data.profile.userId,
      subjects = data.subjects.map((row) => row.id).toSet(),
      tasks = data.tasks.map((row) => row.id).toSet(),
      adHocLearnings = {for (final row in data.adHocLearnings) row.id: row},
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
  // 临时学习实体：只能属于当前账号，可选分类与转换后的正式事项都必须真实存在。
  for (final row in data.adHocLearnings) {
    if (row.userId != owner || row.title.trim().isEmpty) {
      throw const FormatException('临时学习内容或账号标识无效');
    }
    if (row.subjectId != null && !subjects.contains(row.subjectId)) {
      throw const FormatException('临时学习引用的课程无效');
    }
    if (row.convertedTaskId != null && !tasks.contains(row.convertedTaskId)) {
      throw const FormatException('临时学习关联的正式事项无效');
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
    final taskId = row.taskId, adHocId = row.adHocId;
    // 每条记录必须能归属到正式事项或临时学习实体之一：临时学习没有正式事项，
    // 旧数据也不会出现两个归属都缺失的记录。关系分类与归属必须自洽，
    // 但不能要求 scheduled/extra 一定要有 block（计时产生的日志本来就没有 block）。
    if (row.userId != owner ||
        row.minutes < 0 ||
        (taskId == null && adHocId == null) ||
        (taskId != null && !tasks.contains(taskId)) ||
        (adHocId != null && !adHocLearnings.containsKey(adHocId)) ||
        (row.blockId != null &&
            (taskId == null || blocks[row.blockId]?.taskId != taskId)) ||
        (row.relation == TimeLogRelation.adHoc && adHocId == null) ||
        (row.sessionId != null && row.sessionId!.isEmpty) ||
        (row.quotaMinutes != null && row.quotaMinutes! < 0)) {
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
  void capacityMinutes(int value, {int max = 10080}) {
    if (value < 0 || value > max) {
      throw const FormatException('容量设置无效');
    }
  }

  final profile = data.profile;
  for (final value in [
    profile.weeklyBaselineMinutes,
    profile.weeklyRangeMinMinutes,
    profile.weeklyRangeMaxMinutes,
  ]) {
    if (value != null) capacityMinutes(value);
  }
  // 特定周覆盖的键是上海时区的周一日期（YYYY-MM-DD）；跨月/跨年同一周只认一个键。
  for (final entry
      in profile.weekCapacityOverrides?.entries ??
          <MapEntry<String, WeekCapacityOverride>>[]) {
    date(entry.key);
    if (DateTime.parse('${entry.key}T00:00:00Z').weekday != DateTime.monday) {
      throw const FormatException('周容量覆盖的周标识无效');
    }
    final total = entry.value.totalMinutes;
    if (total != null) capacityMinutes(total);
    for (final day in entry.value.days?.entries ?? <MapEntry<String, int>>[]) {
      final index = int.tryParse(day.key);
      if (index == null || index < 0 || index > 6) {
        throw const FormatException('周容量覆盖的星期标识无效');
      }
      capacityMinutes(day.value, max: 1440);
    }
  }
  // 日期覆盖的键必须是有效日期；显式 0 合法（休息日），缺失表示恢复上层规则。
  for (final entry
      in profile.dateCapacityOverrides?.entries ?? <MapEntry<String, int>>[]) {
    date(entry.key);
    capacityMinutes(entry.value, max: 1440);
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
                        'ad_hoc_id',
                        'converted_task_id',
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
