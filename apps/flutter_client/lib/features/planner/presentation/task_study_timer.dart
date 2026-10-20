import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/planner_session.dart';
import '../application/study_timer.dart';
import '../domain/planner_format.dart';
import 'planner_dialogs.dart';

String _formatElapsed(Duration value) => [
  value.inHours,
  value.inMinutes % 60,
  value.inSeconds % 60,
].map((part) => part.toString().padLeft(2, '0')).join(':');

/// The same read-only clock and timer action on today's list and the calendar.
///
/// The widget also renders extra-study rows (a study item without a block on
/// today's list): [extraOnly] starts an explicit extra-study interval instead of
/// the scheduled one.
class TaskStudyTimer extends ConsumerWidget {
  const TaskStudyTimer({
    required this.taskId,
    required this.date,
    required this.plannedMinutes,
    required this.color,
    required this.canStart,
    this.canDiscard = true,
    this.extraOnly = false,
    this.heading,
    this.secondaryAction,
    this.detailsAction,
    super.key,
  });

  final String taskId;
  final String date;
  final int plannedMinutes;
  final Color color;
  final bool canStart;
  final bool canDiscard;
  final bool extraOnly;
  final Widget? heading;
  final Widget? secondaryAction;
  final Widget? detailsAction;

  String get _ownerKey => taskId;

  String _time(DateTime value) {
    final local = value.toUtc().add(const Duration(hours: 8));
    return '${dateOnlyOf(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final timer = ref.read(studyTimerProvider);
    final session = timer.lastSessionFor(taskId, date);
    if (session == null) return;
    final label = session.isLegacy ? '删除历史计时累计' : '撤销上一段计时';
    final confirmed = await confirmAction(
      context,
      title: label,
      message: session.isLegacy
          ? '旧版将同一天的计时合并保存，无法拆分到每次开始和暂停。'
                '\n删除这条历史计时累计（${_formatElapsed(session.elapsed)}）？其他记录将保留。'
          : '${_time(session.startedAt)} 至 ${_time(session.endedAt)}'
                '\n计时 ${_formatElapsed(session.elapsed)}。撤销后会从累计用时中扣除这段时间。',
      confirmLabel: session.isLegacy ? '删除累计' : '撤销这段',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await timer.discardLastSession(
        taskId,
        date,
        expectedSessionId: session.id,
      );
      if (context.mounted) {
        showPlannerMessage(
          context,
          '已撤销 ${_formatElapsed(session.elapsed)} 的计时',
        );
      }
    } catch (_) {
      // The timer exposes failed saves inline and retains them for retry.
    }
  }

  /// Offers the optional follow-up of a paused extra interval without
  /// completing anything automatically.
  void _afterPause(BuildContext context, WidgetRef ref, StudyTimer timer) {
    if (!context.mounted) return;
    if (timer.lastSessionFor(taskId, date)?.relation != TimeLogRelation.extra) {
      return;
    }
    showExtraStudyPauseFollowUp(context, ref, taskId);
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final timer = ref.read(studyTimerProvider);
    try {
      if (timer.activeTaskId == taskId) {
        await timer.pause();
        if (context.mounted) _afterPause(context, ref, timer);
      } else if (extraOnly) {
        await timer.startExtra(taskId);
      } else {
        await timer.start(taskId, date);
      }
    } catch (_) {
      // The controller retains the clock and exposes the error inline.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    // A one-second tick must not rebuild the whole card: this widget watches
    // only the timer fields that do not change per second, while _StudyClock
    // below follows the elapsed time inside its own RepaintBoundary.
    final card = ref.watch(
      studyTimerProvider.select((timer) {
        final last = timer.activeTaskId == taskId
            ? null
            : timer.lastSessionFor(taskId, date);
        return (
          running: timer.activeTaskId == taskId,
          ready: timer.ready,
          busy: timer.busy,
          error: timer.error,
          hasElapsed: timer.elapsedFor(taskId, date) > Duration.zero,
          lastElapsed: last?.elapsed,
          lastIsLegacy: last?.isLegacy,
          lastStartedAt: last?.startedAt,
          lastEndedAt: last?.endedAt,
        );
      }),
    );
    final running = card.running;
    final hasLast = card.lastElapsed != null;
    final action = running
        ? '暂停计时'
        : card.hasElapsed
        ? '继续计时'
        : extraOnly
        ? '开始加学'
        : '开始计时';
    final ring = _StudyClock(
      taskId: taskId,
      date: date,
      plannedMinutes: plannedMinutes,
      color: color,
      extraOnly: extraOnly,
      ownerKey: _ownerKey,
    );
    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // 今日加学卡只是加学计时的展示与控制：没有进行中的计时会话时
            // 不再提供“开始加学”，入口统一在下方事项行的闹钟。
            final showPrimaryAction = !extraOnly || running || card.hasElapsed;
            final actions = <Widget>[
              if (showPrimaryAction)
                FilledButton.icon(
                  key: Key('study-timer-action-$_ownerKey-$date'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(PlannerRadius.small),
                    ),
                  ),
                  onPressed: !card.ready || card.busy || (!running && !canStart)
                      ? null
                      : () => _toggle(context, ref),
                  icon: Icon(
                    running ? Icons.pause : Icons.play_arrow,
                    size: 16,
                  ),
                  label: Text(action),
                ),
              if (running)
                OutlinedButton.icon(
                  key: Key('study-timer-end-$_ownerKey-$date'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: !card.ready || card.busy
                      ? null
                      : () => _toggle(context, ref),
                  icon: const Icon(Icons.stop, size: 15),
                  label: const Text('结束计时'),
                ),
              if (hasLast)
                IconButton(
                  key: Key('undo-study-session-$_ownerKey-$date'),
                  tooltip: card.lastIsLegacy! ? '删除历史计时累计' : '撤销上一段计时',
                  icon: const Icon(Icons.undo, size: 16),
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed:
                      card.ready &&
                          !card.busy &&
                          canDiscard &&
                          card.error == null
                      ? () => _discard(context, ref)
                      : null,
                ),
              ?secondaryAction,
              ?detailsAction,
            ];
            if (constraints.maxWidth < 200) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  actions.first,
                  if (actions.length > 1)
                    Wrap(spacing: 4, children: actions.skip(1).toList()),
                ],
              );
            }
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            );
          },
        ),
        if (hasLast) ...[
          const SizedBox(height: 4),
          Tooltip(
            message:
                '${_time(card.lastStartedAt!)} 至 ${_time(card.lastEndedAt!)}',
            child: Text(
              '${card.lastIsLegacy! ? '历史计时累计' : '上一段'} '
              '${_formatElapsed(card.lastElapsed!)}',
              style: tabularFigures.copyWith(fontSize: 11, color: tokens.muted),
            ),
          ),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (heading != null && constraints.maxWidth < 340) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  heading!,
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ring,
                      const SizedBox(width: 12),
                      Expanded(child: controls),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (heading != null) ...[
                        heading!,
                        const SizedBox(height: 10),
                      ],
                      controls,
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ring,
              ],
            );
          },
        ),
        if (card.error != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  card.error!,
                  style: TextStyle(color: tokens.danger, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: '重试保存计时',
                icon: const Icon(Icons.refresh, size: 19),
                onPressed: card.busy
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
                          // Keep the failed operation visible until persistence succeeds.
                        }
                      },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The only part of the card that follows the one-second tick: its own selects
