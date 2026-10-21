import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planner_ui_vendor/planner_ui_vendor.dart';

import '../../../core/motion.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../../shared/models/task_lifecycle.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/application/study_timer.dart';
import '../../planner/domain/plan_cycle.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/presentation/cycle_dialog.dart';
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';
import '../../planner/presentation/task_study_timer.dart';
import '../../tasks/presentation/task_directory.dart';
import 'today_scroll.dart';

String _compactClock(Duration value) => [
  value.inHours,
  value.inMinutes % 60,
  value.inSeconds % 60,
].map((part) => part.toString().padLeft(2, '0')).join(':');

/// Fixed columns keep the primary action, live clock and expand chevron aligned
/// across planned and extra-study rows.
const double _compactMetaWidth = 176;
const double _compactActionWidth = 112;
const double _compactWideBreakpoint = 720;

/// `/` — 今日。
///
/// 合并后的单页：上半部分是今天的学习区，下半部分是「全部事项」目录（原事项
/// 页）。全页只有一个滚动条，内容宽度上限 1200。「开始计时」按钮、今日用时
/// 饼图、今日净容量和临时学习都已移除；页面顶部也不再展示日期与今日原定/
/// 已学汇总。计时区把计划内事项与纯加学事项合并成一个居中标题的「今日安排」
/// 列表：计划内事项使用单行紧凑计时行，加学分钟内联标记，标签/总进度/撤销
/// 等收进展开；今天没有原定安排、纯加学或复习的事项以同样的紧凑行排在后面。
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
        duration: PlannerMotion.duration(
          context,
          preferred: PlannerDurations.slow,
        ),
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
        // 计划内事项的加学合并进计划行（+加学内联标记）；「今日加学」只保留
        // 今天没有原定安排、纯加学/复习的事项。
        final plannedTaskIds = {for (final group in groups) group.first.taskId};
        final extraTasks = [
          for (final task in data.tasks)
            if (!plannedTaskIds.contains(task.id) &&
                (day_ops.extraMinutesForTaskDay(data, task.id, date) > 0 ||
                    timer.lastSessionFor(task.id, date)?.relation ==
                        TimeLogRelation.extra ||
                    activeExtraTaskId == task.id))
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
                      if (needsCompletion) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            key: const Key('dashboard-complete-cycle'),
                            onPressed: snapshot.editable
                                ? () => ContinueCycleDialog.showCompleteCycle(
                                    context,
                                  )
                                : null,
                            icon: const Icon(
                              LucideIcons.calendarClock,
                              size: 16,
                            ),
                            label: const Text('补全本周期安排'),
                          ),
                        ),
                        const SizedBox(height: PlannerSpace.lg),
                      ],
                      if (emptyPlan) ...[
                        PlannerEmpty(
                          key: const Key('dashboard-empty-plan'),
                          icon: LucideIcons.timer,
                          message: '还没有长期计划，也没关系',
                          hint:
                              '可以先在下方「全部事项」新建事项直接学习；'
                              '之后也可以让 AI 帮你整理成长期路线。',
                          action: FilledButton.icon(
                            key: const Key('dashboard-ai-planning'),
                            onPressed: () => context.go('/interview'),
                            icon: const Icon(LucideIcons.sparkles, size: 17),
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
                            icon: const Icon(LucideIcons.repeat, size: 16),
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
                          icon: LucideIcons.listChecks,
                          message: '今天没有安排学习内容',
                          hint: '可在下方「全部事项」中选择事项加学或新建事项。',
                        ),
                      if (groups.isNotEmpty || extraTasks.isNotEmpty) ...[
                        SectionHeader(
                          title: '今日安排',
                          count: groups.length + extraTasks.length,
                          centered: true,
                        ),
                        const SizedBox(height: PlannerSpace.sm),
                        if (groups.isNotEmpty)
                          _PlannedStudyList(
                            date: date,
                            groups: groups,
                            editable: snapshot.editable,
                          ),
                        for (final task in extraTasks)
                          // W7: per-card repaint isolation.
                          RepaintBoundary(
                            child: _ExtraTaskRow(
                              key: ValueKey('extra-task-${task.id}:$date'),
                              task: task,
                              data: data,
                              date: date,
                              editable: snapshot.editable,
                            ),
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
          // W7: per-card repaint isolation.
          RepaintBoundary(
            child: _TaskDayRow(
              key: ValueKey('${group.first.taskId}:$date'),
              blocks: group,
              date: date,
              editable: editable,
              onMove: () => MoveTaskDayDialog.show(context, group),
            ),
          ),
      ],
    );
  }
}

