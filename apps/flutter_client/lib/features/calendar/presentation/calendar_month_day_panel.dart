import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_day_data.dart';
import '../domain/calendar_month_data.dart';
import 'calendar_month_colors.dart';

/// Read-only plan detail for the selected day of the month mosaic.
///
/// The calendar keeps only dates and colour blocks; every piece of text lives
/// here, outside the grid. In the desktop split layout the panel is placed next
/// to the grid (`stacked = false`, fixed height, scrollable item list); below the
/// split threshold it stacks under the grid and grows naturally.
class CalendarMonthDayPanel extends StatelessWidget {
  const CalendarMonthDayPanel({
    required this.day,
    required this.onOpenDayView,
    this.stacked = false,
    super.key,
  });

  final CalendarMonthDay? day;
  final VoidCallback onOpenDayView;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final selected = day;
    if (selected == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    final hairline = plannerHairline(context);
    final items = _plannedItems(selected);
    final over =
        selected.plannedMinutes > 0 &&
        (selected.capacityMinutes <= 0 ||
            selected.plannedMinutes > selected.capacityMinutes);
    final header = _header(tokens, selected, items.length, over);
    final detail = _items(tokens, hairline, selected, items);
    final link = Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const ValueKey('calendar-month-open-day'),
        onPressed: onOpenDayView,
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        child: const Text('在日视图中查看 →'),
      ),
    );
    return Container(
      key: const ValueKey('calendar-month-day-panel'),
      padding: stacked
          ? const EdgeInsets.only(top: PlannerSpace.md)
          : const EdgeInsets.only(left: PlannerSpace.lg),
      decoration: BoxDecoration(
        border: stacked
            ? Border(
                top: BorderSide(color: tokens.border, width: hairline),
              )
            : Border(
                left: BorderSide(color: tokens.border, width: hairline),
              ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                header,
                const SizedBox(height: PlannerSpace.md),
                detail,
                const SizedBox(height: PlannerSpace.md),
                link,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: PlannerSpace.md),
              Flexible(child: SingleChildScrollView(child: detail)),
              const SizedBox(height: PlannerSpace.md),
              link,
            ],
          );
        },
      ),
    );
  }

  List<CalendarDayItem> _plannedItems(CalendarMonthDay day) => [
    for (final item in day.day.items)
      if (item.plannedMinutes > 0) item,
  ];

  Widget _header(
    PlannerTokens tokens,
    CalendarMonthDay day,
    int itemCount,
    bool over,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '${int.parse(day.date.substring(8))}',
            style: tabularFigures.copyWith(
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: tokens.text,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            weekdayLabel(day.date),
            style: TextStyle(fontSize: 12, height: 1.4, color: tokens.muted),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        '计划 ${duration(day.plannedMinutes)} · $itemCount 项',
        key: const ValueKey('calendar-month-day-total'),
        style: tabularFigures.copyWith(
          fontSize: 12,
          height: 1.5,
          color: tokens.muted,
        ),
      ),
      if (over) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: tokens.noticeWarningBackground,
              border: Border.all(color: tokens.noticeWarningBorder),
              borderRadius: BorderRadius.circular(PlannerRadius.pill),
            ),
            child: Text(
              '超容量 ${duration(day.plannedMinutes - (day.capacityMinutes <= 0 ? 0 : day.capacityMinutes))}',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: tokens.noticeWarningInk,
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget _items(
    PlannerTokens tokens,
    double hairline,
    CalendarMonthDay day,
    List<CalendarDayItem> items,
  ) {
    if (items.isEmpty) {
      return Text(
        '这一天还没有安排',
        style: TextStyle(fontSize: 11.5, height: 1.5, color: tokens.subtle),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++)
          Container(
            key: ValueKey('calendar-month-day-item-${items[index].id}'),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: index == 0
                ? null
                : BoxDecoration(
                    border: Border(
                      top: BorderSide(color: tokens.border, width: hairline),
                    ),
                  ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: calendarMonthItemColor(items[index], tokens),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items[index].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: tokens.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  duration(items[index].plannedMinutes),
                  style: tabularFigures.copyWith(
                    fontSize: 10.5,
                    height: 1.4,
                    color: tokens.subtle,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
