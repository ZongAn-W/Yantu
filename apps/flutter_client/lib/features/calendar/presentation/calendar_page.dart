import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/calendar_view_preference.dart';
import '../domain/calendar_day_data.dart';
import '../domain/calendar_month_data.dart';
import '../domain/calendar_view.dart';
import '../domain/calendar_week_data.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/capacity.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/progress_metrics.dart';
import '../../planner/presentation/planner_page_state.dart';
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
/// The compact status strip (cumulative minutes, remaining work and course
/// content completion) stays independent of the selected date: it always
/// describes "as of today".
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  String _selectedDate = shanghaiToday();
  CalendarMode _mode = CalendarMode.day;

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
    setState(() => _mode = mode);
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
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
      helpText: '选择查看日期',
      cancelText: '取消',
      confirmText: '确定',
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
            const SizedBox(height: 12),
            if (metrics != null) CalendarOverview(metrics: metrics),
            const SizedBox(height: 16),
            ...switch (_mode) {
              CalendarMode.day => _dayScope(data),
              CalendarMode.week => _weekScope(data, weekView),
              CalendarMode.month => _monthScope(data, today),
            },
          ],
        );
      },
    );
  }

  Widget _toolbar(CalendarWeekView weekView) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        SizedBox(
          width: constraints.maxWidth < 360 ? constraints.maxWidth : 340,
          child: Row(
            children: [
              IconButton(
                key: ValueKey(_previousKey),
                tooltip: _previousLabel,
                icon: const Icon(Icons.chevron_left),
                visualDensity: VisualDensity.compact,
                onPressed: () => _stepDate(-1),
              ),
              Expanded(
                child: Tooltip(
                  message: _periodSemantics,
                  // Manual only: an automatic hover tooltip would cover the
                  // compact mode/chart controls below it.
                  triggerMode: TooltipTriggerMode.manual,
                  child: TextButton(
                    key: const ValueKey('calendar-date-picker'),
                    onPressed: _pickDate,
                    child: Text(
                      _periodLabel,
                      style: tabularFigures,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey(_nextKey),
                tooltip: _nextLabel,
                icon: const Icon(Icons.chevron_right),
                visualDensity: VisualDensity.compact,
                onPressed: () => _stepDate(1),
              ),
              TextButton(
                key: ValueKey(_todayKey),
                onPressed: () => _chooseDate(shanghaiToday()),
                child: Text(_todayLabel),
              ),
            ],
          ),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<CalendarMode>(
                  key: const ValueKey('calendar-mode-switch'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    for (final mode in CalendarMode.values)
                      ButtonSegment(value: mode, label: Text(mode.label)),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (values) => _chooseMode(values.single),
                ),
                if (_mode == CalendarMode.week)
                  _WeekChartSelector(
                    value: weekView,
                    onChanged: (view) =>
                        ref.read(calendarWeekViewProvider.notifier).select(view),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> _dayScope(PlannerData data) {
    final day = buildCalendarDayData(data, _selectedDate);
    final capacity = resolveDayCapacity(
      data.profile,
      _selectedDate,
    ).minutes;
    return [
      Column(
        key: ValueKey('calendar-day-$_selectedDate'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: CalendarDayTotals(
              key: const ValueKey('calendar-day-totals'),
              day: day,
              capacityMinutes: capacity,
            ),
          ),
          for (final view in CalendarView.values) ...[
            if (view != CalendarView.values.first) const SizedBox(height: 16),
            CalendarDayChart(
              key: ValueKey('calendar-day-card-${view.name}'),
              day: day,
              view: view,
              showTitle: true,
            ),
          ],
        ],
      ),
    ];
  }

  List<Widget> _weekScope(PlannerData data, CalendarWeekView weekView) {
    final week = buildCalendarWeekData(data, _selectedDate);
    return [
      CalendarWeekChart(
        key: ValueKey('calendar-week-${calendarWeekStart(_selectedDate)}'),
        week: week,
        view: weekView,
        selectedDate: _selectedDate,
        onSelectDate: _chooseDate,
      ),
    ];
  }

  List<Widget> _monthScope(PlannerData data, String today) {
    final month = buildCalendarMonthData(data, _selectedDate, today: today);
    return [
      CalendarMonthChart(
        key: ValueKey('calendar-month-${month.month}'),
        month: month,
        selectedDate: _selectedDate,
        onSelectDate: _chooseDate,
      ),
    ];
  }
}

class _WeekChartSelector extends StatelessWidget {
  const _WeekChartSelector({required this.value, required this.onChanged});

  final CalendarWeekView value;
  final ValueChanged<CalendarWeekView> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<CalendarWeekView>(
      key: const ValueKey('calendar-week-view-switch'),
      value: value,
      isDense: true,
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      icon: const Icon(Icons.unfold_more, size: 18),
      items: [
        for (final option in CalendarWeekView.values)
          DropdownMenuItem(value: option, child: Text(option.label)),
      ],
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    ),
  );
}
