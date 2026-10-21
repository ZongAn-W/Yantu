import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_day_data.dart';
import '../domain/calendar_month_data.dart';
import '../domain/calendar_month_mosaic.dart';
import 'calendar_month_colors.dart';
import 'calendar_month_day_panel.dart';

/// Read-only month mosaic of the plan.
///
/// Every in-month day is one capacity tile: the course-coloured blocks fill the
/// tile from the bottom, the filled height is `planned / capacity`, and each
/// block's area is that course's planned minutes. The grid carries no text
/// besides the date; the selected day's plan is shown in the side panel
/// (desktop split) or below the grid (narrow widths).
///
/// The widget is still keyboard first-class: arrow keys move the selected day,
/// PageUp/PageDown move a whole month, Home returns to today and Space/Enter
/// confirm the selection without side effects. The keys are only consumed while
/// the grid owns focus.
class CalendarMonthChart extends StatefulWidget {
  const CalendarMonthChart({
    required this.month,
    required this.selectedDate,
    required this.onSelectDate,
    required this.onOpenDayView,
    super.key,
  });

  final CalendarMonthData month;
  final String selectedDate;
  final ValueChanged<String> onSelectDate;

  /// Called by the detail panel's "在日视图中查看" link.
  final VoidCallback onOpenDayView;

  @override
  State<CalendarMonthChart> createState() => _CalendarMonthChartState();
}

class _CalendarMonthChartState extends State<CalendarMonthChart> {
  static const double _compactWidth = 620;
  static const double _splitWidth = 940;
  static const double _desktopRowHeight = 106;
  static const double _compactRowHeight = 64;
  static const double _weekdayHeight = 24;
  static const double _compactWeekdayHeight = 22;
  static const double _dayPanelWidth = 296;

