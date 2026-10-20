import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/capacity.dart' as capacity;
import '../domain/planner_format.dart';
import 'planner_snapshot.dart';

/// Whether this account still has to finish the study profile wizard.
final onboardingStatusProvider =
    NotifierProvider<OnboardingStatus, AsyncValue<OnboardingProfile?>>(
      OnboardingStatus.new,
    );

/// Identity only: the status provider must not refetch when unrelated auth state
/// (loading flags, transient errors) changes.
final _authUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authControllerProvider.select((state) => state.user?.id)),
);

class OnboardingStatus extends Notifier<AsyncValue<OnboardingProfile?>> {
  int _generation = 0;
  @override
  AsyncValue<OnboardingProfile?> build() {
    ref.onDispose(() => _generation++);
    final userId = ref.watch(_authUserIdProvider);
    if (userId == null) return const AsyncData(null);
    unawaited(refresh());
    return const AsyncLoading();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    final userId = ref.read(_authUserIdProvider);
    if (userId == null) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    try {
      final profile = await ref.read(plannerApiProvider).profile();
      if (generation != _generation ||
          userId != ref.read(_authUserIdProvider)) {
        return;
      }
      state = AsyncData(profile);
    } catch (error) {
      if (generation != _generation ||
          userId != ref.read(_authUserIdProvider)) {
        return;
      }
      state = AsyncError(error, StackTrace.current);
    }
  }

  void markComplete(OnboardingProfile profile) {
    _generation++;
    state = AsyncData(profile);
  }
}

/// 学习目标与规划设置的表单草稿。
///
/// 目标类型、可选目标日期、一周七天可用时间和本次规划周期都在这里编辑；
/// 保存后写入本机计划，再由既有同步机制提交到云端。
class ProfileSettingsDraft {
  const ProfileSettingsDraft({
    required this.goalText,
    required this.goalType,
    required this.goalSubtype,
    required this.targetDate,
    required this.targetDateConfirmed,
    required this.planStartDate,
    required this.planEndDate,
    required this.targetSchool,
    required this.targetProgram,
    required this.currentProgress,
    required this.constraintsText,
    required this.weeklyMinutes,
    required this.dailyLimitMinutes,
    required this.granularityMinutes,
    required this.bufferMinutes,
    required this.studyStartMinute,
    required this.studyEndMinute,
    this.capacityBasis = CapacityBasis.grossBuffer,
    this.weeklyBaselineMinutes,
    this.weeklyRangeMinMinutes,
    this.weeklyRangeMaxMinutes,
    this.weekCapacityOverrides,
    this.dateCapacityOverrides,
  });

  final String goalText;
  final GoalType goalType;
  final String goalSubtype;
  final String targetDate;
  final bool targetDateConfirmed;
  final String planStartDate;
  final String planEndDate;
  final String targetSchool;
  final String targetProgram;
  final String currentProgress;
  final String constraintsText;
  final Map<String, int> weeklyMinutes;
  final int dailyLimitMinutes;
  final int granularityMinutes;
  final int bufferMinutes;
  final int studyStartMinute;
  final int studyEndMinute;

  /// 容量口径与灵活时间覆盖；旧数据保持 [CapacityBasis.grossBuffer] 旧语义。
  final CapacityBasis capacityBasis;

  /// 经用户确认的每周净学习基线（周总量）。
  final int? weeklyBaselineMinutes;

  /// 用户给出的大致周容量范围，仅用于说明较高容量情景。
  final int? weeklyRangeMinMinutes;
  final int? weeklyRangeMaxMinutes;
  final Map<String, WeekCapacityOverride>? weekCapacityOverrides;
  final Map<String, int>? dateCapacityOverrides;

  static ProfileSettingsDraft from(Profile profile, {required String today}) =>
      ProfileSettingsDraft(
        goalText: profile.goalText,
        goalType: profile.goalType,
        goalSubtype: profile.goalSubtype,
        targetDate: profile.resolvedTargetDate,
        targetDateConfirmed: profile.targetDateConfirmed,
        planStartDate: profile.resolvedPlanStart(today),
        planEndDate: profile.resolvedPlanEnd(today),
        targetSchool: profile.targetSchool,
        targetProgram: profile.targetProgram,
        currentProgress: profile.foundation,
        constraintsText: '',
        weeklyMinutes: profile.weekMinutes,
        dailyLimitMinutes: profile.dailyLimitMinutes,
        granularityMinutes: profile.granularityMinutes,
        bufferMinutes: profile.bufferMinutes,
        studyStartMinute: profile.studyStartMinute,
        studyEndMinute: profile.studyEndMinute,
        capacityBasis: profile.capacityBasis,
        weeklyBaselineMinutes: profile.weeklyBaselineMinutes,
        weeklyRangeMinMinutes: profile.weeklyRangeMinMinutes,
        weeklyRangeMaxMinutes: profile.weeklyRangeMaxMinutes,
        weekCapacityOverrides: profile.weekCapacityOverrides,
        dateCapacityOverrides: profile.dateCapacityOverrides,
      );

