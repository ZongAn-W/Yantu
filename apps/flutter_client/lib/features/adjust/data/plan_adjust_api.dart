import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/http/api_client.dart';
import '../../../core/providers.dart';
import '../../../shared/models/planner_models.dart';

/// AI 对「目标所需学习时长 vs 当前计划」的审查结论。
enum PlanAdjustVerdict {
  reasonable('reasonable', '合理'),
  tooLight('too_light', '强度/总量偏轻'),
  tooHeavy('too_heavy', '强度偏重');

  const PlanAdjustVerdict(this.wire, this.label);

  /// 服务端 JSON 中的取值。
  final String wire;

  /// 预览对话框展示的中文结论。
  final String label;

  static PlanAdjustVerdict parse(Object? value) {
    for (final verdict in values) {
      if (verdict.wire == value) return verdict;
    }
    throw const ResponseFailure('调整方案缺少有效的 verdict 字段');
  }
}

/// 规划周期变化：开始日期不变，只延长或缩短结束日期。
class PlanAdjustCycle {
  const PlanAdjustCycle({
    required this.startDate,
    required this.previousEndDate,
    required this.endDate,
    required this.previousDays,
    required this.days,
    required this.remainingDays,
  });

  factory PlanAdjustCycle.fromJson(JsonMap json) => PlanAdjustCycle(
    startDate: _asString(json, 'cycle.start_date'),
    previousEndDate: _asString(json, 'cycle.previous_end_date'),
    endDate: _asString(json, 'cycle.end_date'),
    previousDays: _asInt(json, 'cycle.previous_days'),
    days: _asInt(json, 'cycle.days'),
    remainingDays: _asInt(json, 'cycle.remaining_days'),
  );

  final String startDate;
  final String previousEndDate;
  final String endDate;
  final int previousDays;
  final int days;
  final int remainingDays;

  /// 新周期相对旧周期的天数变化（正数为延长）。
  int get deltaDays => days - previousDays;
}

/// 总学习时长对比（分钟）：当前计划、调整后计划与目标所需区间。
class PlanAdjustHours {
  const PlanAdjustHours({
    required this.currentMinutes,
    required this.nextMinutes,
    required this.remainingMinutes,
    required this.requiredMinMinutes,
    required this.requiredMaxMinutes,
  });

  factory PlanAdjustHours.fromJson(JsonMap json) => PlanAdjustHours(
    currentMinutes: _asInt(json, 'hours.current_minutes'),
    nextMinutes: _asInt(json, 'hours.next_minutes'),
    remainingMinutes: _asInt(json, 'hours.remaining_minutes'),
    requiredMinMinutes: _asInt(json, 'hours.required_min_minutes'),
    requiredMaxMinutes: _asInt(json, 'hours.required_max_minutes'),
  );

  final int currentMinutes;
  final int nextMinutes;
  final int remainingMinutes;
  final int requiredMinMinutes;
  final int requiredMaxMinutes;
}

/// 学习强度变化：一周七天可用分钟模板的旧值与新值。
///
/// `legacy_default` 口径的旧计划没有可比较的周容量，服务端返回 null，
/// 预览显示「未设置」。
class PlanAdjustIntensity {
  const PlanAdjustIntensity({
    required this.previousWeeklyMinutes,
    required this.weeklyMinutes,
    required this.reason,
  });

  factory PlanAdjustIntensity.fromJson(JsonMap json) => PlanAdjustIntensity(
    previousWeeklyMinutes: _asNullableInt(
      json,
      'intensity.previous_weekly_minutes',
    ),
    weeklyMinutes: _asNullableInt(json, 'intensity.weekly_minutes'),
    reason: _asString(json, 'intensity.reason'),
  );

  final int? previousWeeklyMinutes;
  final int? weeklyMinutes;
  final String reason;
}

/// 工作量变化中的「调整已有事项」。
class PlanAdjustUpdatedTask {
  const PlanAdjustUpdatedTask({
    required this.taskId,
    required this.title,
    required this.subject,
    required this.previousMinutes,
    required this.minutes,
    required this.reason,
  });

