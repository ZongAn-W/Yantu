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
/// 「全部事项」课程目录（原事项页）。全页只有一个滚动条，内容宽度上限 1200。
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
        final emptyPlan =
            data.planning == null ||
            data.subjects.isEmpty ||
            data.tasks.isEmpty;
        final compact = MediaQuery.sizeOf(context).width < 900;

        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 24,
                compact ? 16 : 20,
                compact ? 16 : 24,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SectionHeader(title: '今日学习'),
                      const SizedBox(height: 10),
                      if (needsCompletion) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const Key('dashboard-complete-cycle'),
                            onPressed: snapshot.editable
                                ? () => ContinueCycleDialog.showCompleteCycle(
                                    context,
                                  )
                                : null,
                            icon: const Icon(
                              Icons.event_note_outlined,
                              size: 18,
                            ),
                            label: const Text('补全本周期安排'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (emptyPlan) ...[
                        PlannerEmpty(
                          key: const Key('dashboard-empty-plan'),
                          icon: Icons.timer_outlined,
                          message: '还没有长期计划，也没关系',
                          hint:
                              '可以先在下方「全部事项」新建课程、添加事项直接学习；'
                              '之后也可以让 AI 帮你整理成长期路线。',
                          action: FilledButton.icon(
                            key: const Key('dashboard-ai-planning'),
                            onPressed: () => context.go('/interview'),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: const Text('AI 长期规划'),
                          ),
                        ),
                        const SizedBox(height: 8),
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
                                ? () =>
                                      ContinueCycleDialog.showNextCycle(context)
                                : null,
                            icon: const Icon(Icons.event_repeat, size: 18),
                            label: const Text('继续安排下一周期'),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (restDay) ...[
                        const PlannerNotice(
                          '今天是休息日：没有生成学习安排。'
                          '仍可在下方「全部事项」中按需加学。',
                          tone: PlannerNoticeTone.info,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!emptyPlan && groups.isEmpty && extraTasks.isEmpty)
                        const PlannerEmpty(
                          icon: Icons.list_alt_outlined,
                          message: '今天没有安排学习内容',
                          hint:
                              '可在下方「全部事项」中选择事项加学，'
                              '或新建课程与事项。',
                        ),
                      if (groups.isNotEmpty)
                        _PlannedStudyList(
                          data: data,
                          date: date,
                          groups: groups,
                          editable: snapshot.editable,
                        ),
                      if (extraTasks.isNotEmpty) ...[
                        const Divider(height: 28),
                        const _ExtraStudyHeader(),
                        const SizedBox(height: 4),
                        for (final task in extraTasks)
                          _ExtraTaskRow(
                            key: ValueKey('extra-task-${task.id}:$date'),
                            task: task,
                            data: data,
                            date: date,
                            editable: snapshot.editable,
                          ),
                      ],
                      const SizedBox(height: 28),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ExtraStudyHeader extends StatelessWidget {
  const _ExtraStudyHeader();

  @override
  Widget build(BuildContext context) {
    return Semantics(
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
    );
  }
}

/// 今天计划内事项，按课程分组展示（计时卡原样保留）。
class _PlannedStudyList extends StatelessWidget {
  const _PlannedStudyList({
    required this.data,
    required this.date,
    required this.groups,
    required this.editable,
  });

  final PlannerData data;
  final String date;
  final List<List<ScheduleBlock>> groups;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final taskById = {for (final task in data.tasks) task.id: task};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
