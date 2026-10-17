import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/domain/study_day.dart' show DayStats;
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';

/// Web `/` — today's plan, recorded time, completion and the replan entry point.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = shanghaiToday();
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final stats = day_ops.dayStats(data, date);
        final groups = day_ops.groupDailyBlocks(
          data.blocks.where((block) => block.date == date),
          data.tasks,
        );
        final taskById = {for (final task in data.tasks) task.id: task};
        final pending = [
          for (final group in groups)
            if (group.any(
              (block) =>
                  block.status != BlockStatus.completed &&
                  taskById[block.taskId]?.status != TaskStatus.completed,
            ))
              group,
        ];
        final examDays = math.max(0, daysBetween(date, data.profile.examDate));
        return PlannerPage(
          title: '今天，专注眼前的一步',
          subtitle: '${fullDateLabel(date)} · 距离初试 $examDays 天',
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
                final side = _DaySidebar(
                  data: data,
                  date: date,
                  stats: stats,
                  groups: groups,
                  pending: pending,
                  editable: snapshot.editable,
                );
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
      title: '今日学习 ${groups.length - pending.length}/${groups.length} 项完成',
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
          const SizedBox(height: 8),
          const Text(
            '学完后记录实际用时，再勾选「今日完成」。',
            style: TextStyle(color: PlannerColors.muted, fontSize: 12),
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
                    blocks: group,
                    editable: editable,
                    onRecord: () => RecordTimeDialog.show(
                      context,
                      date: date,
                      taskId: group.first.taskId,
                    ),
                    onMove: () => MoveTaskDayDialog.show(context, group),
                  ),
            ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: editable
                  ? () => RecordTimeDialog.show(context, date: date)
                  : null,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('记录事项用时'),
            ),
          ),
          const Divider(height: 24),
          Text(
            '每日上限 ${duration(data.profile.dailyLimitMinutes)}，'
            '保留 ${duration(data.profile.bufferMinutes)} 机动时间。',
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

/// One task row of a day: goal, recorded time, completion check and date change.
class _TaskDayRow extends ConsumerWidget {
  const _TaskDayRow({
    required this.blocks,
    required this.editable,
    required this.onRecord,
    required this.onMove,
  });

  final List<ScheduleBlock> blocks;
  final bool editable;
  final VoidCallback onRecord;
  final VoidCallback onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final completed =
        task.status == TaskStatus.completed ||
        blocks.every((block) => block.status == BlockStatus.completed);
    final course = data.subjects
        .where((subject) => subject.id == task.subjectId)
        .firstOrNull;
    final color = subjectColor(task.subjectId, course?.color);
    final advice = blocks
        .where((block) => (block.adviceText ?? '').isNotEmpty)
        .map((block) => block.adviceText!)
        .firstOrNull;
    final ratio = planned == 0 ? 0 : (actual / planned * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: completed ? const Color(0xfff4f8f6) : PlannerColors.surface,
          border: Border.all(
            color: completed ? const Color(0xffbfe0cf) : PlannerColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                SubjectChip(name: course?.name ?? task.subjectId, color: color),
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('今日目标 ${duration(planned)}'),
                Text(
                  '已学 ${duration(actual)}',
                  style: tabularFigures.copyWith(
                    color: actual > 0 ? PlannerColors.green : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (actual > planned)
                  Text(
                    '超出目标 ${duration(actual - planned)}',
                    style: const TextStyle(
                      color: PlannerColors.orange,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TimeProgressTrack(
              planned: planned,
              actual: actual,
              color: color,
              semanticsLabel:
                  '${course?.name ?? task.subjectId} · ${task.title}用时进度',
            ),
            const SizedBox(height: 4),
            Text(
              '用时进度 $ratio%',
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: editable ? onRecord : null,
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text(actual > 0 ? '修改用时' : '记录用时'),
                ),
                Tooltip(
                  message: task.status == TaskStatus.completed
                      ? '整项学习已完成'
                      : '标记今天的学习安排完成',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: completed,
                        onChanged:
                            !editable || task.status == TaskStatus.completed
                            ? null
                            : (value) => ref
                                  .read(plannerSessionProvider)
                                  .setTaskDayCompletion(blocks, value ?? false),
                      ),
                      Text(completed ? '今日已完成' : '今日完成'),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: editable ? onMove : null,
                  icon: const Icon(Icons.event_outlined, size: 15),
                  label: const Text('改日期'),
                ),
              ],
            ),
            if (advice != null || (task.description ?? '').isNotEmpty) ...[
              const Divider(height: 20),
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
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '事项截止 ${task.deadline}',
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DaySidebar extends ConsumerWidget {
  const _DaySidebar({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final taskById = {for (final task in data.tasks) task.id: task};
    final logged = [
      for (final task in data.tasks)
        if (day_ops.taskDayMinutes(data, task.id, date) > 0) task,
    ];
    final canUndo = data.replanRuns.any(
      (run) => run.status == ReplanStatus.confirmed,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlannerPanel(
          title: '今日完成',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: SizedBox.square(
                  dimension: 132,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Semantics(
                        label: '今日完成率${stats.rate}%',
                        child: CircularProgressIndicator(
                          value: (stats.rate / 100).clamp(0.0, 1.0),
                          strokeWidth: 10,
                          backgroundColor: PlannerColors.border,
                          valueColor: const AlwaysStoppedAnimation(
                            PlannerColors.blue,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${stats.rate}%',
                            style: tabularFigures.copyWith(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            '实际 / 计划',
                            style: TextStyle(
                              color: PlannerColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PlannerStat(label: '计划时长', value: duration(stats.planned)),
              PlannerStat(
                label: '实际完成',
                value: duration(stats.actual),
                tone: PlannerColors.green,
              ),
              PlannerStat(label: '剩余时长', value: duration(stats.remaining)),
              PlannerStat(label: '超额完成', value: duration(stats.excess)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PlannerPanel(
          title: '今日事项用时',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (logged.isEmpty)
                const Text(
                  '学完后按事项记录实际用时。',
                  style: TextStyle(color: PlannerColors.muted, fontSize: 12),
                ),
              for (final task in logged)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: subjectColor(
                            task.subjectId,
                            data.subjects
                                .where((s) => s.id == task.subjectId)
                                .firstOrNull
                                ?.color,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${subjectNameOf(data, task.subjectId)} · ${task.title}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        duration(day_ops.taskDayMinutes(data, task.id, date)),
                        style: tabularFigures.copyWith(
                          color: PlannerColors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 20),
              Text(
                '待完成 ${pending.length} 项',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final group in pending)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: subjectColor(
                            taskById[group.first.taskId]?.subjectId ?? '',
                            null,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${subjectNameOf(data, taskById[group.first.taskId]?.subjectId ?? '')} · '
                          '${taskById[group.first.taskId]?.title ?? ''}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        duration(
                          math.max(
                            0,
                            group.fold<int>(
                              0,
                              (sum, block) =>
                                  sum +
                                  block.durationMinutes -
                                  block.actualMinutes,
                            ),
                          ),
                        ),
                        style: tabularFigures,
                      ),
                    ],
                  ),
                ),
              if (groups.isNotEmpty && pending.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '今天的计划已全部完成。',
                    style: TextStyle(color: PlannerColors.green),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go('/progress'),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('查看学习进度'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PlannerPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('每一次学习都按实际记录计入进度。'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: AsyncActionButton(
                  label: '撤销最近调整',
                  icon: Icons.history,
                  filled: false,
                  enabled: canUndo && editable,
                  tooltip: '恢复最近一次重排前的计划',
                  onPressed: () async {
                    await ref.read(plannerSessionProvider).undoReplan();
                    if (context.mounted) {
                      showPlannerMessage(
                        context,
                        '已恢复到重排前的计划。',
                        tone: PlannerNoticeTone.success,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
