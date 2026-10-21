import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_month_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_week_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_completion_pie.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_page.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_month_chart.dart';
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

const _pieKey = ValueKey('calendar-period-pie');
const _totalKey = ValueKey('calendar-period-pie-total');
const _emptyKey = ValueKey('calendar-period-pie-empty');

const _taskTitles = ['基础一轮', '英语阅读', '408 真题'];

/// One recorded-learning row of the fixture plan.
class _Entry {
  const _Entry(this.date, this.taskIndex, this.minutes);

  final String date;
  final int taskIndex;
  final int minutes;
}

/// Deterministic three-owner period around the current Shanghai day:
///
/// * today:    基础一轮 30 + 英语阅读 45  → 2 owners, 75 minutes
/// * tomorrow: 基础一轮 20                → 1 owner, 20 minutes
/// * a third day inside the natural month of today: 408 真题 55 → 55 minutes
class _Period {
  _Period() {
    final today = shanghaiToday();
    final tomorrow = addDate(today, 1);
    this.today = today;
    this.tomorrow = tomorrow;
    monthDates = _monthDatesOf(today);
    final candidates = [
      for (final date in monthDates)
        if (date != today && date != tomorrow) date,
    ];
    thirdDate = candidates.first;
    entries = [
      _Entry(today, 0, 30),
      _Entry(today, 1, 45),
      _Entry(tomorrow, 0, 20),
      _Entry(thirdDate, 2, 55),
    ];
  }

  late final String today;
  late final String tomorrow;
  late final String thirdDate;
  late final List<String> monthDates;
  late final List<_Entry> entries;

  int minutesOn(String date) => entries
      .where((entry) => entry.date == date)
      .fold(0, (sum, entry) => sum + entry.minutes);

  int ownersOn(String date) => entries
      .where((entry) => entry.date == date)
      .map((e) => e.taskIndex)
      .toSet()
      .length;

  int minutesIn(Iterable<String> dates) {
    final set = dates.toSet();
    return entries
        .where((entry) => set.contains(entry.date))
        .fold(0, (sum, entry) => sum + entry.minutes);
  }

  int ownersIn(Iterable<String> dates) {
    final set = dates.toSet();
    return entries
        .where((entry) => set.contains(entry.date))
        .map((entry) => entry.taskIndex)
        .toSet()
        .length;
  }

  int minutesInMonthOf(String date) => entries
      .where((entry) => entry.date.substring(0, 7) == date.substring(0, 7))
      .fold(0, (sum, entry) => sum + entry.minutes);

  int ownersInMonthOf(String date) => entries
      .where((entry) => entry.date.substring(0, 7) == date.substring(0, 7))
      .map((entry) => entry.taskIndex)
      .toSet()
      .length;

  /// A day inside the same month that has no recorded minute.
  String get emptyDate => monthDates.firstWhere(
    (date) => entries.every((entry) => entry.date != date),
  );

  PlannerData toPlannerData() {
    final fixture = plannerFixture();
    final tasks = [
      for (var index = 0; index < _taskTitles.length; index++)
        fixture.tasks.single.copyWith(
          id: 'task-${index + 1}',
          title: _taskTitles[index],
        ),
    ];
    return fixture.copyWith(
      tasks: tasks,
      blocks: const [],
      logs: [
        for (var index = 0; index < entries.length; index++)
          TimeLog(
            id: 'log-$index',
            userId: fixture.profile.userId,
            taskId: tasks[entries[index].taskIndex].id,
            blockId: null,
            date: entries[index].date,
            minutes: entries[index].minutes,
            startedAt: '${entries[index].date}T00:00:00.000Z',
            endedAt: '${entries[index].date}T01:00:00.000Z',
            source: LogSource.timer,
            relation: TimeLogRelation.extra,
          ),
      ],
    );
  }
}

List<String> _monthDatesOf(String date) {
  final monthStart = '${date.substring(0, 7)}-01';
  final nextMonthStart = addMonth(monthStart, 1);
  final days = <String>[];
  var cursor = monthStart;
  while (cursor.compareTo(nextMonthStart) < 0) {
    days.add(cursor);
    cursor = addDate(cursor, 1);
  }
  return days;
}