  ProfileSettingsDraft copyWith({
    String? goalText,
    GoalType? goalType,
    String? goalSubtype,
    String? targetDate,
    bool? targetDateConfirmed,
    String? planStartDate,
    String? planEndDate,
    String? targetSchool,
    String? targetProgram,
    String? currentProgress,
    String? constraintsText,
    Map<String, int>? weeklyMinutes,
    int? dailyLimitMinutes,
    int? granularityMinutes,
    int? bufferMinutes,
    int? studyStartMinute,
    int? studyEndMinute,
    CapacityBasis? capacityBasis,
    int? weeklyBaselineMinutes,
    int? weeklyRangeMinMinutes,
    int? weeklyRangeMaxMinutes,
    Map<String, WeekCapacityOverride>? weekCapacityOverrides,
    Map<String, int>? dateCapacityOverrides,
  }) => ProfileSettingsDraft(
    goalText: goalText ?? this.goalText,
    goalType: goalType ?? this.goalType,
    goalSubtype: goalSubtype ?? this.goalSubtype,
    targetDate: targetDate ?? this.targetDate,
    targetDateConfirmed: targetDateConfirmed ?? this.targetDateConfirmed,
    planStartDate: planStartDate ?? this.planStartDate,
    planEndDate: planEndDate ?? this.planEndDate,
    targetSchool: targetSchool ?? this.targetSchool,
    targetProgram: targetProgram ?? this.targetProgram,
    currentProgress: currentProgress ?? this.currentProgress,
    constraintsText: constraintsText ?? this.constraintsText,
    weeklyMinutes: weeklyMinutes ?? this.weeklyMinutes,
    dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
    granularityMinutes: granularityMinutes ?? this.granularityMinutes,
    bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    studyStartMinute: studyStartMinute ?? this.studyStartMinute,
    studyEndMinute: studyEndMinute ?? this.studyEndMinute,
    capacityBasis: capacityBasis ?? this.capacityBasis,
    weeklyBaselineMinutes: weeklyBaselineMinutes ?? this.weeklyBaselineMinutes,
    weeklyRangeMinMinutes: weeklyRangeMinMinutes ?? this.weeklyRangeMinMinutes,
    weeklyRangeMaxMinutes: weeklyRangeMaxMinutes ?? this.weeklyRangeMaxMinutes,
    weekCapacityOverrides: weekCapacityOverrides ?? this.weekCapacityOverrides,
    dateCapacityOverrides: dateCapacityOverrides ?? this.dateCapacityOverrides,
  );

  /// 每日上限取一周最大值，仅用于展示；排程按每天的单独预算计算。
  int get weeklyPeakMinutes {
    var peak = 0;
    for (final value in weeklyMinutes.values) {
      if (value > peak) peak = value;
    }
    return peak;
  }
}