/// keep each tick inside this RepaintBoundary instead of rebuilding the card.
class _StudyClock extends ConsumerWidget {
  const _StudyClock({
    required this.taskId,
    required this.date,
    required this.plannedMinutes,
    required this.color,
    required this.extraOnly,
    required this.ownerKey,
  });

  final String taskId;
  final String date;
  final int plannedMinutes;
  final Color color;
  final bool extraOnly;
  final String ownerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final elapsed = ref.watch(
      studyTimerProvider.select((timer) => timer.elapsedFor(taskId, date)),
    );
    final running = ref.watch(
      studyTimerProvider.select((timer) => timer.activeTaskId == taskId),
    );
    final clock = _formatElapsed(elapsed);
    final targetSeconds = plannedMinutes * 60;
    final ratio = targetSeconds <= 0
        ? 0.0
        : (elapsed.inMilliseconds / (targetSeconds * 1000)).clamp(0.0, 1.0);
    final targetLabel = extraOnly ? '加学计时' : '目标 ${duration(plannedMinutes)}';
    return RepaintBoundary(
      child: Semantics(
        key: Key('study-progress-$ownerKey-$date'),
        label: '学习用时',
        value: '已学 $clock，$targetLabel',
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: 104,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: running
                      ? color.withValues(alpha: 0.28)
                      : tokens.border,
                ),
                boxShadow: running
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.10),
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 3.5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: tokens.surfaceMuted,
                      color: color,
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '已学',
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.3,
                            color: tokens.subtle,
                          ),
                        ),
                        Text(
                          clock,
                          key: Key('study-clock-$ownerKey-$date'),
                          style: tabularFigures.copyWith(
                            fontSize: 14.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          targetLabel,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.3,
                            color: tokens.subtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 事项行闹钟暂停后的可选后续：加学/复习计时保存后提示记录本次内容进度。
///
/// 只在本事项当天最后一段计时是 [TimeLogRelation.extra] 时提示，绝不自动完成
/// 内容或解锁依赖；已完成事项只说明复习计时已记录，内容完成状态保持不变。
void showExtraStudyPauseFollowUp(
  BuildContext context,
  WidgetRef ref,
  String taskId,
) {
  if (!context.mounted) return;
  final date = shanghaiToday();
  final session = ref.read(studyTimerProvider).lastSessionFor(taskId, date);
  if (session?.relation != TimeLogRelation.extra) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final data = ref.read(plannerSessionProvider).data;
  final task = data.tasks.where((item) => item.id == taskId).firstOrNull;
  if (task == null || task.status == TaskStatus.completed) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('复习计时已记录：内容完成状态保持不变。')),
    );
    return;
  }
  messenger?.showSnackBar(
    SnackBar(
      content: const Text('加学时间已保存。需要的话可以记录本次内容进度与困难。'),
      action: SnackBarAction(
        label: '记录内容进度',
        onPressed: () => ContentFeedbackDialog.show(context, taskId),
      ),
    ),
  );
}