  factory PlanAdjustUpdatedTask.fromJson(JsonMap json) => PlanAdjustUpdatedTask(
    taskId: _asString(json, 'workload.updated_tasks[].task_id'),
    title: _asString(json, 'workload.updated_tasks[].title'),
    subject: _asString(json, 'workload.updated_tasks[].subject'),
    previousMinutes: _asInt(json, 'workload.updated_tasks[].previous_minutes'),
    minutes: _asInt(json, 'workload.updated_tasks[].minutes'),
    reason: _asString(json, 'workload.updated_tasks[].reason'),
  );

  final String taskId;
  final String title;
  final String subject;
  final int previousMinutes;
  final int minutes;
  final String reason;
}

/// 工作量变化中的「新增事项」（用于补齐目标所需学习量）。
class PlanAdjustNewTask {
  const PlanAdjustNewTask({
    required this.title,
    required this.subject,
    required this.minutes,
    required this.deadlineKind,
    required this.deadline,
    required this.reason,
  });

  factory PlanAdjustNewTask.fromJson(JsonMap json) => PlanAdjustNewTask(
    title: _asString(json, 'workload.new_tasks[].title'),
    subject: _asString(json, 'workload.new_tasks[].subject'),
    minutes: _asInt(json, 'workload.new_tasks[].minutes'),
    deadlineKind: _asDateKind(json, 'workload.new_tasks[].deadline_kind'),
    deadline: _asNullableString(json, 'workload.new_tasks[].deadline'),
    reason: _asString(json, 'workload.new_tasks[].reason'),
  );

  final String title;
  final String subject;
  final int minutes;
  final ItemDateKind deadlineKind;
  final String? deadline;
  final String reason;
}

/// 按课程汇总的工作量变化。
class PlanAdjustSubjectTotal {
  const PlanAdjustSubjectTotal({
    required this.subjectId,
    required this.name,
    required this.previousMinutes,
    required this.minutes,
  });

  factory PlanAdjustSubjectTotal.fromJson(JsonMap json) => PlanAdjustSubjectTotal(
    subjectId: _asString(json, 'workload.subjects[].subject_id'),
    name: _asString(json, 'workload.subjects[].name'),
    previousMinutes: _asInt(json, 'workload.subjects[].previous_minutes'),
    minutes: _asInt(json, 'workload.subjects[].minutes'),
  );

  final String subjectId;
  final String name;
  final int previousMinutes;
  final int minutes;
}

/// 事项总工作量与新增事项的变化。
class PlanAdjustWorkload {
  const PlanAdjustWorkload({
    required this.updatedTasks,
    required this.newTasks,
    required this.subjects,
  });

  factory PlanAdjustWorkload.fromJson(JsonMap json) => PlanAdjustWorkload(
    updatedTasks: [
      for (final row in _asMapList(json, 'workload.updated_tasks'))
        PlanAdjustUpdatedTask.fromJson(row),
    ],
    newTasks: [
      for (final row in _asMapList(json, 'workload.new_tasks'))
        PlanAdjustNewTask.fromJson(row),
    ],
    subjects: [
      for (final row in _asMapList(json, 'workload.subjects'))
        PlanAdjustSubjectTotal.fromJson(row),
    ],
  );

  final List<PlanAdjustUpdatedTask> updatedTasks;
  final List<PlanAdjustNewTask> newTasks;
  final List<PlanAdjustSubjectTotal> subjects;
}

/// 重新排程的影响：受保护的旧安排、被释放的安排、新排入的安排与仍未安排量。
class PlanAdjustSchedule {
  const PlanAdjustSchedule({
    required this.protectedBlocks,
    required this.releasedBlocks,
    required this.releasedMinutes,
    required this.addedBlocks,
    required this.addedMinutes,
    required this.unscheduledMinutes,
  });

  factory PlanAdjustSchedule.fromJson(JsonMap json) => PlanAdjustSchedule(
    protectedBlocks: _asInt(json, 'schedule.protected_blocks'),
    releasedBlocks: _asInt(json, 'schedule.released_blocks'),
    releasedMinutes: _asInt(json, 'schedule.released_minutes'),
    addedBlocks: _asInt(json, 'schedule.added_blocks'),
    addedMinutes: _asInt(json, 'schedule.added_minutes'),
    unscheduledMinutes: _asInt(json, 'schedule.unscheduled_minutes'),
  );

