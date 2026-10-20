import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_month_chart.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_page.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_week_chart.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

class _MemoryWeekViewStore implements CalendarWeekViewPreferenceStore {
  CalendarWeekView value = CalendarWeekView.mirror;

  @override
  Future<CalendarWeekView> load() async => value;

  @override
  Future<void> save(CalendarWeekView view) async {
    value = view;
  }
}

PlannerData _monthData({required String today}) {
  final fixture = plannerFixture();
  final base = fixture.blocks.single;
  final month = today.substring(0, 7);
  final first = '$month-01';
  final future = addDate(today, 1);
  return fixture.copyWith(
    blocks: [
      base.copyWith(id: 'b-first', date: first, durationMinutes: 60),
      if (future.substring(0, 7) == month)
        base.copyWith(id: 'b-future', date: future, durationMinutes: 45),
    ],
    logs: [
      TimeLog(
        id: 'l-first',
        userId: fixture.profile.userId,
        taskId: base.taskId,
        blockId: null,
        date: first,
        minutes: 30,
        startedAt: '${first}T04:00:00.000Z',
        endedAt: '${first}T05:00:00.000Z',
        source: LogSource.timer,
        relation: TimeLogRelation.scheduled,
      ),
    ],
  );
}

Future<ProviderContainer> _pumpMonthPage(
  WidgetTester tester,
  PlannerData data, {
  Size size = const Size(1200, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      plannerDataProvider.overrideWithValue(
        PlannerSnapshot(
          data: data,
          revision: 1,
          pending: false,
          status: SyncStatus.demo,
          message: '',
          blocked: false,
          ready: true,
          busy: false,
          conflicts: const [],
        ),
      ),
      calendarWeekViewPreferenceStoreProvider.overrideWithValue(
        _MemoryWeekViewStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: plannerTheme(),
        home: const Scaffold(body: CalendarPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'month scope shows plan/capacity grid, selects a day and keeps the date',
    (tester) async {
      final today = shanghaiToday();
      final month = today.substring(0, 7);
      final first = '$month-01';
      final second = addDate(first, 1);
      await _pumpMonthPage(tester, _monthData(today: today));

      // Day is the default scope; switching to the month scope keeps today.
      expect(find.byKey(const ValueKey('calendar-day-chart')), findsNWidgets(2));
      await tester.tap(find.text('月'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarMonthChart), findsOneWidget);
      expect(find.byKey(ValueKey('calendar-month-$month')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-month-chart')), findsOneWidget);
      final summary = tester
          .widget<Text>(find.byKey(const ValueKey('calendar-month-summary')))
          .data!;
      expect(summary, contains('本月计划'));
      expect(summary, contains('实学'));
      expect(summary, contains('中断'));
      expect(find.byKey(ValueKey('calendar-month-day-$today')), findsOneWidget);
      // The former 当天安排 detail panel was removed from the month scope.
      expect(find.text('当天安排'), findsNothing);
      expect(
        find.byKey(const ValueKey('calendar-day-detail-totals')),
        findsNothing,
      );

      // Tapping another day still changes the shared selected date.
      await tester.tap(find.byKey(ValueKey('calendar-month-day-$second')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CalendarMonthChart>(find.byType(CalendarMonthChart))
            .selectedDate,
        second,
      );

      // Month navigation steps whole months and 本月 returns to today.
      await tester.tap(find.byKey(const ValueKey('calendar-previous-month')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-month-chart')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-this-month')));
      await tester.pumpAndSettle();

      // Week and day scopes keep the shared date (today after 本月).
      await tester.tap(find.text('周'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarWeekChart), findsOneWidget);
      await tester.tap(find.text('日'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('calendar-day-$today')), findsOneWidget);

      // Read-only: no timer, edit or completion controls.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('开始计时'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('month grid fits 320px without horizontal overflow', (
    tester,
  ) async {
    final today = shanghaiToday();
    await _pumpMonthPage(
      tester,
      _monthData(today: today),
      size: const Size(320, 2600),
    );
    await tester.tap(find.text('月'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('calendar-month-chart'))).width,
      lessThanOrEqualTo(320),
    );
    expect(find.byType(CalendarMonthChart), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });
}
