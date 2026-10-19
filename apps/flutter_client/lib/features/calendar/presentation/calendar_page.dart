import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/domain/plan_cycle.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/presentation/planner_dialogs.dart'
    show DateField, subjectNameOf;
import '../../planner/presentation/planner_page_state.dart';

/// Read-only calendar for scheduled study and completed work.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  String _startDate = shanghaiToday();
  String _selectedDate = shanghaiToday();
  bool _week = true;
  bool _showAllCompleted = false;

  List<String> get _visibleDays => _week
      ? [for (var index = 0; index < 7; index++) addDate(_startDate, index)]
      : [_selectedDate];

  void _changePeriod(int amount) {
    setState(() {
      _startDate = addDate(_startDate, amount * (_week ? 7 : 1));
      _selectedDate = addDate(_selectedDate, amount * (_week ? 7 : 1));
    });
  }

  void _chooseDate(String value) {
    setState(() {
      _startDate = value;
      _selectedDate = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final today = shanghaiToday();
        final cycleStart = data.profile.resolvedPlanStart(today);
        final cycleEnd = data.profile.resolvedPlanEnd(today);
        final days = _visibleDays;
        final completed = _completedItems(data, cycleStart, cycleEnd);

        return PlannerPage(
          children: [
            PlannerPanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 2,
                    children: [
                      IconButton(
                        key: const ValueKey('calendar-previous-period'),
                        tooltip: '上一时段',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _changePeriod(-1),
                      ),
                      SizedBox(
                        width: 160,
                        child: DateField(
                          label: _week ? '查看起始日期' : '查看日期',
                          value: _week ? _startDate : _selectedDate,
                          onChanged: _chooseDate,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('calendar-next-period'),
                        tooltip: '下一时段',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => _changePeriod(1),
                      ),
                      TextButton(
                        key: const ValueKey('calendar-today'),
                        onPressed: () => _chooseDate(today),
                        child: const Text('今天'),
                      ),
                    ],
                  ),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('日视图')),
                      ButtonSegment(value: true, label: Text('周视图')),
                    ],
                    selected: {_week},
                    onSelectionChanged: (values) {
                      setState(() {
                        _week = values.single;
                        if (_week) _startDate = _selectedDate;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _CycleLine(
              data: data,
              start: cycleStart,
              end: cycleEnd,
              date: _selectedDate,
              onJump: () => _chooseDate(cycleEnd),
            ),
            const SizedBox(height: 8),
            _WeekRiver(
              key: const ValueKey('calendar-week-river'),
              data: data,
              dates: days,
              selectedDate: _selectedDate,
              onSelect: (date) => setState(() => _selectedDate = date),
              title: _week ? '这一周' : '当天',
            ),
            const SizedBox(height: 12),
            _SelectedDayDetails(data: data, date: _selectedDate),
            const SizedBox(height: 12),
            _CompletedSection(
              data: data,
              cycleStart: cycleStart,
              cycleEnd: cycleEnd,
              completed: completed,
              showAll: _showAllCompleted,
              onToggle: () =>
                  setState(() => _showAllCompleted = !_showAllCompleted),
            ),
          ],
        );
      },
    );
  }
}

class _CycleLine extends StatelessWidget {
  const _CycleLine({
    required this.data,
    required this.start,
    required this.end,
    required this.date,
    required this.onJump,
  });

  final PlannerData data;
  final String start;
  final String end;
  final String date;
  final VoidCallback onJump;

  @override
  Widget build(BuildContext context) {
    final full = isFullPeriodPlan(data.planning);
    final detailEnd = data.planning?['detailed_until'];
    final coverage = full
        ? '全周期安排'
        : detailEnd is String && detailEnd.isNotEmpty
        ? '已细化至 $detailEnd'
        : '滚动计划';
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 0,
      children: [
        Text(
          '本周期 $start 至 $end · $coverage',
          style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
        ),
        if (date != end)
          TextButton(
            key: const ValueKey('calendar-jump-cycle-end'),
            onPressed: onJump,
            child: const Text('周期末'),
          ),
      ],
    );
  }
}

