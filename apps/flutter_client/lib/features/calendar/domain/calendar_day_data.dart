import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';
import '../../planner/domain/study_day.dart';

/// The relation of recorded minutes, independent of task completion status.
enum CalendarEffortKind {
  scheduled,
  extra,
  unscheduled,
  legacyUnknown;

  String get label => switch (this) {
    scheduled => '原定学习',
    extra => '已有事项加学',
    unscheduled => '当天未排程的事项',
    legacyUnknown => '历史记录',
  };
}

class CalendarDayEffort {
  const CalendarDayEffort({required this.kind, required this.minutes});

  final CalendarEffortKind kind;
  final int minutes;
}

/// One canonical owner, shared unchanged by all three calendar charts.
class CalendarDayItem {
  const CalendarDayItem({
    required this.id,
    required this.title,
    required this.tagNames,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.scheduledMinutes,
    required this.efforts,
  });

  final String id;
  final String title;
  final List<String> tagNames;
  final int plannedMinutes;
  final int actualMinutes;

  /// Original-plan contribution; extra study cannot fill this quota.
  final int scheduledMinutes;
  final List<CalendarDayEffort> efforts;
}

class CalendarDayData {
  const CalendarDayData({
    required this.date,
    required this.items,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.scaleMinutes,
    required this.riverScaleMinutes,
  });

  final String date;
  final List<CalendarDayItem> items;
  final int plannedMinutes;
  final int actualMinutes;

  /// Shared minutes-to-length/angle denominator for per-item tracks.
  final double scaleMinutes;

  /// Shared denominator for both the planned and actual river.
  final double riverScaleMinutes;
}

/// A read-only union of today's scheduled owners and recorded-learning owners.
///
/// Original-plan attribution comes from the existing domain statistic, including
/// its limited legacy inference. Every displayed log is assigned to exactly one
/// owner.
///
/// Temporary (ad-hoc) learning is retired in the client. The server may still
/// return historical rows for it, so every row that belongs to a temporary
/// learning entity is ignored here: it never creates an item, an effort kind or
/// an actual minute in the calendar. Session ids are deliberately not used to
/// collapse logs: one timer session may legitimately contain distinct relations
/// and Shanghai-day segments.
CalendarDayData buildCalendarDayData(PlannerData data, String date) {
  final summary = dayExecutionSummary(data, date);
  final tasks = {for (final task in data.tasks) task.id: task};
  final tags = {for (final tag in data.tags) tag.id: tag};
  final builders = <String, _DayItemBuilder>{};
  var actualMinutes = 0;

  _DayItemBuilder taskOwner(String taskId) {
    final id = 'task:$taskId';
    return builders.putIfAbsent(id, () {
      final task = tasks[taskId];
      return _DayItemBuilder(
        id: id,
        title: task?.title ?? '已删除事项',
        tagNames: [
          for (final tagId in task?.tagIds ?? const <String>[])
            if (tags[tagId] case final tag?) tag.name,
        ],
      );
    });
  }

  for (final block in data.blocks) {
    if (block.date != date) continue;
    final owner = taskOwner(block.taskId);
    owner.planned += block.durationMinutes;
    owner.firstBlock = math.min(owner.firstBlock, block.startMinute);
  }

  for (final log in data.logs) {
    if (log.date != date) continue;
    // Ignore retired temporary learning, including rows that only carry the
    // conversion pointer: neither a display item nor an actual minute may come
    // from historical ad-hoc data.
    if (log.relation == TimeLogRelation.adHoc || log.adHocId != null) continue;
    final taskId = log.taskId;
    final _DayItemBuilder owner;
    if (taskId != null) {
      owner = taskOwner(taskId);
    } else {
      final id = 'log:${log.id}';
      owner = builders.putIfAbsent(
        id,
        () => _DayItemBuilder(id: id, title: '历史学习记录', tagNames: const []),
      );
    }
    owner.actual += log.minutes;
    actualMinutes += log.minutes;
    // Match dayExecutionSummary: a task-less log is never attributed to a plan,
    // even when the timer recorded it as extra learning.
    final kind = log.relation == TimeLogRelation.extra && log.taskId != null
        ? (owner.hasPlan
              ? CalendarEffortKind.extra
              : CalendarEffortKind.unscheduled)
        : CalendarEffortKind.legacyUnknown;
    owner.byKind[kind] = (owner.byKind[kind] ?? 0) + log.minutes;
  }

  for (final entry in summary.scheduledByTask.entries) {
    final owner = taskOwner(entry.key);
    // Both explicit original learning and reliably inferred old minutes were
    // initially counted in the unknown bucket; move them once. The cap keeps
    // "efforts sum == actualMinutes" even when the summary also inferred from a
    // historical row that is ignored above.
    final unknown = owner.byKind[CalendarEffortKind.legacyUnknown] ?? 0;
    final moved = math.min(entry.value, math.max(0, unknown));
    owner.scheduled += moved;
    owner.byKind[CalendarEffortKind.legacyUnknown] = unknown - moved;
    owner.byKind[CalendarEffortKind.scheduled] =
        (owner.byKind[CalendarEffortKind.scheduled] ?? 0) + moved;
  }

  final ordered = builders.values.toList()
    ..sort((a, b) {
      if (a.hasPlan != b.hasPlan) return a.hasPlan ? -1 : 1;
      if (a.hasPlan) {
        final byBlock = a.firstBlock.compareTo(b.firstBlock);
        if (byBlock != 0) return byBlock;
      }
      return a.id.compareTo(b.id);
    });
  final items = [for (final builder in ordered) builder.build()];
  final itemMaximum = items.fold<int>(
    0,
    (value, item) =>
        math.max(value, math.max(item.plannedMinutes, item.actualMinutes)),
  );
  return CalendarDayData(
    date: date,
    items: List.unmodifiable(items),
    plannedMinutes: summary.planned,
    actualMinutes: actualMinutes,
    scaleMinutes: math.max(1, itemMaximum).toDouble(),
    riverScaleMinutes: math
        .max(1, math.max(summary.planned, actualMinutes))
        .toDouble(),
  );
}

class _DayItemBuilder {
  _DayItemBuilder({
    required this.id,
    required this.title,
    required this.tagNames,
  });

  final String id;
  final String title;
  final List<String> tagNames;
  int planned = 0;
  int actual = 0;
  int scheduled = 0;
  int firstBlock = 1 << 30;
  final byKind = <CalendarEffortKind, int>{};

  bool get hasPlan => firstBlock != 1 << 30;

  CalendarDayItem build() => CalendarDayItem(
    id: id,
    title: title,
    tagNames: List.unmodifiable(tagNames),
    plannedMinutes: planned,
    actualMinutes: actual,
    scheduledMinutes: scheduled,
    efforts: List.unmodifiable([
      for (final kind in CalendarEffortKind.values)
        if ((byKind[kind] ?? 0) > 0)
          CalendarDayEffort(kind: kind, minutes: byKind[kind]!),
    ]),
  );
}