  static const List<String> _weekdayLabels = [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  /// The month page rebuilds this chart under a new month key when the selected
  /// date crosses a month boundary. The keyboard focus is handed over to the
  /// next state through this one-shot flag.
  static bool _pendingGridFocus = false;

  late final FocusNode _gridFocus;
  bool _gridHasFocus = false;

  @override
  void initState() {
    super.initState();
    _gridFocus = FocusNode(debugLabel: 'planner-month-grid');
    if (_pendingGridFocus) {
      _pendingGridFocus = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _gridFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _gridFocus.dispose();
    super.dispose();
  }

  int get _rowCount =>
      ((widget.month.heatLead + widget.month.days.length) / 7).ceil();

  int get _plannedDayCount =>
      widget.month.days.where((day) => day.plannedMinutes > 0).length;

  int get _overCapacityDays => widget.month.days.where(_isOver).length;

  bool _isOver(CalendarMonthDay day) => mosaicOverCapacity(
    plannedMinutes: day.plannedMinutes,
    capacityMinutes: day.capacityMinutes,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final focusRing = <BoxShadow>[
      BoxShadow(color: tokens.focusRing, spreadRadius: 2),
    ];
    return PlannerPanel(
      padding: const EdgeInsets.all(PlannerSpace.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactWidth;
          final split = !compact && constraints.maxWidth >= _splitWidth;
          final rowHeight = compact ? _compactRowHeight : _desktopRowHeight;
          final weekdayHeight = compact
              ? _compactWeekdayHeight
              : _weekdayHeight;
          final gridHeight = weekdayHeight + _rowCount * rowHeight;
          final panel = CalendarMonthDayPanel(
            day: widget.month.dayFor(widget.selectedDate),
            stacked: !split,
            onOpenDayView: widget.onOpenDayView,
          );
          final grid = _grid(
            compact: compact,
            rowHeight: rowHeight,
            weekdayHeight: weekdayHeight,
            focusRing: focusRing,
          );
          return Column(
            key: const ValueKey('calendar-month-chart'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(tokens, compact: compact),
              const SizedBox(height: PlannerSpace.md),
              if (split)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: grid),
                    const SizedBox(width: PlannerSpace.lg),
                    SizedBox(
                      width: _dayPanelWidth,
                      height: gridHeight,
                      child: panel,
                    ),
                  ],
                )
              else ...[
                grid,
                const SizedBox(height: PlannerSpace.md),
                panel,
              ],
              const SizedBox(height: PlannerSpace.md),
              _legend(tokens, compact: compact),
              const SizedBox(height: PlannerSpace.sm),
              Text(
                '色块面积 = 当天各课程计划分钟；浅色 = 未排满容量；琥珀圆点 = 超过容量。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: tokens.subtle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(PlannerTokens tokens, {required bool compact}) {
    final title = Text(
      monthLabel(widget.month.month),
      style: Theme.of(context).textTheme.titleMedium,
    );
    final summary = Text(
      '本月计划 ${duration(widget.month.plannedMinutes)} · '
      '$_plannedDayCount 个学习日 · $_overCapacityDays 天超容量',
      key: const ValueKey('calendar-month-summary'),
      style: tabularFigures.copyWith(
        fontSize: compact ? 11.5 : 12,
        height: 1.5,
        color: tokens.muted,
      ),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [title, const SizedBox(height: 2), summary],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        summary,
      ],
    );
  }

  Widget _grid({
    required bool compact,
    required double rowHeight,
    required double weekdayHeight,
    required List<BoxShadow> focusRing,
  }) {
    final tokens = context.tokens;
    return Focus(
      key: const ValueKey('calendar-month-keyboard'),
      focusNode: _gridFocus,
      debugLabel: 'planner-month-grid',
      includeSemantics: false,
      onKeyEvent: _onGridKeyEvent,
      onFocusChange: _handleGridFocus,
      child: Container(
        decoration: BoxDecoration(
          // Opaque surface so the focus ring's spread shadow only shows around
          // the grid instead of bleeding through the transparent cell gaps.
          color: tokens.surface,
          borderRadius: BorderRadius.circular(PlannerRadius.small),
          boxShadow: _gridHasFocus ? focusRing : null,
        ),
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(PlannerRadius.small),
            child: Column(
              key: const ValueKey('calendar-month-grid'),
              children: [
                SizedBox(
                  height: weekdayHeight,
                  child: Row(
                    children: [
                      for (final label in _weekdayLabels)
                        Expanded(
                          child: Center(
                            child: ExcludeSemantics(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.3,
                                  color: tokens.subtle,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                for (var row = 0; row < _rowCount; row++)
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        for (var column = 0; column < 7; column++)
                          Expanded(
                            child: _cellAt(row * 7 + column, compact: compact),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cellAt(int index, {required bool compact}) {
    final dayIndex = index - widget.month.heatLead;
    if (dayIndex < 0 || dayIndex >= widget.month.days.length) {
      return const SizedBox.expand();
    }
    return _dayCell(widget.month.days[dayIndex], compact: compact);
  }

  Widget _dayCell(CalendarMonthDay day, {required bool compact}) {
    final tokens = context.tokens;
    final over = _isOver(day);
    void select() {
      _gridFocus.requestFocus();
      widget.onSelectDate(day.date);
    }

    final selected = day.date == widget.selectedDate;
    return Tooltip(
      message: _tooltipMessage(day),
      excludeFromSemantics: true,
      child: Semantics(
        key: ValueKey('calendar-month-day-${day.date}'),
        container: true,
        excludeSemantics: true,
        button: true,
        label: _semanticsLabel(day),
        tooltip: _tooltipMessage(day),
        onTap: select,
        child: InkWell(
          onTap: select,
          excludeFromSemantics: true,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(10),
          hoverColor: tokens.hover,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tokens.accent, width: 2),
                  )
                : const BoxDecoration(),
            child: compact
                ? _compactCell(day, over: over)
                : _mosaicCell(day, over: over),
          ),
        ),
      ),
    );
  }

  Widget _mosaicCell(CalendarMonthDay day, {required bool over}) => Padding(
    padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: Row(
            children: [
              _dateNumber(day, compact: false),
              const Spacer(),
              if (over) _overDot(compact: false),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _MosaicTile(day: day, over: over),
        ),
      ],
    ),
  );

  Widget _compactCell(CalendarMonthDay day, {required bool over}) => Padding(
    padding: const EdgeInsets.fromLTRB(3, 4, 3, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: Row(
            children: [
              _dateNumber(day, compact: true),
              const Spacer(),
              if (over) _overDot(compact: true),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Expanded(
          child: _MosaicTile(day: day, over: over, compact: true),
        ),
      ],
    ),
  );

  Widget _dateNumber(CalendarMonthDay day, {required bool compact}) {
    final tokens = context.tokens;
    final number = '${int.parse(day.date.substring(8))}';
    if (day.isToday) {
      final size = compact ? 16.0 : 18.0;
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tokens.accent, shape: BoxShape.circle),
        child: Text(
          number,
          maxLines: 1,
          style: tabularFigures.copyWith(
            fontSize: compact ? 9.5 : 10.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: tokens.accentOn,
          ),
        ),
      );
    }
    return Text(
      number,
      maxLines: 1,
      style: tabularFigures.copyWith(
        fontSize: compact ? 10.5 : 11.5,
        height: 1.2,
        fontWeight: day.isFuture ? FontWeight.w500 : FontWeight.w600,
        color: day.isFuture ? tokens.muted : tokens.text,
      ),
    );
  }

  Widget _overDot({required bool compact}) {
    final size = compact ? 5.0 : 6.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.tokens.warning,
        shape: BoxShape.circle,
        border: Border.all(color: context.tokens.surface, width: 1),
      ),
    );
  }

  Widget _legend(PlannerTokens tokens, {required bool compact}) {
    final courses = _courseEntries(tokens);
    final visibleCourses = compact ? courses.take(6) : courses.take(10);
    final hiddenCourses = courses.length - visibleCourses.length;
    return Wrap(
      key: const ValueKey('calendar-month-legend'),
      spacing: compact ? 10 : 14,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (courses.isNotEmpty)
          Text(
            '课程色',
            style: TextStyle(fontSize: 11, height: 1.4, color: tokens.muted),
          ),
        for (final course in visibleCourses)
          _legendDot(course.color, course.name, tokens: tokens),
        if (hiddenCourses > 0)
          Text(
            '+$hiddenCourses',
            style: TextStyle(fontSize: 11, height: 1.4, color: tokens.subtle),
          ),
        if (courses.isNotEmpty)
          Container(width: 1, height: 12, color: tokens.border),
        _legendSquare(
          tokens.surfaceMuted,
          border: tokens.border,
          label: '未排满容量',
          tokens: tokens,
        ),
        _legendDot(tokens.warning, '超容量', tokens: tokens, hollow: true),
      ],
    );
  }

  List<({String name, Color color})> _courseEntries(PlannerTokens tokens) {
    final seen = <String>{};
    final entries = <({String name, Color color})>[];
    for (final day in widget.month.days) {
      for (final item in day.day.items) {
        if (item.plannedMinutes <= 0) continue;
        final name = item.tagNames.isNotEmpty ? item.tagNames.first : '其他事项';
        if (!seen.add(name)) continue;
        entries.add((name: name, color: calendarMonthItemColor(item, tokens)));
      }
    }
    return entries;
  }

  Widget _legendDot(
    Color color,
    String label, {
    required PlannerTokens tokens,
    bool hollow = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: hollow ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: hollow ? Border.all(color: color, width: 1.5) : null,
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(fontSize: 11, height: 1.4, color: tokens.muted),
      ),
    ],
  );

  Widget _legendSquare(
    Color color, {
    required Color border,
    required String label,
    required PlannerTokens tokens,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
          border: Border.all(color: border),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(fontSize: 11, height: 1.4, color: tokens.muted),
      ),
    ],
  );

  /// Desktop keyboard navigation, active only while the grid owns the focus.
  KeyEventResult _onGridKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _stepDays(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _stepDays(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _stepDays(-7);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _stepDays(7);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _stepMonths(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      _stepMonths(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _selectDate(widget.month.today);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _stepDays(int days) => _selectDate(addDate(widget.selectedDate, days));

  void _stepMonths(int months) =>
      _selectDate(addMonth(widget.selectedDate, months));

  void _selectDate(String date) {
    if (date == widget.selectedDate) return;
    if (date.substring(0, 7) != widget.month.month) {
      _pendingGridFocus = true;
    }
    widget.onSelectDate(date);
  }

  void _handleGridFocus(bool hasFocus) {
    if (!mounted || hasFocus == _gridHasFocus) return;
    setState(() => _gridHasFocus = hasFocus);
  }

  String _semanticsLabel(CalendarMonthDay day) {
    final items = _plannedItems(day);
    return [
      fullDateLabel(day.date),
      if (day.isToday) '今天',
      '计划 ${duration(day.plannedMinutes)}',
      '容量 ${duration(day.capacityMinutes)}',
      if (_isOver(day)) '超出容量',
      '${items.length} 项事项',
    ].join('，');
  }

  String _tooltipMessage(CalendarMonthDay day) => [
    fullDateLabel(day.date),
    '计划 ${duration(day.plannedMinutes)} · '
        '容量 ${duration(day.capacityMinutes)}',
    if (_isOver(day))
      '超出容量 ${duration(day.plannedMinutes - math.max(0, day.capacityMinutes))}',
    for (final item in _plannedItems(day))
      '${item.title} · 计划 ${duration(item.plannedMinutes)}',
  ].join('\n');

  List<CalendarDayItem> _plannedItems(CalendarMonthDay day) => [
    for (final item in day.day.items)
      if (item.plannedMinutes > 0) item,
  ];
}

/// The capacity tile of one day: course blocks grow from the bottom.
class _MosaicTile extends StatelessWidget {
  const _MosaicTile({
    required this.day,
    required this.over,
    this.compact = false,
  });

  final CalendarMonthDay day;
  final bool over;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final items = _sortedItems(day);
    final minutes = [for (final item in items) item.plannedMinutes];
    final blocks = layoutMosaicBlocks(minutes);
    final fill = mosaicFillRatio(
      plannedMinutes: day.plannedMinutes,
      capacityMinutes: day.capacityMinutes,
    );
    final radius = compact ? 4.0 : 7.0;
    final blockRadius = compact ? 2.0 : 5.0;
    final gap = compact ? 1.0 : 2.0;
    final inset = gap / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.surfaceMuted),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: over
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: tokens.warning,
                    width: compact ? 1 : 1.5,
                  ),
                )
              : const BoxDecoration(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final fillHeight = height * fill;
              final top = height - fillHeight;
              if (day.plannedMinutes > 0 && blocks.isEmpty) {
                // A plan without attributable items still has to show its load.
                return Stack(
                  children: [
                    Positioned(
                      left: inset,
                      top: top + inset,
                      width: math.max(0.0, width - gap),
                      height: math.max(0.0, fillHeight - gap),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(blockRadius),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return Stack(
                key: ValueKey('calendar-month-tile-${day.date}'),
                children: [
                  for (final block in blocks)
                    Positioned(
                      left: block.left * width + inset,
                      top: top + block.top * fillHeight + inset,
                      width: math.max(0.0, block.width * width - gap),
                      height: math.max(0.0, block.height * fillHeight - gap),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: calendarMonthItemColor(
                            items[block.itemIndex],
                            tokens,
                          ),
                          borderRadius: BorderRadius.circular(blockRadius),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<CalendarDayItem> _sortedItems(CalendarMonthDay day) => [
    for (final item in day.day.items)
      if (item.plannedMinutes > 0) item,
  ]..sort((a, b) => b.plannedMinutes.compareTo(a.plannedMinutes));
}