class _WeekRiver extends StatelessWidget {
  const _WeekRiver({
    required this.data,
    required this.dates,
    required this.selectedDate,
    required this.onSelect,
    required this.title,
    super.key,
  });

  final PlannerData data;
  final List<String> dates;
  final String selectedDate;
  final ValueChanged<String> onSelect;
  final String title;

  @override
  Widget build(BuildContext context) {
    final days = [for (final date in dates) day_ops.calendarDay(data, date)];
    final planTotal = days.fold<int>(0, (sum, day) => sum + day.planned);
    final actualTotal = days.fold<int>(0, (sum, day) => sum + day.actual);
    final scale = math
        .max(
          1,
          days.fold<int>(0, (maximum, day) => math.max(maximum, day.capacity)),
        )
        .toInt();
    return PlannerPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      title: title,
      trailing: Wrap(
        spacing: 12,
        children: [
          Text(
            '计划 ${duration(planTotal)}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '实学 ${duration(actualTotal)}',
            style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final date in dates)
                Expanded(
                  child: _RiverDay(
                    data: data,
                    date: date,
                    selected: date == selectedDate,
                    scaleMinutes: scale,
                    onTap: () => onSelect(date),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              _LegendMark(color: PlannerColors.border),
              SizedBox(width: 5),
              Text(
                '计划',
                style: TextStyle(color: PlannerColors.muted, fontSize: 11),
              ),
              SizedBox(width: 14),
              _LegendMark(color: PlannerColors.blue),
              SizedBox(width: 5),
              Text(
                '原定已学',
                style: TextStyle(color: PlannerColors.muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiverDay extends StatelessWidget {
  const _RiverDay({
    required this.data,
    required this.date,
    required this.selected,
    required this.scaleMinutes,
    required this.onTap,
  });

  final PlannerData data;
  final String date;
  final bool selected;
  final int scaleMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final day = day_ops.calendarDay(data, date);
    final segments = _courseSegments(data, date);
    final label =
        '${weekdayLabel(date)} $date，计划 ${duration(day.planned)}，'
        '可用 ${duration(day.capacity)}，实学 ${duration(day.actual)}'
        '${day.capacityWarning == null ? '' : '，${day.capacityWarning}'}';
    return Semantics(
      key: ValueKey('calendar-day-$date'),
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? PlannerColors.blue : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(6),
            color: selected ? const Color(0x12275e91) : Colors.transparent,
          ),
          child: Column(
            children: [
              Text(
                weekdayLabel(date),
                maxLines: 1,
                style: TextStyle(
                  color: selected ? PlannerColors.blue : PlannerColors.muted,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              Text(
                date.substring(8),
                style: tabularFigures.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: CustomPaint(
                  size: const Size(26, 50),
                  painter: _RiverPainter(
                    segments: segments,
                    scaleMinutes: scaleMinutes,
                    capacity: day.capacity,
                    planned: day.planned,
                  ),
                ),
              ),
              if (day.capacityWarning != null)
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: PlannerColors.orange,
                    size: 13,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiverSegment {
  const _RiverSegment({
    required this.color,
    required this.planned,
    required this.actual,
  });

  final Color color;
  final int planned;
  final int actual;
}

List<_RiverSegment> _courseSegments(PlannerData data, String date) {
  final tasks = {for (final task in data.tasks) task.id: task};
  final blocks = data.blocks
      .where((block) => block.date == date && tasks[block.taskId] != null)
      .toList();
  final bySubject = <String, List<ScheduleBlock>>{};
  final order = <String>[];
  for (final block in blocks) {
    final task = tasks[block.taskId]!;
    if (task.status == TaskStatus.archived) continue;
    final list = bySubject[task.subjectId];
    if (list == null) {
      bySubject[task.subjectId] = [block];
      order.add(task.subjectId);
    } else {
      list.add(block);
    }
  }
  return [
    for (final subjectId in order)
      () {
        final subjectBlocks = bySubject[subjectId]!;
        final plannedByTask = <String, int>{};
        for (final block in subjectBlocks) {
          plannedByTask.update(
            block.taskId,
            (minutes) => minutes + block.durationMinutes,
            ifAbsent: () => block.durationMinutes,
          );
        }
        final planned = plannedByTask.values.fold<int>(0, (a, b) => a + b);
        final actual = plannedByTask.entries.fold<int>(0, (sum, entry) {
          return sum +
              math.min(
                entry.value,
                day_ops.scheduledMinutesForTaskDay(data, entry.key, date),
              );
        });
        final subject = data.subjects
            .where((item) => item.id == subjectId)
            .firstOrNull;
        return _RiverSegment(
          color: subjectColor(subjectId, subject?.color),
          planned: planned,
          actual: actual,
        );
      }(),
  ];
}

class _RiverPainter extends CustomPainter {
  const _RiverPainter({
    required this.segments,
    required this.scaleMinutes,
    required this.capacity,
    required this.planned,
  });

  final List<_RiverSegment> segments;
  final int scaleMinutes;
  final int capacity;
  final int planned;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final track = RRect.fromRectAndRadius(bounds, const Radius.circular(3));
    canvas.drawRRect(
      track,
      Paint()..color = PlannerColors.border.withValues(alpha: 0.45),
    );
    canvas.save();
    canvas.clipRRect(track);
    var bottom = size.height;
    for (final segment in segments) {
      final segmentHeight = segment.planned / scaleMinutes * size.height;
      final top = bottom - segmentHeight;
      final plannedRect = Rect.fromLTRB(0, top, size.width, bottom);
      canvas.drawRect(
        plannedRect,
        Paint()..color = Color.lerp(segment.color, Colors.white, 0.78)!,
      );
      final actualHeight =
          segmentHeight *
          (segment.actual / segment.planned).clamp(0.0, 1.0).toDouble();
      if (actualHeight > 0) {
        canvas.drawRect(
          Rect.fromLTRB(0, bottom - actualHeight, size.width, bottom),
          Paint()..color = Color.lerp(segment.color, PlannerColors.text, 0.2)!,
        );
      }
      bottom = top;
    }
    final capacityY =
        size.height -
        (capacity / scaleMinutes).clamp(0.0, 1.0).toDouble() * size.height;
    canvas.drawLine(
      Offset(0, capacityY),
      Offset(size.width, capacityY),
      Paint()
        ..color = planned > capacity ? PlannerColors.orange : Colors.white
        ..strokeWidth = planned > capacity ? 2 : 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RiverPainter oldDelegate) => true;
}

class _LegendMark extends StatelessWidget {
  const _LegendMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _SelectedDayDetails extends StatelessWidget {
  const _SelectedDayDetails({required this.data, required this.date});

  final PlannerData data;
  final String date;

  @override
  Widget build(BuildContext context) {
    final day = day_ops.calendarDay(data, date);
    final tasks = {for (final task in data.tasks) task.id: task};
    final blocks = data.blocks
        .where(
          (block) =>
              block.date == date &&
              tasks[block.taskId]?.status != TaskStatus.archived,
        )
        .toList();
    final groups = day_ops.groupDailyBlocks(blocks, data.tasks);
    return PlannerPanel(
      key: const ValueKey('calendar-selected-day-details'),
      title: fullDateLabel(date),
      trailing: Text(
        '计划 ${duration(day.planned)} · 实学 ${duration(day.actual)}',
        style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (day.capacityWarning != null) ...[
            PlannerNotice(
              day.capacityWarning!,
              tone: PlannerNoticeTone.warning,
            ),
            const SizedBox(height: 8),
          ],
          if (data.profile.planningMode == PlanningMode.timed)
            _TimedTrack(data: data, date: date, blocks: blocks)
          else
            _DailyFlow(data: data, date: date, groups: groups),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _emptyDayReason(data, date),
                style: const TextStyle(color: PlannerColors.muted),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '当天可用 ${duration(day.capacity)}',
            style: const TextStyle(color: PlannerColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DailyFlow extends StatelessWidget {
  const _DailyFlow({
    required this.data,
    required this.date,
    required this.groups,
  });

  final PlannerData data;
  final String date;
  final List<List<ScheduleBlock>> groups;

  @override
  Widget build(BuildContext context) {
    final tasks = {for (final task in data.tasks) task.id: task};
    return Column(
      children: [
        for (final group in groups)
          _TaskFlowRow(
            data: data,
            task: tasks[group.first.taskId]!,
            blocks: group,
            date: date,
          ),
      ],
    );
  }
}

class _TaskFlowRow extends StatelessWidget {
  const _TaskFlowRow({
    required this.data,
    required this.task,
    required this.blocks,
    required this.date,
  });

  final PlannerData data;
  final Task task;
  final List<ScheduleBlock> blocks;
  final String date;

  @override
  Widget build(BuildContext context) {
    final planned = blocks.fold<int>(
      0,
      (sum, block) => sum + block.durationMinutes,
    );
    final actual = day_ops.taskDayMinutes(data, task.id, date);
    final subject = data.subjects
        .where((item) => item.id == task.subjectId)
        .firstOrNull;
    final color = subjectColor(task.subjectId, subject?.color);
    final completed =
        task.status == TaskStatus.completed ||
        blocks.every((block) => block.status == BlockStatus.completed);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 38,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (completed)
                      const Tooltip(
                        message: '已完成',
                        child: Icon(
                          Icons.check_circle,
                          size: 17,
                          color: PlannerColors.green,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${subjectNameOf(data, task.subjectId)} · 计划 ${duration(planned)} · 实学 ${duration(actual)}',
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 5),
                _ProgressStrip(
                  color: color,
                  ratio: planned == 0 ? 0 : actual / planned,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.color, required this.ratio});

  final Color color;
  final double ratio;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: PlannerColors.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: constraints.maxWidth * ratio.clamp(0.0, 1.0).toDouble(),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimedTrack extends StatelessWidget {
  const _TimedTrack({
    required this.data,
    required this.date,
    required this.blocks,
  });

  final PlannerData data;
  final String date;
  final List<ScheduleBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final start = data.profile.studyStartMinute;
    final end = math.max(start + 1, data.profile.studyEndMinute).toInt();
    final tasks = {for (final task in data.tasks) task.id: task};
    final actualByTask = day_ops.scheduledMinutesByTask(data, date);
    final progressByBlock = <String, int>{};
    final blocksByTask = <String, List<ScheduleBlock>>{};
    for (final block in blocks) {
      blocksByTask.putIfAbsent(block.taskId, () => []).add(block);
    }
    for (final entry in blocksByTask.entries) {
      final sorted = [...entry.value]
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
      var remaining = actualByTask[entry.key] ?? 0;
      for (final block in sorted) {
        final actual = math.min(remaining, block.durationMinutes);
        progressByBlock[block.id] = actual;
        remaining -= actual;
      }
    }
    final entries = <_TimelineEntry>[
      for (final block in blocks)
        if (tasks[block.taskId] case final task?)
          _TimelineEntry(
            id: block.id,
            title: task.title,
            detail:
                '${clockTime(block.startMinute)} · ${duration(block.durationMinutes)} · 实学 ${duration(day_ops.taskDayMinutes(data, task.id, date))}',
            startMinute: block.startMinute,
            durationMinutes: block.durationMinutes,
            color: subjectColor(
              task.subjectId,
              data.subjects
                  .where((subject) => subject.id == task.subjectId)
                  .firstOrNull
                  ?.color,
            ),
            actualMinutes: progressByBlock[block.id] ?? 0,
          ),
    ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    return Column(
      children: [
        _TimelineAxis(start: start, end: end),
        for (final entry in entries)
          _TimelineRow(entry: entry, start: start, end: end),
      ],
    );
  }
}

class _TimelineEntry {
  const _TimelineEntry({
    required this.id,
    required this.title,
    required this.detail,
    required this.startMinute,
    required this.durationMinutes,
    required this.color,
    required this.actualMinutes,
  });

  final String id;
  final String title;
  final String detail;
  final int startMinute;
  final int durationMinutes;
  final Color color;
  final int actualMinutes;
}

class _TimelineAxis extends StatelessWidget {
  const _TimelineAxis({required this.start, required this.end});

  final int start;
  final int end;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(width: 116, child: Text('事项 / 事件')),
      Expanded(
        child: SizedBox(
          height: 27,
          child: CustomPaint(
            painter: _AxisPainter(start: start, end: end),
          ),
        ),
      ),
    ],
  );
}

class _AxisPainter extends CustomPainter {
  const _AxisPainter({required this.start, required this.end});

  final int start;
  final int end;

  @override
  void paint(Canvas canvas, Size size) {
    final range = math.max(1, end - start);
    final lineY = 11.0;
    final paint = Paint()
      ..color = PlannerColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, lineY), Offset(size.width, lineY), paint);
    for (final fraction in const [0.0, 0.25, 0.5, 0.75, 1.0]) {
      final x = size.width * fraction;
      canvas.drawLine(Offset(x, lineY - 3), Offset(x, lineY + 3), paint);
      final label = clockTime(start + (range * fraction).round());
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: PlannerColors.muted, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 42);
      final left = (x - text.width / 2).clamp(0.0, size.width - text.width);
      text.paint(canvas, Offset(left, 15));
    }
  }

  @override
  bool shouldRepaint(covariant _AxisPainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.start,
    required this.end,
  });

  final _TimelineEntry entry;
  final int start;
  final int end;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(
          width: 116,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  entry.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 26,
            child: CustomPaint(
              painter: _TimelinePainter(entry: entry, start: start, end: end),
            ),
          ),
        ),
      ],
    ),
  );
}

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.entry,
    required this.start,
    required this.end,
  });

  final _TimelineEntry entry;
  final int start;
  final int end;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 8, size.width, 10),
      const Radius.circular(4),
    );
    canvas.drawRRect(
      track,
      Paint()..color = PlannerColors.border.withValues(alpha: 0.5),
    );
    final range = math.max(1, end - start);
    final left = ((entry.startMinute - start) / range * size.width)
        .clamp(0.0, size.width)
        .toDouble();
    final rawWidth = entry.durationMinutes / range * size.width;
    final right = (left + math.max(3.0, rawWidth))
        .clamp(left, size.width)
        .toDouble();
    if (right <= left) return;
    final rect = Rect.fromLTRB(left, 5, right, 21);
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(
      rounded,
      Paint()..color = Color.lerp(entry.color, Colors.white, 0.68)!,
    );
    final fraction = (entry.actualMinutes / entry.durationMinutes).clamp(
      0.0,
      1.0,
    );
    if (fraction > 0) {
      final actual = RRect.fromRectAndCorners(
        Rect.fromLTRB(left, 5, left + rect.width * fraction, 21),
        topLeft: const Radius.circular(4),
        bottomLeft: const Radius.circular(4),
      );
      canvas.drawRRect(
        actual,
        Paint()..color = Color.lerp(entry.color, PlannerColors.text, 0.2)!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) => true;
}

class _CompletedItem {
  const _CompletedItem({
    required this.task,
    required this.cycleBlocks,
    required this.inCycle,
  });

  final Task task;
  final List<ScheduleBlock> cycleBlocks;
  final bool inCycle;
}

List<_CompletedItem> _completedItems(
  PlannerData data,
  String cycleStart,
  String cycleEnd,
) {
  final completedTasks =
      data.tasks.where((task) => task.status == TaskStatus.completed).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
  return [
    for (final task in completedTasks)
      () {
        final cycleBlocks = data.blocks
            .where(
              (block) =>
                  block.taskId == task.id &&
                  block.date.compareTo(cycleStart) >= 0 &&
                  block.date.compareTo(cycleEnd) <= 0,
            )
            .toList();
        return _CompletedItem(
          task: task,
          cycleBlocks: cycleBlocks,
          inCycle: cycleBlocks.isNotEmpty,
        );
      }(),
  ];
}

class _CompletedSection extends StatelessWidget {
  const _CompletedSection({
    required this.data,
    required this.cycleStart,
    required this.cycleEnd,
    required this.completed,
    required this.showAll,
    required this.onToggle,
  });

  final PlannerData data;
  final String cycleStart;
  final String cycleEnd;
  final List<_CompletedItem> completed;
  final bool showAll;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final current = completed.where((item) => item.inCycle).toList();
    final earlier = completed.where((item) => !item.inCycle).toList();
    return PlannerPanel(
      key: const ValueKey('calendar-completed-section'),
      title: '已完成',
      trailing: Text('${completed.length} 项'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '本周期曾安排 · $cycleStart 至 $cycleEnd',
            style: const TextStyle(color: PlannerColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          if (current.isEmpty)
            const Text(
              '本周期暂无已完成事项',
              style: TextStyle(color: PlannerColors.muted),
            )
          else
            for (final item in current)
              _CompletedRow(
                data: data,
                item: item,
                inCycle: true,
                cycleStart: cycleStart,
                cycleEnd: cycleEnd,
              ),
          if (earlier.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('calendar-show-all-completed'),
                onPressed: onToggle,
                icon: Icon(showAll ? Icons.expand_less : Icons.expand_more),
                label: Text(
                  showAll ? '收起其他已完成事项' : '查看全部已完成（${completed.length}）',
                ),
              ),
            ),
            if (showAll) ...[
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '此前或无本周期排程依据',
                  style: TextStyle(color: PlannerColors.muted, fontSize: 11),
                ),
              ),
              for (final item in earlier)
                _CompletedRow(
                  data: data,
                  item: item,
                  inCycle: false,
                  cycleStart: cycleStart,
                  cycleEnd: cycleEnd,
                ),
            ],
          ],
          if (completed.isEmpty)
            const Text(
              '还没有已完成事项',
              style: TextStyle(color: PlannerColors.muted),
            ),
        ],
      ),
    );
  }
}

class _CompletedRow extends StatelessWidget {
  const _CompletedRow({
    required this.data,
    required this.item,
    required this.inCycle,
    required this.cycleStart,
    required this.cycleEnd,
  });

  final PlannerData data;
  final _CompletedItem item;
  final bool inCycle;
  final String cycleStart;
  final String cycleEnd;

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    final subject = data.subjects
        .where((subject) => subject.id == task.subjectId)
        .firstOrNull;
    final planned = item.cycleBlocks.fold<int>(
      0,
      (sum, block) => sum + block.durationMinutes,
    );
    final actual = data.logs
        .where(
          (log) =>
              log.taskId == task.id &&
              (!inCycle ||
                  (log.date.compareTo(cycleStart) >= 0 &&
                      log.date.compareTo(cycleEnd) <= 0)),
        )
        .fold<int>(0, (sum, log) => sum + log.minutes);
    final detail = inCycle
        ? '本周期排程 ${duration(planned)} · 本周期实学 ${duration(actual)}'
        : '累计实学 ${duration(actual)} · 未归入本周期';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            size: 17,
            color: subjectColor(task.subjectId, subject?.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${subjectNameOf(data, task.subjectId)} · $detail',
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _emptyDayReason(PlannerData data, String date) {
  if (day_ops.calendarDay(data, date).capacity <= 0) {
    return '当天可用时间为零，未安排学习事项';
  }
  if (isFullPeriodPlan(data.planning)) {
    return '当天没有剩余工作量，未安排学习事项';
  }
  final until = data.planning?['detailed_until'];
  if (until is String && until.isNotEmpty && date.compareTo(until) > 0) {
    return '滚动计划尚未细化到该日期，可在今日页补全本周期安排';
  }
  return '尚未安排学习事项';
}
