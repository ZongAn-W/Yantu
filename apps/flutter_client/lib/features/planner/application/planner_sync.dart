import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../core/sync/planner_coordinator.dart';
import '../../../core/sync/sync_api.dart';
import '../../auth/application/auth_controller.dart';

final syncApiProvider = Provider<SyncApi>(
  (ref) => HttpSyncApi(ref.watch(apiClientProvider)),
);

/// Background retry cadence. Widget tests override it with `null` so no periodic
/// timer outlives the test.
final syncRetryIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(seconds: 15),
);

/// Keeps the coordinator alive for the whole signed-in session.
///
/// It is deliberately not `autoDispose`: the router renders a dedicated loading
/// route while the study profile is fetched, so no page watches the plan yet. An
/// auto-disposed coordinator would be discarded there and restart its sync on
/// every route change.
final plannerSyncProvider = ChangeNotifierProvider<PlannerCoordinator>((ref) {
  final user = ref.watch(authControllerProvider.select((state) => state.user));
  final config = ref.watch(appConfigProvider);
  final retryInterval = ref.watch(syncRetryIntervalProvider);
  final coordinator = PlannerCoordinator(
    userId: user?.id ?? '',
    scope: Uri.encodeComponent(config.apiBaseUrl),
    storage: ref.watch(storageRepositoryProvider),
    api: ref.watch(syncApiProvider),
    retryInterval: retryInterval,
  );
  final observer = _ResumeObserver(coordinator);
  final auth = ref.read(authControllerProvider.notifier);
  final participant = AccountDeletionParticipant(
    suspend: coordinator.suspendForAccountDeletion,
    resume: coordinator.resumeAfterAccountDeletionFailure,
  );
  auth.addDeletionParticipant(participant);
  WidgetsBinding.instance.addObserver(observer);
  // The coordinator is the provider's notifier, so Riverpod disposes it; this
  // callback only removes the lifecycle observer.
  ref.onDispose(() {
    auth.removeDeletionParticipant(participant);
    WidgetsBinding.instance.removeObserver(observer);
  });
  if (user != null) unawaited(coordinator.initialize());
  return coordinator;
});

class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this.coordinator);
  final PlannerCoordinator coordinator;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(coordinator.sync());
  }
}