  final int protectedBlocks;
  final int releasedBlocks;
  final int releasedMinutes;
  final int addedBlocks;
  final int addedMinutes;
  final int unscheduledMinutes;
}

/// 调整后仍可能错过真实截止日期的事项。
class PlanAdjustDeadlineRisk {
  const PlanAdjustDeadlineRisk({
    required this.taskId,
    required this.title,
    required this.deadline,
    required this.unscheduledMinutes,
  });

  factory PlanAdjustDeadlineRisk.fromJson(JsonMap json) =>
      PlanAdjustDeadlineRisk(
        taskId: _asString(json, 'deadline_risks[].task_id'),
        title: _asString(json, 'deadline_risks[].title'),
        deadline: _asString(json, 'deadline_risks[].deadline'),
        unscheduledMinutes: _asInt(
          json,
          'deadline_risks[].unscheduled_minutes',
        ),
      );

  final String taskId;
  final String title;
  final String deadline;
  final int unscheduledMinutes;
}

/// 服务端返回的一次 AI 调整方案预览（契约 §3），确认前不写入任何数据。
class PlanAdjustPreview {
  const PlanAdjustPreview({
    required this.id,
    required this.baseRevision,
    required this.assessment,
    required this.verdict,
    required this.hours,
    required this.cycle,
    required this.intensity,
    required this.workload,
    required this.schedule,
    required this.deadlineRisks,
    required this.warnings,
    required this.notes,
  });

  factory PlanAdjustPreview.fromJson(JsonMap json) => PlanAdjustPreview(
    id: _asString(json, 'id'),
    baseRevision: _asInt(json, 'base_revision'),
    assessment: _asString(json, 'assessment'),
    verdict: PlanAdjustVerdict.parse(json['verdict']),
    hours: PlanAdjustHours.fromJson(_asMap(json['hours'], 'hours')),
    cycle: PlanAdjustCycle.fromJson(_asMap(json['cycle'], 'cycle')),
    intensity: PlanAdjustIntensity.fromJson(
      _asMap(json['intensity'], 'intensity'),
    ),
    workload: PlanAdjustWorkload.fromJson(
      _asMap(json['workload'], 'workload'),
    ),
    schedule: PlanAdjustSchedule.fromJson(
      _asMap(json['schedule'], 'schedule'),
    ),
    deadlineRisks: [
      for (final row in _asMapList(json, 'deadline_risks'))
        PlanAdjustDeadlineRisk.fromJson(row),
    ],
    warnings: _asStringList(json, 'warnings'),
    notes: _asStringList(json, 'notes'),
  );

  final String id;
  final int baseRevision;
  final String assessment;
  final PlanAdjustVerdict verdict;
  final PlanAdjustHours hours;
  final PlanAdjustCycle cycle;
  final PlanAdjustIntensity intensity;
  final PlanAdjustWorkload workload;
  final PlanAdjustSchedule schedule;
  final List<PlanAdjustDeadlineRisk> deadlineRisks;
  final List<String> warnings;
  final List<String> notes;

  /// 创建接口的 `id` 是权威任务 id，用它覆盖预览内可能缺失/重复的 id。
  PlanAdjustPreview withId(String value) => PlanAdjustPreview(
    id: value,
    baseRevision: baseRevision,
    assessment: assessment,
    verdict: verdict,
    hours: hours,
    cycle: cycle,
    intensity: intensity,
    workload: workload,
    schedule: schedule,
    deadlineRisks: deadlineRisks,
    warnings: warnings,
    notes: notes,
  );
}

/// 调整预览与确认接口。测试通过覆盖 [planAdjustApiProvider] 传入 fake。
abstract interface class PlanAdjustApi {
  /// 基于云端快照生成一次 AI 调整预览；[requestId] 同时作为幂等键。
  Future<PlanAdjustPreview> create({
    required int expectedRevision,
    required String requestId,
  });

