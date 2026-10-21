import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_day_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_week_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_day_chart.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_week_chart.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/router/app_router.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import 'planner_ui_test.dart' as harness;

void main() {
  testWidgets(
    'calendar is read-only and keeps two stacked day charts on the shared date',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = harness.FakeSyncServer(plan: harness.todayFixture());
      final container = await harness.signIn(tester, respond: server.respond);
      container.read(appRouterProvider).go('/calendar');
      await tester.pumpAndSettle();

      _expectStackedDay(tester, shanghaiToday());
      expect(find.text('日'), findsOneWidget);
      expect(find.text('周'), findsOneWidget);
      expect(find.text('已完成'), findsNothing);
      expect(find.textContaining('本周期'), findsNothing);
      expect(find.text('学习日历'), findsNothing);
      expect(find.byType(LongPressDraggable), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.text('开始计时'), findsNothing);
      expect(find.byKey(const ValueKey('calendar-view-switch')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('calendar-next-day')));
      await tester.pumpAndSettle();
      final tomorrow = addDate(shanghaiToday(), 1);
      _expectStackedDay(tester, tomorrow);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('calendar-today')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('calendar-day-${shanghaiToday()}')),
        findsOneWidget,
      );
      _expectStackedDay(tester, shanghaiToday());
      await tester.tap(find.byKey(const ValueKey('calendar-previous-day')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('calendar-day-${addDate(shanghaiToday(), -1)}')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-date-picker')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('planner-date-picker')), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      final sharedDate = addDate(shanghaiToday(), -1);
      _expectStackedDay(tester, sharedDate);

      // Week scope: one whole-week chart keeps the very same selected date.
      await tester.tap(find.text('周'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarWeekChart), findsOneWidget);
      expect(find.byType(CalendarDayTotals), findsNothing);
      var weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.selectedDate, sharedDate);
      expect(weekChart.view, CalendarWeekView.mirror);
      expect(weekChart.week.days, hasLength(7));
      expect(weekChart.week.weekStart, calendarWeekStart(sharedDate));
      for (final date in calendarWeekDates(sharedDate)) {
        expect(find.byKey(ValueKey('calendar-week-day-$date')), findsOneWidget);
      }
      final weekSemantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('calendar-week-view-switch')),
            )
            .rect
            .height,
        lessThanOrEqualTo(60),
        reason: 'the week selector must not absorb the main chart semantics',
      );
      weekSemantics.dispose();

      // Week navigation moves the shared date by seven days.
      await tester.tap(find.byKey(const ValueKey('calendar-next-week')));
      await tester.pumpAndSettle();
      weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.selectedDate, addDate(sharedDate, 7));
      await tester.tap(find.byKey(const ValueKey('calendar-previous-week')));
      await tester.pumpAndSettle();
      weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.selectedDate, sharedDate);
      await tester.tap(find.byKey(const ValueKey('calendar-this-week')));
      await tester.pumpAndSettle();
      weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.selectedDate, shanghaiToday());

      // Week graphic switching also keeps the selected date.
      await tester.tap(find.byKey(const ValueKey('calendar-week-view-switch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('学习山脉').last);
      await tester.pumpAndSettle();
      weekChart = tester.widget<CalendarWeekChart>(
        find.byType(CalendarWeekChart),
      );
      expect(weekChart.view, CalendarWeekView.mountain);
      expect(weekChart.selectedDate, shanghaiToday());
      expect(find.byKey(const ValueKey('calendar-week-chart')), findsOneWidget);

      // Back to the day scope: all three cards use the same selected date.
      await tester.tap(find.text('日'));
      await tester.pumpAndSettle();
      _expectStackedDay(tester, shanghaiToday());
      expect(
        server.pushCount,
        0,
        reason: 'read-only navigation must never write schedules or logs',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'all day charts name owners inside the graphic and expose read-only details at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = harness.todayFixture();
      final task = base.tasks.single;
      final other = task.copyWith(
        id: 'unplanned',
        title: '未排程事项：很长的学习名称用于检验换行与可读性',
      );
      final date = shanghaiToday();
      final data = base.copyWith(
        tasks: [
          task.copyWith(completedAt: '2026-10-16T00:00:00.000Z'),
          other,
        ],
        blocks: [base.blocks.single.copyWith(durationMinutes: 60)],
        // Historical temporary-learning data: retired in the client, so the
        // read-only calendar must never project it into an item or a legend.
        adHocLearnings: [
          AdHocLearning(
            id: 'reading',
            userId: task.userId,
            title: '临时学习：阅读',
            createdAt: '2026-10-19',
            updatedAt: '2026-10-19',
          ),
        ],
        logs: [
          _log(
            task.userId,
            date,
            'scheduled',
            task.id,
            20,
            TimeLogRelation.scheduled,
          ),
          _log(task.userId, date, 'extra', task.id, 15, TimeLogRelation.extra),
          _log(task.userId, date, 'other', other.id, 10, TimeLogRelation.extra),
          _log(
            task.userId,
            date,
            'temporary',
            null,
            5,
            TimeLogRelation.adHoc,
            adHocId: 'reading',
          ),
        ],
      );
      final day = buildCalendarDayData(data, date);
      // The 5 historical ad-hoc minutes are ignored: 20 scheduled + 15 + 10 extra.
      expect(day.actualMinutes, 45);
      expect(day.plannedMinutes, 60);
      expect(day.items, hasLength(2));
      expect(day.items.any((item) => item.id.startsWith('adhoc:')), isFalse);
      final colors = <String, Color?>{};
      for (final mode in CalendarView.values) {
        await _show(tester, day, mode);
        expect(find.text('计划 1小时'), findsOneWidget);
        expect(find.text('实学 45分钟'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-day-chart')),
          findsOneWidget,
        );
        expect(
          find.byType(Divider),
          findsNothing,
          reason: 'there is no independent item detail section below the chart',
        );
        for (final item in day.items) {
          final name = find.byKey(
            ValueKey('calendar-chart-label-text-${item.id}'),
          );
          final target = find.byKey(
            ValueKey('calendar-chart-label-target-${item.id}'),
          );
          expect(name, findsOneWidget, reason: '${mode.name}: ${item.title}');
          expect(tester.widget<Text>(name).data, item.title);
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pump();
          final details = find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                widget.message?.startsWith('${item.title}，') == true,
          );
          expect(details, findsOneWidget);
          final tooltip = tester.widget<Tooltip>(details);
          expect(
            tooltip.message,
            contains('计划 ${duration(item.plannedMinutes)}'),
          );
          expect(
            tooltip.message,
            contains('实学 ${duration(item.actualMinutes)}'),
          );
          final dot = tester.widget<DecoratedBox>(
            find.byKey(ValueKey('calendar-chart-color-${item.id}')),
          );
          final color = (dot.decoration as BoxDecoration).color;
          colors.putIfAbsent(item.id, () => color);
          expect(color, colors[item.id]);
          expect(tester.takeException(), isNull);
        }
        expect(find.textContaining('已有事项加学'), findsWidgets);
        expect(find.textContaining('当天未排程的事项'), findsWidgets);
        // Regression guard: even when historical ad-hoc data is present in the
        // plan, no temporary-learning item, kind or legend text is rendered.
        expect(find.textContaining('临时学习'), findsNothing);
        expect(find.byIcon(Icons.check_circle), findsNothing);
      }
    },
  );

  testWidgets(
    'empty, plan-only, actual-only, zero capacity, over-plan and many items render in every view',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final base = harness.todayFixture();
      final task = base.tasks.single;
      final date = shanghaiToday();
      final fixtures = [
        base.copyWith(blocks: [], logs: []),
        base.copyWith(logs: []),
        base.copyWith(
          blocks: [],
          logs: [
            _log(
              task.userId,
              date,
              'extra',
              task.id,
              240,
              TimeLogRelation.extra,
            ),
          ],
        ),
        base.copyWith(
          profile: base.profile.copyWith(dateCapacityOverrides: {date: 0}),
          logs: [
            _log(
              task.userId,
              date,
              'over',
              task.id,
              600,
              TimeLogRelation.extra,
            ),
          ],
        ),
        base.copyWith(
          tasks: [
            for (var i = 0; i < 28; i++)
              task.copyWith(id: 'item-$i', title: '大量事项 $i：完整名称可换行'),
          ],
          blocks: [
            for (var i = 0; i < 28; i++)
              base.blocks.single.copyWith(
                id: 'b-$i',
                taskId: 'item-$i',
                durationMinutes: i + 1,
              ),
          ],
          logs: [
            for (var i = 0; i < 28; i++)
              _log(
                task.userId,
                date,
                'l-$i',
                'item-$i',
                1,
                TimeLogRelation.extra,
              ),
          ],
        ),
      ];
      for (final plan in fixtures) {
        final day = buildCalendarDayData(plan, date);
        for (final mode in CalendarView.values) {
          await _show(tester, day, mode);
          expect(
            tester.takeException(),
            isNull,
            reason: '${day.items.length} items in ${mode.name}',
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('calendar-actual-total')),
                )
                .data,
            '实学 ${duration(day.actualMinutes)}',
          );
          if (day.items.isNotEmpty) {
            for (final item in day.items) {
              expect(
                find.byKey(ValueKey('calendar-chart-label-${item.id}')),
                findsOneWidget,
              );
            }
            await tester.ensureVisible(
              find.byKey(
                ValueKey('calendar-chart-label-target-${day.items.last.id}'),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );
}

void _expectStackedDay(WidgetTester tester, String date) {
  final charts = tester
      .widgetList<CalendarDayChart>(find.byType(CalendarDayChart))
      .toList();
  expect(charts.map((chart) => chart.view), CalendarView.values);
  expect(charts, hasLength(2));
  expect(find.byKey(ValueKey('calendar-day-$date')), findsOneWidget);
  expect(find.byKey(const ValueKey('calendar-day-chart')), findsNWidgets(2));
  expect(find.byKey(const ValueKey('calendar-view-switch')), findsNothing);
  final totals = find.byKey(const ValueKey('calendar-day-totals'));
  expect(totals, findsOneWidget);
  expect(find.byType(CalendarDayTotals), findsOneWidget);
  expect(find.byKey(const ValueKey('calendar-planned-total')), findsOneWidget);
  expect(find.byKey(const ValueKey('calendar-actual-total')), findsOneWidget);
  expect(tester.widget<CalendarDayTotals>(totals).day, same(charts.first.day));
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('calendar-planned-total')))
        .data,
    '计划 ${duration(charts.first.day.plannedMinutes)}',
  );
  expect(
    tester
        .widget<Text>(find.byKey(const ValueKey('calendar-actual-total')))
        .data,
    '实学 ${duration(charts.first.day.actualMinutes)}',
  );
  for (final chart in charts) {
    expect(chart.day.date, date);
    expect(identical(chart.day, charts.first.day), isTrue);
    expect(chart.showTitle, isTrue);
    expect(find.text(chart.view.label), findsOneWidget);
    expect(
      find.descendant(
        of: find.byWidget(chart),
        matching: find.byType(CalendarDayTotals),
      ),
      findsNothing,
      reason: 'the selected day totals belong above the stack, not in a card',
    );
  }
  final panels = [
    for (final mode in CalendarView.values)
      tester.getRect(find.byKey(ValueKey('calendar-day-card-${mode.name}'))),
  ];
  for (var i = 1; i < panels.length; i++) {
    expect(panels[i].top, greaterThanOrEqualTo(panels[i - 1].bottom));
  }
  expect(tester.getRect(totals).bottom, lessThanOrEqualTo(panels.first.top));
  for (final panel in panels) {
    expect(panel.width, lessThanOrEqualTo(320));
  }
}

TimeLog _log(
  String userId,
  String date,
  String id,
  String? taskId,
  int minutes,
  TimeLogRelation relation, {
  String? adHocId,
}) => TimeLog(
  id: id,
  userId: userId,
  taskId: taskId,
  blockId: null,
  date: date,
  minutes: minutes,
  startedAt: '${date}T00:00:00Z',
  endedAt: '${date}T01:00:00Z',
  source: LogSource.timer,
  relation: relation,
  adHocId: adHocId,
);

Future<void> _show(
  WidgetTester tester,
  CalendarDayData day,
  CalendarView view,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: plannerTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: CalendarDayChart(
            key: ValueKey('${day.items.length}-${view.name}'),
            day: day,
            view: view,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