/// Settings form validation shared by the settings page and its tests.
String? validateSettingsDraft(ProfileSettingsDraft draft) {
  if (draft.planStartDate.isEmpty) return '请选择规划开始日期';
  if (draft.planEndDate.isEmpty) return '请选择规划结束日期';
  final start = DateTime.tryParse('${draft.planStartDate}T00:00:00Z');
  final end = DateTime.tryParse('${draft.planEndDate}T00:00:00Z');
  if (start == null) return '规划开始日期无效';
  if (end == null) return '规划结束日期无效';
  if (draft.planEndDate.compareTo(draft.planStartDate) < 0) {
    return '规划结束日期不能早于开始日期';
  }
  if (end.difference(start).inDays > 1095) {
    return '单次规划周期不能超过三年，请先安排一段有限周期';
  }
  if (draft.targetDate.isNotEmpty) {
    final target = DateTime.tryParse('${draft.targetDate}T00:00:00Z');
    if (target == null) return '目标日期无效，或直接清空目标日期';
  }

  if (draft.bufferMinutes < 30 || draft.bufferMinutes > 180) {
    return '每日机动时间需要在 30 至 180 分钟之间';
  }
  if (draft.granularityMinutes != 30 && draft.granularityMinutes != 60) {
    return '时间粒度只能是 30 或 60 分钟';
  }
  if (draft.studyStartMinute < 0 ||
      draft.studyEndMinute > 1440 ||
      draft.studyEndMinute <= draft.studyStartMinute) {
    return '学习时间窗口无效';
  }
  for (final entry in draft.weeklyMinutes.entries) {
    if (entry.value < 0 || entry.value > 480) {
      return '每天可用时间需要在 0 至 480 分钟之间';
    }
  }
  if (!draft.weeklyMinutes.values.any((value) => value > 30)) {
    return '请至少设置一天超过30分钟的可用时间，预留30分钟机动';
  }
  final baselineError = _validateCapacityDraft(draft);
  if (baselineError != null) return baselineError;
  return null;
}

/// 灵活容量字段校验：范围、基线、特定周/日期覆盖。
String? _validateCapacityDraft(ProfileSettingsDraft draft) {
  final min = draft.weeklyRangeMinMinutes;
  final max = draft.weeklyRangeMaxMinutes;
  final baseline = draft.weeklyBaselineMinutes;
  for (final (label, value) in [
    ('周容量范围下限', min),
    ('周容量范围上限', max),
    ('采用周容量基线', baseline),
  ]) {
    if (value != null && (value < 0 || value > 10080)) {
      return '$label需要在 0 至 10080 分钟（一周）之间';
    }
  }
  if (min != null && max != null && min > max) {
    return '周容量范围下限不能大于上限';
  }
  if (baseline != null && max != null && baseline > max) {
    return '采用的周容量基线不能超过用户给出的范围上限';
  }
  final weeks = draft.weekCapacityOverrides ?? const {};
  for (final entry in weeks.entries) {
    final monday = DateTime.tryParse('${entry.key}T00:00:00Z');
    if (monday == null || monday.weekday != DateTime.monday) {
      return '特定周必须使用周一日期：${entry.key}';
    }
    final total = entry.value.totalMinutes;
    if (total != null && (total < 0 || total > 10080)) {
      return '特定周（${entry.key}）的总量需要在 0 至 10080 分钟之间';
    }
    for (final day in (entry.value.days ?? const {}).entries) {
      if (day.value < 0 || day.value > 1440) {
        return '特定周（${entry.key}）的日容量需要在 0 至 1440 分钟之间';
      }
    }
  }
  for (final entry in (draft.dateCapacityOverrides ?? const {}).entries) {
    if (DateTime.tryParse('${entry.key}T00:00:00Z') == null) {
      return '特定日期格式无效：${entry.key}';
    }
    if (entry.value < 0 || entry.value > 1440) {
      return '特定日期（${entry.key}）的容量需要在 0 至 1440 分钟之间';
    }
  }
  return null;
}

/// 净容量口径下，每日上限取基线分配结果与模板峰值的较大者。
int _netDailyLimit(
  int weeklyPeak,
  int? baseline,
  Map<String, int> weeklyMinutes,
) {
  if (baseline == null || baseline <= 0) return weeklyPeak;
  final weights = {
    for (var day = 0; day < 7; day++) day: weeklyMinutes['$day'] ?? 0,
  };
  final distributed = capacity.distributeWeeklyTotal(baseline, weights);
  var peak = weeklyPeak;
  for (final value in distributed.values) {
    if (value > peak) peak = value;
  }
  return peak;
}

