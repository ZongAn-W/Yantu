import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers.dart';
import '../../../shared/models/planner_models.dart';
import '../data/planner_api.dart';
import 'planner_sync.dart';
import '../../../core/sync/sync_state.dart';

final plannerApiProvider = Provider<PlannerApi>(
  (ref) => PlannerApi(ref.watch(apiClientProvider)),
);

final plannerSnapshotProvider = Provider<AsyncValue<PlannerData?>>((ref) {
  final state = ref.watch(plannerSyncProvider);
  if (!state.ready || (state.data == null && state.busy)) {
    return const AsyncLoading();
  }
  if (state.data == null &&
      (state.blocked ||
          state.status == SyncStatus.offline ||
          state.status == SyncStatus.error)) {
    return AsyncError(StateError(state.message), StackTrace.current);
  }
  return AsyncData(state.data);
});

class TodayItem {
  const TodayItem({
    required this.title,
    required this.tags,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.taskId,
  });
  final String title;
  final List<String> tags;
  final int plannedMinutes;
  final int actualMinutes;
  final String taskId;
}

List<TodayItem> todayItems(PlannerData data, String date) {
  final planned = <String, int>{};
  for (final block in data.blocks.where((block) => block.date == date)) {
    planned.update(
      block.taskId,
      (value) => value + block.durationMinutes,
      ifAbsent: () => block.durationMinutes,
    );
  }
  final actual = <String, int>{};
  for (final log in data.logs.where((log) => log.date == date)) {
    final taskId = log.taskId;
    // Task-less temporary learning is not a task item; it is reported by the
    // temporary-learning entries instead of borrowing another task's identity.
    if (taskId == null) continue;
    actual.update(
      taskId,
      (value) => value + log.minutes,
      ifAbsent: () => log.minutes,
    );
  }
  final tagsById = {for (final tag in data.tags) tag.id: tag.name};
  return [
    for (final task in data.tasks)
      if (planned.containsKey(task.id) || actual.containsKey(task.id))
        TodayItem(
          taskId: task.id,
          title: task.title,
          tags: [
            for (final id in task.tagIds)
              if (tagsById[id] case final name?) name,
          ],
          plannedMinutes: planned[task.id] ?? 0,
          actualMinutes: actual[task.id] ?? 0,
        ),
  ];
}
