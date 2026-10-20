import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_week_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_day_chart.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_page.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_week_chart.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const _weekStartDate = '2026-10-19';

ScheduleBlock _block(
  PlannerData data, {
  required String id,
  required String taskId,
  required String date,
  int minutes = 60,
  int startMinute = 0,
}) => ScheduleBlock(
  id: id,
  userId: data.profile.userId,
  taskId: taskId,
  date: date,
  startMinute: startMinute,
  durationMinutes: minutes,
  actualMinutes: 0,
  isFixed: false,
  status: BlockStatus.planned,
  createdAt: '${date}T00:00:00+08:00',
  updatedAt: '${date}T00:00:00+08:00',
);

TimeLog _log(
  PlannerData data, {
  required String id,
  required int minutes,
  required String date,
  String? taskId,
  String? adHocId,
  TimeLogRelation relation = TimeLogRelation.legacyUnknown,
}) => TimeLog(
  id: id,
  userId: data.profile.userId,
  taskId: taskId,
  adHocId: adHocId,
  blockId: null,
  date: date,
  minutes: minutes,
  relation: relation,
  startedAt: '${date}T00:00:00+08:00',
  endedAt: '${date}T01:00:00+08:00',
  source: LogSource.timer,
);

/// A week that exercises every required display state:
/// plan gap + extra on the same unfilled item, an unscheduled existing item,
/// historical temporary learning that must stay invisible, an only-plan day, a
/// blank day, an over-plan day and a long item title.
PlannerData _scenarioData({
  required String anchor,
  String longTitle = '超长的学习事项名称：用于确认完整名称可以在窄屏换行显示而不溢出',
}) {
  final base = plannerFixture();
  final task = base.tasks.single;
  final english = base.tags.single.copyWith(
    id: 'english',
    name: '英语',
    color: '#1f7a5c',
  );
  final plannedOnly = task.copyWith(
    id: 'planned-only',
    tagIds: [english.id],
    title: '仅计划事项',
  );
  final unscheduled = task.copyWith(id: 'unscheduled', title: longTitle);
  final over = task.copyWith(id: 'over', title: '超计划事项');

  String date(int offset) => addDate(anchor, offset);

  return base.copyWith(
    tags: [base.tags.single, english],
    tasks: [task, plannedOnly, unscheduled, over],
    // Retired temporary learning: still present in historical data, but the
    // read-only calendar must never project it into an item or a legend.
    adHocLearnings: [
      AdHocLearning(
        id: 'photo',
        userId: base.profile.userId,
        title: '摄影构图（历史记录）',
        createdAt: '${date(0)}T00:00:00+08:00',
        updatedAt: '${date(0)}T00:00:00+08:00',
      ),
    ],
    blocks: [
      _block(base, id: 'b1', taskId: task.id, date: date(0), minutes: 60),
      _block(
        base,
        id: 'b2',
        taskId: plannedOnly.id,
        date: date(3),
        minutes: 45,
        startMinute: 60,
      ),
      _block(base, id: 'b3', taskId: over.id, date: date(5), minutes: 30),
    ],
    logs: [
      _log(
        base,
        id: 'l1',
        taskId: task.id,
        date: date(0),
        minutes: 20,
        relation: TimeLogRelation.scheduled,
      ),
      _log(
        base,
        id: 'l2',
        taskId: task.id,
        date: date(0),
        minutes: 30,
        relation: TimeLogRelation.extra,
      ),
      _log(
        base,
        id: 'l3',
        taskId: unscheduled.id,
        date: date(1),
        minutes: 25,
        relation: TimeLogRelation.extra,
      ),
      // Retired temporary-learning row: any projection of it would surface the
      // owner title, an ad-hoc layer or extra actual minutes.
      _log(
        base,
        id: 'l4',
        adHocId: 'photo',
        date: date(2),
        minutes: 15,
        relation: TimeLogRelation.adHoc,
      ),
      _log(
        base,
        id: 'l5',
        taskId: over.id,
        date: date(5),
        minutes: 30,
        relation: TimeLogRelation.scheduled,
      ),
      _log(
        base,
        id: 'l6',
        taskId: over.id,
        date: date(5),
        minutes: 90,
        relation: TimeLogRelation.extra,
      ),
    ],
  );
}

class _WeekHost extends StatefulWidget {
  const _WeekHost({
    required this.week,
    required this.view,
    required this.initialDate,
    super.key,
  });

  final CalendarWeekData week;
  final CalendarWeekView view;
  final String initialDate;

