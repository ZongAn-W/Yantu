import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import '../../auth/application/auth_controller.dart';
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
    required this.subjectLimitMinutes,
    required this.studyStartMinute,
    required this.studyEndMinute,
    required this.priorities,
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
  final int subjectLimitMinutes;
  final int studyStartMinute;
  final int studyEndMinute;
  final Map<String, int> priorities;

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
        subjectLimitMinutes: profile.subjectLimitMinutes,
        studyStartMinute: profile.studyStartMinute,
        studyEndMinute: profile.studyEndMinute,
        priorities: const {},
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
    int? subjectLimitMinutes,
    int? studyStartMinute,
    int? studyEndMinute,
    Map<String, int>? priorities,
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
    subjectLimitMinutes: subjectLimitMinutes ?? this.subjectLimitMinutes,
    studyStartMinute: studyStartMinute ?? this.studyStartMinute,
    studyEndMinute: studyEndMinute ?? this.studyEndMinute,
    priorities: priorities ?? this.priorities,
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
  if (draft.subjectLimitMinutes < 60 || draft.subjectLimitMinutes > 480) {
    return '单科每日上限需要在 60 至 480 分钟之间';
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
  return null;
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
      dailyLimitMinutes: draft.weeklyPeakMinutes,
      granularityMinutes: draft.granularityMinutes,
      bufferMinutes: draft.bufferMinutes,
      subjectLimitMinutes: draft.subjectLimitMinutes,
      studyStartMinute: draft.studyStartMinute,
      studyEndMinute: draft.studyEndMinute,
    ),
    subjects: [
      for (final subject in data.subjects)
        subject.copyWith(
          priority: draft.priorities[subject.id] ?? subject.priority,
        ),
    ],
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
  if (draft.subjectLimitMinutes != current.subjectLimitMinutes) return true;
  if (draft.granularityMinutes != current.granularityMinutes) return true;
  if (current.planningMode == PlanningMode.timed &&
      (draft.studyStartMinute != current.studyStartMinute ||
          draft.studyEndMinute != current.studyEndMinute)) {
    return true;
  }
  return false;
}
