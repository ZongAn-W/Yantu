import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/plan_cycle.dart';
import '../domain/planner_format.dart';

/// 应用新排程约束前的预览：调整前后的每日负荷、被释放和新增的安排、未安排量。
///
/// 只在确认后写回计划；取消不会修改设置或安排。
class ScheduleChangeDialog extends StatelessWidget {
  const ScheduleChangeDialog({
    required this.before,
    required this.adjustment,
    required this.start,
    required this.end,
    super.key,
  });

  final PlannerData before;
  final ScheduleAdjustment adjustment;
  final String start;
  final String end;

  static Future<bool> show(
    BuildContext context, {
    required PlannerData before,
    required ScheduleAdjustment adjustment,
    required String start,
    required String end,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ScheduleChangeDialog(
        before: before,
        adjustment: adjustment,
        start: start,
        end: end,
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final today = shanghaiToday();
    final changed = adjustment.changedDays;
    final shown = changed.length > 14 ? changed.sublist(0, 14) : changed;
    return AlertDialog(
      title: const Text('预览日程调整'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '规划区间：${before.profile.resolvedPlanStart(today)} 至 '
                '${before.profile.resolvedPlanEnd(today)} → $start 至 $end',
              ),
              const SizedBox(height: 12),
              PlannerStat(
                label: '已释放的未来安排',
                value:
                    '${adjustment.releasedBlocks} 段 · ${duration(adjustment.releasedMinutes)}',
              ),
              PlannerStat(
                label: '重新排入',
                value:
                    '${adjustment.placedBlocks} 段 · ${duration(adjustment.placedMinutes)}',
              ),
              PlannerStat(
                label: '仍未安排',
                value: duration(adjustment.unscheduledMinutes),
                tone: adjustment.unscheduledMinutes > 0
                    ? PlannerColors.orange
                    : null,
              ),
              PlannerStat(
                label: '保持不变（固定 / 已完成 / 已有用时）',
                value: '${adjustment.protectedBlocks} 段',
              ),
              if (shown.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('每日计划时长', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final date in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${monthDayLabel(date)} ${weekdayLabel(date)}',
                          ),
                        ),
                        Text(
                          '${duration(adjustment.beforeLoad[date] ?? 0)} → '
                          '${duration(adjustment.afterLoad[date] ?? 0)}',
                          style: tabularFigures,
                        ),
                      ],
                    ),
                  ),
                if (changed.length > shown.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '另有 ${changed.length - shown.length} 天发生变化。',
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              if (adjustment.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final note in adjustment.notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      note,
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                '历史记录、已完成安排、固定事件和有实际用时的安排不会被改动。',
                style: TextStyle(color: PlannerColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.check),
          label: const Text('确认并应用'),
        ),
      ],
    );
  }
}
