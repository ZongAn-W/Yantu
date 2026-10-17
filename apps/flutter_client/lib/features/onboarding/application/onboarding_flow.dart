import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_state.dart';
import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../planner/application/onboarding_controller.dart'
    show onboardingStatusProvider;
import '../../planner/application/planner_session.dart';
import '../data/onboarding_api.dart';
import '../domain/onboarding_session.dart';

class OnboardingFlowState {
  const OnboardingFlowState({
    this.session,
    this.loading = false,
    this.error,
    this.planChanged = false,
  });
  final OnboardingSession? session;
  final bool loading;
  final String? error;
  final bool planChanged;
}

final onboardingFlowProvider =
    NotifierProvider.autoDispose<OnboardingFlow, OnboardingFlowState>(
      OnboardingFlow.new,
    );

class OnboardingFlow extends AutoDisposeNotifier<OnboardingFlowState> {
  int _generation = 0;
  @override
  OnboardingFlowState build() {
    ref.watch(authControllerProvider.select((state) => state.user?.id));
    ref.onDispose(() => _generation++);
    unawaited(Future.microtask(reload));
    return const OnboardingFlowState(loading: true);
  }

  Future<void> reload() async {
    final generation = ++_generation;
    final api = OnboardingApi(ref.read(apiClientProvider));
    state = OnboardingFlowState(session: state.session, loading: true);
    try {
      final session = await api.load();
      if (generation != _generation) return;
      state = OnboardingFlowState(session: session);
      if (session.stage == 'complete') await _complete(session);
    } catch (error) {
      if (generation == _generation) {
        state = OnboardingFlowState(error: _message(error));
      }
    }
  }

  void editCourses(List<CourseDraft> courses) {
    if (state.loading) return;
    state = OnboardingFlowState(session: state.session!.edit(courses: courses));
  }

  void editItems(List<ItemDraft> items) {
    if (state.loading) return;
    state = OnboardingFlowState(session: state.session!.edit(items: items));
  }

  Future<bool> act(JsonMap action) async {
    final session = state.session;
    if (state.loading || session == null) return false;
    final generation = ++_generation;
    final api = OnboardingApi(ref.read(apiClientProvider));
    state = OnboardingFlowState(session: session, loading: true);
    try {
      if (session.hasPlan &&
          const [
            'resume_interview',
            'restart_interview',
            'refresh_plan',
            'finish',
          ].contains(action['type'])) {
        await ref.read(plannerSessionProvider).sync();
        if (generation != _generation) return false;
        final plan = ref.read(plannerDataProvider);
        if (plan.pending ||
            plan.blocked ||
            plan.conflicts.isNotEmpty ||
            plan.status != SyncStatus.connected) {
          throw const ConflictFailure('当前计划尚未同步，请先到设置页完成同步后再规划');
        }
      }
      final next = await api.advance(session.revision, action);
      if (generation != _generation) return false;
      state = OnboardingFlowState(session: next);
      if (next.stage == 'complete') await _complete(next);
      return true;
    } catch (error) {
      if (generation == _generation) {
        state = OnboardingFlowState(
          session: session,
          error: _message(error),
          planChanged:
              action['type'] == 'finish' &&
              session.replanning &&
              error is ConflictFailure,
        );
      }
      return false;
    }
  }

  Future<void> _complete(OnboardingSession session) async {
    ref.read(onboardingStatusProvider.notifier).markComplete(session.profile);
    await ref.read(plannerSessionProvider).sync();
  }

  String _message(Object error) =>
      error is AppFailure ? error.message : '操作失败，请重试：$error';
}
