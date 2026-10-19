import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/application/study_timer.dart';
import '../../planner/domain/capacity.dart' as capacity;
import '../../planner/domain/plan_cycle.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/domain/study_day.dart' show DayCapacityBreakdown;
import '../../planner/presentation/cycle_dialog.dart';
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';
import '../../planner/presentation/planning_details.dart';
import '../../planner/presentation/planning_feedback_view.dart';
import '../../planner/presentation/task_study_timer.dart';
import 'task_time_pie.dart';

/// Web `/` — today's plan, extra/temporary study, recorded time and the plan
/// cycle entry point for full-period plans.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(studyTimerProvider.select((_) => shanghaiToday()));
    final activeAdHocId = ref.watch(
      studyTimerProvider.select((timer) => timer.activeAdHocId),
    );
    final activeExtraTaskId = ref.watch(
      studyTimerProvider.select(
        (timer) => timer.activeRelation == TimeLogRelation.extra
            ? timer.activeTaskId
            : null,
      ),
    );
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final timer = ref.read(studyTimerProvider);
        final breakdown = day_ops.dayCapacityBreakdown(data, date);
        final groups = day_ops.groupDailyBlocks(
          data.blocks.where((block) => block.date == date),
          data.tasks,
        );
        final groupTaskIds = {for (final group in groups) group.first.taskId};
        final extraTasks = [
          for (final task in data.tasks)
            if (!groupTaskIds.contains(task.id) &&
                (day_ops.extraMinutesForTaskDay(data, task.id, date) > 0 ||
                    timer.lastSessionFor(task.id, date)?.relation ==
                        TimeLogRelation.extra ||
                    activeExtraTaskId == task.id))
              task,
        ];
        final adHocEntries = [
          for (final entry in day_ops.adHocLearningEntries(
            data,
            date: date,
            includeIds: {
              ?activeAdHocId,
              for (final learning in data.adHocLearnings)
                if (timer.lastSessionForAdHoc(learning.id, date) != null)
                  learning.id,
            },
          ))
            if (entry.todayMinutes > 0 ||
                activeAdHocId == entry.learning.id ||
                timer.lastSessionForAdHoc(entry.learning.id, date) != null)
              entry,
        ];
        final cycle = planCycleState(data.profile, date);
        final needsCompletion = planPeriodNeedsCompletion(data, today: date);
        final restDay = breakdown.capacity <= 0;
        final emptyPlan =
            data.planning == null ||
            data.subjects.isEmpty ||
            data.tasks.isEmpty;
        return PlannerPage(
          title: '',
          subtitle: '',
          actions: [
            if (!emptyPlan)
              AsyncActionButton(
                label: '开始计时',
                icon: Icons.play_arrow,
                enabled: snapshot.editable,
                onPressed: () => StartStudyDialog.show(context),
              ),
          ],
          children: [
            if (needsCompletion) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('dashboard-complete-cycle'),
                  onPressed: snapshot.editable
                      ? () => ContinueCycleDialog.showCompleteCycle(context)
                      : null,
                  icon: const Icon(Icons.event_note_outlined, size: 18),
                  label: const Text('补全本周期安排'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (emptyPlan) ...[
              const PlannerEmpty(
                icon: Icons.timer_outlined,
                message: '还没有长期计划，也没关系',
                hint: '你可以先记录今天想做的事，直接开始学习；之后再让 AI 帮你整理成长期路线。',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('dashboard-quick-start'),
                    onPressed: snapshot.editable
                        ? () => StartStudyDialog.show(context)
                        : null,
                    icon: const Icon(Icons.timer_outlined),
                    label: const Text('开始计时'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('dashboard-ai-planning'),
                    onPressed: () => context.go('/interview'),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('AI 长期规划'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (!emptyPlan && cycle != PlanCycleState.running) ...[
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
                  key: const Key('dashboard-next-cycle'),
                  onPressed: snapshot.editable
                      ? () => ContinueCycleDialog.showNextCycle(context)
                      : null,
                  icon: const Icon(Icons.event_repeat, size: 18),
                  label: const Text('继续安排下一周期'),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (restDay) ...[
              const PlannerNotice(
                '今天是休息日：可用学习净容量为 0，不生成学习安排。'
                '如果实际发生了学习仍可以如实计时，记录会显示为“超出原容量”。',
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
                  breakdown: breakdown,
                  groups: groups,
                  extraTasks: extraTasks,
                  adHocEntries: adHocEntries,
                  editable: snapshot.editable,
                  showEmpty: !emptyPlan,
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

class _TodayStudyPanel extends ConsumerWidget {
  const _TodayStudyPanel({
    required this.data,
    required this.date,
    required this.breakdown,
    required this.groups,
    required this.extraTasks,
    required this.adHocEntries,
    required this.editable,
    required this.showEmpty,
  });

  final PlannerData data;
  final String date;
  final DayCapacityBreakdown breakdown;
  final List<List<ScheduleBlock>> groups;
  final List<Task> extraTasks;
  final List<day_ops.AdHocLearningEntry> adHocEntries;
  final bool editable;
  final bool showEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskById = {for (final task in data.tasks) task.id: task};
    final source = capacity.resolveDayCapacity(data.profile, date);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showEmpty &&
            groups.isEmpty &&
            extraTasks.isEmpty &&
            adHocEntries.isEmpty)
          const PlannerEmpty(
            icon: Icons.list_alt_outlined,
            message: '今天还没有学习内容：可以按原定安排开始，也可以加学已有事项或临时学习。',
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
                  date: date,
                  editable: editable,
                  onMove: () => MoveTaskDayDialog.show(context, group),
                ),
          ],
        if (extraTasks.isNotEmpty) ...[
          const Divider(height: 24),
          Semantics(
            header: true,
            child: Row(
              children: [
                const Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: PlannerColors.orange,
                ),
                const SizedBox(width: 6),
                Text('今日加学', style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          for (final task in extraTasks)
            _ExtraTaskRow(
              key: ValueKey('extra-task-${task.id}:$date'),
              task: task,
              data: data,
              date: date,
              editable: editable,
            ),
        ],
        if (adHocEntries.isNotEmpty) ...[
          const Divider(height: 24),
          Semantics(
            header: true,
            child: Row(
              children: [
                const Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: PlannerColors.orange,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '今日临时学习',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  key: const Key('dashboard-new-adhoc'),
                  onPressed: () => AdHocStudyDialog.show(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新增'),
                ),
              ],
            ),
          ),
          for (final entry in adHocEntries)
            _AdHocLearningRow(
              key: ValueKey('ad-hoc-${entry.learning.id}:$date'),
              entry: entry,
              data: data,
              date: date,
            ),
        ],
        const Divider(height: 24),
        Text(
          '今日净容量 ${duration(breakdown.capacity)}'
          '（${capacity.capacitySourceLabel(source.source)}'
          '${source.estimated ? ' · 估算' : ''}） · '
          '实际投入 ${duration(breakdown.actual)} · '
          '有效预留 ${duration(breakdown.reserved)} · '
          '新增可安排 ${duration(breakdown.available)}'
          '${breakdown.over > 0 ? ' · 超出 ${duration(breakdown.over)}' : ''}。',
          key: const Key('today-capacity-breakdown'),
          style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

/// One task's live clock, timer action and expandable study details.
class _TaskDayRow extends ConsumerStatefulWidget {
  const _TaskDayRow({
    required this.blocks,
    required this.date,
    required this.editable,
    required this.onMove,
    super.key,
  });

  final List<ScheduleBlock> blocks;
  final String date;
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
    final date = widget.date;
    final task = data.tasks
        .where((item) => item.id == blocks.first.taskId)
        .firstOrNull;
    if (task == null) return const SizedBox.shrink();
    final planned = blocks.fold<int>(
      0,
      (sum, block) => sum + block.durationMinutes,
    );
    final actual = day_ops.taskDayMinutes(data, task.id, date);
    final scheduled = day_ops.scheduledMinutesForTaskDay(data, task.id, date);
    final extra = day_ops.extraMinutesForTaskDay(data, task.id, date);
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
                  if (extra > 0)
                    Container(
                      key: Key('task-extra-chip-${task.id}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: PlannerColors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '+加学 ${duration(extra)}',
                        style: const TextStyle(
                          color: PlannerColors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (scheduled > 0)
                    Text(
                      '原定完成 ${duration(scheduled)} / ${duration(planned)}',
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12,
                      ),
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
                  if (task.status == TaskStatus.completed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: Key('task-review-${task.id}'),
                        onPressed: editable
                            ? () async {
                                try {
                                  await ref
                                      .read(studyTimerProvider)
                                      .startExtra(task.id);
                                } catch (error) {
                                  if (context.mounted) {
                                    showPlannerMessage(
                                      context,
                                      error is StateError
                                          ? error.message
                                          : '$error',
                                      tone: PlannerNoticeTone.error,
                                    );
                                  }
                                }
                              }
                            : null,
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('复习计时（不重新打开事项）'),
                      ),
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

/// An existing item that received extra study today although it has no block.
class _ExtraTaskRow extends ConsumerWidget {
  const _ExtraTaskRow({
    required this.task,
    required this.data,
    required this.date,
    required this.editable,
    super.key,
  });

  final Task task;
  final PlannerData data;
  final String date;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = data.subjects
        .where((subject) => subject.id == task.subjectId)
        .firstOrNull;
    final color = subjectColor(task.subjectId, course?.color);
    final extra = day_ops.extraMinutesForTaskDay(data, task.id, date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PlannerColors.surface,
          border: Border.all(color: PlannerColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TaskStudyTimer(
          heading: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${course?.name ?? task.subjectId} · ${task.title}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '今日加学 ${duration(extra)}',
                key: Key('extra-minutes-${task.id}'),
                style: const TextStyle(
                  color: PlannerColors.orange,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          taskId: task.id,
          date: date,
          plannedMinutes: 0,
          color: color,
          extraOnly: true,
          canDiscard: editable,
          canStart: editable && task.status != TaskStatus.archived,
          secondaryAction: IconButton(
            tooltip: '记录内容进度',
            icon: const Icon(Icons.rate_review_outlined, size: 19),
            onPressed: editable
                ? () => ContentFeedbackDialog.show(context, task.id)
                : null,
          ),
        ),
      ),
    );
  }
}

/// One temporary-learning entity with its own timer row on today's page.
class _AdHocLearningRow extends ConsumerWidget {
  const _AdHocLearningRow({
    required this.entry,
    required this.data,
    required this.date,
    super.key,
  });

  final day_ops.AdHocLearningEntry entry;
  final PlannerData data;
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learning = entry.learning;
    final subject = learning.subjectId == null
        ? null
        : data.subjects
              .where((item) => item.id == learning.subjectId)
              .firstOrNull;
    final color = subjectColor(learning.subjectId ?? 'ad-hoc', subject?.color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: PlannerColors.surface,
          border: Border.all(color: PlannerColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: TaskStudyTimer(
          heading: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                learning.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (subject != null)
                SubjectChip(name: subject.name, color: color, compact: true),
              Text(
                '今日 ${duration(entry.todayMinutes)} · 累计 ${duration(entry.totalMinutes)}',
                key: Key('ad-hoc-minutes-${learning.id}'),
                style: const TextStyle(
                  color: PlannerColors.orange,
                  fontSize: 12,
                ),
              ),
              if (learning.archived)
                Text(
                  learning.convertedTaskId == null ? '已归档' : '已转为正式事项/已关联',
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          adHocId: learning.id,
          date: date,
          plannedMinutes: 0,
          color: color,
          canDiscard: true,
          canStart: !learning.archived,
          secondaryAction: learning.archived
              ? null
              : PopupMenuButton<String>(
                  tooltip: '临时学习后续操作',
                  onSelected: (value) {
                    if (value == 'convert') {
                      AdHocConvertDialog.show(context, learning.id);
                    } else {
                      TaskPickerDialog.showLinkAdHoc(context, learning.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'convert', child: Text('转为正式事项')),
                    PopupMenuItem(value: 'link', child: Text('关联到已有事项')),
                  ],
                ),
        ),
      ),
    );
  }
}