Future<ProviderContainer> _pumpCalendarPage(
  WidgetTester tester,
  PlannerData data, {
  Size size = const Size(1200, 3200),
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

String _pieTotal(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_totalKey)).data!;

Future<void> _switchMode(WidgetTester tester, String label) async {
  // Scope to the segmented control: scope content (e.g. the month weekday
  // header "日") may contain the same one-character label.
  final switcher = find.byKey(const ValueKey('calendar-mode-switch'));
  await tester.tap(find.descendant(of: switcher, matching: find.text(label)));
  await tester.pumpAndSettle();
}

Future<void> _tapDay(WidgetTester tester, String date) async {
  final day = find.byKey(ValueKey('calendar-month-day-$date'));
  expect(day, findsOneWidget, reason: 'the month grid must show $date');
  await tester.tap(day);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('day, week and month scopes all show the period pie at the top', (
    tester,
  ) async {
    final period = _Period();
    await _pumpCalendarPage(tester, period.toPlannerData());

    // Day scope: the pie opens the scope above the shared day totals.
    expect(find.byType(CalendarCompletionPie), findsOneWidget);
    expect(find.byKey(_pieKey), findsOneWidget);
    expect(find.text('本期完成事项'), findsOneWidget);
    expect(find.text('按实际学习用时'), findsOneWidget);
    expect(_pieTotal(tester), duration(period.minutesOn(period.today)));
    expect(find.text('共 ${period.ownersOn(period.today)} 个事项'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(_pieKey)).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('calendar-day-totals'))).top,
      ),
    );

    // Stepping the selected day changes the pie; returning restores it.
    await tester.tap(find.byKey(const ValueKey('calendar-next-day')));
    await tester.pumpAndSettle();
    expect(find.byKey(_pieKey), findsOneWidget);
    expect(_pieTotal(tester), duration(period.minutesOn(period.tomorrow)));
    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await tester.pumpAndSettle();
    expect(_pieTotal(tester), duration(period.minutesOn(period.today)));

    // Week scope: one whole-week pie above the week chart.
    await _switchMode(tester, '周');
    expect(find.byKey(_pieKey), findsOneWidget);
    expect(
      _pieTotal(tester),
      duration(period.minutesIn(calendarWeekDates(period.today))),
    );
    expect(find.byType(CalendarWeekChart), findsOneWidget);
    expect(
      tester.getRect(find.byKey(_pieKey)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(CalendarWeekChart)).top),
    );

    // Month scope: one whole-month pie above the month chart.
    await _switchMode(tester, '月');
    expect(find.byKey(_pieKey), findsOneWidget);
    expect(_pieTotal(tester), duration(period.minutesInMonthOf(period.today)));
    expect(
      find.text('共 ${period.ownersInMonthOf(period.today)} 个事项'),
      findsOneWidget,
    );
    expect(find.byType(CalendarMonthChart), findsOneWidget);
    expect(
      tester.getRect(find.byKey(_pieKey)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(CalendarMonthChart)).top),
    );

    // Selecting another day in the month grid keeps the month pie unchanged,
    // then the day scope shows that day's own slice.
    await _tapDay(tester, period.thirdDate);
    expect(_pieTotal(tester), duration(period.minutesInMonthOf(period.today)));
    await _switchMode(tester, '日');
    expect(
      find.byKey(ValueKey('calendar-day-${period.thirdDate}')),
      findsOneWidget,
    );
    expect(_pieTotal(tester), duration(period.minutesOn(period.thirdDate)));
    expect(
      find.text('共 ${period.ownersOn(period.thirdDate)} 个事项'),
      findsOneWidget,
    );

    // A day without records shows the quiet empty state instead of a donut.
    final emptyDate = period.emptyDate;
    await _switchMode(tester, '月');
    await _tapDay(tester, emptyDate);
    await _switchMode(tester, '日');
    expect(find.byKey(_emptyKey), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(_emptyKey)).data, '本期还没有学习记录');
    expect(find.byKey(_totalKey), findsNothing);
    expect(find.byType(CalendarCompletionPie), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the period pie is read-only in every scope', (tester) async {
    final period = _Period();
    await _pumpCalendarPage(
      tester,
      period.toPlannerData(),
      size: const Size(1000, 3200),
    );

    for (final label in ['日', '周', '月']) {
      if (label != '日') await _switchMode(tester, label);
      final pie = find.byKey(_pieKey);
      expect(pie, findsOneWidget, reason: label);
      expect(
        find.text('本期完成事项'),
        findsOneWidget,
        reason: 'the pie must be visible in the $label scope',
      );
      for (final control in <Finder>[
        find.byType(TextButton),
        find.byType(FilledButton),
        find.byType(OutlinedButton),
        find.byType(IconButton),
        find.byType(TextField),
        find.byType(Checkbox),
        find.byType(Switch),
        find.byType(Slider),
      ]) {
        expect(
          find.descendant(of: pie, matching: control),
          findsNothing,
          reason: '$control inside the $label pie',
        );
      }
      expect(find.text('开始计时'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.byType(LongPressDraggable), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('period pie fits 320px in all three scopes', (tester) async {
    final period = _Period();
    await _pumpCalendarPage(
      tester,
      period.toPlannerData(),
      size: const Size(320, 6000),
    );

    for (final label in ['日', '周', '月']) {
      if (label != '日') await _switchMode(tester, label);
      final pie = find.byKey(_pieKey);
      expect(pie, findsOneWidget, reason: label);
      expect(tester.getSize(pie).width, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull, reason: label);
    }
  });
}
