import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_month_data.dart';

/// Read-only month grid: plan versus capacity, actual heat and execution status.
///
/// Selecting a cell only changes the shared read-only date; the month grid never
/// edits, completes, drags or starts anything. Following the "Mist Ink" calendar
/// recipe the surface is white with hairline rules: the heat no longer fills the
/// whole cell, today is a 24 px ink-blue circle and the selected day is an inset
/// 2 px ring.
class CalendarMonthChart extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hairline = plannerHairline(context);
    return PlannerPanel(
      title: monthLabel(month.month),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final cellHeight = compact ? 52.0 : 100.0;
          final rows = _weeksFor(month);
          return Column(
            key: const ValueKey('calendar-month-chart'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '本月计划 ${duration(month.plannedMinutes)} · '
                    '实学 ${duration(month.actualMinutes)}'
                    // Narrow panels break before the interruption fact instead
                    // of splitting "中断 0 天" across two lines.
                    '${compact ? '\n' : ' · '}'
                    '中断 ${month.interruptedDays}\u00A0天',
                    key: const ValueKey('calendar-month-summary'),
                    style: tabularFigures.copyWith(
                      fontSize: compact ? 11.5 : 12,
                      height: 1.5,
                      color: PlannerColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PlannerSpace.md),
              _weekdayHeader(context),
              const SizedBox(height: 6),
              _grid(
                rows,
                compact: compact,
                cellHeight: cellHeight,
                hairline: hairline,
              ),
              const SizedBox(height: PlannerSpace.md),
              _legend(context, compact: compact),
              const SizedBox(height: PlannerSpace.sm),
              const Text(
                '未来日期只显示计划与每日容量；实学热度只统计已经发生的日期。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: PlannerColors.subtle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<List<CalendarMonthDay?>> _weeksFor(CalendarMonthData data) {
    final slots = <CalendarMonthDay?>[
      for (var i = 0; i < data.heatLead; i++) null,
      ...data.days,
    ];
    while (slots.length % 7 != 0) {
      slots.add(null);
    }
    return [
      for (var start = 0; start < slots.length; start += 7)
        slots.sublist(start, start + 7),
    ];
  }

  Widget _weekdayHeader(BuildContext context) => Row(
    children: [
      for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
        Expanded(
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: PlannerColors.subtle,
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
        ),
    ],
  );

  /// White canvas with hairline rules: each cell draws only its top and left
  /// line, the outer border closes the grid. No per-cell card fills.
  Widget _grid(
    List<List<CalendarMonthDay?>> rows, {
    required bool compact,
    required double cellHeight,
    required double hairline,
  }) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: PlannerColors.surface,
      borderRadius: BorderRadius.circular(PlannerRadius.small),
      border: Border.all(color: PlannerColors.border, width: hairline),
    ),
    child: Column(
      children: [
        for (var row = 0; row < rows.length; row++)
          SizedBox(
            height: cellHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          left: column == 0
                              ? BorderSide.none
                              : BorderSide(
                                  color: PlannerColors.border,
                                  width: hairline,
                                ),
                          top: row == 0
                              ? BorderSide.none
                              : BorderSide(
                                  color: PlannerColors.border,
                                  width: hairline,
                                ),
                        ),
                      ),
                      child: _cellFor(rows[row][column], compact),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _cellFor(CalendarMonthDay? day, bool compact) {
    if (day == null) return const SizedBox.expand();
    final selected = day.date == selectedDate;
    final today = day.isToday;
    return Semantics(
      button: true,
      label:
          '${fullDateLabel(day.date)}，计划 ${duration(day.plannedMinutes)}，'
          '容量 ${duration(day.capacityMinutes)}，实学 ${duration(day.actualMinutes)}，'
          '${day.status.label}',
      child: Tooltip(
        message:
            '${fullDateLabel(day.date)}\n'
            '计划 ${duration(day.plannedMinutes)} · 容量 ${duration(day.capacityMinutes)}'
            ' · 实学 ${duration(day.actualMinutes)}\n'
            '${day.status.label}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('calendar-month-day-${day.date}'),
            borderRadius: BorderRadius.circular(PlannerRadius.small),
            onTap: () => onSelectDate(day.date),
            child: Ink(
              decoration: BoxDecoration(
                color: selected ? PlannerColors.blueSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(PlannerRadius.small),
                border: selected
                    ? Border.all(
                        color: PlannerColors.blue,
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignInside,
                      )
                    : null,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 4 : 8,
                  compact ? 5 : 6,
                  compact ? 4 : 8,
                  compact ? 4 : 5,
                ),
                child: compact
                    ? _compactCell(day, today)
                    : _fullCell(day, today),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Narrow cells keep the date, the execution status and a thin plan/capacity
  /// bar; the full facts stay in semantics and the day tooltip. The status mark
  /// is positioned so the 320 px grid cannot overflow its 36 px cells.
  Widget _compactCell(CalendarMonthDay day, bool today) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 22,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _dateNumber(day, today, compact: true),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: _statusMarker(day.status, compact: true),
            ),
          ],
        ),
      ),
      const Spacer(),
      if (day.capacityMinutes > 0 && day.plannedMinutes > 0)
        _planBar(day)
      else if (day.isRestDay)
        Text(
          '休',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9,
            height: 1.3,
            color: PlannerColors.subtle,
          ),
        ),
    ],
  );

  Widget _fullCell(CalendarMonthDay day, bool today) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          _dateNumber(day, today, compact: false),
          const Spacer(),
          _statusMarker(day.status, compact: false),
        ],
      ),
      const SizedBox(height: 3),
      _cellLine('计划 ${duration(day.plannedMinutes)}', PlannerColors.text),
      const SizedBox(height: 1),
      _cellLine('容量 ${duration(day.capacityMinutes)}', PlannerColors.muted),
      const SizedBox(height: 1),
      _cellLine(
        day.isRestDay
            ? '休息日'
            : day.isFuture
            ? '未到'
            : '实学 ${duration(day.actualMinutes)}',
        PlannerColors.subtle,
      ),
      const Spacer(),
      Align(
        alignment: Alignment.bottomRight,
        child: Container(
          width: 18,
          height: 3,
          decoration: BoxDecoration(
            color: _heatColor(day.heatLevel),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ],
  );

  Widget _cellLine(String text, Color color) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: tabularFigures.copyWith(fontSize: 10.5, height: 1.3, color: color),
  );

  Widget _dateNumber(
    CalendarMonthDay day,
    bool today, {
    required bool compact,
  }) {
    final number = '${int.parse(day.date.substring(8))}';
    if (today) {
      final size = compact ? 22.0 : 24.0;
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: PlannerColors.blue,
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          maxLines: 1,
          style: tabularFigures.copyWith(
            fontSize: compact ? 10.5 : 11.5,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: Colors.white,
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
            color: day.isFuture ? PlannerColors.muted : PlannerColors.text,
          ),
        ),
      ),
    );
  }

  Widget _planBar(CalendarMonthDay day) {
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
          backgroundColor: PlannerColors.surfaceMuted,
          valueColor: const AlwaysStoppedAnimation<Color>(PlannerColors.blue),
        ),
      ),
    );
  }

  Widget _statusMarker(CalendarDayStatus status, {required bool compact}) =>
      switch (status) {
        CalendarDayStatus.completed => Icon(
          Icons.check,
          size: compact ? 11 : 12,
          color: PlannerColors.green,
        ),
        CalendarDayStatus.partial => Icon(
          Icons.brightness_6,
          size: compact ? 11 : 12,
          color: PlannerColors.orange,
        ),
        CalendarDayStatus.interrupted => _Dot(
          color: PlannerColors.danger,
          size: compact ? 6 : 7,
        ),
        CalendarDayStatus.extraOnly => _Dot(
          color: PlannerColors.orange,
          size: compact ? 6 : 7,
        ),
        CalendarDayStatus.pending => Container(
          width: compact ? 7 : 8,
          height: compact ? 7 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: PlannerColors.blue, width: 1.5),
          ),
        ),
        CalendarDayStatus.upcoming => Container(
          width: compact ? 7 : 8,
          height: compact ? 7 : 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xff9dc0dd), width: 1.5),
          ),
        ),
        CalendarDayStatus.rest => Text(
          '休',
          style: TextStyle(
            fontSize: compact ? 8 : 9,
            height: 1.3,
            color: PlannerColors.subtle,
          ),
        ),
        CalendarDayStatus.free => const SizedBox.shrink(),
      };

  Widget _legend(BuildContext context, {required bool compact}) => Wrap(
    spacing: compact ? 10 : 14,
    runSpacing: 7,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text(
        '实学热度',
        style: TextStyle(fontSize: 11, height: 1.4, color: PlannerColors.muted),
      ),
      for (var level = 0; level <= 4; level++)
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _heatColor(level),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: level == 0 ? PlannerColors.border : Colors.transparent,
            ),
          ),
        ),
      const Text(
        '少→多',
        style: TextStyle(
          fontSize: 11,
          height: 1.4,
          color: PlannerColors.subtle,
        ),
      ),
      const _LegendItem(
        icon: Icon(Icons.check, size: 12, color: PlannerColors.green),
        label: '完成原定',
      ),
      const _LegendItem(
        icon: Icon(Icons.brightness_6, size: 12, color: PlannerColors.orange),
        label: '部分执行',
      ),
      const _LegendItem(
        icon: _Dot(color: PlannerColors.danger),
        label: '中断',
      ),
      const _LegendItem(
        icon: _Dot(color: PlannerColors.orange),
        label: '计划外学习',
      ),
      const _LegendItem(
        icon: _Ring(color: PlannerColors.blue),
        label: '今天',
      ),
      if (!compact)
        const _LegendItem(
          icon: Icon(
            Icons.hotel_outlined,
            size: 12,
            color: PlannerColors.muted,
          ),
          label: '休息日',
        ),
    ],
  );

  static Color _heatColor(int level) => switch (level) {
    0 => PlannerColors.surfaceMuted,
    1 => const Color(0xffcfe0f0),
    2 => const Color(0xff9dc0dd),
    3 => const Color(0xff5d8fbd),
    _ => PlannerColors.blue,
  };
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      icon,
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          height: 1.4,
          color: PlannerColors.muted,
        ),
      ),
    ],
  );
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
