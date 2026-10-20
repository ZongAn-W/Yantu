import 'package:flutter/material.dart';
import 'package:planner_ui_vendor/planner_ui_vendor.dart';
import 'package:table_calendar/table_calendar.dart';

import 'theme.dart';

/// Read-only-safe, fully Chinese date picker built on the same table_calendar
/// primitives as the month scope.
///
/// The Material showDatePicker renders its month/weekday headers through
/// Flutter localizations; without flutter_localizations those headings stay
/// English in an otherwise Chinese-only product. Rather than adding a new
/// localization dependency, this dialog reuses TableCalendarBase (Apache-2.0,
/// registered in THIRD_PARTY_NOTICES.md) with a planner-designed header,
/// Chinese weekday labels, token colours and the same 12/10 px radius ladder.
Future<DateTime?> showPlannerDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择日期',
}) {
  final first = _day(firstDate ?? DateTime(1900));
  final last = _day(lastDate ?? DateTime(2200, 12, 31));
  final initial = _clamp(_day(initialDate), first, last);
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _PlannerDatePickerDialog(
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      title: title,
    ),
  );
}

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

DateTime _clamp(DateTime value, DateTime first, DateTime last) {
  if (value.isBefore(first)) return first;
  if (value.isAfter(last)) return last;
  return value;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _two(int value) => value.toString().padLeft(2, '0');

String _iso(DateTime value) =>
    '${value.year}-${_two(value.month)}-${_two(value.day)}';

class _PlannerDatePickerDialog extends StatefulWidget {
  const _PlannerDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  @override
  State<_PlannerDatePickerDialog> createState() =>
      _PlannerDatePickerDialogState();
}

class _PlannerDatePickerDialogState extends State<_PlannerDatePickerDialog> {
  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  late DateTime _focusedDay = widget.initialDate;
  late DateTime _selectedDay = widget.initialDate;

  void _moveMonth(int delta) {
    setState(() {
      final target = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
      if (target.isBefore(
        DateTime(widget.firstDate.year, widget.firstDate.month),
      )) {
        return;
      }
      if (target.isAfter(
        DateTime(widget.lastDate.year, widget.lastDate.month),
      )) {
        return;
      }
      _focusedDay = target;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final today = DateTime.now();
    return AlertDialog(
      key: const ValueKey('planner-date-picker'),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      title: Text(
        widget.title,
        style: text.titleMedium?.copyWith(color: tokens.text),
      ),
      content: SizedBox(
        width: 292,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  key: const ValueKey('planner-date-picker-previous'),
                  tooltip: '上个月',
                  onPressed: () => _moveMonth(-1),
                  icon: Icon(
                    LucideIcons.chevronLeft,
                    size: 17,
                    color: tokens.muted,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${_focusedDay.year}年${_focusedDay.month}月',
                      style: tabularFigures.copyWith(
                        fontSize: 13.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('planner-date-picker-next'),
                  tooltip: '下个月',
                  onPressed: () => _moveMonth(1),
                  icon: Icon(
                    LucideIcons.chevronRight,
                    size: 17,
                    color: tokens.muted,
                  ),
                ),
              ],
            ),
            TableCalendarBase(
              key: ValueKey(
                'planner-date-picker-grid-${_focusedDay.year}-${_focusedDay.month}',
              ),
              firstDay: DateTime.utc(
                widget.firstDate.year,
                widget.firstDate.month,
                widget.firstDate.day,
              ),
              lastDay: DateTime.utc(
                widget.lastDate.year,
                widget.lastDate.month,
                widget.lastDate.day,
              ),
              focusedDay: DateTime.utc(
                _focusedDay.year,
                _focusedDay.month,
                _focusedDay.day,
              ),
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              availableGestures: AvailableGestures.none,
              pageAnimationEnabled: false,
              rowHeight: 38,
              dowHeight: 24,
              dowBuilder: (context, date) => Center(
                child: Text(
                  _weekdayLabels[date.weekday - 1],
                  style: text.labelSmall?.copyWith(
                    fontSize: 11.5,
                    color: tokens.muted,
                  ),
                ),
              ),
              dayBuilder: (context, date, focusedDay) {
                if (date.month != _focusedDay.month) {
                  return const SizedBox.shrink();
                }
                final day = _day(date);
                final selected = _sameDay(day, _selectedDay);
                final isToday = _sameDay(day, today);
                return Semantics(
                  button: true,
                  selected: selected,
                  label: '${day.month}月${day.day}日',
                  child: InkWell(
                    key: ValueKey('planner-date-picker-day-${_iso(day)}'),
                    onTap: () => setState(() => _selectedDay = day),
                    borderRadius: BorderRadius.circular(tokens.radiusSmall),
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? tokens.accent : Colors.transparent,
                          shape: BoxShape.circle,
                          border: !selected && isToday
                              ? Border.all(color: tokens.accent)
                              : null,
                        ),
                        child: Text(
                          '${day.day}',
                          style: tabularFigures.copyWith(
                            fontSize: 12.5,
                            height: 1.2,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? tokens.accentOn
                                : isToday
                                ? tokens.accent
                                : tokens.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('planner-date-picker-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('planner-date-picker-confirm'),
          onPressed: () => Navigator.of(context).pop(_selectedDay),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
