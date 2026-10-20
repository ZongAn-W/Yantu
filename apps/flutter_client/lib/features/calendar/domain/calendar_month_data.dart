import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';
import '../../planner/domain/capacity.dart';
import '../../planner/domain/planner_format.dart';
import 'calendar_day_data.dart';

/// How one day of the month grid presents its plan/execution facts.
///
/// The status is derived from the same capped facts as the day and week charts:
/// [CalendarMonthDay.scheduledMinutes] is the original-plan achievement, so
/// extra study never marks an unfinished original plan as completed.
enum CalendarDayStatus {
  /// Capacity override 0 with no plan and no record.
  rest,

  /// Nothing planned and nothing recorded.
  free,

  /// A future day that already carries planned minutes.
  upcoming,

  /// Today with a plan that has not been achieved yet.
  pending,

  /// The original plan was achieved (capped per task/day).
  completed,

  /// Part of the original plan was achieved.
  partial,

  /// A past day had a plan but no original-plan achievement.
  interrupted,

  /// No plan, but real study was recorded.
  extraOnly,
}

extension CalendarDayStatusLabel on CalendarDayStatus {
  String get label => switch (this) {
    CalendarDayStatus.rest => '休息日',
    CalendarDayStatus.free => '没有安排',
    CalendarDayStatus.upcoming => '未到',
    CalendarDayStatus.pending => '今天待执行',
    CalendarDayStatus.completed => '完成原定',
    CalendarDayStatus.partial => '部分执行',
    CalendarDayStatus.interrupted => '中断',
    CalendarDayStatus.extraOnly => '计划外学习',
  };
}

/// One read-only day inside a month snapshot.
class CalendarMonthDay {
  const CalendarMonthDay({
    required this.date,
    required this.day,
    required this.capacityMinutes,
    required this.today,
  });

  /// `YYYY-MM-DD` in Asia/Shanghai.
  final String date;
  final CalendarDayData day;

  /// Net learning budget of the day, resolved from the confirmed capacity rules.
  final int capacityMinutes;

  /// The Shanghai "today" the page was built for.
  final String today;

  int get plannedMinutes => day.plannedMinutes;
  int get actualMinutes => day.actualMinutes;

  /// Original-plan achievement (capped per task/day), never inflated by extra study.
  int get scheduledMinutes =>
      day.items.fold<int>(0, (sum, item) => sum + item.scheduledMinutes);

  bool get hasPlan => plannedMinutes > 0;
  bool get isFuture => date.compareTo(today) > 0;
  bool get isToday => date == today;

  bool get isRestDay =>
      capacityMinutes <= 0 && plannedMinutes == 0 && actualMinutes == 0;

  /// Remaining arrangeable minutes after the larger of plan and actual.
  int get remainingMinutes =>
      math.max(0, capacityMinutes - math.max(plannedMinutes, actualMinutes));

  /// 0 for no recorded time, otherwise 1..4 by 120-minute steps.
  int get heatLevel =>
      actualMinutes <= 0 ? 0 : math.min(4, (actualMinutes + 119) ~/ 120);

  CalendarDayStatus get status {
    if (isRestDay) return CalendarDayStatus.rest;
    if (isFuture) {
      return hasPlan ? CalendarDayStatus.upcoming : CalendarDayStatus.free;
    }
    if (!hasPlan) {
      return actualMinutes > 0
          ? CalendarDayStatus.extraOnly
          : CalendarDayStatus.free;
    }
    if (scheduledMinutes >= plannedMinutes) return CalendarDayStatus.completed;
    if (scheduledMinutes > 0) return CalendarDayStatus.partial;
    if (isToday) return CalendarDayStatus.pending;
    return CalendarDayStatus.interrupted;
  }
}

/// One immutable month snapshot built from the existing daily facts and the
/// confirmed capacity rules. The month grid, its summary and the selected-day
/// detail all read this object, so plan, actual and capacity cannot drift.
class CalendarMonthData {
  const CalendarMonthData({
    required this.month,
    required this.days,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.capacityMinutes,
    required this.interruptedDays,
    required this.studiedDays,
    required this.today,
  });

  /// `YYYY-MM`.
  final String month;

  /// Every natural day of the month, in calendar order.
  final List<CalendarMonthDay> days;
  final int plannedMinutes;
  final int actualMinutes;
  final int capacityMinutes;

  /// Past/today days with a plan but no original-plan achievement.
  final int interruptedDays;

  /// Days with at least one recorded minute.
  final int studiedDays;
  final String today;

  String get monthStart => '$month-01';
  bool get isEmpty => plannedMinutes == 0 && actualMinutes == 0;

  /// Monday-based lead blanks before the first day of the month.
  int get heatLead => mondayIndex(monthStart);

  CalendarMonthDay? dayFor(String date) {
    for (final day in days) {
      if (day.date == date) return day;
    }
    return null;
  }
}

/// Builds the read-only month snapshot that contains [anchorDate].
CalendarMonthData buildCalendarMonthData(
  PlannerData data,
  String anchorDate, {
  required String today,
}) {
  final month = anchorDate.length >= 7
      ? anchorDate.substring(0, 7)
      : monthStart(anchorDate).substring(0, 7);
  final start = monthStart(anchorDate);
  final length = daysInMonth(month);
  final days = <CalendarMonthDay>[];
  var planned = 0;
  var actual = 0;
  var capacity = 0;
  var interrupted = 0;
  var studied = 0;
  for (var index = 0; index < length; index++) {
    final date = addDate(start, index);
    final day = buildCalendarDayData(data, date);
    final dayCapacity = resolveDayCapacity(data.profile, date).minutes;
    final entry = CalendarMonthDay(
      date: date,
      day: day,
      capacityMinutes: dayCapacity,
      today: today,
    );
    days.add(entry);
    planned += entry.plannedMinutes;
    actual += entry.actualMinutes;
    capacity += dayCapacity;
    if (date.compareTo(today) <= 0 &&
        entry.plannedMinutes > 0 &&
        entry.scheduledMinutes == 0) {
      interrupted++;
    }
    if (entry.actualMinutes > 0) studied++;
  }
  return CalendarMonthData(
    month: month,
    days: List.unmodifiable(days),
    plannedMinutes: planned,
    actualMinutes: actual,
    capacityMinutes: capacity,
    interruptedDays: interrupted,
    studiedDays: studied,
    today: today,
  );
}

/// `2026年10月` label used by the month toolbar and panel heading.
String monthLabel(String month) {
  if (month.length < 7) return month;
  final monthNumber = int.tryParse(month.substring(5, 7)) ?? 0;
  return '${month.substring(0, 4)}年$monthNumber月';
}

/// Moves a `YYYY-MM-DD` date by whole months, clamping the day if needed.
String addMonth(String date, int months) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null) return date;
  final total = parsed.year * 12 + (parsed.month - 1) + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = math.min(parsed.day, lastDay);
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
