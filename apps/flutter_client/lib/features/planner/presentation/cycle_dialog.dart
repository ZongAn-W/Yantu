import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/planner_session.dart';
import '../domain/plan_cycle.dart';
import '../domain/planner_format.dart';
import 'planner_dialogs.dart' show DateField;

/// 续排对话框：确认新的规划区间、延展本期安排边界并生成新的每日安排。
///
/// 只在确认后写回计划，已有安排、固定事件和历史学习记录都不会被覆盖；
/// 同一区间重复确认是幂等的，不会重复生成已经存在的每日安排。
class ContinueCycleDialog extends ConsumerStatefulWidget {
  const ContinueCycleDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const ContinueCycleDialog(),
    );
    return result == true;
  }

  @override
  ConsumerState<ContinueCycleDialog> createState() =>
      _ContinueCycleDialogState();
}

class _ContinueCycleDialogState extends ConsumerState<ContinueCycleDialog> {
  late final String _today = shanghaiToday();
  String? _start;
  String? _end;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerDataProvider).data;
    if (data == null) return const SizedBox.shrink();
    final cycleEnd = data.profile.resolvedPlanEnd(_today);
    final nextStartCandidate = cycleEnd.compareTo(_today) < 0
        ? _today
        : addDate(cycleEnd, 1);
    _start ??= nextStartCandidate;
    _end ??= addDate(_start!, 27);
    final extended = extendPlanCycle(
      data,
      start: _start!,
      end: _end!,
      today: _today,
    );
    final preview = generatePlanBlocks(
      extended,
      from: _start!,
      to: _end!,
    );
    final pendingItems = extended.tasks.where(
      (task) =>
          task.status != TaskStatus.completed &&
          task.status != TaskStatus.archived &&
          task.estimatedMinutes > task.completedMinutes,
    );
    final remaining = pendingItems.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes - task.completedMinutes,
    );
    return AlertDialog(
      title: const Text('继续安排下一周期'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('当前规划：${data.profile.resolvedPlanStart(_today)} 至 $cycleEnd'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 220,
                    child: DateField(
                      label: '新的开始日期',
                      value: _start!,
                      onChanged: (value) => setState(() => _start = value),
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: DateField(
                      label: '新的结束日期',
                      value: _end!,
                      onChanged: (value) => setState(() => _end = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PlannerStat(label: '待安排事项', value: '${pendingItems.length} 个'),
              PlannerStat(label: '剩余工作量', value: duration(remaining)),
              PlannerStat(
                label: '本次新增安排',
                value: '${preview.blocks} 段 · ${duration(preview.scheduledMinutes)}',
              ),
              const SizedBox(height: 8),
              const Text(
                '已有安排、固定事件、历史学习记录和已完成事项保持不变。',
                style: TextStyle(color: PlannerColors.muted, fontSize: 12),
              ),
              for (final gap in preview.gaps)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: PlannerNotice(gap, tone: PlannerNoticeTone.warning),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final expected = jsonEncode(data.toJson());
                  try {
                    await ref
                        .read(plannerSessionProvider)
                        .edit((current) {
                          if (jsonEncode(current.toJson()) != expected) {
                            throw StateError('计划已更新，请重新打开续排预览');
                          }
                          return preview.data;
                        });
                    if (navigator.mounted) navigator.pop(true);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '已生成新的每日安排：${preview.blocks} 段，共 ${duration(preview.scheduledMinutes)}。',
                        ),
                      ),
                    );
                  } catch (error) {
                    if (mounted) {
                      setState(() => _busy = false);
                    }
                    messenger.showSnackBar(
                      SnackBar(content: Text('安排失败：$error')),
                    );
                  }
                },
          icon: const Icon(Icons.event_repeat),
          label: const Text('确认并生成安排'),
        ),
      ],
    );
  }
}
