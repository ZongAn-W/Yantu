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
///
/// One panel, three metric tiles and hairline separators: the strip must read as
/// a single quiet summary band, never as three competing cards.
class CalendarOverview extends StatelessWidget {
  const CalendarOverview({required this.metrics, super.key});

  final ProgressMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final estimated = metrics.overallMinutes;
    final completed = metrics.completedMinutes;
    final contentRate = estimated == 0 ? null : completed / estimated;
    final forecast = metrics.forecast;
    final horizon = metrics.targetDate.isNotEmpty
        ? '${metrics.targetConfirmed ? '目标日期' : '预计目标日期'} ${metrics.targetDate}'
        : '本次规划结束 ${metrics.cycleEnd}';
    final hairline = plannerHairline(context);
    final stats = <_OverviewStat>[
      _OverviewStat(
        label: '累计实际学习',
        value: duration(metrics.totalActual),
        noteKey: const ValueKey('progress-relation-breakdown'),
        note:
            '原定执行 ${duration(metrics.scheduledActual)} · '
            '加学 ${duration(metrics.extraActual)}',
      ),
      _OverviewStat(
        label: '本期剩余',
        value: duration(metrics.remainingMinutes),
        noteKey: const ValueKey('calendar-overview-forecast'),
        note: forecast == null ? '记录学习后可估算完成日期' : '预计完成 $forecast · $horizon',
      ),
      _OverviewStat(
        label: '事项完成',
        value: contentRate == null ? '—' : '${(contentRate * 100).round()}%',
        noteKey: const ValueKey('calendar-overview-content'),
        note: estimated == 0
            ? '还没有事项'
            : '已完成 ${duration(completed)} / 计划 ${duration(estimated)}',
      ),
    ];
    return Semantics(
      container: true,
      child: PlannerPanel(
        key: const ValueKey('calendar-overview'),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 720) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var index = 0; index < stats.length; index++) ...[
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: SizedBox(
                          width: hairline,
                          height: 46,
                          child: const ColoredBox(color: PlannerColors.border),
                        ),
                      ),
                    Expanded(child: _OverviewMetric(stat: stats[index])),
                  ],
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  if (index > 0)
                    SizedBox(
                      height: hairline,
                      child: const ColoredBox(color: PlannerColors.border),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _OverviewMetric(stat: stats[index]),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OverviewStat {
  const _OverviewStat({
    required this.label,
    required this.value,
    required this.note,
    this.noteKey,
  });

  final String label;
  final String value;
  final String note;
  final Key? noteKey;
}

/// A [MetricTile] plus the keyed note line: the existing overview tests identify
/// the breakdown text by key, and [MetricTile] does not expose a note key.
class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.stat});

  final _OverviewStat stat;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MetricTile(label: stat.label, value: stat.value),
        const SizedBox(height: 3),
        Text(
          stat.note,
          key: stat.noteKey,
          style: text.bodySmall?.copyWith(fontSize: 12),
        ),
      ],
    );
  }
}
