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
  if (owner.isEmpty) throw const FormatException('计划缺少账号标识');
  for (final row in data.subjects) {
    if (row.userId != owner) throw const FormatException('计划账号不一致');
  }
  for (final row in data.tasks) {
    if (row.userId != owner ||
        !subjects.contains(row.subjectId) ||
        row.estimatedMinutes <= 0 ||
        row.completedMinutes < 0) {
      throw const FormatException('事项内容或课程引用无效');
    }
    date(row.deadline);
    if (row.earliestDate != null) {
      date(row.earliestDate!);
      if (row.earliestDate!.compareTo(row.deadline) > 0) {
        throw const FormatException('事项开始日期晚于截止日期');
      }
    }
  }
  for (final row in data.blocks) {
    date(row.date);
    if (row.userId != owner ||
        !tasks.contains(row.taskId) ||
        row.durationMinutes <= 0 ||
        row.actualMinutes < 0) {
      throw const FormatException('日程内容或事项引用无效');
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
                : ['postponed', 'advanced'].contains(key) && item is List
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