/// One task's compact row: title, today's planned progress, the live clock and
/// the primary timer action. Secondary information (tags, overall progress,
/// undo, move, advice, deadline) lives behind the chevron.
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
    final tokens = context.tokens;
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
    final color = _taskColor(task.id, tokens);
    final advice = blocks
        .where((block) => (block.adviceText ?? '').isNotEmpty)
        .map((block) => block.adviceText!)
        .firstOrNull;
    final progress = taskTimeProgress(data, task);
    final completed = taskIsCompleted(data, task);
    final state = ref.watch(
      studyTimerProvider.select((timer) {
        final last = timer.activeTaskId == task.id
            ? null
            : timer.lastSessionFor(task.id, date);
        return (
          running: timer.activeTaskId == task.id,
          ready: timer.ready,
          busy: timer.busy,
          error: timer.error,
          hasElapsed: timer.elapsedFor(task.id, date) > Duration.zero,
          hasLast: last != null,
        );
      }),
    );
    final running = state.running;
    final actionLabel = running
        ? '暂停计时'
        : state.hasElapsed
        ? '继续计时'
        : '开始计时';
    final canStart = editable && !taskIsArchived(task) && !completed;
    final movable =
        editable &&
        !taskIsArchived(task) &&
        !completed &&
        !task.isFixed &&
        actual == 0 &&
        !state.hasElapsed &&
        !running;

    Future<void> toggle() async {
      final timer = ref.read(studyTimerProvider);
      try {
        if (running) {
          await timer.pause();
          if (context.mounted) {
            showExtraStudyPauseFollowUp(context, ref, task.id);
          }
        } else {
          await timer.start(task.id, date);
        }
      } catch (_) {
        // The timer keeps the failure inline; _TimerErrorRow offers a retry.
      }
    }

    final actionButton = FilledButton.icon(
      key: Key('study-timer-action-${task.id}-$date'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlannerRadius.small),
        ),
      ),
      onPressed: !state.ready || state.busy || (!running && !canStart)
          ? null
          : () => toggle(),
      icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 16),
      label: Text(actionLabel),
    );
    final expandButton = IconButton(
      tooltip: _detailsExpanded ? '收起学习详情' : '展开学习详情',
      icon: Icon(
        _detailsExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
        size: 17,
      ),
      style: plannerIconButtonStyle(context),
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      onPressed: () => setState(() => _detailsExpanded = !_detailsExpanded),
    );
    final title = Text(
      task.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14.5,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
    final minuteLabel = Text(
      '$scheduled/$planned分',
      style: _compactMetaStyle(tokens),
    );
    final extraChip = extra > 0
        ? Text(
            '+加学 ${duration(extra)}',
            key: Key('task-extra-chip-${task.id}'),
            style: _compactMetaStyle(tokens, color: tokens.warning),
          )
        : null;
    final clockText = _CompactStudyClock(
      taskId: task.id,
      date: date,
      style: _compactClockStyle(tokens),
    );

    Widget content({required bool wide}) {
      if (wide) {
        return Row(
          children: [
            StatusDot(color: color),
            const SizedBox(width: PlannerSpace.sm),
            Expanded(child: title),
            const SizedBox(width: PlannerSpace.sm),
            SizedBox(
              width: _compactMetaWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    minuteLabel,
                    if (extraChip != null) ...[
                      const SizedBox(width: PlannerSpace.xs),
                      extraChip,
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: PlannerSpace.md),
            SizedBox(width: _compactActionWidth, child: actionButton),
            const SizedBox(width: PlannerSpace.sm),
            clockText,
            expandButton,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusDot(color: color),
              const SizedBox(width: PlannerSpace.sm),
              Expanded(child: title),
              expandButton,
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: PlannerSpace.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [actionButton, minuteLabel, ?extraChip, clockText],
          ),
        ],
      );
    }

    final details = _detailsExpanded
        ? <Widget>[
            const SizedBox(height: PlannerSpace.sm),
            const Divider(height: 1),
            const SizedBox(height: PlannerSpace.sm),
            Wrap(
              spacing: PlannerSpace.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (task.isFixed)
                  Tooltip(
                    message: '固定事项',
                    child: Icon(
                      LucideIcons.lock,
                      size: 13,
                      color: tokens.subtle,
                    ),
                  ),
                for (final tag in _taskTag(data, task, tokens)) tag,
                PlannerTag(
                  key: Key('task-progress-${task.id}'),
                  label: progress.shortLabel,
                  color: taskProgressTone(progress, tokens),
                  dense: true,
                ),
                Text(
                  scheduled > 0
                      ? '原定完成 ${duration(scheduled)} / ${duration(planned)}'
                      : '原定 ${duration(planned)}',
                  style: _compactMetaStyle(tokens),
                ),
                if (state.hasLast)
                  IconButton(
                    key: Key('undo-study-session-${task.id}-$date'),
                    tooltip: '撤销上一段计时',
                    icon: const Icon(Icons.undo, size: 16),
                    style: plannerIconButtonStyle(context),
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: editable && !state.busy
                        ? () => _discardLastSession(context, ref, task.id, date)
                        : null,
                  ),
                if (movable)
                  IconButton(
                    key: Key('task-move-${task.id}'),
                    tooltip: '调整日期',
                    icon: const Icon(LucideIcons.calendar, size: 17),
                    style: plannerIconButtonStyle(context),
                    constraints: const BoxConstraints.tightFor(
                      width: 30,
                      height: 30,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: widget.onMove,
                  ),
              ],
            ),
            if (advice != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        LucideIcons.sparkles,
                        size: 13,
                        color: tokens.accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '今日建议：$advice',
                        style: const TextStyle(fontSize: 12.5, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            if ((task.description ?? '').isNotEmpty)
              Text(
                task.description!,
                style: TextStyle(
                  color: tokens.muted,
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
            if (completed)
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
                                error is StateError ? error.message : '$error',
                                tone: PlannerNoticeTone.error,
                              );
                            }
                          }
                        }
                      : null,
                  icon: const Icon(LucideIcons.rotateCcw, size: 16),
                  label: const Text('复习计时（不重新打开事项）'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${task.deadlineKind == ItemDateKind.planEnd ? '本期安排边界' : '事项截止'} ${task.deadline}',
                style: TextStyle(
                  color: tokens.subtle,
                  fontSize: 11.5,
                  height: 1.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ]
        : const <Widget>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: PlannerSpace.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.border),
          borderRadius: PlannerRadius.cardRadius,
          boxShadow: plannerPanelShadow(context),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content(wide: constraints.maxWidth >= _compactWideBreakpoint),
                if (state.error != null)
                  _TimerErrorRow(message: state.error!, busy: state.busy),
                ...details,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// An existing item that received extra study today without a scheduled block
/// today (planned items show their extra minutes inline on the planned row).
class _ExtraTaskRow extends ConsumerStatefulWidget {
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
  ConsumerState<_ExtraTaskRow> createState() => _ExtraTaskRowState();
}

class _ExtraTaskRowState extends ConsumerState<_ExtraTaskRow> {
  bool _detailsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final data = widget.data;
    final date = widget.date;
    final editable = widget.editable;
    final tokens = context.tokens;
    final color = _taskColor(task.id, tokens);
    final extra = day_ops.extraMinutesForTaskDay(data, task.id, date);
    final progress = taskTimeProgress(data, task);
    final state = ref.watch(
      studyTimerProvider.select((timer) {
        final last = timer.activeTaskId == task.id
            ? null
            : timer.lastSessionFor(task.id, date);
        return (
          running: timer.activeTaskId == task.id,
          ready: timer.ready,
          busy: timer.busy,
          error: timer.error,
          hasElapsed: timer.elapsedFor(task.id, date) > Duration.zero,
          hasLast: last != null,
        );
      }),
    );
    final running = state.running;
    final canStart = editable && !taskIsArchived(task);
    final actionLabel = running
        ? '暂停计时'
        : state.hasElapsed
        ? '继续计时'
        : '开始加学';

    Future<void> toggle() async {
      final timer = ref.read(studyTimerProvider);
      try {
        if (running) {
          await timer.pause();
          if (context.mounted) {
            showExtraStudyPauseFollowUp(context, ref, task.id);
          }
        } else {
          await timer.startExtra(task.id);
        }
      } catch (_) {
        // The timer keeps the failure inline; _TimerErrorRow offers a retry.
      }
    }

    final info = Text(
      '今日加学 ${duration(extra)}',
      key: Key('extra-minutes-${task.id}'),
      style: _compactMetaStyle(tokens, color: tokens.warning),
    );
    final title = Text(
      task.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14.5,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
    final clockText = _CompactStudyClock(
      taskId: task.id,
      date: date,
      style: _compactClockStyle(tokens),
    );
    final actionButton = FilledButton.icon(
      key: Key('study-timer-action-${task.id}-$date'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlannerRadius.small),
        ),
      ),
      onPressed: !state.ready || state.busy || (!running && !canStart)
          ? null
          : () => toggle(),
      icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 16),
      label: Text(actionLabel),
    );
    final undoButton = state.hasLast
        ? IconButton(
            key: Key('undo-study-session-${task.id}-$date'),
            tooltip: '撤销上一段计时',
            icon: const Icon(Icons.undo, size: 16),
            style: plannerIconButtonStyle(context),
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            onPressed: editable && !state.busy
                ? () => _discardLastSession(context, ref, task.id, date)
                : null,
          )
        : null;
    final expandButton = IconButton(
      tooltip: _detailsExpanded ? '收起学习详情' : '展开学习详情',
      icon: Icon(
        _detailsExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
        size: 17,
      ),
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      onPressed: () => setState(() => _detailsExpanded = !_detailsExpanded),
    );
    // 今日加学卡只是加学计时的展示与控制：没有进行中的计时会话时不再提供
    // “开始加学”，入口统一在下方事项行的闹钟。
    final showPrimaryAction = running || state.hasElapsed;

    Widget content({required bool wide}) {
      if (wide) {
        return Row(
          children: [
            StatusDot(color: color),
            const SizedBox(width: PlannerSpace.sm),
            Expanded(child: title),
            const SizedBox(width: PlannerSpace.sm),
            SizedBox(
              width: _compactMetaWidth,
              child: Align(alignment: Alignment.centerRight, child: info),
            ),
            const SizedBox(width: PlannerSpace.md),
            SizedBox(
              width: _compactActionWidth,
              child: showPrimaryAction ? actionButton : const SizedBox.shrink(),
            ),
            const SizedBox(width: PlannerSpace.sm),
            clockText,
            expandButton,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StatusDot(color: color),
              const SizedBox(width: PlannerSpace.sm),
              Expanded(child: title),
              expandButton,
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: PlannerSpace.sm,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [if (showPrimaryAction) actionButton, info, clockText],
          ),
        ],
      );
    }

    final details = _detailsExpanded
        ? <Widget>[
            const SizedBox(height: PlannerSpace.sm),
            const Divider(height: 1),
            const SizedBox(height: PlannerSpace.sm),
            Wrap(
              spacing: PlannerSpace.sm,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final tag in _taskTag(data, task, tokens)) tag,
                PlannerTag(
                  key: Key('extra-progress-${task.id}'),
                  label: progress.shortLabel,
                  color: taskProgressTone(progress, tokens),
                  dense: true,
                ),
                Text(
                  '今日加学 ${duration(extra)}',
                  key: Key('extra-details-minutes-${task.id}'),
                  style: _compactMetaStyle(tokens, color: tokens.warning),
                ),
                ?undoButton,
              ],
            ),
            if ((task.description ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  task.description!,
                  style: TextStyle(
                    color: tokens.muted,
                    fontSize: 12.5,
                    height: 1.55,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${task.deadlineKind == ItemDateKind.planEnd ? '本期安排边界' : '事项截止'} ${task.deadline}',
                style: TextStyle(
                  color: tokens.subtle,
                  fontSize: 11.5,
                  height: 1.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ]
        : const <Widget>[];

    return Padding(
      padding: const EdgeInsets.only(bottom: PlannerSpace.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border.all(color: tokens.border),
          borderRadius: PlannerRadius.cardRadius,
          boxShadow: plannerPanelShadow(context),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content(wide: constraints.maxWidth >= _compactWideBreakpoint),
                if (state.error != null)
                  _TimerErrorRow(message: state.error!, busy: state.busy),
                ...details,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The only part of a compact row that follows the one-second tick.
class _CompactStudyClock extends ConsumerWidget {
  const _CompactStudyClock({
    required this.taskId,
    required this.date,
    required this.style,
  });

  final String taskId;
  final String date;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elapsed = ref.watch(
      studyTimerProvider.select((timer) => timer.elapsedFor(taskId, date)),
    );
    return RepaintBoundary(
      child: Text(
        _compactClock(elapsed),
        key: Key('study-clock-$taskId-$date'),
        style: style,
      ),
    );
  }
}

class _TimerErrorRow extends ConsumerWidget {
  const _TimerErrorRow({required this.message, required this.busy});

  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: tokens.danger, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '重试保存计时',
            icon: const Icon(Icons.refresh, size: 19),
            onPressed: busy
                ? null
                : () async {
                    final timer = ref.read(studyTimerProvider);
                    try {
                      if (timer.ready) {
                        await timer.checkpoint();
                      } else {
                        await timer.initialize();
                      }
                    } catch (_) {
                      // Keep the failure visible until persistence succeeds.
                    }
                  },
          ),
        ],
      ),
    );
  }
}

