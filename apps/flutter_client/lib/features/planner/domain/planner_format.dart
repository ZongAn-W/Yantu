import '../../../shared/models/planner_models.dart';

/// The Web client resolves every calendar day in Asia/Shanghai. Flutter keeps the
/// same wall clock so a device in another time zone still opens the same day.
const Duration _shanghaiOffset = Duration(hours: 8);

/// `YYYY-MM-DD` for the current Asia/Shanghai day.
String shanghaiToday([DateTime? now]) => dateOnly(
  (now ?? DateTime.now()).toUtc().add(_shanghaiOffset),
);

/// Formats a `DateTime` that already carries the Asia/Shanghai wall clock.
String dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// Calendar arithmetic on date-only strings; no local time zone is involved.
String addDate(String date, int days) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null) return date;
  return dateOnly(parsed.toUtc().add(Duration(days: days)));
}

/// Whole days between two date-only strings, matching the Web millisecond math.
int daysBetween(String from, String to) {
  final start = DateTime.tryParse('${from}T00:00:00Z');
  final end = DateTime.tryParse('${to}T00:00:00Z');
  if (start == null || end == null) return 0;
  return (end.difference(start).inMilliseconds / 86400000).ceil();
}

/// Same rounding as JavaScript `Math.round`: halves go towards +Infinity, which
/// differs from Dart's `round()` for negative halves (irrelevant for minutes but
/// kept explicit so both clients cannot drift).
int jsRound(num value) => (value + 0.5).floor();

String duration(num minutes) {
  // Round the whole value first, exactly like the Web client, so a fractional
  // total can never leave an impossible "60分" remainder behind.
  final total = jsRound(minutes);
  if (total >= 60) {
    return '${total ~/ 60}小时${total % 60 != 0 ? '${total % 60}分' : ''}';
  }
  return '$total分钟';
}

const statusLabels = {
  TaskStatus.notStarted: '未开始',
  TaskStatus.inProgress: '进行中',
  TaskStatus.completed: '完成',
  TaskStatus.delayed: '延期',
  TaskStatus.conflict: '冲突',
};

const priorityLabels = {1: '普通', 2: '中高', 3: '高'};

const fixedEventKindLabels = {
  FixedEventKind.rest: '休息',
  FixedEventKind.course: '固定课程',
  FixedEventKind.exam: '模拟考试',
  FixedEventKind.officialExam: '正式考试',
};

const fixedEventRepeatLabels = {
  EventRepeat.none: '不重复',
  EventRepeat.daily: '每天',
  EventRepeat.weekly: '每周',
};

const completionStatusLabels = {
  CompletionStatus.notStarted: '未开始',
  CompletionStatus.partial: '部分完成',
  CompletionStatus.completed: '已完成',
  CompletionStatus.skipped: '跳过',
};

/// `HH:mm` for a minute-of-day value.
String clockTime(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// Parses `HH:mm` back into a minute-of-day value; returns null when malformed.
int? parseClockTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

const _weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String weekdayLabel(String date) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null) return '';
  return _weekdayNames[parsed.toUtc().weekday - 1];
}

String monthDayLabel(String date) =>
    date.length >= 10 ? '${date.substring(5, 7)}月${date.substring(8, 10)}日' : date;

/// `M月D日 周X`, matching the Web dashboard heading.
String fullDateLabel(String date) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null) return date;
  return '${parsed.toUtc().month}月${parsed.toUtc().day}日 '
      '${_weekdayNames[parsed.toUtc().weekday - 1]}';
}

/// First day of the month that contains [date].
String monthStart(String date) => '${date.substring(0, 7)}-01';

int daysInMonth(String month) {
  final year = int.tryParse(month.substring(0, 4)) ?? 0;
  final index = int.tryParse(month.substring(5, 7)) ?? 1;
  if (index < 1 || index > 12) return 0;
  return DateTime.utc(year, index + 1, 0).day;
}

/// Monday-based index (0 = Monday) used by the monthly heat map.
int mondayIndex(String date) {
  final parsed = DateTime.tryParse('${date}T00:00:00Z');
  if (parsed == null) return 0;
  return parsed.toUtc().weekday - 1;
}

String nowIso() => DateTime.now().toUtc().toIso8601String();
