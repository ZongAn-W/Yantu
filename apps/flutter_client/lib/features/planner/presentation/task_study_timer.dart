import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart' show dateOnlyOf;
import '../application/study_timer.dart';
import '../domain/planner_format.dart';

/// The same read-only clock and timer action on today's list and the calendar.
class TaskStudyTimer extends ConsumerWidget {
  const TaskStudyTimer({
    required this.taskId,
    required this.date,
    required this.plannedMinutes,
    required this.color,
    required this.canStart,
    this.canDiscard = true,
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
  final Widget? heading;
  final Widget? secondaryAction;
  final Widget? detailsAction;

  String _elapsed(Duration value) => [
    value.inHours,
    value.inMinutes % 60,
    value.inSeconds % 60,
  ].map((part) => part.toString().padLeft(2, '0')).join(':');

  String _time(DateTime value) {
    final local = value.toUtc().add(const Duration(hours: 8));
    return '${dateOnlyOf(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  Future<void> _discard(
    BuildContext context,
    StudyTimer timer,
    StudyTimerSession session,
  ) async {
    final label = session.isLegacy ? '删除历史计时累计' : '撤销上一段计时';
    final confirmed = await confirmAction(
      context,
      title: label,
      message: session.isLegacy
          ? '旧版将同一天的计时合并保存，无法拆分到每次开始和暂停。'
                '\n删除这条历史计时累计（${_elapsed(session.elapsed)}）？其他记录将保留。'
          : '${_time(session.startedAt)} 至 ${_time(session.endedAt)}'
                '\n计时 ${_elapsed(session.elapsed)}。撤销后会从累计用时中扣除这段时间。',
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
        showPlannerMessage(context, '已撤销 ${_elapsed(session.elapsed)} 的计时');
      }
    } catch (_) {
      // The timer exposes failed saves inline and retains them for retry.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(studyTimerProvider);
    final elapsed = timer.elapsedFor(taskId, date);
    final running = timer.activeTaskId == taskId;
    final clock = _elapsed(elapsed);
    final last = running ? null : timer.lastSessionFor(taskId, date);
    final targetSeconds = plannedMinutes * 60;
    final ratio = targetSeconds <= 0
        ? 0.0
        : (elapsed.inMilliseconds / (targetSeconds * 1000)).clamp(0.0, 1.0);
    final action = running
        ? '暂停计时'
        : elapsed > Duration.zero
        ? '继续计时'
        : '开始计时';
    final ring = Semantics(
      key: Key('study-progress-$taskId-$date'),
      label: '学习用时',
      value: '已学 $clock，目标 ${duration(plannedMinutes)}',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 104,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: PlannerColors.border,
                  color: color,
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '已学',
                      style: TextStyle(
                        fontSize: 10,
                        color: PlannerColors.muted,
                      ),
                    ),
                    Text(
                      clock,
                      key: Key('study-clock-$taskId-$date'),
                      style: tabularFigures.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '目标 ${duration(plannedMinutes)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: PlannerColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final actions = <Widget>[
              FilledButton.icon(
                key: Key('study-timer-action-$taskId-$date'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: !timer.ready || timer.busy || (!running && !canStart)
                    ? null
                    : () async {
                        try {
                          if (running) {
                            await timer.pause();
                          } else {
                            await timer.start(taskId, date);
                          }
                        } catch (_) {
                          // The controller retains the clock and exposes the error inline.
                        }
                      },
                icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 18),
                label: Text(action),
              ),
              if (last != null)
                IconButton(
                  key: Key('undo-study-session-$taskId-$date'),
                  tooltip: last.isLegacy ? '删除历史计时累计' : '撤销上一段计时',
                  icon: const Icon(Icons.undo, size: 19),
                  onPressed:
                      timer.ready &&
                          !timer.busy &&
                          canDiscard &&
                          timer.error == null
                      ? () => _discard(context, timer, last)
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
        if (last != null) ...[
          const SizedBox(height: 4),
          Tooltip(
            message: '${_time(last.startedAt)} 至 ${_time(last.endedAt)}',
            child: Text(
              '${last.isLegacy ? '历史计时累计' : '上一段'} ${_elapsed(last.elapsed)}',
              style: tabularFigures.copyWith(
                fontSize: 11,
                color: PlannerColors.muted,
              ),
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
        if (timer.error != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  timer.error!,
                  style: const TextStyle(
                    color: PlannerColors.danger,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                tooltip: '重试保存计时',
                icon: const Icon(Icons.refresh, size: 19),
                onPressed: timer.busy
                    ? null
                    : () async {
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
