import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_month_data.dart';

/// Read-only month grid: plan versus capacity, actual heat and execution status.
///
/// Selecting a cell only changes the shared read-only date; the month grid never
/// edits, completes, drags or starts anything. On narrow screens each cell keeps
/// the date, execution status and a thin plan/capacity bar, while the full facts
/// stay available through semantics and the selected-day detail below.
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
    return PlannerPanel(
      title: monthLabel(month.month),
      trailing: Text(
        '本月计划 ${duration(month.plannedMinutes)} · '
        '实学 ${duration(month.actualMinutes)} · '
        '中断 ${month.interruptedDays}天',
        key: const ValueKey('calendar-month-summary'),
        style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final cellHeight = compact ? 54.0 : 84.0;
          final rows = _weeksFor(month);
          return Column(
            key: const ValueKey('calendar-month-chart'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _weekdayHeader(context),
              const SizedBox(height: 2),
              for (final week in rows)
                SizedBox(
                  height: cellHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < 7; index++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: _cellFor(week[index], compact),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              _legend(context, compact: compact),
              const SizedBox(height: 6),
              const Text(
                '未来日期只显示计划与每日容量；实学热度只统计已经发生的日期。',
                style: TextStyle(color: PlannerColors.muted, fontSize: 11),
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
              style: const TextStyle(color: PlannerColors.muted, fontSize: 11),
            ),
          ),
        ),
    ],
  );

  Widget _cellFor(CalendarMonthDay? day, bool compact) {
    if (day == null) return const SizedBox.shrink();
    final selected = day.date == selectedDate;
    final color = _heatColor(day.heatLevel);
    final strong = day.heatLevel >= 3;
    final foreground = strong ? Colors.white : PlannerColors.text;
    final mutedForeground = strong
        ? const Color(0xffdde7f1)
        : PlannerColors.muted;
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
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelectDate(day.date),
            child: Ink(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? PlannerColors.blue : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 3 : 8,
                  4,
                  compact ? 2 : 8,
                  3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${int.parse(day.date.substring(8))}',
                                style: TextStyle(
                                  fontSize: compact ? 10 : 13,
                                  fontWeight: FontWeight.w600,
                                  color: foreground,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        _statusMarker(day.status, compact: compact),
                      ],
                    ),
                    if (!compact) ...[
                      const Spacer(),
                      Text(
                        '计划 ${duration(day.plannedMinutes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: foreground),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '容量 ${duration(day.capacityMinutes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: mutedForeground),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        day.isRestDay
                            ? '休息日'
                            : day.isFuture
                            ? '未到'
                            : '实学 ${duration(day.actualMinutes)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: mutedForeground,
                        ),
                      ),
                    ] else ...[
                      const Spacer(),
                      if (day.capacityMinutes > 0 && day.plannedMinutes > 0)
                        _planBar(day, strong ? Colors.white : PlannerColors.blue)
                      else if (day.isRestDay)
                        Text(
                          '休',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 9, color: mutedForeground),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _planBar(CalendarMonthDay day, Color color) {
    final ratio =
        (day.plannedMinutes / day.capacityMinutes).clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 3,
          backgroundColor: Colors.white.withValues(alpha: 0.45),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    );
  }

  Widget _statusMarker(CalendarDayStatus status, {required bool compact}) =>
      switch (status) {
        CalendarDayStatus.completed => Icon(
          Icons.check,
          size: compact ? 11 : 13,
          color: PlannerColors.green,
        ),
        CalendarDayStatus.partial => Icon(
          Icons.brightness_6,
          size: compact ? 11 : 13,
          color: PlannerColors.orange,
        ),
        CalendarDayStatus.interrupted => _Dot(
          color: PlannerColors.danger,
          size: compact ? 6 : 8,
        ),
        CalendarDayStatus.extraOnly => _Dot(
          color: PlannerColors.blue,
          size: compact ? 6 : 8,
        ),
        CalendarDayStatus.pending => Container(
          width: compact ? 7 : 9,
          height: compact ? 7 : 9,
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
            color: PlannerColors.muted,
          ),
        ),
        CalendarDayStatus.free => const SizedBox.shrink(),
      };

  Widget _legend(BuildContext context, {required bool compact}) => Wrap(
    spacing: compact ? 8 : 12,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Text(
        '实学热度',
        style: TextStyle(fontSize: 10, color: PlannerColors.muted),
      ),
      for (var level = 0; level <= 4; level++)
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: _heatColor(level),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      const Text(
        '少→多',
        style: TextStyle(fontSize: 10, color: PlannerColors.muted),
      ),
      const _LegendItem(
        icon: Icon(Icons.check, size: 12, color: PlannerColors.green),
        label: '完成原定',
      ),
      const _LegendItem(
        icon: Icon(Icons.brightness_6, size: 12, color: PlannerColors.orange),
        label: '部分执行',
      ),
      const _LegendItem(icon: _Dot(color: PlannerColors.danger), label: '中断'),
      const _LegendItem(icon: _Dot(color: PlannerColors.blue), label: '计划外学习'),
      const _LegendItem(icon: _Ring(color: PlannerColors.blue), label: '今天'),
      if (!compact)
        const _LegendItem(
          icon: Icon(Icons.hotel_outlined, size: 12, color: PlannerColors.muted),
          label: '休息日',
        ),
    ],
  );

  static Color _heatColor(int level) => switch (level) {
    0 => const Color(0xffeef2f7),
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
        style: const TextStyle(fontSize: 10, color: PlannerColors.muted),
      ),
    ],
  );
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 8});
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
