import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';
import '../../planner/domain/planner_format.dart';
import 'calendar_day_data.dart';

/// Monday-based week helpers on Asia/Shanghai date-only strings.
///
/// The strings already carry the Shanghai wall clock (the client never converts
/// them again), so week membership is plain calendar arithmetic without any
/// device time zone involvement.
String calendarWeekStart(String date) => addDate(date, -mondayIndex(date));

String calendarWeekEnd(String date) => addDate(calendarWeekStart(date), 6);

/// Monday through Sunday of the week that contains [date].
List<String> calendarWeekDates(String date) {
  final start = calendarWeekStart(date);
  return [for (var index = 0; index < 7; index++) addDate(start, index)];
}

/// Compact range label for the week navigation button.
String weekRangeLabel(String weekStart) {
  final end = addDate(weekStart, 6);
  final startYear = weekStart.length >= 4 ? weekStart.substring(0, 4) : '';
  final endYear = end.length >= 4 ? end.substring(0, 4) : '';
  String compact(String date) {
    if (date.length < 10) return date;
    final month = int.tryParse(date.substring(5, 7)) ?? 0;
    final day = int.tryParse(date.substring(8, 10)) ?? 0;
    return '$month月$day日';
  }

  final sameMonth =
      weekStart.length >= 7 &&
      end.length >= 7 &&
      weekStart.substring(0, 7) == end.substring(0, 7);
  if (sameMonth) {
    final endDay = int.tryParse(end.substring(8, 10)) ?? 0;
    return '${compact(weekStart)}–$endDay日';
  }
  if (startYear != endYear) {
    return '$startYear年${compact(weekStart)} – $endYear年${compact(end)}';
  }
  return '${compact(weekStart)} – ${compact(end)}';
}

/// Full spoken range label, used for semantics and the day detail heading.
String weekSemanticRange(String weekStart) =>
    '${fullDateLabel(weekStart)}至${fullDateLabel(addDate(weekStart, 6))}';

/// One read-only day inside a week snapshot.
class CalendarWeekDay {
  const CalendarWeekDay({
    required this.date,
    required this.index,
    required this.day,
  });

  /// `YYYY-MM-DD` in Asia/Shanghai.
  final String date;

  /// 0 = Monday … 6 = Sunday.
  final int index;
  final CalendarDayData day;

  int get plannedMinutes => day.plannedMinutes;
  int get actualMinutes => day.actualMinutes;
}

/// One effort-kind stacking layer, shared by both week charts.
///
/// The position in [CalendarWeekData.layers] is the fixed stacking and legend
/// order for the whole week. A day without that kind of effort contributes `0`
/// instead of reordering the layers.
class CalendarWeekLayer {
  const CalendarWeekLayer({
    required this.kind,
    required this.minutesByDay,
    required this.totalMinutes,
  });

  final CalendarEffortKind kind;

  /// Seven values, Monday through Sunday; never reordered or dropped.
  final List<int> minutesByDay;
  final int totalMinutes;

  int minutesOn(int dayIndex) => minutesByDay[dayIndex];
}

/// One immutable week snapshot built from the existing daily domain facts.
///
/// Both week charts, their legends and the day detail read this same object, so
/// totals, owners, classifications and item order cannot drift
/// between the two graphics. Totals are aggregated directly across unique task
/// rows, without repeating any values for tasks that carry multiple tags. The
/// model never writes to the plan and never derives an effort kind from
/// `actual - planned`.
class CalendarWeekData {
  const CalendarWeekData({
    required this.weekStart,
    required this.days,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.scaleMinutes,
    required this.layers,
    required this.minutesByKind,
  });

  final String weekStart;

  /// Exactly seven entries, Monday through Sunday.
  final List<CalendarWeekDay> days;
  final int plannedMinutes;
  final int actualMinutes;

  /// Shared vertical denominator. Both the planned outline and the actual
  /// mountains/bars use it, so the two sides of the mirror never normalize
  /// independently and over-plan minutes are never truncated.
  final double scaleMinutes;

  /// Fixed effort-kind stacking order for the whole week.
  final List<CalendarWeekLayer> layers;
  final Map<CalendarEffortKind, int> minutesByKind;

  String get weekEnd => days[6].date;
  bool get isEmpty => plannedMinutes == 0 && actualMinutes == 0;

  CalendarWeekDay dayAt(int index) => days[index];

  CalendarWeekDay? dayFor(String date) {
    for (final day in days) {
      if (day.date == date) return day;
    }
    return null;
  }

  /// The item order shown in the shared detail list, Monday through Sunday.
  List<CalendarDayItem> itemsFor(String date) =>
      dayFor(date)?.day.items ?? const [];
}

/// Builds the read-only week snapshot that contains [anchorDate].
CalendarWeekData buildCalendarWeekData(PlannerData data, String anchorDate) {
  final dates = calendarWeekDates(anchorDate);
  final days = [
    for (var index = 0; index < dates.length; index++)
      CalendarWeekDay(
        date: dates[index],
        index: index,
        day: buildCalendarDayData(data, dates[index]),
      ),
  ];

  // Aggregate each unique task row once into fixed effort-kind layers. A task's
  // tag list is presentation metadata and never expands its minutes.
  final layerMinutes = <CalendarEffortKind, List<int>>{};
  for (final weekDay in days) {
    for (final item in weekDay.day.items) {
      for (final effort in item.efforts) {
        if (effort.minutes <= 0) continue;
        final minutes = layerMinutes.putIfAbsent(
          effort.kind,
          () => List<int>.filled(7, 0),
        );
        minutes[weekDay.index] += effort.minutes;
      }
    }
  }
  final layers = [
    for (final kind in CalendarEffortKind.values)
      if (layerMinutes.containsKey(kind))
        CalendarWeekLayer(
          kind: kind,
          minutesByDay: List<int>.unmodifiable(layerMinutes[kind]!),
          totalMinutes: layerMinutes[kind]!.fold<int>(
            0,
            (sum, value) => sum + value,
          ),
        ),
  ];

  final minutesByKind = <CalendarEffortKind, int>{};
  for (final layer in layers) {
    minutesByKind[layer.kind] =
        (minutesByKind[layer.kind] ?? 0) + layer.totalMinutes;
  }

  var planned = 0;
  var actual = 0;
  var maximum = 0;
  for (final weekDay in days) {
    planned += weekDay.plannedMinutes;
    actual += weekDay.actualMinutes;
    maximum = math.max(
      maximum,
      math.max(weekDay.plannedMinutes, weekDay.actualMinutes),
    );
  }

  return CalendarWeekData(
    weekStart: dates.first,
    days: List<CalendarWeekDay>.unmodifiable(days),
    plannedMinutes: planned,
    actualMinutes: actual,
    scaleMinutes: math.max(1, maximum).toDouble(),
    layers: List<CalendarWeekLayer>.unmodifiable(layers),
    minutesByKind: Map<CalendarEffortKind, int>.unmodifiable(minutesByKind),
  );
}
