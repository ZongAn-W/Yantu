import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'planner_models.freezed.dart';
part 'planner_models.g.dart';

typedef JsonMap = Map<String, dynamic>;

int _versionOne(Object? value) {
  if (value != 1) throw const FormatException('本地数据版本不兼容');
  return 1;
}

int _priority(Object? value) {
  if (value is! int || value < 1 || value > 3) {
    throw const FormatException('优先级格式异常');
  }
  return value;
}

/// 自然日加若干天，不依赖本地时区。
String addDateOnly(String date, int days) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null) return date;
  return dateOnlyOf(parsed.toUtc().add(Duration(days: days)));
}

/// 日期部分，用于自然日字符串。
String dateOnlyOf(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// 一周配置必须包含 0 到 6 七个键，且每项是 0 至 1440 的整数分钟。
bool isReliableWeek(Map<String, int>? value) {
  if (value == null || value.length != 7) return false;
  for (var day = 0; day < 7; day++) {
    final minutes = value['$day'];
    if (minutes == null || minutes < 0 || minutes > 1440) return false;
  }
  return true;
}

int _revision(Object? value) {
  if (value is! int || value < 0 || value > 9007199254740991) {
    throw const FormatException('同步版本号异常');
  }
  return value;
}

/// 通用目标类型：考试备考、课程学习、技能提升、自主学习、其他。
@JsonEnum(fieldRename: FieldRename.snake)
enum GoalType { exam, course, skill, selfStudy, other }

/// 事项日期的语义：真实截止日期，或本期安排边界。
@JsonEnum(fieldRename: FieldRename.snake)
enum ItemDateKind { deadline, planEnd }

@JsonEnum(fieldRename: FieldRename.snake)
enum TaskStatus {
  notStarted,
  inProgress,
  completed,
  delayed,
  conflict,
  archived,
}

enum PlanningMode { daily, timed }

enum BlockStatus { planned, completed }

@JsonEnum(fieldRename: FieldRename.snake)
enum CompletionStatus { notStarted, partial, completed, skipped }

enum LogSource { timer, manual }

@JsonEnum(fieldRename: FieldRename.snake)
enum FixedEventKind { course, exam, rest, officialExam }

enum EventRepeat { none, daily, weekly }

enum ChangeType { added, deleted, moved }

enum ReplanStatus { confirmed, undone }

enum ReplanMode { unfinished, overcompleted }

@freezed
abstract class PlannerData with _$PlannerData {
  const PlannerData._();
  const factory PlannerData({
    @JsonKey(fromJson: _versionOne) required int version,
    required Profile profile,
    required List<Subject> subjects,
    required List<Task> tasks,
    required List<ScheduleBlock> blocks,
    required List<TimeLog> logs,
    required List<FixedEvent> fixedEvents,
    required List<ReplanRun> replanRuns,
    required List<Phase> phases,
    Map<String, String>? dailyFeedback,
  }) = _PlannerData;
  factory PlannerData.fromJson(JsonMap json) => _$PlannerDataFromJson(json);
  String toJsonString() => jsonEncode(toJson());
}

@freezed
abstract class Profile with _$Profile {
  const Profile._();

  /// Missing legacy values behave as daily while staying absent on JSON export.
  PlanningMode get planningMode => storedPlanningMode ?? PlanningMode.daily;

  /// 用户目标日期；空字符串表示没有目标日期。
  ///
  /// 旧数据把目标日期保存在 [examDate]。历史兼容只在反序列化边界做一次
  /// （见 [normalizeProfileJson]），因此这里不再回退旧字段：
  /// 用户清空目标日期后，不会被旧考试日期重新填回。
  String get resolvedTargetDate => targetDate;

  /// 本次规划周期的开始日期；旧数据没有周期，退回今天。
  String resolvedPlanStart(String today) =>
      planStartDate.isNotEmpty ? planStartDate : today;

  /// 本次规划周期的结束日期，必须是有限区间。
  String resolvedPlanEnd(String today) {
    if (planEndDate.isNotEmpty) return planEndDate;
    if (examEndDate.isNotEmpty) return examEndDate;
    if (examDate.isNotEmpty) return examDate;
    return addDateOnly(today, 27);
  }

  /// 一周七天的可用分钟数（0 为周日，6 为周六）。
  ///
  /// 只有完整且合法的七天配置才算可靠来源；缺键或越界的旧数据按每日上限补齐，
  /// 不会把 0 分量的休息日替换成默认时间。
  Map<String, int> get weekMinutes {
    final stored = weeklyMinutes;
    if (isReliableWeek(stored)) return Map<String, int>.from(stored!);
    return {
      for (var day = 0; day < 7; day++) '$day': dailyLimitMinutes,
    };
  }

  const factory Profile({
    required String userId,
    @JsonKey(name: 'planning_mode') PlanningMode? storedPlanningMode,
    @Default('') String goalText,
    @Default(GoalType.other) GoalType goalType,
    @Default('') String goalSubtype,
    @Default('') String targetDate,
    @Default(false) bool targetDateConfirmed,
    @Default('') String planStartDate,
    @Default('') String planEndDate,
    Map<String, int>? weeklyMinutes,
    @Default('') String constraints,
    @Default('') String targetSchool,
    @Default('') String targetProgram,
    @Default('') String examDate,
    @Default('') String examEndDate,
    required int dailyLimitMinutes,
    required int granularityMinutes,
    required int bufferMinutes,
    required int subjectLimitMinutes,
    required int studyStartMinute,
    required int studyEndMinute,
    required String foundation,
  }) = _Profile;
  factory Profile.fromJson(JsonMap json) => _$ProfileFromJson(normalizeProfileJson(json));
}

/// 反序列化边界的历史字段归一化。
///
/// - 新字段**缺失**：说明是通用改造之前的数据，可以用旧考试日期作为来源。
/// - 新字段存在（null 或空字符串）：表示用户当前的有效值，其中空值代表主动清空，
///   不能再从旧字段恢复日期。
JsonMap normalizeProfileJson(JsonMap json) {
  final map = JsonMap.from(json);
  if (!map.containsKey('target_date')) {
    final legacy = map['exam_date'];
    map['target_date'] = legacy is String ? legacy : '';
  }
  if (!map.containsKey('plan_end_date')) {
    final legacy = map['exam_end_date'] ?? map['exam_date'];
    map['plan_end_date'] = legacy is String ? legacy : '';
  }
  if (!map.containsKey('target_date_confirmed')) map['target_date_confirmed'] = false;
  return map;
}

@freezed
abstract class Subject with _$Subject {
  const factory Subject({
    required String id,
    required String userId,
    required String name,
    required String color,
    @JsonKey(fromJson: _priority) required int priority,
  }) = _Subject;
  factory Subject.fromJson(JsonMap json) => _$SubjectFromJson(json);
}

typedef Course = Subject;

@freezed
abstract class Task with _$Task {
  const factory Task({
    required String id,
    required String userId,
    required String subjectId,
    required String title,
    String? description,
    required int estimatedMinutes,
    required int completedMinutes,
    @JsonKey(fromJson: _priority) required int priority,
    required String deadline,
    @Default(ItemDateKind.deadline) ItemDateKind deadlineKind,
    String? earliestDate,
    required bool isFixed,
    required TaskStatus status,
    required String createdAt,
    required String updatedAt,
  }) = _Task;
  factory Task.fromJson(JsonMap json) => _$TaskFromJson(json);
}

typedef Item = Task;

@freezed
abstract class ScheduleBlock with _$ScheduleBlock {
  const factory ScheduleBlock({
    required String id,
    required String userId,
    required String taskId,
    required String date,
    required int startMinute,
    required int durationMinutes,
    required int actualMinutes,
    required bool isFixed,
    required BlockStatus status,
    required String createdAt,
    required String updatedAt,
    String? adviceText,
    List<String>? adviceTopics,
    CompletionStatus? completionStatus,
    String? feedback,
  }) = _ScheduleBlock;
  factory ScheduleBlock.fromJson(JsonMap json) => _$ScheduleBlockFromJson(json);
}

@freezed
abstract class TimeLog with _$TimeLog {
  const factory TimeLog({
    required String id,
    required String userId,
    required String taskId,
    @JsonKey(includeIfNull: true) required String? blockId,
    required String date,
    required int minutes,
    required String startedAt,
    required String endedAt,
    required LogSource source,
  }) = _TimeLog;
  factory TimeLog.fromJson(JsonMap json) => _$TimeLogFromJson(json);
}

typedef StudyLog = TimeLog;

@freezed
abstract class FixedEvent with _$FixedEvent {
  const factory FixedEvent({
    required String id,
    required String userId,
    required String title,
    required String date,
    required int startMinute,
    required int durationMinutes,
    required FixedEventKind kind,
    required EventRepeat repeat,
    required String createdAt,
    required String updatedAt,
  }) = _FixedEvent;
  factory FixedEvent.fromJson(JsonMap json) => _$FixedEventFromJson(json);
}

@freezed
abstract class Phase with _$Phase {
  const factory Phase({
    required String id,
    required String title,
    required String start,
    required String end,
    required String description,
  }) = _Phase;
  factory Phase.fromJson(JsonMap json) => _$PhaseFromJson(json);
}

@freezed
abstract class ReplanChange with _$ReplanChange {
  const factory ReplanChange({
    required String id,
    required String userId,
    required String runId,
    required ChangeType type,
    required String blockId,
    @JsonKey(includeIfNull: true) required ScheduleBlock? before,
    @JsonKey(includeIfNull: true) required ScheduleBlock? after,
  }) = _ReplanChange;
  factory ReplanChange.fromJson(JsonMap json) => _$ReplanChangeFromJson(json);
}

@freezed
abstract class Conflict with _$Conflict {
  const factory Conflict({
    required String taskId,
    required String title,
    required int minutes,
    required String reason,
  }) = _Conflict;
  factory Conflict.fromJson(JsonMap json) => _$ConflictFromJson(json);
}

@freezed
abstract class DayChange with _$DayChange {
  const factory DayChange({
    required String date,
    required int beforeMinutes,
    required int afterMinutes,
  }) = _DayChange;
  factory DayChange.fromJson(JsonMap json) => _$DayChangeFromJson(json);
}

@freezed
abstract class TaskStatusSnapshot with _$TaskStatusSnapshot {
  const factory TaskStatusSnapshot({
    required String id,
    required TaskStatus status,
  }) = _TaskStatusSnapshot;
  factory TaskStatusSnapshot.fromJson(JsonMap json) =>
      _$TaskStatusSnapshotFromJson(json);
}

@freezed
abstract class ReplanPreview with _$ReplanPreview {
  const factory ReplanPreview({
    required String id,
    required String userId,
    required String createdAt,
    required List<ScheduleBlock> before,
    required List<ScheduleBlock> after,
    required List<ReplanChange> changes,
    required List<String> postponed,
    required List<String> advanced,
    required List<Conflict> conflicts,
    required List<DayChange> dailyChanges,
  }) = _ReplanPreview;
  factory ReplanPreview.fromJson(JsonMap json) => _$ReplanPreviewFromJson(json);
}

@freezed
abstract class ReplanRun with _$ReplanRun {
  const factory ReplanRun({
    required String id,
    required String userId,
    required String createdAt,
    required List<ScheduleBlock> before,
    required List<ScheduleBlock> after,
    required List<ReplanChange> changes,
    required List<String> postponed,
    required List<String> advanced,
    required List<Conflict> conflicts,
    required List<DayChange> dailyChanges,
    required ReplanStatus status,
    List<TaskStatusSnapshot>? taskStatusBefore,
    List<TaskStatusSnapshot>? taskStatusAfter,

    /// Local application guard; old TypeScript runs omit it and use block protection.
    JsonMap? localUndoGuard,
  }) = _ReplanRun;
  factory ReplanRun.fromJson(JsonMap json) => _$ReplanRunFromJson(json);
}

@freezed
abstract class ReplanInput with _$ReplanInput {
  const factory ReplanInput({
    required List<Task> tasks,
    required List<ScheduleBlock> blocks,
    required List<TimeLog> logs,
    required List<FixedEvent> fixedEvents,
    required Profile profile,
    required String today,
    required ReplanMode mode,
    int? excessMinutes,
  }) = _ReplanInput;
  factory ReplanInput.fromJson(JsonMap json) => _$ReplanInputFromJson(json);
}

@freezed
abstract class SyncMetadata with _$SyncMetadata {
  const factory SyncMetadata({
    @JsonKey(fromJson: _versionOne) @Default(1) int version,
    @JsonKey(fromJson: _revision) @Default(0) int revision,
    @Default(false) bool pending,
    @JsonKey(includeIfNull: true) PlannerData? base,
    @JsonKey(name: 'updatedAt', includeIfNull: true) DateTime? updatedAt,
  }) = _SyncMetadata;
  factory SyncMetadata.fromJson(JsonMap json) => _$SyncMetadataFromJson(json);
}