TextStyle _compactMetaStyle(PlannerTokens tokens, {Color? color}) => TextStyle(
  color: color ?? tokens.muted,
  fontSize: 12,
  height: 1.4,
  fontFeatures: const [FontFeature.tabularFigures()],
);

TextStyle _compactClockStyle(PlannerTokens tokens) => tabularFigures.copyWith(
  fontSize: 12,
  height: 1.4,
  color: tokens.muted,
  fontWeight: FontWeight.w500,
);

String _sessionTime(DateTime value) {
  final local = value.toUtc().add(const Duration(hours: 8));
  return '${dateOnlyOf(local)} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}:'
      '${local.second.toString().padLeft(2, '0')}';
}

Future<void> _discardLastSession(
  BuildContext context,
  WidgetRef ref,
  String taskId,
  String date,
) async {
  final timer = ref.read(studyTimerProvider);
  final session = timer.lastSessionFor(taskId, date);
  if (session == null) return;
  final label = session.isLegacy ? '删除历史计时累计' : '撤销上一段计时';
  final confirmed = await confirmAction(
    context,
    title: label,
    message: session.isLegacy
        ? '旧版将同一天的计时合并保存，无法拆分到每次开始和暂停。'
              '\n删除这条历史计时累计（${_compactClock(session.elapsed)}）？其他记录将保留。'
        : '${_sessionTime(session.startedAt)}  至 ${_sessionTime(session.endedAt)}'
              '\n计时 ${_compactClock(session.elapsed)}。撤销后会从累计用时中扣除这段时间。',
    confirmLabel: session.isLegacy ? '删除累计' : '撤销这段',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  try {
    await timer.discardLastSession(taskId, date, expectedSessionId: session.id);
    if (context.mounted) {
      showPlannerMessage(context, '已撤销 ${_compactClock(session.elapsed)} 的计时');
    }
  } catch (_) {
    // The timer keeps the failure inline.
  }
}

List<Widget> _taskTag(PlannerData data, Task task, PlannerTokens tokens) {
  final tagsById = {for (final tag in data.tags) tag.id: tag};
  return [
    for (final id in task.tagIds)
      if (tagsById[id] case final tag?)
        PlannerTag(
          label: tag.name,
          color: _tagColor(tag.color, tokens),
          dense: true,
        ),
  ];
}

/// Explicit tag colours keep their hue; dark mode lifts them through dataTone
/// so a user palette stays readable on the graphite surface.
Color _tagColor(String? hex, PlannerTokens tokens) {
  if (hex == null || hex.length < 7) return tokens.muted;
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) return tokens.muted;
  return tokens.dataTone(Color(0xff000000 | value));
}

/// Stable per-task accent for the read-only clock dent: the fallback palette is
/// the theme's tag palette, so light values stay byte-identical.
Color _taskColor(String id, PlannerTokens tokens) {
  var hash = 0;
  for (final code in id.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  final palette = tokens.tagFallbackColors;
  return palette[hash % palette.length];
}