  /// 确认并让服务端原子写入该预览；revision 不一致时抛出 `ConflictFailure`。
  Future<void> confirm(String id, {required int expectedRevision});
}

class HttpPlanAdjustApi implements PlanAdjustApi {
  HttpPlanAdjustApi(this.client);

  final ApiClient client;

  @override
  Future<PlanAdjustPreview> create({
    required int expectedRevision,
    required String requestId,
  }) async {
    final response = await client.post(
      '/api/ai/plan-adjustments',
      data: {'expectedRevision': expectedRevision, 'requestId': requestId},
      options: Options(headers: {'Idempotency-Key': requestId}),
    );
    try {
      final body = _asMap(response.data, '响应');
      final id = body['id'];
      if (id is! String || id.isEmpty) {
        throw const ResponseFailure('服务器未返回调整任务 ID');
      }
      return PlanAdjustPreview.fromJson(
        _asMap(body['preview'], 'preview'),
      ).withId(id);
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const ResponseFailure();
    }
  }

  @override
  Future<void> confirm(String id, {required int expectedRevision}) async {
    final response = await client.post(
      '/api/ai/plan-adjustments/${Uri.encodeComponent(id)}/confirm',
      data: {'expectedRevision': expectedRevision},
    );
    final data = response.data;
    if (data is! Map || data['confirmed'] != true) {
      throw const ResponseFailure('服务器未确认调整已应用');
    }
  }
}

final planAdjustApiProvider = Provider<PlanAdjustApi>(
  (ref) => HttpPlanAdjustApi(ref.watch(apiClientProvider)),
);

// ------------------------------------------------------------------ JSON 解析

JsonMap _asMap(Object? value, String field) {
  if (value is! Map) throw ResponseFailure('调整预览的 $field 字段缺失或格式不正确');
  try {
    return JsonMap.from(value);
  } catch (_) {
    throw ResponseFailure('调整预览的 $field 字段格式不正确');
  }
}

/// 必需的整数字段：缺失、null 或类型错误都必须报错，不能静默当 0。
int _asInt(JsonMap json, String field) {
  final value = json[field.split('.').last];
  if (value is! int) throw ResponseFailure('调整预览的 $field 字段缺失或类型错误');
  return value;
}

/// 可空的整数字段（契约里明确允许 null，例如旧计划的周容量）。
int? _asNullableInt(JsonMap json, String field) {
  final key = field.split('.').last;
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw ResponseFailure('调整预览的 $field 字段类型错误');
  return value;
}

String _asString(JsonMap json, String field) {
  final value = json[field.split('.').last];
  if (value is! String) throw ResponseFailure('调整预览的 $field 字段缺失或类型错误');
  return value;
}

String? _asNullableString(JsonMap json, String field) {
  final key = field.split('.').last;
  if (!json.containsKey(key)) return null;
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw ResponseFailure('调整预览的 $field 字段类型错误');
  return value;
}

ItemDateKind _asDateKind(JsonMap json, String field) {
  switch (json[field.split('.').last]) {
    case 'deadline':
      return ItemDateKind.deadline;
    case 'plan_end':
      return ItemDateKind.planEnd;
  }
  throw ResponseFailure('调整预览的 $field 字段缺失或类型错误');
}

List<JsonMap> _asMapList(JsonMap json, String field) {
  final key = field.split('.').last;
  final value = json[key];
  if (value is! List) throw ResponseFailure('调整预览的 $field 字段缺失或类型错误');
  return [
    for (var index = 0; index < value.length; index++)
      _asMap(value[index], '$field[$index]'),
  ];
}

List<String> _asStringList(JsonMap json, String field) {
  final value = json[field.split('.').last];
  if (value is! List) throw ResponseFailure('调整预览的 $field 字段缺失或类型错误');
  final result = <String>[];
  for (var index = 0; index < value.length; index++) {
    final item = value[index];
    if (item is! String) {
      throw ResponseFailure('调整预览的 $field[$index] 字段类型错误');
    }
    result.add(item);
  }
  return result;
}
