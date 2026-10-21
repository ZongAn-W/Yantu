import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planner_ui_vendor/planner_ui_vendor.dart';

import '../../../core/motion.dart';
import '../../../core/planner_date_picker.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/calendar_view_preference.dart';
import '../domain/calendar_completion_data.dart';
import '../domain/calendar_day_data.dart';
import '../domain/calendar_month_data.dart';
import '../domain/calendar_view.dart';
import '../domain/calendar_week_data.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/capacity.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/progress_metrics.dart';
import '../../planner/presentation/planner_page_state.dart';
import 'calendar_completion_pie.dart';
import 'calendar_day_chart.dart';
import 'calendar_month_chart.dart';
import 'calendar_overview.dart';
import 'calendar_week_chart.dart';

/// The plan without retired temporary-learning rows.
///
/// Temporary learning is no longer created by the client (the dashboard, timer
/// and calendar all ignore it). Historical rows stay in the stored document and
/// sync untouched; only the merged progress reporting ignores them so the
/// cumulative totals, month heat and week charts share one denominator.
final calendarReportingDataProvider = Provider<PlannerData?>((ref) {
  final data = ref.watch(plannerDataProvider).data;
  if (data == null) return null;
  return data.copyWith(
    logs: [
      for (final log in data.logs)
        if (log.relation != TimeLogRelation.adHoc && log.adHocId == null) log,
    ],
  );
});

/// Current goal-level metrics of the merged calendar, computed once per plan
/// change (not once per date navigation).
final calendarOverviewMetricsProvider = Provider<ProgressMetrics?>((ref) {
  final data = ref.watch(calendarReportingDataProvider);
  if (data == null) return null;
  final today = shanghaiToday();
  return progressMetrics(data, date: today, month: today.substring(0, 7));
});

