import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import '../../auth/application/auth_controller.dart';
import 'planner_session.dart';
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

/// Local schedule boundary fields of one onboarding profile.
///
/// The Node profile only stores the exam date and the weekly study minutes, so the
/// remaining fields are local planner settings and keep their current values.
class ProfileSettingsDraft {
  const ProfileSettingsDraft({
    required this.targetSchool,
    required this.targetProgram,
    required this.examDate,
    required this.examEndDate,
    required this.dailyLimitMinutes,
    required this.granularityMinutes,
    required this.bufferMinutes,
    required this.subjectLimitMinutes,
    required this.studyStartMinute,
    required this.studyEndMinute,
    required this.priorities,
  });

  final String targetSchool;
  final String targetProgram;
  final String examDate;
  final String examEndDate;
  final int dailyLimitMinutes;
  final int granularityMinutes;
  final int bufferMinutes;
  final int subjectLimitMinutes;
  final int studyStartMinute;
  final int studyEndMinute;
  final Map<String, int> priorities;

  static ProfileSettingsDraft from(Profile profile) => ProfileSettingsDraft(
    targetSchool: profile.targetSchool,
    targetProgram: profile.targetProgram,
    examDate: profile.examDate,
    examEndDate: profile.examEndDate,
    dailyLimitMinutes: profile.dailyLimitMinutes,
    granularityMinutes: profile.granularityMinutes,
    bufferMinutes: profile.bufferMinutes,
    subjectLimitMinutes: profile.subjectLimitMinutes,
    studyStartMinute: profile.studyStartMinute,
    studyEndMinute: profile.studyEndMinute,
    priorities: const {},
  );

  ProfileSettingsDraft copyWith({
    String? targetSchool,
    String? targetProgram,
    String? examDate,
    String? examEndDate,
    int? dailyLimitMinutes,
    int? granularityMinutes,
    int? bufferMinutes,
    int? subjectLimitMinutes,
    int? studyStartMinute,
    int? studyEndMinute,
    Map<String, int>? priorities,
  }) => ProfileSettingsDraft(
    targetSchool: targetSchool ?? this.targetSchool,
    targetProgram: targetProgram ?? this.targetProgram,
    examDate: examDate ?? this.examDate,
    examEndDate: examEndDate ?? this.examEndDate,
    dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
    granularityMinutes: granularityMinutes ?? this.granularityMinutes,
    bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    subjectLimitMinutes: subjectLimitMinutes ?? this.subjectLimitMinutes,
    studyStartMinute: studyStartMinute ?? this.studyStartMinute,
    studyEndMinute: studyEndMinute ?? this.studyEndMinute,
    priorities: priorities ?? this.priorities,
  );
}

