import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/application/study_timer.dart';
import '../../planner/domain/plan_cycle.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/presentation/cycle_dialog.dart';
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';
import '../../planner/presentation/planning_details.dart';
import '../../planner/presentation/planning_feedback_view.dart';
import '../../planner/presentation/task_study_timer.dart';
import '../../tasks/presentation/task_directory.dart';
import 'today_scroll.dart';

/// `/` — 今日。
///
/// 合并后的单页：上半部分是今天计划内事项的计时区（原今日页），下半部分是
/// 「全部事项」目录（原事项页）。全页只有一个滚动条，内容宽度上限 1200。
/// 「开始计时」按钮、今日用时饼图、今日净容量和临时学习都已移除；计划外事项
/// 的加学计时统一从下方事项行的闹钟发起，并展示在今日加学里。
class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  final GlobalKey _itemsSectionKey = GlobalKey();

  void _scrollToItemsIfRequested() {
    if (!TodayItemsScrollRequest.consume()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _itemsSectionKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _scrollToItemsIfRequested();
    final date = ref.watch(studyTimerProvider.select((_) => shanghaiToday()));
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
        // 计划内事项的加学也进入今日加学：从下方闹钟启动的计时必须在上方可见。
        final extraTasks = [
          for (final task in data.tasks)
            if (day_ops.extraMinutesForTaskDay(data, task.id, date) > 0 ||
                timer.lastSessionFor(task.id, date)?.relation ==
                    TimeLogRelation.extra ||
                activeExtraTaskId == task.id)
              task,
        ];
        final cycle = planCycleState(data.profile, date);
        final needsCompletion = planPeriodNeedsCompletion(data, today: date);
        final restDay = breakdown.capacity <= 0;
        final emptyPlan = data.tasks.isEmpty;
        final compact = MediaQuery.sizeOf(context).width < 900;

        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 28,
                compact ? 16 : 24,
                compact ? 16 : 28,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: plannerPageMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TodayHeader(
                        date: date,
                        planned: breakdown.planned,
                        actual: breakdown.actual,
                        needsCompletion: needsCompletion,
                        onComplete: snapshot.editable
                            ? () =>
                                  ContinueCycleDialog.showCompleteCycle(context)
                            : null,
                      ),
                      const SizedBox(height: PlannerSpace.xl),
                      if (emptyPlan) ...[
                        PlannerEmpty(
                          key: const Key('dashboard-empty-plan'),
                          icon: Icons.timer_outlined,
                          message: '还没有长期计划，也没关系',
                          hint:
                              '可以先在下方「全部事项」新建事项直接学习；'
                              '之后也可以让 AI 帮你整理成长期路线。',
                          action: FilledButton.icon(
                            key: const Key('dashboard-ai-planning'),
                            onPressed: () => context.go('/interview'),
                            icon: const Icon(
                              Icons.auto_awesome_outlined,
                              size: 17,
                            ),
                            label: const Text('AI 长期规划'),
                          ),
                        ),
                        const SizedBox(height: PlannerSpace.sm),
                      ],
                      if (!emptyPlan && cycle != PlanCycleState.running) ...[
                        PlannerNotice(
                          cycle == PlanCycleState.ended
                              ? '本次规划周期已经结束。这不代表长期目标完成或失败，可以继续安排下一周期。'
                              : '本次规划周期即将结束，可以提前安排下一周期。',
                          tone: PlannerNoticeTone.info,
                        ),
                        const SizedBox(height: PlannerSpace.md),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const Key('dashboard-next-cycle'),
                            onPressed: snapshot.editable
                                ? () =>
                                      ContinueCycleDialog.showNextCycle(context)
                                : null,
                            icon: const Icon(Icons.event_repeat, size: 16),
                            label: const Text('继续安排下一周期'),
                          ),
                        ),
                        const SizedBox(height: PlannerSpace.lg),
                      ],
                      if (restDay) ...[
                        const PlannerNotice(
                          '今天是休息日：没有生成学习安排。'
                          '仍可在下方「全部事项」中按需加学。',
                          tone: PlannerNoticeTone.info,
                        ),
                        const SizedBox(height: PlannerSpace.lg),
                      ],
                      if (!emptyPlan && groups.isEmpty && extraTasks.isEmpty)
                        const PlannerEmpty(
                          icon: Icons.list_alt_outlined,
                          message: '今天没有安排学习内容',
                          hint: '可在下方「全部事项」中选择事项加学或新建事项。',
                        ),
                      if (groups.isNotEmpty) ...[
                        SectionHeader(
                          title: '学习安排',
                          count: groups.length,
                          trailing: const _PlannedHint(),
                        ),
                        const SizedBox(height: PlannerSpace.sm),
                        _PlannedStudyList(
                          date: date,
                          groups: groups,
                          editable: snapshot.editable,
                        ),
                      ],
                      if (extraTasks.isNotEmpty) ...[
                        const SizedBox(height: PlannerSpace.xl),
                        SectionHeader(
                          title: '今日加学',
                          count: extraTasks.length,
                          trailing: const _ExtraStudyHint(),
                        ),
                        const SizedBox(height: PlannerSpace.sm),
                        for (final task in extraTasks)
                          _ExtraTaskRow(
                            key: ValueKey('extra-task-${task.id}:$date'),
                            task: task,
                            data: data,
                            date: date,
                            editable: snapshot.editable,
                          ),
                      ],
                      const SizedBox(height: PlannerSpace.section),
                      KeyedSubtree(
                        key: _itemsSectionKey,
                        child: TaskDirectory(
                          data: data,
                          editable: snapshot.editable,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 今日页头部：日期 + 今日原定/已学，保留一个「补全本周期安排」入口。
class _TodayHeader extends StatelessWidget {
  const _TodayHeader({
    required this.date,
    required this.planned,
    required this.actual,
    required this.needsCompletion,
    required this.onComplete,
  });

  final String date;
  final int planned;
  final int actual;
  final bool needsCompletion;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: PlannerSpace.lg,
      runSpacing: PlannerSpace.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '今日学习',
              style: text.labelMedium?.copyWith(
                color: PlannerColors.subtle,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              fullDateLabel(date),
              style: text.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '今日原定 ${duration(planned)} · 已学 ${duration(actual)}',
              style: text.bodyMedium?.copyWith(
                color: PlannerColors.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (needsCompletion)
          OutlinedButton.icon(
            key: const Key('dashboard-complete-cycle'),
            onPressed: onComplete,
            icon: const Icon(Icons.event_note_outlined, size: 16),
            label: const Text('补全本周期安排'),
          ),
      ],
    );
  }
}

class _PlannedHint extends StatelessWidget {
  const _PlannedHint();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const StatusDot(color: PlannerColors.blue, size: 6),
      const SizedBox(width: 6),
      Text(
        '开始计时后自动累计实际用时',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
      ),
    ],
  );
}

