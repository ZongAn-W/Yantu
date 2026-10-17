import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/application/study_timer.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/scheduler/planner_scheduler.dart' as scheduler;
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/domain/study_day.dart' show DayStats;
import '../../planner/presentation/cycle_dialog.dart';
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';
import '../../planner/presentation/planning_details.dart';
import '../../planner/presentation/planning_feedback_view.dart';
import '../../planner/presentation/task_study_timer.dart';
import 'task_time_pie.dart';

/// Web `/` — today's plan, recorded time, completion and the replan entry point.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(studyTimerProvider.select((_) => shanghaiToday()));
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final stats = day_ops.dayStats(data, date);
        final groups = day_ops.groupDailyBlocks(
          data.blocks.where((block) => block.date == date),
          data.tasks,
        );
        final pending = [
          for (final group in groups)
            if (day_ops.taskDayMinutes(data, group.first.taskId, date) <
                group.fold<int>(0, (sum, block) => sum + block.durationMinutes))
              group,
        ];
        final cycle = planCycleState(data.profile, date);
        final restDay =
            scheduler.availableDailyMinutes(
              data.profile,
              data.fixedEvents,
              date,
            ) <=
            0;
        final emptyPlan = data.subjects.isEmpty && data.tasks.isEmpty;
        return PlannerPage(
          title: '今天，专注眼前的一步',
          subtitle: dashboardGoalLine(data.profile, date),
          actions: [
            AsyncActionButton(
              label: '结束今天',
              icon: Icons.check,
              filled: false,
              onPressed: () => DailyReviewDialog.show(context, date: date),
            ),
            AsyncActionButton(
              label: '智能重排',
              icon: Icons.refresh,
              enabled: snapshot.editable,
              onPressed: () => ReplanDialog.show(context),
            ),
          ],
          children: [
            if (data.planning != null) ...[
              PlanningRouteView(planning: data.planning, compact: true),
              if (data.planning?['rolling'] == true &&
                  cycle != PlanCycleState.ended)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: snapshot.editable
                        ? () => ContinueCycleDialog.showRolling(context)
                        : null,
                    icon: const Icon(Icons.event_note_outlined, size: 18),
                    label: const Text('细化近期安排'),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (emptyPlan) ...[
              const PlannerNotice(
                '还没有学习计划：先完成学习目标访谈，确认课程和学习事项。',
                tone: PlannerNoticeTone.info,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => context.go('/interview'),
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('开始学习目标访谈'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (cycle != PlanCycleState.running) ...[
              PlannerNotice(
                cycle == PlanCycleState.ended
                    ? '本次规划周期已经结束。这不代表长期目标完成或失败，可以继续安排下一周期。'
                    : '本次规划周期即将结束，可以提前安排下一周期。',
                tone: PlannerNoticeTone.info,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: snapshot.editable
                      ? () => ContinueCycleDialog.show(context)
                      : null,
                  icon: const Icon(Icons.event_repeat, size: 18),
                  label: const Text('继续安排下一周期'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (restDay) ...[
              const PlannerNotice(
                '今天是休息日：可用学习时间为 0，不生成学习安排，也不计入执行失败。',
                tone: PlannerNoticeTone.info,
              ),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1000;
                final main = _TodayStudyPanel(
                  data: data,
                  date: date,
                  stats: stats,
                  groups: groups,
                  pending: pending,
                  editable: snapshot.editable,
                );
                final side = TaskTimePiePanel(data: data, date: date);
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [main, const SizedBox(height: 16), side],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: main),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: side),
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

class _TodayStudyPanel extends StatelessWidget {
  const _TodayStudyPanel({
    required this.data,
    required this.date,
    required this.stats,
    required this.groups,
    required this.pending,
    required this.editable,
  });

  final PlannerData data;
  final String date;
  final DayStats stats;
  final List<List<ScheduleBlock>> groups;
  final List<List<ScheduleBlock>> pending;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final taskById = {for (final task in data.tasks) task.id: task};
    return PlannerPanel(
      title: '今日学习 ${groups.length - pending.length}/${groups.length} 项达标',
      trailing: TextButton.icon(
        onPressed: () => context.go('/calendar'),
        icon: const Icon(Icons.arrow_forward, size: 16),
        label: const Text('调整计划'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 20,
            runSpacing: 4,
            children: [
              _SummaryItem(
                icon: Icons.schedule,
                label: '计划',
                value: duration(stats.planned),
              ),
              _SummaryItem(
                icon: Icons.check_circle_outline,
                label: '已学',
                value: duration(stats.actual),
                tone: PlannerColors.green,
                valueKey: const Key('today-completed-minutes'),
              ),
              _SummaryItem(
                icon: Icons.hourglass_empty,
                label: '剩余',
                value: duration(stats.remaining),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty)
            PlannerEmpty(
              icon: Icons.list_alt_outlined,
              message: '今天还没有学习事项',
              action: TextButton.icon(
                onPressed: () => context.go('/tasks'),
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('添加事项并安排到今天'),
              ),
            ),
          for (final subject in data.subjects)
            if (groups.any(
              (group) => taskById[group.first.taskId]?.subjectId == subject.id,
            )) ...[
              Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    subject.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
              for (final group in groups)
                if (taskById[group.first.taskId]?.subjectId == subject.id)
                  _TaskDayRow(
                    key: ValueKey('${group.first.taskId}:$date'),
                    blocks: group,
                    editable: editable,
                    onMove: () => MoveTaskDayDialog.show(context, group),
                  ),
            ],
          const Divider(height: 24),
          Text(
            '今天可安排 '
            '${duration(scheduler.availableDailyMinutes(data.profile, data.fixedEvents, date))}，'
            '已扣除 ${duration(data.profile.bufferMinutes)} 机动时间和固定安排。',
            style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
    this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? tone;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: tone ?? PlannerColors.muted),
      const SizedBox(width: 6),
      Text('$label ', style: TextStyle(color: tone)),
      Text(
        value,
        key: valueKey,
        style: tabularFigures.copyWith(
          fontWeight: FontWeight.w700,
          color: tone,
        ),
      ),
    ],
  );
}

/// One task's live clock, timer action and expandable study details.
class _TaskDayRow extends ConsumerStatefulWidget {
  const _TaskDayRow({
    required this.blocks,
    required this.editable,
    required this.onMove,
    super.key,
  });

  final List<ScheduleBlock> blocks;
  final bool editable;
  final VoidCallback onMove;

  @override
  ConsumerState<_TaskDayRow> createState() => _TaskDayRowState();
}

class _TaskDayRowState extends ConsumerState<_TaskDayRow> {
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final blocks = widget.blocks;
    final editable = widget.editable;
    final data = ref.watch(plannerSessionProvider).data;
    final date = blocks.first.date;
    final task = data.tasks
        .where((item) => item.id == blocks.first.taskId)
        .firstOrNull;
    if (task == null) return const SizedBox.shrink();
    final planned = blocks.fold<int>(
      0,
      (sum, block) => sum + block.durationMinutes,
    );
    final actual = day_ops.taskDayMinutes(data, task.id, date);
    final course = data.subjects
        .where((subject) => subject.id == task.subjectId)
        .firstOrNull;
    final color = subjectColor(task.subjectId, course?.color);
    final advice = blocks
        .where((block) => (block.adviceText ?? '').isNotEmpty)
        .map((block) => block.adviceText!)
        .firstOrNull;
    final timer = ref.watch(studyTimerProvider);
    final movable =
        editable &&
        task.status != TaskStatus.archived &&
        task.status != TaskStatus.completed &&
        !task.isFixed &&
        actual == 0 &&
        timer.elapsedFor(task.id, date) == Duration.zero &&
        !timer.isRunning(task.id, date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PlannerColors.surface,
          border: Border.all(color: PlannerColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaskStudyTimer(
              heading: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 4,
                children: [
                  Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (task.isFixed)
                    const Tooltip(
                      message: '固定事项',
                      child: Icon(Icons.lock_outline, size: 14),
                    ),
                ],
              ),
              taskId: task.id,
              date: date,
              plannedMinutes: planned,
              color: color,
              canDiscard: editable,
              canStart:
                  editable &&
                  task.status != TaskStatus.archived &&
                  task.status != TaskStatus.completed,
              secondaryAction: movable
                  ? IconButton(
                      onPressed: widget.onMove,
                      tooltip: '调整日期',
                      icon: const Icon(Icons.event_outlined, size: 19),
                    )
                  : null,
              detailsAction: IconButton(
                tooltip: _detailsExpanded ? '收起学习详情' : '展开学习详情',
                icon: Icon(
                  _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _detailsExpanded = !_detailsExpanded),
              ),
            ),
            if (_detailsExpanded) ...[
              const Divider(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (advice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: PlannerColors.blue,
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text('今日建议：$advice')),
                        ],
                      ),
                    ),
                  if ((task.description ?? '').isNotEmpty)
                    Text(
                      task.description!,
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  WorkloadDetails(planning: task.planning),
                  PlanningFeedbackView(
                    task: task,
                    data: data,
                    editable: editable,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${task.deadlineKind == ItemDateKind.planEnd ? '本期安排边界' : '事项截止'} ${task.deadline}',
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