/// Settings form validation shared by the settings page and its tests.
String? validateSettingsDraft(ProfileSettingsDraft draft) {
  if (draft.dailyLimitMinutes < 60 || draft.dailyLimitMinutes > 1440) {
    return '每日学习上限需要在 60 至 1440 分钟之间';
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
  if (draft.examDate.isEmpty) return '请填写初试第一天';
  return null;
}

/// Applies the local settings to the current plan without touching tasks.
PlannerData applySettings(PlannerData data, ProfileSettingsDraft draft) {
  final error = validateSettingsDraft(draft);
  if (error != null) throw StateError(error);
  return data.copyWith(
    profile: data.profile.copyWith(
      targetSchool: draft.targetSchool,
      targetProgram: draft.targetProgram,
      examDate: draft.examDate,
      examEndDate: draft.examEndDate,
      dailyLimitMinutes: draft.dailyLimitMinutes,
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

/// Six profile steps plus the draft confirmation step.
class OnboardingState {
  const OnboardingState({
    this.step = 1,
    required this.profile,
    this.draftId = '',
    this.draft,
    this.loading = false,
    this.error,
  });

  final int step;
  final OnboardingProfile profile;
  final String draftId;
  final PlanDraft? draft;
  final bool loading;
  final String? error;

  bool get onDraft => step == 7 && draft != null;

  OnboardingState copyWith({
    int? step,
    OnboardingProfile? profile,
    String? draftId,
    PlanDraft? draft,
    bool? loading,
    String? error,
  }) => OnboardingState(
    step: step ?? this.step,
    profile: profile ?? this.profile,
    draftId: draftId ?? this.draftId,
    draft: draft ?? this.draft,
    loading: loading ?? this.loading,
    error: error,
  );
}

OnboardingProfile initialOnboardingProfile([DateTime? now]) {
  final value = now ?? DateTime.now();
  return OnboardingProfile(
    examType: '考研',
    examDate: '${value.year + 1}-12-25',
    weeklyMinutes: const {
      '0': 0,
      '1': 120,
      '2': 120,
      '3': 120,
      '4': 120,
      '5': 120,
      '6': 180,
    },
  );
}

/// Field validation per wizard step, so the UI cannot advance with empty answers.
String? validateOnboardingStep(OnboardingProfile profile, int step) {
  switch (step) {
    case 1:
      if (profile.examType.isEmpty) return '请选择考试类型';
      return null;
    case 2:
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(profile.examDate)) {
        return '请选择正式考试日期';
      }
      return null;
    case 3:
      if (profile.targetSchool.trim().isEmpty) return '请填写目标院校或单位';
      return null;
    case 4:
      if (profile.currentProgress.trim().isEmpty) return '请填写当前进度';
      return null;
    case 5:
      final total = profile.weeklyMinutes.values.fold<int>(0, (a, b) => a + b);
      if (total <= 0) return '请至少填写一天的可用学习时间';
      if (profile.weeklyMinutes.values.any(
        (value) => value < 0 || value > 1440,
      )) {
        return '每天的学习时间需要在 0 至 1440 分钟之间';
      }
      return null;
    default:
      return null;
  }
}

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );

class OnboardingController extends Notifier<OnboardingState> {
  @override
  OnboardingState build() =>
      OnboardingState(profile: initialOnboardingProfile());

  void updateProfile(OnboardingProfile profile) =>
      state = state.copyWith(profile: profile, error: null);

  String? next() {
    final error = validateOnboardingStep(state.profile, state.step);
    if (error != null) {
      state = state.copyWith(error: error);
      return error;
    }
    state = state.copyWith(step: state.step + 1, error: null);
    return null;
  }

  void back() {
    if (state.step > 1) {
      state = state.copyWith(step: state.step - 1, error: null);
    }
  }

  void goTo(int step) => state = state.copyWith(step: step, error: null);

  void updateDraft(PlanDraft draft) => state = state.copyWith(draft: draft);
  void clearError() => state = state.copyWith(error: null);

  /// Saves the profile and asks the server for a plan draft.
  Future<bool> submitProfile() async {
    if (state.loading) return false;
    state = state.copyWith(loading: true, error: null);
    try {
      final api = ref.read(plannerApiProvider);
      await api.saveProfile(state.profile);
      final result = await api.createDraft(
        state.profile,
        requestId: api.newRequestId(),
      );
      state = state.copyWith(
        loading: false,
        draftId: result.id,
        draft: result.draft,
        step: 7,
      );
      return true;
    } catch (error) {
      state = state.copyWith(loading: false, error: _message(error));
      return false;
    }
  }

  /// Confirms the reviewed draft and reloads the server plan into the local store.
  Future<bool> confirmDraft() async {
    final draft = state.draft;
    if (draft == null || state.loading) return false;
    if (draft.items.isEmpty) {
      state = state.copyWith(error: '请至少保留一个事项');
      return false;
    }
    state = state.copyWith(loading: true, error: null);
    try {
      await ref.read(plannerApiProvider).confirmDraft(state.draftId, draft);
      ref.read(onboardingStatusProvider.notifier).markComplete(state.profile);
      await ref.read(plannerSessionProvider).sync();
      state = state.copyWith(loading: false);
      return true;
    } catch (error) {
      state = state.copyWith(loading: false, error: _message(error));
      return false;
    }
  }

  String _message(Object error) => error is AppFailure
      ? error.message
      : error is StateError
      ? error.message
      : '操作失败，请重试：$error';
}