class _ExtraStudyHint extends StatelessWidget {
  const _ExtraStudyHint();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const StatusDot(color: PlannerColors.orange, size: 6),
      const SizedBox(width: 6),
      Text(
        '计划外或复习计时',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
      ),
    ],
  );
}

/// Today's planned tasks appear once each. Tags add context without grouping.
class _PlannedStudyList extends StatelessWidget {
  const _PlannedStudyList({
    required this.date,
    required this.groups,
    required this.editable,
  });

  final String date;
  final List<List<ScheduleBlock>> groups;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups)
          _TaskDayRow(
            key: ValueKey('${group.first.taskId}:$date'),
            blocks: group,
            date: date,
            editable: editable,
            onMove: () => MoveTaskDayDialog.show(context, group),
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
    final color = _taskColor(task.id);
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
      padding: const EdgeInsets.only(bottom: PlannerSpace.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          PlannerSpace.lg,
          PlannerSpace.md,
          PlannerSpace.lg,
          PlannerSpace.md,
        ),
        decoration: BoxDecoration(
          color: PlannerColors.surface,
          border: Border.all(color: PlannerColors.border),
          borderRadius: PlannerRadius.cardRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaskStudyTimer(
              heading: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      StatusDot(color: color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.title,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: PlannerSpace.sm,
                    runSpacing: 4,
                    children: [
                      if (task.isFixed)
                        const Tooltip(
                          message: '固定事项',
                          child: Icon(
                            Icons.lock_outline,
                            size: 13,
                            color: PlannerColors.subtle,
                          ),
                        ),
                      for (final tag in _taskTag(data, task)) tag,
                      Text(
                        scheduled > 0
                            ? '原定完成 ${duration(scheduled)} / ${duration(planned)}'
                            : '原定 ${duration(planned)}',
                        style: const TextStyle(
                          color: PlannerColors.muted,
                          fontSize: 12,
                          height: 1.4,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (extra > 0)
                        PlannerTag(
                          key: Key('task-extra-chip-${task.id}'),
                          label: '+加学 ${duration(extra)}',
                          color: PlannerColors.orange,
                          dense: true,
                        ),
                    ],
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
                  ? PlannerIconAction(
                      onPressed: widget.onMove,
                      tooltip: '调整日期',
                      icon: Icons.event_outlined,
                      iconSize: 17,
                    )
                  : null,
              detailsAction: PlannerIconAction(
                tooltip: _detailsExpanded ? '收起学习详情' : '展开学习详情',
                icon: _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                iconSize: 17,
                onPressed: () =>
                    setState(() => _detailsExpanded = !_detailsExpanded),
              ),
            ),
            if (_detailsExpanded) ...[
              const SizedBox(height: PlannerSpace.md),
              const Divider(height: 1),
              const SizedBox(height: PlannerSpace.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (advice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 3),
                            child: Icon(
                              Icons.auto_awesome,
                              size: 13,
                              color: PlannerColors.blue,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '今日建议：$advice',
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if ((task.description ?? '').isNotEmpty)
                    Text(
                      task.description!,
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12.5,
                        height: 1.55,
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
                        icon: const Icon(Icons.replay, size: 16),
                        label: const Text('复习计时（不重新打开事项）'),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${task.deadlineKind == ItemDateKind.planEnd ? '本期安排边界' : '事项截止'} ${task.deadline}',
                      style: const TextStyle(
                        color: PlannerColors.subtle,
                        fontSize: 11.5,
                        height: 1.4,
                        fontFeatures: [FontFeature.tabularFigures()],
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

/// An existing item that received extra study today, including items that also
/// have a scheduled block today (its chip appears on the planned card as well).
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
    final color = _taskColor(task.id);
    final extra = day_ops.extraMinutesForTaskDay(data, task.id, date);
    return Padding(
      padding: const EdgeInsets.only(bottom: PlannerSpace.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          PlannerSpace.lg,
          PlannerSpace.md,
          PlannerSpace.lg,
          PlannerSpace.md,
        ),
        decoration: BoxDecoration(
          color: PlannerColors.surface,
          border: Border.all(color: PlannerColors.border),
          borderRadius: PlannerRadius.cardRadius,
        ),
        child: TaskStudyTimer(
          heading: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: PlannerSpace.sm,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final tag in _taskTag(data, task)) tag,
                  Text(
                    '今日加学 ${duration(extra)}',
                    key: Key('extra-minutes-${task.id}'),
                    style: const TextStyle(
                      color: PlannerColors.orange,
                      fontSize: 12,
                      height: 1.4,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
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
          secondaryAction: PlannerIconAction(
            tooltip: '记录内容进度',
            icon: Icons.rate_review_outlined,
            iconSize: 17,
            onPressed: editable
                ? () => ContentFeedbackDialog.show(context, task.id)
                : null,
          ),
        ),
      ),
    );
  }
}

List<Widget> _taskTag(PlannerData data, Task task) {
  final tagsById = {for (final tag in data.tags) tag.id: tag};
  return [
    for (final id in task.tagIds)
      if (tagsById[id] case final tag?)
        PlannerTag(label: tag.name, color: _tagColor(tag.color), dense: true),
  ];
}

Color _tagColor(String? hex) {
  if (hex == null || hex.length < 7) return PlannerColors.muted;
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? PlannerColors.muted : Color(0xff000000 | value);
}

Color _taskColor(String id) {
  var hash = 0;
  for (final code in id.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  const palette = [
    Color(0xff537c87),
    Color(0xff7d629f),
    Color(0xffa06145),
    Color(0xff537e52),
    Color(0xff985c78),
    Color(0xff66739b),
  ];
  return palette[hash % palette.length];
}
