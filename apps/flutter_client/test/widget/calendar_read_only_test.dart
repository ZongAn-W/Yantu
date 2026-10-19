import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_sync.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/router/app_router.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import 'planner_ui_test.dart' as harness;

void main() {
  testWidgets('calendar is read-only and keeps date selection available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final server = harness.FakeSyncServer();
    final container = await harness.signIn(tester, respond: server.respond);
    container.read(appRouterProvider).go('/calendar');
    await tester.pumpAndSettle();

    final plan = container.read(plannerSyncProvider).data!;
    final task = plan.tasks.first;
    final date = shanghaiToday();
    expect(find.text('学习日历'), findsNothing);
    expect(find.text('查看每日安排与完成记录'), findsNothing);
    expect(find.byKey(ValueKey('calendar-day-$date')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-selected-day-details')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('study-timer-action-${task.id}-$date')),
      findsNothing,
    );
    expect(find.text('创建固定事件'), findsNothing);
    expect(find.textContaining('午休'), findsNothing);
    expect(find.textContaining('固定安排'), findsNothing);
    expect(find.text('当天可用 7小时30分'), findsOneWidget);
    expect(find.text('调整日期'), findsNothing);
    expect(
      find.byWidgetPredicate((widget) => widget is LongPressDraggable),
      findsNothing,
    );

    final tomorrow = addDate(date, 1);
    final tomorrowDay = find.byKey(ValueKey('calendar-day-$tomorrow'));
    await tester.ensureVisible(tomorrowDay);
    await tester.tap(tomorrowDay);
    await tester.pumpAndSettle();
    expect(find.text(fullDateLabel(tomorrow)), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed tasks without schedule blocks remain in the archive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final base = harness.todayFixture();
    final completed = base.tasks.first.copyWith(
      id: 'completed-without-block',
      title: '完成但无排程块',
      status: TaskStatus.completed,
      completedMinutes: 90,
      updatedAt: '2026-10-19T09:00:00.000Z',
    );
    final plan = base.copyWith(tasks: [...base.tasks, completed]);
    final server = harness.FakeSyncServer(plan: plan);
    final container = await harness.signIn(tester, respond: server.respond);
    container.read(appRouterProvider).go('/calendar');
    await tester.pumpAndSettle();

    final reveal = find.byKey(const ValueKey('calendar-show-all-completed'));
    await Scrollable.ensureVisible(tester.element(reveal));
    await tester.pumpAndSettle();
    await tester.tap(reveal);
    await tester.pumpAndSettle();

    expect(find.text('完成但无排程块'), findsOneWidget);
    expect(find.textContaining('此前或无本周期排程依据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
