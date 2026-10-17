import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/application/study_timer.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';
import '../../planner/presentation/task_study_timer.dart';

/// Web `/calendar` — day/week plan, fixed events, capacity and conflict feedback.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  String _date = shanghaiToday();
  bool _week = true;
  String? _draggingBlockId;
  String? _notice;
  PlannerNoticeTone _noticeTone = PlannerNoticeTone.info;

  List<String> get _days => _week
      ? [for (var index = 0; index < 7; index++) addDate(_date, index)]
      : [_date];

  Future<void> _move(List<ScheduleBlock> blocks, String targetDate) async {
    if (blocks.first.date == targetDate) return;
    try {
      await ref.read(plannerSessionProvider).moveTaskDay(blocks, targetDate);
      if (!mounted) return;
      setState(() {
        _notice = '事项已移动到 $targetDate';
        _noticeTone = PlannerNoticeTone.success;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = error is StateError ? error.message : '$error';
        _noticeTone = PlannerNoticeTone.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        return PlannerPage(
          title: '学习日历',
          subtitle: '按事项安排每日时长，查看实际学习记录。',
          actions: [
            AsyncActionButton(
              label: '创建固定事件',
              icon: Icons.add,
              enabled: snapshot.editable,
              onPressed: () => FixedEventDialog.show(context, date: _date),
            ),
          ],
          children: [
            PlannerPanel(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconButton(
                        tooltip: '上一时段',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(
                          () => _date = addDate(_date, _week ? -7 : -1),
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: DateField(
                          label: '日历起始日期',
                          value: _date,
                          onChanged: (value) => setState(() => _date = value),
                        ),
                      ),
                      IconButton(
                        tooltip: '下一时段',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(
                          () => _date = addDate(_date, _week ? 7 : 1),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            setState(() => _date = shanghaiToday()),
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
                    onSelectionChanged: (values) =>
                        setState(() => _week = values.single),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_notice != null) ...[
              PlannerNotice(_notice!, tone: _noticeTone),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = _week && constraints.maxWidth >= 1100
                    ? 4
                    : _week && constraints.maxWidth >= 760
                    ? 2
                    : 1;
                final itemWidth =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final day in _days)
                      SizedBox(
                        width: itemWidth,
                        child: _CalendarDayColumn(
                          date: day,
                          data: data,
                          editable: snapshot.editable,
                          draggingBlockId: _draggingBlockId,
                          onDragStart: (blockId) =>
                              setState(() => _draggingBlockId = blockId),
                          onDropBlocks: (blocks) => _move(blocks, day),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _CalendarDayColumn extends ConsumerWidget {
  const _CalendarDayColumn({
    required this.date,
    required this.data,
    required this.editable,
    required this.draggingBlockId,
    required this.onDragStart,
    required this.onDropBlocks,
  });

  final String date;
  final PlannerData data;
  final bool editable;
  final String? draggingBlockId;
  final ValueChanged<String> onDragStart;
  final Future<void> Function(List<ScheduleBlock> blocks) onDropBlocks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = day_ops.calendarDay(data, date);
    final groups = day_ops.groupDailyBlocks(
      data.blocks.where((block) => block.date == date),
      data.tasks,
    );
    final events = day_ops.fixedEventsOn(data, date);
    final isToday = date == shanghaiToday();
    final taskById = {for (final task in data.tasks) task.id: task};
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => editable && details.data.isNotEmpty,
      onAcceptWithDetails: (details) {
        final target = data.blocks
            .where((block) => block.id == details.data)
            .firstOrNull;
        if (target == null) return;
        final group = [
          for (final block in data.blocks)
            if (block.date == target.date && block.taskId == target.taskId)
              block,
        ];
        onDropBlocks(group);
      },
      builder: (context, candidate, rejected) => PlannerPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  weekdayLabel(date),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text(
                  date.substring(5),
                  style: tabularFigures.copyWith(
                    color: isToday ? PlannerColors.blue : PlannerColors.muted,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                Text(
                  '计划 ${duration(day.planned)}',
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            if (day.capacityWarning != null) ...[
              const SizedBox(height: 8),
              PlannerNotice(
                day.capacityWarning!,
                tone: PlannerNoticeTone.warning,
              ),
            ],
            const SizedBox(height: 8),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '尚未安排学习事项',
                  style: TextStyle(color: PlannerColors.muted, fontSize: 12),
                ),
              ),
            for (final group in groups)
              _CalendarTaskRow(
                blocks: group,
                task: taskById[group.first.taskId],
                data: data,
                editable: editable,
                isDragging: draggingBlockId == group.first.id,
                onDragStart: () => onDragStart(group.first.id),
              ),
            if (events.isNotEmpty) ...[
              const Divider(height: 20),
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_outline, size: 13),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${clockTime(event.startMinute)} · ${event.title} · '
                          '${duration(event.durationMinutes)}',
                          style: const TextStyle(
                            color: PlannerColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: '删除固定事件',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close, size: 14),
                          onPressed: () async {
                            final confirmed = await confirmAction(
                              context,
                              title: '删除固定事件',
                              message: '删除“${event.title}”？该时段会重新计入每日可用容量。',
                              confirmLabel: '删除',
                              destructive: true,
                            );
                            if (!confirmed || !context.mounted) return;
                            await ref
                                .read(plannerSessionProvider)
                                .deleteFixedEvent(event.id);
                          },
                        ),
                    ],
                  ),
                ),
              Text(
                '固定事件占 ${duration(day.fixedMinutes)}，当天可用 ${duration(day.capacity)}',
                style: const TextStyle(
                  color: PlannerColors.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CalendarTaskRow extends ConsumerWidget {
  const _CalendarTaskRow({
    required this.blocks,
    required this.task,
    required this.data,
    required this.editable,
    required this.isDragging,
    required this.onDragStart,
  });

  final List<ScheduleBlock> blocks;
  final Task? task;
  final PlannerData data;
  final bool editable;
  final bool isDragging;
  final VoidCallback onDragStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = task;
    if (item == null) return const SizedBox.shrink();
    final date = blocks.first.date;
    final planned = blocks.fold<int>(
      0,
      (sum, block) => sum + block.durationMinutes,
    );
    final actual = day_ops.taskDayMinutes(data, item.id, date);
    final timer = ref.watch(studyTimerProvider);
    final completed =
        item.status == TaskStatus.completed ||
        blocks.every((block) => block.status == BlockStatus.completed);
    final color = subjectColor(
      item.subjectId,
      data.subjects
          .where((subject) => subject.id == item.subjectId)
          .firstOrNull
          ?.color,
    );
    final movable =
        editable &&
        !timer.isRunning(item.id, date) &&
        timer.elapsedFor(item.id, date) == Duration.zero &&
        item.status != TaskStatus.archived &&
        actual == 0 &&
        !item.isFixed &&
        blocks.every(
          (block) => !block.isFixed && block.status != BlockStatus.completed,
        );
    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: completed ? const Color(0xfff4f8f6) : PlannerColors.surface,
        border: Border.all(
          color: isDragging ? PlannerColors.blue : PlannerColors.border,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskStudyTimer(
            heading: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${subjectNameOf(data, item.subjectId)} · ${item.title}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (item.isFixed)
                  const Tooltip(
                    message: '固定事项',
                    child: Icon(Icons.lock_outline, size: 13),
                  ),
              ],
            ),
            taskId: item.id,
            date: date,
            plannedMinutes: planned,
            color: color,
            canDiscard: editable,
            canStart:
                editable &&
                date == shanghaiToday() &&
                item.status != TaskStatus.archived &&
                item.status != TaskStatus.completed,
            secondaryAction: movable
                ? IconButton(
                    tooltip: '调整日期',
                    onPressed: () => MoveTaskDayDialog.show(context, blocks),
                    icon: const Icon(Icons.event_outlined, size: 15),
                  )
                : null,
          ),
        ],
      ),
    );
    if (!movable) return card;
    return LongPressDraggable<String>(
      data: blocks.first.id,
      onDragStarted: onDragStart,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text('移动 ${item.title}'),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: card,
    );
  }
}
