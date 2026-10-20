import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_month_data.dart';

/// Read-only month grid: plan versus capacity, actual heat and execution status.
///
/// The month paging and the Monday-first week layout come from
/// table_calendar 3.3.0 (MIT, registered in THIRD_PARTY_NOTICES.md) instead of a
/// hand-written Column/Row grid. [TableCalendarBase] is used directly rather
/// than the higher-level TableCalendar: the latter wraps every calendar builder
/// in a Semantics node with excludeSemantics and an English date label, which
/// would erase the Chinese plan/capacity/actual facts from the accessibility
/// tree. Every cell, the Chinese weekday header, the +N overflow, the today
/// circle, the inset selected ring and the heat legend are rendered below so the
/// "Mist Ink" language (white canvas, hairline grid, one ink-blue accent,
/// tabular digits) is preserved and each day keeps its full-fact Semantics.
///
/// Selecting a cell only changes the shared read-only date; the month grid never
/// edits, completes, drags or starts anything.
///
/// The grid itself is focusable for desktop keyboard use: arrow keys move the
/// selected day, PageUp/PageDown move a whole month, Home returns to today and
/// Space/Enter confirm the current selection without side effects. The keys are
/// only consumed while the grid owns the focus, so text inputs and dialogs keep
/// their own keyboard behaviour. Tapping a day moves the focus to the grid and a
/// 2 px [PlannerTokens.focusRing] ring follows the focus.
class CalendarMonthChart extends StatefulWidget {
  const CalendarMonthChart({
    required this.month,
    required this.selectedDate,
    required this.onSelectDate,
    super.key,
  });

  final CalendarMonthData month;
  final String selectedDate;
  final ValueChanged<String> onSelectDate;

  @override
  State<CalendarMonthChart> createState() => _CalendarMonthChartState();
}

class _CalendarMonthChartState extends State<CalendarMonthChart> {
  /// Inner width under which cells switch from the facts card to the compact
  /// date/status/progress layout.
  static const double _compactWidth = 620;

  /// How many event titles fit inside a desktop cell before the +N badge.
  static const int _visibleItems = 2;

