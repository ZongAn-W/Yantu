import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/progress_metrics.dart';
import '../../planner/presentation/planner_page_state.dart';

/// Web `/progress` — subject progress, weekly comparison, heat map and burndown.
class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  String _month = shanghaiToday().substring(0, 7);

  @override
  Widget build(BuildContext context) {
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final date = shanghaiToday();
        final metrics = progressMetrics(data, date: date, month: _month);
        return PlannerPage(
          title: '学习进度',
          subtitle: '计划指明方向，真实记录呈现进步。',
          actions: [
            PlannerPanel(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Text(
                '累计实际学习 ${duration(metrics.totalActual)}',
                style: tabularFigures.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          children: [
            _SubjectProgressPanel(metrics: metrics),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1040;
                final weekly = _WeeklyPanel(metrics: metrics);
                final heatmap = _HeatmapPanel(
                  metrics: metrics,
                  month: _month,
                  onMonthChanged: (value) => setState(() => _month = value),
                );
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      weekly,
                      const SizedBox(height: 16),
                      heatmap,
                      const SizedBox(height: 16),
                      _BurnPanel(metrics: metrics),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    weekly,
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: heatmap),
                        const SizedBox(width: 16),
                        Expanded(child: _BurnPanel(metrics: metrics)),
                      ],
                    ),
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

class _SubjectProgressPanel extends StatelessWidget {
  const _SubjectProgressPanel({required this.metrics});
  final ProgressMetrics metrics;

  @override
  Widget build(BuildContext context) => PlannerPanel(
    title: '课程进度',
    trailing: const Text(
      '完成量按各事项实际记录封顶后汇总',
      style: TextStyle(color: PlannerColors.muted, fontSize: 12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (metrics.subjectProgress.every((item) => item.estimated == 0))
          const PlannerEmpty(
            message: '还没有课程。请在事项管理中创建事项，课程会自动出现。',
            icon: Icons.bar_chart_outlined,
          ),
        for (final item in metrics.subjectProgress)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    SubjectChip(
                      name: item.subject.name,
                      color: subjectColor(item.subject.id, item.subject.color),
                    ),
                    Text(
                      '完成 ${duration(item.completed)} / 预算 ${duration(item.estimated)}'
                      ' · 实际 ${duration(item.actual)}',
                      style: tabularFigures.copyWith(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TimeProgressTrack(
                  planned: item.estimated,
                  actual: item.completed,
                  color: subjectColor(item.subject.id, item.subject.color),
                  semanticsLabel: '${item.subject.name}完成进度',
                ),
                const SizedBox(height: 4),
                Text(
                  '剩余 ${duration(item.remaining)} · 完成率 '
                  '${(item.ratio * 100).round()}%',
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _WeeklyPanel extends StatelessWidget {
  const _WeeklyPanel({required this.metrics});
  final ProgressMetrics metrics;

  @override
  Widget build(BuildContext context) => PlannerPanel(
    title: '近7天 · 课程进度',
    trailing: Text(
      '${metrics.week.first.substring(5)} — ${metrics.date.substring(5)}',
      style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 12, height: 12, color: PlannerColors.border),
                const SizedBox(width: 6),
                const Text('计划', style: TextStyle(fontSize: 12)),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 12, height: 12, color: PlannerColors.blue),
                const SizedBox(width: 6),
                const Text('实际完成', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          label: '课程周计划与实际时长柱状图',
          child: SizedBox(
            height: 210,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final stat in metrics.weekStats)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Tooltip(
                                    message: '计划 ${duration(stat.planned)}',
                                    child: _Bar(
                                      ratio: stat.planned / metrics.maxWeekly,
                                      color: PlannerColors.border,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Tooltip(
                                    message: '实际 ${duration(stat.actual)}',
                                    child: _Bar(
                                      ratio: stat.actual / metrics.maxWeekly,
                                      color: subjectColor(
                                        stat.subject.id,
                                        stat.subject.color,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          SubjectChip(
                            name: stat.subject.name,
                            color: subjectColor(
                              stat.subject.id,
                              stat.subject.color,
                            ),
                            compact: true,
                          ),
                          Text(
                            '${duration(stat.planned)} / ${duration(stat.actual)}',
                            style: tabularFigures.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 24),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            for (final stat in metrics.weekStats)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SubjectChip(
                    name: stat.subject.name,
                    color: subjectColor(stat.subject.id, stat.subject.color),
                    compact: true,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    duration(stat.totalActual),
                    style: tabularFigures.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: ratio.clamp(0.0, 1.0),
    alignment: Alignment.bottomCenter,
    child: Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
    ),
  );
}

class _HeatmapPanel extends StatelessWidget {
  const _HeatmapPanel({
    required this.metrics,
    required this.month,
    required this.onMonthChanged,
  });

  final ProgressMetrics metrics;
  final String month;
  final ValueChanged<String> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    final unique = <String>[];
    for (var offset = -6; offset <= 6; offset++) {
      final value = _monthOf(metrics.date, offset);
      if (!unique.contains(value)) unique.add(value);
    }
    if (!unique.contains(month)) unique.add(month);
    return PlannerPanel(
      title: '月度学习热力图',
      trailing: DropdownButton<String>(
        value: month,
        underline: const SizedBox.shrink(),
        items: [
          for (final value in unique)
            DropdownMenuItem(value: value, child: Text(value)),
        ],
        onChanged: (value) {
          if (value != null) onMonthChanged(value);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '本月中断 ${metrics.interruptedDays} 天 · 仅统计有计划但没有实际记录的过去日期',
            style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final cell = (constraints.maxWidth - 6 * 4) / 7;
              return Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var index = 0; index < metrics.heatLead; index++)
                    SizedBox(width: cell, height: cell),
                  for (final entry in metrics.heatCells)
                    Tooltip(
                      message:
                          '${entry.date} · 实际${duration(entry.actual)} · '
                          '完成率${entry.rate}%',
                      child: Semantics(
                        label:
                            '${entry.date} 实际${duration(entry.actual)} '
                            '完成率${entry.rate}%',
                        child: Container(
                          width: cell,
                          height: cell,
                          decoration: BoxDecoration(
                            color: _heatColor(entry.level),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: Text(
                              '${int.parse(entry.date.substring(8))}',
                              style: TextStyle(
                                fontSize: 10,
                                color: entry.level >= 3
                                    ? Colors.white
                                    : PlannerColors.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('少', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 6),
              for (var level = 0; level <= 4; level++)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _heatColor(level),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              const Text('多', style: TextStyle(fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  static String _monthOf(String date, int offset) {
    final year = int.parse(date.substring(0, 4));
    final month = int.parse(date.substring(5, 7));
    final total = year * 12 + (month - 1) + offset;
    return '${total ~/ 12}-${(total % 12 + 1).toString().padLeft(2, '0')}';
  }

  static Color _heatColor(int level) => switch (level) {
    0 => const Color(0xffeef2f7),
    1 => const Color(0xffcfe0f0),
    2 => const Color(0xff9dc0dd),
    3 => const Color(0xff5d8fbd),
    _ => PlannerColors.blue,
  };
}

class _BurnPanel extends StatelessWidget {
  const _BurnPanel({required this.metrics});
  final ProgressMetrics metrics;

  @override
  Widget build(BuildContext context) => PlannerPanel(
    title: '总体燃尽',
    trailing: Text(
      metrics.lagging
          ? '当前进度落后'
          : metrics.forecast != null
          ? '按当前速度推进'
          : '记录学习后可估算进度',
      style: TextStyle(
        color: metrics.lagging ? PlannerColors.orange : PlannerColors.muted,
        fontSize: 12,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlannerStat(label: '剩余事项量', value: duration(metrics.remainingMinutes)),
        PlannerStat(label: '预计完成', value: metrics.forecast ?? '尚无实际记录'),
        PlannerStat(label: '目标截止', value: metrics.examDate),
        const SizedBox(height: 12),
        Semantics(
          label: '按实际完成记录计算的剩余事项量燃尽图',
          child: SizedBox(
            height: 160,
            child: CustomPaint(
              painter: _BurnPainter(
                values: metrics.burnValues,
                overall: metrics.overallMinutes,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${metrics.burnDays.first} → ${metrics.date}',
          style: tabularFigures.copyWith(fontSize: 11),
        ),
        const SizedBox(height: 4),
        const Text(
          '蓝线按各事项实际完成量封顶后绘制。预计完成日期使用首次记录以来的日均实际用时，尚无记录时不作预测。',
          style: TextStyle(color: PlannerColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
}

class _BurnPainter extends CustomPainter {
  _BurnPainter({required this.values, required this.overall});
  final List<int> values;
  final int overall;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    final width = size.width - left - 4;
    final height = size.height - 8;
    canvas.drawLine(
      Offset(left, height),
      Offset(left + width, height),
      Paint()
        ..color = PlannerColors.border
        ..strokeWidth = 1,
    );
    if (values.length < 2) return;
    final path = Path();
    final dots = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = left + (index * width) / (values.length - 1);
      final ratio = overall == 0 ? 0.0 : values[index] / overall;
      final y = height - ratio * (height - 8);
      dots.add(Offset(x, y));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = PlannerColors.blue
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    final dot = Paint()..color = PlannerColors.blue;
    for (final point in dots) {
      canvas.drawCircle(point, 2, dot);
    }
  }

  @override
  bool shouldRepaint(_BurnPainter old) =>
      old.overall != overall ||
      old.values.length != values.length ||
      old.values.first != values.first ||
      old.values.last != values.last;
}