/// Applies the local settings to the current plan without touching tasks.
PlannerData applySettings(PlannerData data, ProfileSettingsDraft draft) {
  final error = validateSettingsDraft(draft);
  if (error != null) throw StateError(error);
  // 保存后文档只使用新字段：清空目标日期时同时清掉旧镜像，
  // 避免新旧字段各自指向不同的日期，也避免空日期被标记为“已确认”。
  final emptyTarget = draft.targetDate.trim().isEmpty;
  return data.copyWith(
    profile: data.profile.copyWith(
      goalText: draft.goalText.trim(),
      goalType: draft.goalType,
      goalSubtype: draft.goalSubtype.trim(),
      targetDate: draft.targetDate.trim(),
      targetDateConfirmed: emptyTarget ? false : draft.targetDateConfirmed,
      examDate: '',
      examEndDate: '',
      planStartDate: draft.planStartDate,
      planEndDate: draft.planEndDate,
      targetSchool: draft.targetSchool,
      targetProgram: draft.targetProgram,
      foundation: draft.currentProgress,
      constraints: draft.constraintsText,
      weeklyMinutes: {
        for (var day = 0; day < 7; day++)
          '$day': draft.weeklyMinutes['$day'] ?? 0,
      },
      dailyLimitMinutes: draft.capacityBasis == CapacityBasis.net
          ? _netDailyLimit(
              draft.weeklyPeakMinutes,
              draft.weeklyBaselineMinutes,
              {
                for (var day = 0; day < 7; day++)
                  '$day': draft.weeklyMinutes['$day'] ?? 0,
              },
            )
          : draft.weeklyPeakMinutes,
      granularityMinutes: draft.granularityMinutes,
      bufferMinutes: draft.bufferMinutes,
      studyStartMinute: draft.studyStartMinute,
      studyEndMinute: draft.studyEndMinute,
      capacityBasis: draft.capacityBasis,
      weeklyBaselineMinutes: draft.weeklyBaselineMinutes,
      weeklyRangeMinMinutes: draft.weeklyRangeMinMinutes,
      weeklyRangeMaxMinutes: draft.weeklyRangeMaxMinutes,
      weekCapacityOverrides: draft.weekCapacityOverrides,
      dateCapacityOverrides: draft.dateCapacityOverrides,
    ),
  );
}

/// 会影响未来排程的设置变化，必须走预览与确认流程。
///
/// 目标描述、目标类型和目标日期只影响展示与业务含义，不会改写已有安排，
/// 因此不触发重排。
bool settingsAffectSchedule(PlannerData data, ProfileSettingsDraft draft) {
  final today = shanghaiToday();
  final current = data.profile;
  if (draft.planStartDate != current.resolvedPlanStart(today)) return true;
  if (draft.planEndDate != current.resolvedPlanEnd(today)) return true;
  final week = current.weekMinutes;
  for (var day = 0; day < 7; day++) {
    if ((week['$day'] ?? 0) != (draft.weeklyMinutes['$day'] ?? 0)) return true;
  }
  if (draft.bufferMinutes != current.bufferMinutes) return true;
  if (draft.granularityMinutes != current.granularityMinutes) return true;
  if (current.planningMode == PlanningMode.timed &&
      (draft.studyStartMinute != current.studyStartMinute ||
          draft.studyEndMinute != current.studyEndMinute)) {
    return true;
  }
  if (draft.capacityBasis != current.capacityBasis) return true;
  if (draft.weeklyBaselineMinutes != current.weeklyBaselineMinutes) return true;
  if (draft.weeklyRangeMinMinutes != current.weeklyRangeMinMinutes) return true;
  if (draft.weeklyRangeMaxMinutes != current.weeklyRangeMaxMinutes) return true;
  if (!_sameOverrides(
    draft.weekCapacityOverrides,
    current.weekCapacityOverrides,
  )) {
    return true;
  }
  if (!_sameIntMap(
    draft.dateCapacityOverrides,
    current.dateCapacityOverrides,
  )) {
    return true;
  }
  return false;
}

bool _sameOverrides(
  Map<String, WeekCapacityOverride>? a,
  Map<String, WeekCapacityOverride>? b,
) {
  final left = a ?? const <String, WeekCapacityOverride>{};
  final right = b ?? const <String, WeekCapacityOverride>{};
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null) return false;
    if (entry.value.totalMinutes != other.totalMinutes) return false;
    final daysLeft = entry.value.days ?? const <String, int>{};
    final daysRight = other.days ?? const <String, int>{};
    if (daysLeft.length != daysRight.length) return false;
    for (final day in daysLeft.entries) {
      if (daysRight[day.key] != day.value) return false;
    }
  }
  return true;
}

bool _sameIntMap(Map<String, int>? a, Map<String, int>? b) {
  if ((a?.length ?? 0) != (b?.length ?? 0)) return false;
  for (final entry in (a ?? const <String, int>{}).entries) {
    if ((b ?? const <String, int>{})[entry.key] != entry.value) return false;
  }
  return true;
}