  static const List<String> _weekdayLabels = [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  /// The calendar page rebuilds this chart under a new month key when the
  /// selected date crosses a month boundary, disposing this state (and its focus
  /// node). A keyboard step therefore hands the focus over to the next state
  /// instance through this one-shot flag, so arrow/PageUp/PageDown/Home
  /// navigation stays continuous across months.
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final focusRing = <BoxShadow>[
      BoxShadow(color: tokens.focusRing, spreadRadius: 2),
    ];
    final hairline = plannerHairline(context);
    return PlannerPanel(
      title: monthLabel(widget.month.month),
      padding: const EdgeInsets.all(PlannerSpace.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactWidth;
          return Column(
            key: const ValueKey('calendar-month-chart'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _summary(tokens, compact: compact),
              const SizedBox(height: PlannerSpace.md),
              Focus(
                key: const ValueKey('calendar-month-keyboard'),
                focusNode: _gridFocus,
                debugLabel: 'planner-month-grid',
                includeSemantics: false,
                onKeyEvent: _onGridKeyEvent,
                onFocusChange: _handleGridFocus,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(PlannerRadius.small),
                    border: Border.all(color: tokens.border, width: hairline),
                    boxShadow: _gridHasFocus ? focusRing : null,
                  ),
                  // W7: cache the read-only month grid.
                  child: RepaintBoundary(
                    child: LayoutBuilder(
                      // table_calendar lays its month pager out in a PageView;
                      // a fractional page width (e.g. while the desktop sidebar
                      // animates) trips Flutter's fixed-extent sliver precision
                      // assertion. Lay the grid out on whole logical pixels.
                      builder: (context, inner) => Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: inner.maxWidth.floorToDouble(),
                          child: _calendar(
                            compact: compact,
                            hairline: hairline,
                            rowHeight: compact ? 52 : 100,
                            tokens: tokens,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PlannerSpace.md),
              _legend(tokens, compact: compact),
              const SizedBox(height: PlannerSpace.sm),
              Text(
                '未来日期只显示计划与每日容量；实学热度只统计已经发生的日期。',
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

  /// Read-only month calendar: no header, no swipes, no format change and no
  /// long-press editing. Only the day tap forwards the shared read-only date,
  /// and days outside the month render as non-interactive blank grid cells.
  Widget _calendar({
    required bool compact,
    required double hairline,
    required double rowHeight,
    required PlannerTokens tokens,
  }) => TableCalendarBase(
    focusedDay: _utcDate(widget.selectedDate),
    firstDay: DateTime.utc(1900),
    lastDay: DateTime.utc(2200, 12, 31),
    calendarFormat: CalendarFormat.month,
    startingDayOfWeek: StartingDayOfWeek.monday,
    availableGestures: AvailableGestures.none,
    pageAnimationEnabled: false,
    rowHeight: rowHeight,
    dowVisible: true,
    dowHeight: compact ? 24 : 28,
    dowBuilder: (context, date) =>
        _weekdayCell(tokens, date, hairline: hairline),
    dayBuilder: (context, date, focusedDay) {
      final entry = widget.month.dayFor(dateOnly(date));
      if (entry == null) return _blankCell(tokens, date, hairline: hairline);
      return _dayCell(
        tokens,
        entry,
        date,
        compact: compact,
        hairline: hairline,
      );
    },
  );

  /// Desktop keyboard navigation, active only while the grid owns the focus.
  /// Returns [KeyEventResult.ignored] for every other key so text inputs,
  /// dialogs and the rest of the page keep their normal keyboard behaviour.
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
      // Confirm the current selection. The month grid is read-only, so there is
      // nothing to trigger and nothing to write.
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

  Widget _summary(PlannerTokens tokens, {required bool compact}) => Text(
    '本月计划 ${duration(widget.month.plannedMinutes)} · '
    '实学 ${duration(widget.month.actualMinutes)}'
    // Narrow panels break before the interruption fact instead of splitting
    // "中断 0 天" across two lines.
    '${compact ? '\n' : ' · '}'
    '中断 ${widget.month.interruptedDays}\u00A0天',
    key: const ValueKey('calendar-month-summary'),
    style: tabularFigures.copyWith(
      fontSize: compact ? 11.5 : 12,
      height: 1.5,
      color: tokens.muted,
    ),
  );

  /// One read-only day: a single Semantics node carries the full Chinese facts,
  /// the tooltip and the button action, so assistive technologies never fall
  /// back to the English date label of the library.
  Widget _dayCell(
    PlannerTokens tokens,
    CalendarMonthDay day,
    DateTime date, {
    required bool compact,
    required double hairline,
  }) {
    final selected = day.date == widget.selectedDate;
    void select() {
      // Clicking a day moves the keyboard focus to the grid so the arrow keys
      // keep working without a separate Tab stop.
      _gridFocus.requestFocus();
      widget.onSelectDate(day.date);
    }

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
          borderRadius: BorderRadius.zero,
          hoverColor: tokens.hover,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: _gridBorder(
                tokens,
                hairline: hairline,
                left: date.weekday != DateTime.monday,
                top: _rowOf(day) > 0,
              ),
            ),
            child: DecoratedBox(
              // Painted as an overlay without insetting the cell, so selecting
              // a day never squeezes the facts into an overflow.
              decoration: selected
                  ? BoxDecoration(
                      color: tokens.accentSoft,
                      border: Border.fromBorderSide(
                        BorderSide(
                          color: tokens.accent,
                          width: 2,
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                      ),
                    )
                  : const BoxDecoration(),
              child: Padding(
                padding: compact
                    ? const EdgeInsets.fromLTRB(4, 5, 4, 4)
                    : const EdgeInsets.fromLTRB(8, 5, 8, 4),
                child: compact
                    ? _compactCell(tokens, day)
                    : _fullCell(tokens, day),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Leading/trailing outside days keep the grid rectangle complete: they draw
  /// the same hairline rules as a real day but carry no content and no tap.
  Widget _blankCell(
    PlannerTokens tokens,
    DateTime date, {
    required double hairline,
  }) {
    final leading = dateOnly(date).compareTo(widget.month.monthStart) < 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: _gridBorder(
          tokens,
          hairline: hairline,
          left: date.weekday != DateTime.monday,
          top: !leading,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _weekdayCell(
    PlannerTokens tokens,
    DateTime date, {
    required double hairline,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(
          color: tokens.border,
          width: hairline,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
    ),
    child: Center(
      child: ExcludeSemantics(
        child: Text(
          _weekdayLabels[date.weekday - 1],
          style: TextStyle(fontSize: 11, height: 1.3, color: tokens.subtle),
        ),
      ),
    ),
  );

  /// White canvas with hairline rules: each cell draws only its top and left
  /// line, the rounded panel border closes the grid. No per-cell card fills.
  Border _gridBorder(
    PlannerTokens tokens, {
    required bool left,
    required bool top,
    required double hairline,
  }) {
    final side = BorderSide(
      color: tokens.border,
      width: hairline,
      strokeAlign: BorderSide.strokeAlignInside,
    );
    return Border(
      left: left ? side : BorderSide.none,
      top: top ? side : BorderSide.none,
    );
  }

  /// Zero-based week row of a day inside the month grid (Monday starts a row).
  int _rowOf(CalendarMonthDay day) {
    final dayNumber = int.tryParse(day.date.substring(8)) ?? 1;
    return (widget.month.heatLead + dayNumber - 1) ~/ 7;
  }

  /// Narrow cells keep the date, the execution status and a thin plan/capacity
  /// bar; the full facts stay in the tooltip. The status mark is positioned so
  /// the 320 px grid cannot overflow its 36 px cells.
  Widget _compactCell(PlannerTokens tokens, CalendarMonthDay day) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 22,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _dateNumber(tokens, day, compact: true),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: _statusMarker(tokens, day.status, compact: true),
            ),
          ],
        ),
      ),
      const Spacer(),
      if (day.capacityMinutes > 0 && day.plannedMinutes > 0)
        _planBar(tokens, day)
      else if (day.isRestDay)
        Text(
          '休',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, height: 1.3, color: tokens.subtle),
        ),
    ],
  );

  /// Desktop cell: date, plan/capacity/actual facts, up to two event titles
  /// with the +N overflow badge and the heat bar.
  Widget _fullCell(PlannerTokens tokens, CalendarMonthDay day) {
    final items = day.day.items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _dateNumber(tokens, day, compact: false),
            const Spacer(),
            _statusMarker(tokens, day.status, compact: false),
          ],
        ),
        const SizedBox(height: 2),
        _cellLine(
          '计划 ${duration(day.plannedMinutes)} · '
          '容量 ${duration(day.capacityMinutes)}',
          tokens.text,
        ),
        const SizedBox(height: 1),
        _cellLine(
          day.isRestDay
              ? '休息日'
              : day.isFuture
              ? '未到'
              : '实学 ${duration(day.actualMinutes)}',
          tokens.subtle,
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 2),
          _itemLine(tokens, items.first.title),
          if (items.length > 1)
            SizedBox(
              height: 12,
              child: Row(
                children: [
                  Expanded(child: _itemLine(tokens, items[1].title)),
                  if (items.length > _visibleItems) ...[
                    const SizedBox(width: 4),
                    _overflowBadge(tokens, items.length - _visibleItems),
                  ],
                ],
              ),
            ),
        ],
        const Spacer(),
        Align(alignment: Alignment.centerRight, child: _heatBar(tokens, day)),
      ],
    );
  }

  Widget _cellLine(String text, Color color) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: tabularFigures.copyWith(fontSize: 11, height: 1.2, color: color),
  );

  Widget _itemLine(PlannerTokens tokens, String title) => Text(
    '· $title',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: tabularFigures.copyWith(
      fontSize: 11,
      height: 1.0,
      color: tokens.muted,
    ),
  );

  Widget _dateNumber(
    PlannerTokens tokens,
    CalendarMonthDay day, {
    required bool compact,
  }) {
    final number = '${int.parse(day.date.substring(8))}';
    if (day.isToday) {
      final size = compact ? 22.0 : 24.0;
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tokens.accent, shape: BoxShape.circle),
        child: Text(
          number,
          maxLines: 1,
          style: tabularFigures.copyWith(
            fontSize: compact ? 11 : 11.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: tokens.accentOn,
          ),
        ),
      );
    }
    return SizedBox(
      height: compact ? 20 : 24,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          number,
          maxLines: 1,
          style: tabularFigures.copyWith(
            fontSize: compact ? 11 : 12.5,
            height: 1.3,
            fontWeight: day.isFuture ? FontWeight.w500 : FontWeight.w600,
            color: day.isFuture ? tokens.muted : tokens.text,
          ),
        ),
      ),
    );
  }

  Widget _planBar(PlannerTokens tokens, CalendarMonthDay day) {
    final ratio = (day.plannedMinutes / day.capacityMinutes)
        .clamp(0.0, 1.0)
        .toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 3,
          backgroundColor: tokens.surfaceMuted,
          valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
        ),
      ),
    );
  }

  Widget _heatBar(PlannerTokens tokens, CalendarMonthDay day) => Container(
    width: 18,
    height: 3,
    decoration: BoxDecoration(
      color: _heatColor(tokens, day.heatLevel),
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _statusMarker(
    PlannerTokens tokens,
    CalendarDayStatus status, {
    required bool compact,
  }) => switch (status) {
    CalendarDayStatus.completed => Icon(
      Icons.check,
      size: compact ? 11 : 12,
      color: tokens.success,
    ),
    CalendarDayStatus.partial => Icon(
      Icons.brightness_6,
      size: compact ? 11 : 12,
      color: tokens.warning,
    ),
    CalendarDayStatus.interrupted => _Dot(
      color: tokens.danger,
      size: compact ? 6 : 7,
    ),
    CalendarDayStatus.extraOnly => _Dot(
      color: tokens.warning,
      size: compact ? 6 : 7,
    ),
    CalendarDayStatus.pending => Container(
      width: compact ? 7 : 8,
      height: compact ? 7 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tokens.accent, width: 1.5),
      ),
    ),
    CalendarDayStatus.upcoming => Container(
      width: compact ? 7 : 8,
      height: compact ? 7 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: tokens.dataTone(const Color(0xff9dc0dd)),
          width: 1.5,
        ),
      ),
    ),
    CalendarDayStatus.rest => Text(
      '休',
      style: TextStyle(fontSize: 11, height: 1.3, color: tokens.subtle),
    ),
    CalendarDayStatus.free => const SizedBox.shrink(),
  };

  /// +N overflow for the event titles that do not fit in the cell.
  Widget _overflowBadge(PlannerTokens tokens, int hidden) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      '+$hidden',
      style: tabularFigures.copyWith(
        fontSize: 11,
        height: 1.0,
        fontWeight: FontWeight.w600,
        color: tokens.muted,
      ),
    ),
  );

  Widget _legend(PlannerTokens tokens, {required bool compact}) => Wrap(
    spacing: compact ? 10 : 14,
    runSpacing: 7,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        '实学热度',
        style: TextStyle(fontSize: 11, height: 1.4, color: tokens.muted),
      ),
      for (var level = 0; level <= 4; level++)
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _heatColor(tokens, level),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: level == 0 ? tokens.border : Colors.transparent,
            ),
          ),
        ),
      Text(
        '少→多',
        style: TextStyle(fontSize: 11, height: 1.4, color: tokens.subtle),
      ),
      _LegendItem(
        icon: Icon(Icons.check, size: 12, color: tokens.success),
        label: '完成原定',
      ),
      _LegendItem(
        icon: Icon(Icons.brightness_6, size: 12, color: tokens.warning),
        label: '部分执行',
      ),
      _LegendItem(
        icon: _Dot(color: tokens.danger),
        label: '中断',
      ),
      _LegendItem(
        icon: _Dot(color: tokens.warning),
        label: '计划外学习',
      ),
      _LegendItem(
        icon: _Ring(color: tokens.accent),
        label: '今天',
      ),
      if (!compact)
        _LegendItem(
          icon: Icon(Icons.hotel_outlined, size: 12, color: tokens.muted),
          label: '休息日',
        ),
    ],
  );

  static String _semanticsLabel(CalendarMonthDay day) =>
      '${fullDateLabel(day.date)}，计划 ${duration(day.plannedMinutes)}，'
      '容量 ${duration(day.capacityMinutes)}，'
      '实学 ${duration(day.actualMinutes)}，${day.status.label}';

  /// Full facts of the day, including every event, so truncation in the cell
  /// never hides data. Keeps the former tooltip format.
  static String _tooltipMessage(CalendarMonthDay day) => [
    fullDateLabel(day.date),
    '计划 ${duration(day.plannedMinutes)} · '
        '容量 ${duration(day.capacityMinutes)}'
        ' · 实学 ${duration(day.actualMinutes)}',
    day.status.label,
    for (final item in day.day.items)
      '${item.title} · 计划 ${duration(item.plannedMinutes)}'
          ' · 实学 ${duration(item.actualMinutes)}',
  ].join('\n');

  static DateTime _utcDate(String date) =>
      DateTime.tryParse('${date}T00:00:00Z') ?? DateTime.utc(1970);

  static Color _heatColor(PlannerTokens tokens, int level) => switch (level) {
    0 => tokens.surfaceMuted,
    1 => tokens.dataTone(const Color(0xffcfe0f0)),
    2 => tokens.dataTone(const Color(0xff9dc0dd)),
    3 => tokens.dataTone(const Color(0xff5d8fbd)),
    _ => tokens.accent,
  };
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, height: 1.4, color: tokens.muted),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 7});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 2),
    ),
  );
}
