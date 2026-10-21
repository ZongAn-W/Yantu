import 'calendar_day_data.dart';

/// One item's share of the actually recorded learning time in a period.
///
/// The period is whatever day/week/month the calendar currently shows. Only
/// minutes that were really recorded count: a task that was planned but never
/// studied has no slice, and the retired temporary (ad-hoc) rows never reach
/// this model because [buildCalendarDayData] already ignores them.
class CalendarCompletionSlice {
  const CalendarCompletionSlice({
    required this.id,
    required this.title,
    required this.tagNames,
    required this.tagColor,
    required this.minutes,
  });

  /// Stable owner id: `task:<taskId>` for a live task, or one of the merged
  /// buckets below.
  final String id;
  final String title;
  final List<String> tagNames;

  /// The task's first explicit tag colour (`#rrggbb`), when it has one.
  final String? tagColor;

  /// Recorded minutes inside the period; always greater than zero.
  final int minutes;

  /// Bucket id of every task-less historical log row.
  static const String legacyId = 'legacy';

  /// Bucket id of every log whose task was deleted from the plan.
  static const String deletedId = 'deleted';
}

/// The completed-item time composition of one calendar period.
///
/// Slices are ordered by recorded minutes (descending), then title and id so
/// equal totals never flip between builds. [totalMinutes] is the exact sum of
/// the slices: it is the same denominator the percentage labels use.
class CalendarCompletionData {
  const CalendarCompletionData({
    required this.slices,
    required this.totalMinutes,
  });

  static const CalendarCompletionData empty = CalendarCompletionData(
    slices: [],
    totalMinutes: 0,
  );

  final List<CalendarCompletionSlice> slices;
  final int totalMinutes;

  bool get isEmpty => totalMinutes <= 0;
  int get itemCount => slices.length;
}

/// Aggregates one or more already-built day snapshots into one period snapshot.
///
/// The day/week/month scopes all reuse [buildCalendarDayData], so this function
/// cannot drift from the per-scope totals: it only groups the same actual
/// minutes by owner. Task-less historical logs share the single
/// [CalendarCompletionSlice.legacyId] bucket because their per-row ids are not
/// meaningful to the reader; logs whose task was deleted share
/// [CalendarCompletionSlice.deletedId] for the same reason. Both merged buckets
/// drop tag metadata because they no longer describe one visible task.
CalendarCompletionData buildCalendarCompletionData(
  Iterable<CalendarDayData> days,
) {
  final builders = <String, _CompletionSliceBuilder>{};
  for (final day in days) {
    for (final item in day.items) {
      if (item.actualMinutes <= 0) continue;
      final bucket = _bucketOf(item);
      final builder = builders.putIfAbsent(
        bucket.id,
        () => _CompletionSliceBuilder(id: bucket.id, title: bucket.title),
      );
      builder.minutes += item.actualMinutes;
      if (builder.id == item.id) {
        // A live task owner keeps its metadata; merged buckets stay anonymous.
        if (builder.tagNames.isEmpty && item.tagNames.isNotEmpty) {
          builder.tagNames = item.tagNames;
        }
        builder.tagColor ??= item.tagColor;
      }
    }
  }

  final slices =
      [
        for (final builder in builders.values)
          if (builder.minutes > 0)
            CalendarCompletionSlice(
              id: builder.id,
              title: builder.title,
              tagNames: List.unmodifiable(builder.tagNames),
              tagColor: builder.tagColor,
              minutes: builder.minutes,
            ),
      ]..sort((a, b) {
        final byMinutes = b.minutes.compareTo(a.minutes);
        if (byMinutes != 0) return byMinutes;
        final byTitle = a.title.compareTo(b.title);
        if (byTitle != 0) return byTitle;
        return a.id.compareTo(b.id);
      });

  var total = 0;
  for (final slice in slices) {
    total += slice.minutes;
  }
  return CalendarCompletionData(
    slices: List.unmodifiable(slices),
    totalMinutes: total,
  );
}

({String id, String title}) _bucketOf(CalendarDayItem item) {
  if (item.id.startsWith('log:')) {
    return (id: CalendarCompletionSlice.legacyId, title: '历史学习记录');
  }
  if (item.title == '已删除事项') {
    return (id: CalendarCompletionSlice.deletedId, title: '已删除事项');
  }
  return (id: item.id, title: item.title);
}

class _CompletionSliceBuilder {
  _CompletionSliceBuilder({required this.id, required this.title});

  final String id;
  final String title;
  int minutes = 0;
  List<String> tagNames = const [];
  String? tagColor;
}
