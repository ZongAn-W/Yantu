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
import '../core/widgets.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/shell/app_shell.dart';

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

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = _AuthRouteState(
    ref.read(authControllerProvider).user != null,
  );
  // Keep profile lookup available without letting its loading/error state
  // decide whether the authenticated workbench is accessible.
  ref.listen(onboardingStatusProvider, (_, _) {});
  ref.listen(authControllerProvider, (_, next) {
    session.update(next.user != null);
  });
  final planner = _PlannerRouter(session);
  ref.onDispose(() {
    planner.router.dispose();
    session.dispose();
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

class _PlannerRouter {
  _PlannerRouter(this.session);
  final _AuthRouteState session;

  late final GoRouter router = GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final login = location == AppRoutes.login;
      if (!session.authenticated) return login ? null : AppRoutes.login;
      // The planning interview is optional. Let a new account reach the
      // workbench while profile lookup and local plan bootstrap happen in the
      // background; /onboarding remains available from the explicit AI planning
      // entry point.
      if (login || location == AppRoutes.loading) {
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
        // 事项页已合并进「今日」页的下半部分；保留旧链接可用。
        redirect: (context, state) => AppRoutes.today,
      ),
      GoRoute(
        path: AppRoutes.progress,
        // 进度页已并入「日历」栏目；保留旧链接可用。
        redirect: (context, state) => AppRoutes.calendar,
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
          selectedPath: AppRoutes.adjust,
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
              if (error == null) const PlannerSpinner(size: 20),
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
