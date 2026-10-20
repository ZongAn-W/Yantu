import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/progress_metrics.dart';

/// Compact, always-visible status strip of the merged calendar.
///
/// These numbers are current facts (as of today) and deliberately do not follow
/// the selected date: the day/week/month scopes below answer "what is planned
/// and what happened", this strip answers "how far have I got".
class CalendarOverview extends StatelessWidget {
  const CalendarOverview({required this.metrics, super.key});

  final ProgressMetrics metrics;

  @override
  Widget build(BuildContext context) {
    var estimated = 0;
    var completed = 0;
    for (final progress in metrics.subjectProgress) {
      estimated += progress.estimated;
      completed += progress.completed;
    }
    final contentRate = estimated == 0 ? null : completed / estimated;
    final forecast = metrics.forecast;
    final horizon = metrics.targetDate.isNotEmpty
        ? '${metrics.targetConfirmed ? '目标日期' : '预计目标日期'} ${metrics.targetDate}'
        : '本次规划结束 ${metrics.cycleEnd}';
    final stats = <_OverviewStat>[
      _OverviewStat(
        label: '累计实际学习',
        value: duration(metrics.totalActual),
        subKey: const ValueKey('progress-relation-breakdown'),
        sub:
            '原定执行 ${duration(metrics.scheduledActual)} · '
            '加学 ${duration(metrics.extraActual)}',
      ),
      _OverviewStat(
        label: '本期剩余',
        value: duration(metrics.remainingMinutes),
        subKey: const ValueKey('calendar-overview-forecast'),
        sub: forecast == null
            ? '记录学习后可估算完成日期'
            : '预计完成 $forecast · $horizon',
      ),
      _OverviewStat(
        label: '课程内容完成',
        value: contentRate == null ? '—' : '${(contentRate * 100).round()}%',
        subKey: const ValueKey('calendar-overview-content'),
        sub: estimated == 0
            ? '还没有课程事项'
            : '已完成 ${duration(completed)} / 计划 ${duration(estimated)}',
      ),
    ];
    return Semantics(
      container: true,
      child: PlannerPanel(
        key: const ValueKey('calendar-overview'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 720) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < stats.length; index++) ...[
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: 1,
                          height: 58,
                          child: ColoredBox(color: PlannerColors.border),
                        ),
                      ),
                    Expanded(child: stats[index]),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  stats[index],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({
    required this.label,
    required this.value,
    required this.sub,
    this.subKey,
  });

  final String label;
  final String value;
  final String sub;
  final Key? subKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(color: PlannerColors.muted, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: tabularFigures.copyWith(fontSize: 19)),
      const SizedBox(height: 2),
      Text(
        sub,
        key: subKey,
        style: const TextStyle(color: PlannerColors.muted, fontSize: 11),
      ),
    ],
  );
}