/// One read-only calendar of planned and recorded learning.
///
/// One date drives every scope: the day scope shows that exact day, the week
/// scope shows the Monday–Sunday week containing it, and the month scope shows
/// the calendar month containing it. Switching the scope, the graphic or the
/// month never changes the selected date, and the page never writes data.
///
/// The compact status strip (cumulative minutes, remaining work and task
/// completion) stays independent of the selected date: it always
/// describes "as of today".
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  String _selectedDate = shanghaiToday();
  CalendarMode _mode = CalendarMode.day;

  /// True after the first explicit scope switch: the initial page build keeps
  /// the route transition only, later switches add the 120 ms scope fade.
  bool _hasSwitchedMode = false;

  int get _stepDays => _mode == CalendarMode.day ? 1 : 7;

  String get _periodLabel => switch (_mode) {
    CalendarMode.day => fullDateLabel(_selectedDate),
    CalendarMode.week => weekRangeLabel(calendarWeekStart(_selectedDate)),
    CalendarMode.month => monthLabel(_selectedDate.substring(0, 7)),
  };

  String get _periodSemantics => switch (_mode) {
    CalendarMode.day => fullDateLabel(_selectedDate),
    CalendarMode.week => weekSemanticRange(calendarWeekStart(_selectedDate)),
    CalendarMode.month =>
      '${_selectedDate.substring(0, 4)}年'
          '${int.parse(_selectedDate.substring(5, 7))}月',
  };

  String get _previousLabel => switch (_mode) {
    CalendarMode.day => '前一天',
    CalendarMode.week => '前一周',
    CalendarMode.month => '上个月',
  };

  String get _nextLabel => switch (_mode) {
    CalendarMode.day => '后一天',
    CalendarMode.week => '后一周',
    CalendarMode.month => '下个月',
  };

  String get _todayLabel => switch (_mode) {
    CalendarMode.day => '今天',
    CalendarMode.week => '本周',
    CalendarMode.month => '本月',
  };

  String get _previousKey => switch (_mode) {
    CalendarMode.day => 'calendar-previous-day',
    CalendarMode.week => 'calendar-previous-week',
    CalendarMode.month => 'calendar-previous-month',
  };

  String get _nextKey => switch (_mode) {
    CalendarMode.day => 'calendar-next-day',
    CalendarMode.week => 'calendar-next-week',
    CalendarMode.month => 'calendar-next-month',
  };

  String get _todayKey => switch (_mode) {
    CalendarMode.day => 'calendar-today',
    CalendarMode.week => 'calendar-this-week',
    CalendarMode.month => 'calendar-this-month',
  };

  void _chooseDate(String date) => setState(() => _selectedDate = date);

  void _chooseMode(CalendarMode mode) {
    if (_mode == mode) return;
    // The selected date is deliberately shared by every scope.
    setState(() {
      _mode = mode;
      _hasSwitchedMode = true;
    });
  }

  void _stepDate(int direction) {
    if (_mode == CalendarMode.month) {
      _chooseDate(addMonth(_selectedDate, direction));
      return;
    }
    final days = direction * _stepDays;
    _chooseDate(addDate(_selectedDate, days));
  }

  Future<void> _pickDate() async {
    final selected = DateTime.parse(_selectedDate);
    final picked = await showPlannerDatePicker(
      context,
      initialDate: selected,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      title: '选择查看日期',
    );
    if (picked != null && mounted) _chooseDate(dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final weekView = ref.watch(calendarWeekViewProvider);
    final metrics = ref.watch(calendarOverviewMetricsProvider);
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final today = shanghaiToday();
        return PlannerPage(
          children: [
            _toolbar(weekView),
            const SizedBox(height: PlannerSpace.lg),
            if (metrics != null) CalendarOverview(metrics: metrics),
            const SizedBox(height: PlannerSpace.lg),
            _CalendarScopeTransition(
              mode: _mode,
              animate: _hasSwitchedMode,
              child: switch (_mode) {
                CalendarMode.day => _dayScope(data),
                CalendarMode.week => _weekScope(data, weekView),
                CalendarMode.month => _monthScope(data, today),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _toolbar(CalendarWeekView weekView) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 620;
      final navigation = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlannerIconAction(
            key: ValueKey(_previousKey),
            tooltip: _previousLabel,
            icon: LucideIcons.chevronLeft,
            iconSize: 19,
            onPressed: () => _stepDate(-1),
          ),
          Flexible(
            child: Tooltip(
              message: _periodSemantics,
              // Manual only: an automatic hover tooltip would cover the
              // compact mode/chart controls below it.
              triggerMode: TooltipTriggerMode.manual,
              child: TextButton(
                key: const ValueKey('calendar-date-picker'),
                onPressed: _pickDate,
                style: TextButton.styleFrom(
                  foregroundColor: context.tokens.text,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(
                      Radius.circular(PlannerRadius.small),
                    ),
                  ),
                ),
                child: Text(
                  _periodLabel,
                  style: tabularFigures.copyWith(
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: context.tokens.text,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          PlannerIconAction(
            key: ValueKey(_nextKey),
            tooltip: _nextLabel,
            icon: LucideIcons.chevronRight,
            iconSize: 19,
            onPressed: () => _stepDate(1),
          ),
          const SizedBox(width: PlannerSpace.xs),
          TextButton(
            key: ValueKey(_todayKey),
            onPressed: () => _chooseDate(shanghaiToday()),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              _todayLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: compact ? 168 : 204,
            height: 30,
            child: PlannerSegmented<CalendarMode>(
              key: const ValueKey('calendar-mode-switch'),
              value: _mode,
              items: [
                for (final mode in CalendarMode.values) (mode, mode.label),
              ],
              onChanged: _chooseMode,
            ),
          ),
          if (_mode == CalendarMode.week) ...[
            const SizedBox(width: PlannerSpace.sm),
            _WeekChartSelector(
              value: weekView,
              onChanged: (view) =>
                  ref.read(calendarWeekViewProvider.notifier).select(view),
            ),
          ],
        ],
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            navigation,
            const SizedBox(height: PlannerSpace.sm),
            controls,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: navigation),
          const SizedBox(width: PlannerSpace.md),
          controls,
        ],
      );
    },
  );

  Widget _dayScope(PlannerData data) {
    final day = buildCalendarDayData(data, _selectedDate);
    final capacity = resolveDayCapacity(data.profile, _selectedDate).minutes;
    return Column(
      key: ValueKey('calendar-day-$_selectedDate'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The period composition opens every scope; the day totals and the two
        // day graphics below stay one shared read-only view of the same facts.
        CalendarCompletionPie(data: buildCalendarCompletionData([day])),
        const SizedBox(height: PlannerSpace.md),
        CalendarDayTotals(
          key: const ValueKey('calendar-day-totals'),
          day: day,
          capacityMinutes: capacity,
        ),
        const SizedBox(height: PlannerSpace.md),
        for (final view in CalendarView.values) ...[
          if (view != CalendarView.values.first)
            const SizedBox(height: PlannerSpace.md),
          CalendarDayChart(
            key: ValueKey('calendar-day-card-${view.name}'),
            day: day,
            view: view,
            showTitle: true,
          ),
        ],
      ],
    );
  }

  Widget _weekScope(PlannerData data, CalendarWeekView weekView) {
    final week = buildCalendarWeekData(data, _selectedDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalendarCompletionPie(
          data: buildCalendarCompletionData([
            for (final day in week.days) day.day,
          ]),
        ),
        const SizedBox(height: PlannerSpace.md),
        CalendarWeekChart(
          key: ValueKey('calendar-week-${calendarWeekStart(_selectedDate)}'),
          week: week,
          view: weekView,
          selectedDate: _selectedDate,
          onSelectDate: _chooseDate,
        ),
      ],
    );
  }

  Widget _monthScope(PlannerData data, String today) {
    final month = buildCalendarMonthData(data, _selectedDate, today: today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CalendarCompletionPie(
          data: buildCalendarCompletionData([
            for (final day in month.days) day.day,
          ]),
        ),
        const SizedBox(height: PlannerSpace.md),
        CalendarMonthChart(
          key: ValueKey('calendar-month-${month.month}'),
          month: month,
          selectedDate: _selectedDate,
          onSelectDate: _chooseDate,
          onOpenDayView: () => _chooseMode(CalendarMode.day),
        ),
      ],
    );
  }
}

/// Menu-style week graphic selector: a hairline control that opens the shared
/// popup menu instead of a Material [DropdownButton].
class _WeekChartSelector extends StatelessWidget {
  const _WeekChartSelector({required this.value, required this.onChanged});

  final CalendarWeekView value;
  final ValueChanged<CalendarWeekView> onChanged;

  @override
  Widget build(BuildContext context) {
    final hairline = plannerHairline(context);
    return PopupMenuButton<CalendarWeekView>(
      key: const ValueKey('calendar-week-view-switch'),
      tooltip: '切换周视图图表',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in CalendarWeekView.values)
          PopupMenuItem<CalendarWeekView>(
            value: option,
            height: 36,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: option == value
                      ? Icon(
                          LucideIcons.check,
                          size: 14,
                          color: context.tokens.accent,
                        )
                      : null,
                ),
                Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: option == value
                        ? FontWeight.w500
                        : FontWeight.w400,
                    color: option == value
                        ? context.tokens.text
                        : context.tokens.muted,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 10, right: 8),
        decoration: BoxDecoration(
          color: context.tokens.surfaceInset,
          borderRadius: PlannerRadius.controlRadius,
          border: Border.all(color: context.tokens.border, width: hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: context.tokens.muted,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: context.tokens.subtle,
            ),
          ],
        ),
      ),
    );
  }
}

/// 120 ms fade + 4 px rise for a day/week/month scope switch.
///
/// Only the new scope exists in the tree (unlike [AnimatedSwitcher] there is no
/// second child during the animation), so "switch mode, then find exactly one
/// chart" assertions stay valid. Only opacity/transform animate; reduced motion
/// shows the final state without creating a ticker, and the first build of the
/// page is not animated because the route transition already covers entry.
class _CalendarScopeTransition extends StatelessWidget {
  const _CalendarScopeTransition({
    required this.mode,
    required this.animate,
    required this.child,
  });

  final CalendarMode mode;
  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    final duration = PlannerMotion.duration(
      context,
      preferred: PlannerDurations.fast,
    );
    if (duration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(mode),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: PlannerMotion.curve(context),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}
