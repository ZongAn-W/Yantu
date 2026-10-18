import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/adjust/presentation/adjust_plan_page.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/auth_page.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/onboarding/presentation/onboarding_page.dart';
import '../features/planner/application/onboarding_controller.dart';
import '../core/errors/app_failure.dart';
import '../core/providers.dart';
import '../features/progress/presentation/progress_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/app_shell.dart';
import '../features/tasks/presentation/tasks_page.dart';

/// Route paths shared with the Web client; they keep the same semantics in Flutter.
abstract final class AppRoutes {
  static const login = '/login';
  static const onboarding = '/onboarding';
  static const loading = '/loading';
  static const today = '/';
  static const calendar = '/calendar';
  static const tasks = '/tasks';
  static const progress = '/progress';
  static const adjust = '/adjust';
  static const interview = '/interview';
  static const settings = '/settings';
}

final _hasLocalPlanProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(
    authControllerProvider.select((state) => state.user?.id),
  );
  if (userId == null) return false;
  final config = ref.watch(appConfigProvider);
  final storage = ref.watch(storageRepositoryProvider);
  final key =
      'sjtu-study-planner:items-v2:${Uri.encodeComponent(config.apiBaseUrl)}:cloud:$userId';
  final snapshot = await storage.load(key);
  return snapshot.data?.profile.userId == userId;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = _AuthRouteState(
    ref.read(authControllerProvider).user != null,
  );
  final onboarding = _OnboardingRouteState(
    ref.read(onboardingStatusProvider).valueOrNull != null,
    ref.read(onboardingStatusProvider).isLoading,
    ref.read(onboardingStatusProvider).hasError,
  );
  void updateLocalPlan() {
    onboarding.updateLocalPlan(
      ref.read(_hasLocalPlanProvider).valueOrNull == true,
    );
  }

  updateLocalPlan();
  ref.listen(authControllerProvider, (_, next) {
    session.update(next.user != null);
  });
  ref.listen(onboardingStatusProvider, (_, next) {
    onboarding.update(next.valueOrNull != null, next.isLoading, next.hasError);
  });
  ref.listen(_hasLocalPlanProvider, (_, _) => updateLocalPlan());
  final planner = _PlannerRouter(session, onboarding);
  ref.onDispose(() {
    planner.router.dispose();
    session.dispose();
    onboarding.dispose();
  });
  return planner.router;
});

class _AuthRouteState extends ChangeNotifier {
  _AuthRouteState(this.authenticated);
  bool authenticated;

  void update(bool next) {
    if (authenticated == next) return;
    authenticated = next;
    notifyListeners();
  }
}

class _OnboardingRouteState extends ChangeNotifier {
  _OnboardingRouteState(this.complete, this.loading, this.failed);
  bool complete;
  bool loading;
  bool failed;
  bool hasLocalPlan = false;

  void update(bool nextComplete, bool nextLoading, bool nextFailed) {
    if (complete == nextComplete &&
        loading == nextLoading &&
        failed == nextFailed) {
      return;
    }
    complete = nextComplete;
    loading = nextLoading;
    failed = nextFailed;
    notifyListeners();
  }

  void updateLocalPlan(bool next) {
    if (hasLocalPlan == next) return;
    hasLocalPlan = next;
    notifyListeners();
  }
}

class _PlannerRouter {
  _PlannerRouter(this.session, this.onboarding);
  final _AuthRouteState session;
  final _OnboardingRouteState onboarding;

  late final GoRouter router = GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: Listenable.merge([session, onboarding]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      final login = location == AppRoutes.login;
      if (!session.authenticated) return login ? null : AppRoutes.login;
      // Hold a dedicated route while the profile lookup runs, so an account that
      // already finished onboarding never sees the wizard flash.
      if ((onboarding.loading || onboarding.failed) &&
          !onboarding.hasLocalPlan) {
        return location == AppRoutes.loading ? null : AppRoutes.loading;
      }
      if (!onboarding.complete && !onboarding.loading && !onboarding.failed) {
        return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
      }
      if (login ||
          location == AppRoutes.onboarding ||
          location == AppRoutes.loading) {
        return AppRoutes.today;
      }
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.login, builder: (context, _) => const AuthPage()),
      GoRoute(
        path: AppRoutes.loading,
        builder: (context, _) => const _SessionLoadingPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, _) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.today,
        builder: (context, _) => const AppShell(
          selectedPath: AppRoutes.today,
          child: DashboardPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.calendar,
        builder: (context, _) => const AppShell(
          selectedPath: AppRoutes.calendar,
          child: CalendarPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.tasks,
        builder: (context, _) =>
            const AppShell(selectedPath: AppRoutes.tasks, child: TasksPage()),
      ),
      GoRoute(
        path: AppRoutes.progress,
        builder: (context, _) => const AppShell(
          selectedPath: AppRoutes.progress,
          child: ProgressPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adjust,
        builder: (context, _) => const AppShell(
          selectedPath: AppRoutes.adjust,
          child: AdjustPlanPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.interview,
        builder: (context, _) => const AppShell(
          selectedPath: AppRoutes.interview,
          child: OnboardingPage(embedded: true),
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, _) => const AppShell(
          selectedPath: AppRoutes.settings,
          child: SettingsPage(),
        ),
      ),
    ],
  );
}

/// Shown while the account profile is being read, before the workspace or the
/// onboarding wizard can be decided.
class _SessionLoadingPage extends ConsumerWidget {
  const _SessionLoadingPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(onboardingStatusProvider);
    final error = profile.hasError ? profile.error : null;
    return Scaffold(
      body: Center(
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                error == null
                    ? '正在读取学习目标…'
                    : error is AppFailure
                    ? error.message
                    : '学习目标读取失败，请重试',
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(onboardingStatusProvider.notifier).refresh(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试读取学习目标'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