  @override
  State<_WeekHost> createState() => _WeekHostState();
}

class _WeekHostState extends State<_WeekHost> {
  late String _selectedDate = widget.initialDate;

  @override
  Widget build(BuildContext context) => CalendarWeekChart(
    week: widget.week,
    view: widget.view,
    selectedDate: _selectedDate,
    onSelectDate: (date) => setState(() => _selectedDate = date),
  );
}

Future<void> _pumpWeekHost(
  WidgetTester tester,
  CalendarWeekData week,
  CalendarWeekView view, {
  String? initialDate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: plannerTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: _WeekHost(
            key: ValueKey(
              'week-${week.weekStart}-${view.name}-'
              '${initialDate ?? week.days[1].date}',
            ),
            week: week,
            view: view,
            initialDate: initialDate ?? week.days[1].date,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectSevenDayButtons(CalendarWeekData week) {
  for (final day in week.days) {
    expect(
      find.byKey(ValueKey('calendar-week-day-${day.date}')),
      findsOneWidget,
    );
  }
  expect(find.byKey(const ValueKey('calendar-week-axis')), findsOneWidget);
}

/// In-memory chart preference stores.
///
/// The real Sembast-backed store is covered by the unit tests; the page widget
/// test only needs to prove the week wiring and legacy day-choice compatibility,
/// must not perform real file I/O inside Flutter's fake-async test zone.
class _MemoryDayViewStore implements CalendarViewPreferenceStore {
  CalendarView value = CalendarView.rivers;
  final saved = <CalendarView>[];

  @override
  Future<CalendarView> load() async => value;

  @override
  Future<void> save(CalendarView view) async {
    value = view;
    saved.add(view);
  }
}

class _MemoryWeekViewStore implements CalendarWeekViewPreferenceStore {
  CalendarWeekView value = CalendarWeekView.mirror;
  final saved = <CalendarWeekView>[];

  @override
  Future<CalendarWeekView> load() async => value;

  @override
  Future<void> save(CalendarWeekView view) async {
    value = view;
    saved.add(view);
  }
}

Future<ProviderContainer> _pumpCalendarPage(
  WidgetTester tester,
  PlannerData data, {
  required _MemoryDayViewStore dayStore,
  required _MemoryWeekViewStore weekStore,
}) async {
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
      calendarViewPreferenceStoreProvider.overrideWithValue(dayStore),
      calendarWeekViewPreferenceStoreProvider.overrideWithValue(weekStore),
    ],
  );
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

/// Bounded settle so a non-settling animation fails at the offending call.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 50),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 20),
);

void main() {
  testWidgets(
    'both whole-week charts show all seven days in one plot with identical facts',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = _scenarioData(anchor: _weekStartDate);
      final week = buildCalendarWeekData(data, _weekStartDate);
      expect(week.days, hasLength(7));
      expect(
        [for (final day in week.days) day.plannedMinutes],
        [60, 0, 0, 45, 0, 30, 0],
      );
      expect(
        [for (final day in week.days) day.actualMinutes],
        [50, 25, 0, 0, 0, 120, 0],
      );
      // Wednesday carries only historical temporary-learning minutes: it is an
      // empty day and adds nothing to the shared week facts.
      expect(week.days[2].day.items, isEmpty);
      expect(week.actualMinutes, 195);

      final facts = <String, ({String totals, List<String> items})>{};
      for (final view in CalendarWeekView.values) {
        await _pumpWeekHost(tester, week, view, initialDate: week.days[1].date);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('calendar-week-chart')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey(
              view == CalendarWeekView.mirror
                  ? 'calendar-week-mirror-canvas'
                  : 'calendar-week-mountain-canvas',
            ),
          ),
          findsOneWidget,
          reason: '${view.name} must be one whole-week coordinate system',
        );
        _expectSevenDayButtons(week);
        expect(
          find.text('周计划 ${duration(week.plannedMinutes)}'),
          findsOneWidget,
        );
        expect(
          find.text('周实学 ${duration(week.actualMinutes)}'),
          findsOneWidget,
        );
        // Effort types remain identified with text and pattern legends.
        expect(
          find.byKey(const ValueKey('calendar-week-kind-planned')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('calendar-week-kind-scheduled')),
          findsOneWidget,
        );
        expect(find.text('计划外'), findsOneWidget);
        // Regression guard: historical temporary learning is never rendered.
        expect(find.textContaining('摄影构图'), findsNothing);
        expect(find.textContaining('临时学习'), findsNothing);
        // The overview stays compact until the user asks for a day's facts.
        expect(
          find.byKey(const ValueKey('calendar-week-detail')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('calendar-week-detail-totals')),
          findsNothing,
        );
        expect(find.textContaining('用于确认完整名称'), findsNothing);
        expect(find.textContaining('两个方向使用同一分钟比例'), findsNothing);
        expect(find.textContaining('课程'), findsNothing);
        await tester.tap(
          find.byKey(ValueKey('calendar-week-day-${week.days[1].date}')),
        );
        await tester.pumpAndSettle();
        // On-demand detail stays complete and identical in both chart modes.
        expect(
          find.byKey(const ValueKey('calendar-week-detail')),
          findsOneWidget,
        );
        final detailTotals = tester
            .widget<Text>(
              find.byKey(const ValueKey('calendar-week-detail-totals')),
            )
            .data!;
        expect(detailTotals, contains('计划'));
        expect(find.textContaining('用于确认完整名称'), findsWidgets);
        facts[view.name] = (
          totals: detailTotals,
          items: [
            for (final item in week.itemsFor(week.days[1].date)) item.title,
          ],
        );
        // The read-only popover fits a 320px viewport.
        final detailRect = tester.getRect(
          find.byKey(const ValueKey('calendar-week-detail')),
        );
        expect(detailRect.left, greaterThanOrEqualTo(0));
        expect(detailRect.right, lessThanOrEqualTo(320));
        // Re-open the chart fresh (no popover) and select Saturday's complete
        // detail; this also checks that the popover starts closed.
        await _pumpWeekHost(tester, week, view, initialDate: week.days[5].date);
        expect(
          find.byKey(const ValueKey('calendar-week-detail')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(ValueKey('calendar-week-day-${week.days[5].date}')),
        );
        await tester.pumpAndSettle();
        expect(find.text(fullDateLabel(week.days[5].date)), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('calendar-week-detail-totals')),
              )
              .data,
          '计划 ${duration(week.days[5].plannedMinutes)} · '
          '实学 ${duration(week.days[5].actualMinutes)}',
        );
        expect(find.text('超计划事项'), findsWidgets);
        expect(tester.takeException(), isNull);
      }
      expect(facts['mirror']!.totals, facts['mountain']!.totals);
      expect(facts['mirror']!.items, facts['mountain']!.items);
      // Read-only: no completion controls or editing affordances.
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.text('已完成'), findsNothing);
    },
  );

  testWidgets(
    'empty, plan-only, actual-only and only-plan weeks keep seven positions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = plannerFixture();
      final task = base.tasks.single;
      final fixtures = <PlannerData>[
        base.copyWith(blocks: [], logs: []),
        base.copyWith(logs: []),
        base.copyWith(blocks: []),
        base.copyWith(
          tasks: [task.copyWith(id: 'actual-only', title: '仅实学的历史事项')],
          blocks: [],
          logs: [
            _log(
              base,
              id: 'actual-only',
              taskId: 'actual-only',
              date: _weekStartDate,
              minutes: 45,
              relation: TimeLogRelation.extra,
            ),
          ],
        ),
      ];
      for (final data in fixtures) {
        final week = buildCalendarWeekData(data, _weekStartDate);
        for (final view in CalendarWeekView.values) {
          await _pumpWeekHost(tester, week, view);
          expect(tester.takeException(), isNull);
          _expectSevenDayButtons(week);
          expect(
            find.text('周计划 ${duration(week.plannedMinutes)}'),
            findsOneWidget,
          );
          expect(
            find.text('周实学 ${duration(week.actualMinutes)}'),
            findsOneWidget,
          );
          if (week.isEmpty) {
            expect(
              find.byKey(const ValueKey('calendar-week-empty')),
              findsOneWidget,
            );
          }
        }
      }
    },
  );

  testWidgets('hover, chart taps and keyboard expose day facts on demand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _scenarioData(anchor: _weekStartDate);
    final week = buildCalendarWeekData(data, _weekStartDate);
    await _pumpWeekHost(
      tester,
      week,
      CalendarWeekView.mirror,
      initialDate: week.days[3].date,
    );
    final canvas = find.byKey(const ValueKey('calendar-week-mirror-canvas'));
    final rect = tester.getRect(canvas);
    final host = tester.state<_WeekHostState>(find.byType(_WeekHost));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: rect.center);
    addTearDown(gesture.removePointer);
    // Hover reveals complete text without adding a permanent detail list or
    // changing the selected date.
    await gesture.moveTo(
      Offset(rect.left + 36 + (rect.width - 36) / 7 * .5, rect.center.dy),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(fullDateLabel(week.days[0].date)),
      findsOneWidget,
    );
    expect(
      find.textContaining(week.days[0].day.items.first.title),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar-week-detail')), findsNothing);
    expect(host._selectedDate, week.days[3].date);
    await gesture.moveTo(Offset(rect.right + 40, rect.bottom + 80));
    await tester.pumpAndSettle();
    expect(find.textContaining(fullDateLabel(week.days[0].date)), findsNothing);
    expect(find.byKey(const ValueKey('calendar-week-detail')), findsNothing);
    expect(host._selectedDate, week.days[3].date);

    // Tapping an arbitrarily short/empty graph column still opens the full day.
    await tester.tapAt(
      Offset(rect.left + 36 + (rect.width - 36) / 7 * 1.5, rect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-week-detail')), findsOneWidget);
    expect(find.textContaining('用于确认完整名称'), findsWidgets);
    expect(host._selectedDate, week.days[1].date);

    // Tab reaches the first day control; Enter activates it like a tap.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text(fullDateLabel(week.days[0].date)), findsOneWidget);

    final semantics = tester.ensureSemantics();
    final dayNode = tester.getSemantics(
      find.byKey(ValueKey('calendar-week-day-${week.days[0].date}')),
    );
    expect(dayNode.label, contains('计划'));
    expect(dayNode.label, contains('实学'));
    expect(dayNode.label, contains('10月19日 周一'));
    expect(dayNode.getSemanticsData().flagsCollection.isButton, isTrue);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('镜像图'))).label,
      contains('实学'),
    );
    semantics.dispose();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-week-detail')), findsNothing);
    expect(host._selectedDate, week.days[0].date);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page switches day/week and charts while keeping the selected date at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = shanghaiToday();
      final data = _scenarioData(anchor: today);
      final dayStore = _MemoryDayViewStore();
      final weekStore = _MemoryWeekViewStore();
      final container = await _pumpCalendarPage(
        tester,
        data,
        dayStore: dayStore,
        weekStore: weekStore,
      );
      addTearDown(container.dispose);

      // Day mode always shows the three graphics together in a fixed order.
      _expectDayStack(tester, today);
      expect(find.byType(CalendarWeekChart), findsNothing);
      expect(dayStore.saved, isEmpty);

      // Switch to the week scope: same date, one whole-week chart.
      await tester.tap(find.text('周'));
      await _settle(tester);
      expect(find.byType(CalendarWeekChart), findsOneWidget);
      expect(find.byType(CalendarDayTotals), findsNothing);
      var weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.selectedDate, today);
      expect(weekChart.view, CalendarWeekView.mirror);
      expect(weekChart.week.weekStart, calendarWeekStart(today));
      expect(weekChart.week.days, hasLength(7));

      // Week navigation moves by seven days and 本周 returns to today.
      await tester.tap(find.byKey(const ValueKey('calendar-next-week')));
      await _settle(tester);
      weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.selectedDate, addDate(today, 7));
      expect(weekChart.week.weekStart, addDate(calendarWeekStart(today), 7));
      await tester.tap(find.byKey(const ValueKey('calendar-previous-week')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-this-week')));
      await _settle(tester);
      weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.selectedDate, today);

      // Week chart choice is remembered and does not change the date.
      await tester.tap(find.byKey(const ValueKey('calendar-week-view-switch')));
      await _settle(tester);
      await tester.tap(find.text('学习山脉').last);
      await _settle(tester);
      expect(
        container.read(calendarWeekViewProvider),
        CalendarWeekView.mountain,
      );
      expect(weekStore.saved, [CalendarWeekView.mountain]);
      weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.view, CalendarWeekView.mountain);
      expect(weekChart.selectedDate, today);

      // Date picker opens in week scope too; cancelling changes nothing.
      await tester.tap(find.byKey(const ValueKey('calendar-date-picker')));
      await _settle(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _settle(tester);
      expect(
        tester
            .widget<CalendarWeekChart>(find.byType(CalendarWeekChart))
            .selectedDate,
        today,
      );

      // Selecting a day in the week axis keeps the shared date for day mode.
      final dayDate = addDate(calendarWeekStart(today), 4);
      await tester.tap(find.byKey(ValueKey('calendar-week-day-$dayDate')));
      await _settle(tester);
      expect(
        tester
            .widget<CalendarWeekChart>(find.byType(CalendarWeekChart))
            .selectedDate,
        dayDate,
      );
      expect(
        find.byKey(const ValueKey('calendar-week-detail')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      await tester.tap(find.text('日'));
      await _settle(tester);
      _expectDayStack(tester, dayDate);

      // No horizontal overflow and no hidden control absorbing the main plot.
      expect(tester.takeException(), isNull);
      for (final mode in CalendarView.values) {
        expect(
          tester
              .getSize(find.byKey(ValueKey('calendar-day-card-${mode.name}')))
              .width,
          lessThanOrEqualTo(320),
        );
      }
      await tester.tap(find.text('周'));
      await _settle(tester);
      expect(
        tester.getSize(find.byKey(const ValueKey('calendar-week-chart'))).width,
        lessThanOrEqualTo(320),
      );
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      final weekSwitchRect = tester
          .getSemantics(find.byKey(const ValueKey('calendar-week-view-switch')))
          .rect;
      expect(weekSwitchRect.height, lessThanOrEqualTo(60));
      final chartRect = tester.getRect(
        find.byKey(const ValueKey('calendar-week-chart')),
      );
      for (final day in calendarWeekDates(today)) {
        final node = tester.getSemantics(
          find.byKey(ValueKey('calendar-week-day-$day')),
        );
        expect(node.label, contains('实学'));
        expect(
          tester.getRect(find.byKey(ValueKey('calendar-week-day-$day'))).top,
          greaterThanOrEqualTo(chartRect.top),
          reason: 'day controls must belong to the panel, not cover it',
        );
      }
      semantics.dispose();

      // Read-only: the calendar exposes no completion/timer/edit controls.
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.text('已完成'), findsNothing);
      expect(find.text('开始计时'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'week preference restores while legacy day choice leaves all cards visible',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = shanghaiToday();
      final data = _scenarioData(anchor: today);
      final dayStore = _MemoryDayViewStore();
      final weekStore = _MemoryWeekViewStore();
      var container = await _pumpCalendarPage(
        tester,
        data,
        dayStore: dayStore,
        weekStore: weekStore,
      );

      _expectDayStack(tester, today);
      await tester.tap(find.text('周'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-week-view-switch')));
      await _settle(tester);
      await tester.tap(find.text('学习山脉').last);
      await _settle(tester);
      expect(
        container.read(calendarWeekViewProvider),
        CalendarWeekView.mountain,
      );

      // Reopen with a fresh provider container but the same saved preferences.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      container = await _pumpCalendarPage(
        tester,
        data,
        dayStore: dayStore,
        weekStore: weekStore,
      );
      addTearDown(container.dispose);

      // A stored day selection never hides a day graphic.
      _expectDayStack(tester, today);
      await tester.pumpAndSettle();
      expect(dayStore.value, CalendarView.rivers);
      expect(dayStore.saved, isEmpty);
      await tester.tap(find.text('周'));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(
        container.read(calendarWeekViewProvider),
        CalendarWeekView.mountain,
      );
      expect(
        tester.widget<CalendarWeekChart>(find.byType(CalendarWeekChart)).view,
        CalendarWeekView.mountain,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectDayStack(WidgetTester tester, String date) {
  final charts = tester
      .widgetList<CalendarDayChart>(find.byType(CalendarDayChart))
      .toList();
  expect(charts, hasLength(2));
  expect(charts.map((chart) => chart.view), CalendarView.values);
  expect(find.byKey(ValueKey('calendar-day-$date')), findsOneWidget);
  expect(find.byKey(const ValueKey('calendar-view-switch')), findsNothing);
  final totals = find.byKey(const ValueKey('calendar-day-totals'));
  expect(totals, findsOneWidget);
  expect(find.byType(CalendarDayTotals), findsOneWidget);
  expect(find.byKey(const ValueKey('calendar-planned-total')), findsOneWidget);
  expect(find.byKey(const ValueKey('calendar-actual-total')), findsOneWidget);
  expect(tester.widget<CalendarDayTotals>(totals).day, same(charts.first.day));
  expect(
    tester.getRect(totals).bottom,
    lessThanOrEqualTo(
      tester
          .getRect(find.byKey(const ValueKey('calendar-day-card-growth')))
          .top,
    ),
  );
  for (final chart in charts) {
    expect(chart.day.date, date);
    expect(identical(chart.day, charts.first.day), isTrue);
    expect(chart.showTitle, isTrue);
    expect(
      find.descendant(
        of: find.byWidget(chart),
        matching: find.byType(CalendarDayTotals),
      ),
      findsNothing,
    );
  }
}
