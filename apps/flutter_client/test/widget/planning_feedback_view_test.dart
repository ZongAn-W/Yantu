import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/features/planner/presentation/planning_feedback_view.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

class _Sync implements SyncApi {
  _Sync(this.data);
  PlannerData data;
  @override
  Future<RemoteSnapshot> pull({int? revision}) async => RemoteSnapshot(data, 1);
  @override
  Future<RemoteSnapshot> push(
    PlannerData next,
    PlannerData? base,
    int expected,
  ) async {
    data = next;
    return RemoteSnapshot(next, expected + 1);
  }
}

void main() {
  testWidgets(
    'feedback saves across the closing dialog animation without disposing a live input',
    (tester) async {
      final data = plannerFixture();
      final coordinator =
          PlannerCoordinator(
              userId: data.profile.userId,
              scope: 'feedback-test',
              storage: MemoryStorageRepository(),
              api: _Sync(data),
              retryInterval: null,
            )
            ..data = data
            ..ready = true
            ..status = SyncStatus.connected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [plannerSyncProvider.overrideWith((_) => coordinator)],
          child: MaterialApp(
            home: Scaffold(
              body: PlanningFeedbackView(
                task: data.tasks.first,
                data: data,
                editable: true,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('记录内容进度与困难'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2');
      await tester.tap(find.text('保存反馈'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final changed = coordinator.data!.tasks.first;
      expect((changed.planning!['feedback'] as Map)['content_units'], 2);
      expect(changed.status, data.tasks.first.status);
      expect(coordinator.data!.logs, data.logs);
      expect(coordinator.data!.blocks, data.blocks);
    },
  );
}
