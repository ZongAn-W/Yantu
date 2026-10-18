import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/planner_session.dart';
import '../application/study_timer.dart';
import '../domain/planner_format.dart';
import 'planner_dialogs.dart';

/// The same read-only clock and timer action on today's list and the calendar.
///
/// The widget also renders extra-study rows (a study item without a block on
/// today's list) and temporary-learning rows: [adHocId] switches the owner to a
/// task-less ad-hoc entity and [extraOnly] starts an explicit extra-study
/// interval instead of the scheduled one.
class TaskStudyTimer extends ConsumerWidget {
  const TaskStudyTimer({
    this.taskId,
    this.adHocId,
    required this.date,
    required this.plannedMinutes,
    required this.color,
    required this.canStart,
    this.canDiscard = true,
    this.extraOnly = false,
    this.adHocTitle,
    this.adHocSubjectId,
    this.heading,
    this.secondaryAction,
    this.detailsAction,
    super.key,
  }) : assert(taskId != null || adHocId != null);

  final String? taskId;
  final String? adHocId;
  final String date;
  final int plannedMinutes;
  final Color color;
  final bool canStart;
  final bool canDiscard;
  final bool extraOnly;
  final String? adHocTitle;
  final String? adHocSubjectId;
  final Widget? heading;
  final Widget? secondaryAction;
  final Widget? detailsAction;

  String get _ownerKey => adHocId ?? taskId!;

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
      if (adHocId != null) {
        await timer.discardLastAdHocSession(
          adHocId!,
          date,
          expectedSessionId: session.id,
        );
      } else {
        await timer.discardLastSession(
          taskId!,
          date,
          expectedSessionId: session.id,
        );
      }
      if (context.mounted) {
        showPlannerMessage(context, '已撤销 ${_elapsed(session.elapsed)} 的计时');
      }
    } catch (_) {
      // The timer exposes failed saves inline and retains them for retry.
    }
  }

  /// Offers the optional follow-up of a paused extra/temporary interval without
  /// completing anything automatically.
  void _afterPause(BuildContext context, WidgetRef ref, StudyTimer timer) {
    if (!context.mounted) return;
    final session = adHocId != null
        ? timer.lastSessionForAdHoc(adHocId!, date)
        : timer.lastSessionFor(taskId!, date);
    final relation = session?.relation;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (relation == TimeLogRelation.adHoc && adHocId != null) {
      messenger?.showSnackBar(
        SnackBar(
          content: const Text('临时学习已保存。需要的话可以转为正式事项或关联到已有事项。'),
          action: SnackBarAction(
            label: '转为正式事项',
            onPressed: () => AdHocConvertDialog.show(context, adHocId!),
          ),
        ),
      );
      return;
    }
    if (relation != TimeLogRelation.extra || taskId == null) return;
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
          onPressed: () => ContentFeedbackDialog.show(context, taskId!),
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    StudyTimer timer,
  ) async {
    try {
      if (timer.activeTaskId == taskId && adHocId == null ||
          timer.activeAdHocId == adHocId && adHocId != null) {
        await timer.pause();
        if (context.mounted) _afterPause(context, ref, timer);
      } else if (adHocId != null) {
        final data = ref.read(plannerSessionProvider).data;
        final learning = data.adHocLearnings
            .where((item) => item.id == adHocId)
            .firstOrNull;
        await timer.startAdHoc(
          title: learning?.title ?? adHocTitle ?? '',
          subjectId: learning?.subjectId ?? adHocSubjectId,
        );
      } else if (extraOnly) {
        await timer.startExtra(taskId!);
      } else {
        await timer.start(taskId!, date);
      }
    } catch (_) {
      // The controller retains the clock and exposes the error inline.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(studyTimerProvider);
    final elapsed = adHocId != null
        ? timer.elapsedForAdHoc(adHocId!, date)
        : timer.elapsedFor(taskId!, date);
    final running = adHocId != null
        ? timer.isRunningAdHoc(adHocId!, date)
        : timer.activeTaskId == taskId;
    final clock = _elapsed(elapsed);
    final last = running
        ? null
        : adHocId != null
        ? timer.lastSessionForAdHoc(adHocId!, date)
        : timer.lastSessionFor(taskId!, date);
    final targetSeconds = plannedMinutes * 60;
    final ratio = targetSeconds <= 0
        ? 0.0
        : (elapsed.inMilliseconds / (targetSeconds * 1000)).clamp(0.0, 1.0);
    final action = running
        ? '暂停计时'
        : elapsed > Duration.zero
        ? '继续计时'
        : adHocId != null
        ? '开始临时学习'
        : extraOnly
        ? '开始加学'
        : '开始计时';
    final targetLabel = adHocId != null || extraOnly
        ? (elapsed > Duration.zero ? '已学 ${duration(elapsed.inMinutes)}' : '名称即可计时')
        : '目标 ${duration(plannedMinutes)}';
    final ring = Semantics(
      key: Key('study-progress-$_ownerKey-$date'),
      label: '学习用时',
      value: '已学 $clock，$targetLabel',
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
                      key: Key('study-clock-$_ownerKey-$date'),
                      style: tabularFigures.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      targetLabel,
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
                key: Key('study-timer-action-$_ownerKey-$date'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: !timer.ready || timer.busy || (!running && !canStart)
                    ? null
                    : () => _toggle(context, ref, timer),
                icon: Icon(running ? Icons.pause : Icons.play_arrow, size: 18),
                label: Text(action),
              ),
              if (last != null)
                IconButton(
                  key: Key('undo-study-session-$_ownerKey-$date'),
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
