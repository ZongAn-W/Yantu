import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_month_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_month_chart.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_page.dart';
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

CalendarMonthChart _chart(WidgetTester tester) =>
    tester.widget<CalendarMonthChart>(find.byType(CalendarMonthChart));

FocusNode _gridFocusNode(WidgetTester tester) => tester
    .widget<Focus>(find.byKey(const ValueKey('calendar-month-keyboard')))
    .focusNode!;

/// Focus ring decoration is a 2 px spread shadow in [PlannerColors.focusRing].
final Finder _focusRingFinder = find.byWidgetPredicate((widget) {
  if (widget is! Container) return false;
  final decoration = widget.decoration;
  if (decoration is! BoxDecoration) return false;
  return (decoration.boxShadow ?? const <BoxShadow>[]).any(
    (shadow) =>
        shadow.color == PlannerColors.focusRing && shadow.spreadRadius == 2,
  );
});

Future<void> _openMonthScope(WidgetTester tester) async {
  await tester.tap(find.text('月'));
  await tester.pumpAndSettle();
  expect(find.byType(CalendarMonthChart), findsOneWidget);
}

void main() {
  testWidgets('arrow keys move the selected day from the focused month grid', (
    tester,
  ) async {
    final today = shanghaiToday();
    final first = '${today.substring(0, 7)}-01';
    final start = addDate(first, 9);
    await _pumpMonthPage(tester, _monthData(today: today));
    await _openMonthScope(tester);

    await tester.tap(find.byKey(ValueKey('calendar-month-day-$start')));
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, start);
    expect(
      _gridFocusNode(tester).hasFocus,
      isTrue,
      reason: 'clicking a day keeps the keyboard focus on the month grid',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, addDate(start, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, start);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, addDate(start, 7));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, start);

    // Space/Enter only confirm the current selection: no date change, no side
    // effect, and the focus stays on the grid.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, start);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, start);
    expect(_gridFocusNode(tester).hasFocus, isTrue);
    expect(_focusRingFinder, findsOneWidget);

    // The page must stay keyboard navigable after the steps.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_chart(tester).selectedDate, addDate(start, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PageUp/PageDown step whole months, keep focus and Home returns to today',
    (tester) async {
      final today = shanghaiToday();
      final month = today.substring(0, 7);
      final start = addDate('$month-01', 9);
      final nextMonth = addMonth(start, 1);
      final nextMonthKey = nextMonth.substring(0, 7);
      await _pumpMonthPage(tester, _monthData(today: today));
      await _openMonthScope(tester);

      await tester.tap(find.byKey(ValueKey('calendar-month-day-$start')));
      await tester.pumpAndSettle();
      expect(_chart(tester).selectedDate, start);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(_chart(tester).selectedDate, nextMonth);
      expect(
        find.byKey(ValueKey('calendar-month-$nextMonthKey')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('calendar-month-day-$nextMonth')),
        findsOneWidget,
      );
      expect(
        _gridFocusNode(tester).hasFocus,
        isTrue,
        reason: 'PageDown must hand the focus to the rebuilt next month grid',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(_chart(tester).selectedDate, start);
      expect(find.byKey(ValueKey('calendar-month-$month')), findsOneWidget);
      expect(_gridFocusNode(tester).hasFocus, isTrue);

      // Home returns to today even when today is in a different month.
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(_chart(tester).selectedDate.substring(0, 7), nextMonthKey);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(_chart(tester).selectedDate, shanghaiToday());
      expect(find.byKey(ValueKey('calendar-month-$month')), findsOneWidget);
      expect(_gridFocusNode(tester).hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'focus ring follows the grid focus and 320px stays overflow free',
    (tester) async {
      final today = shanghaiToday();
      final first = '${today.substring(0, 7)}-01';
      await _pumpMonthPage(
        tester,
        _monthData(today: today),
        size: const Size(320, 2600),
      );
      await _openMonthScope(tester);

      expect(_focusRingFinder, findsNothing);
      final focusNode = _gridFocusNode(tester);
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(_focusRingFinder, findsOneWidget);
      expect(tester.takeException(), isNull);

      focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(_focusRingFinder, findsNothing);

      final target = addDate(first, 4);
      await tester.tap(find.byKey(ValueKey('calendar-month-day-$target')));
      await tester.pumpAndSettle();
      expect(_chart(tester).selectedDate, target);
      expect(focusNode.hasFocus, isTrue);
      expect(_focusRingFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Tab reaches the month grid and shows the focus ring', (
    tester,
  ) async {
    final today = shanghaiToday();
    await _pumpMonthPage(tester, _monthData(today: today));
    await _openMonthScope(tester);

    var reached = false;
    for (var step = 0; step < 30; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      if (_gridFocusNode(tester).hasFocus) {
        reached = true;
        break;
      }
    }
    expect(reached, isTrue, reason: 'Tab must reach the month grid');
    expect(_focusRingFinder, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
