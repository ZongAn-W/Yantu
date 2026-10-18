import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/planner_session.dart';
import '../domain/capacity.dart' as capacity;
import '../domain/plan_cycle.dart';
import '../domain/planner_format.dart';
import 'planner_dialogs.dart' show DateField;

/// 周期对话框的两种模式。
enum ContinueCycleMode {
  /// 旧滚动计划的一次性“补全本周期安排”（预览 + 确认转 full）。
  completeCurrent,

  /// 全量计划在周期结束后继续安排下一周期。
  nextCycle,
}

/// 周期安排对话框。
///
/// - 旧滚动计划：显示“补全本周期安排”，把未来缺失的每日安排补齐到周期末，
///   确认后写入 full 模式元数据（`mode: full`、`rolling: false`、
///   `detail_days` 覆盖整个周期、`detailed_until` 为周期末、`forecast: null`）。
///   已有安排、固定事件、已完成事项和历史学习记录全部保持不变。
/// - 全量计划：显示“继续安排下一周期”，确认后延展周期并生成新周期的每日安排。
class ContinueCycleDialog extends ConsumerStatefulWidget {
  const ContinueCycleDialog({this.mode = ContinueCycleMode.nextCycle, super.key});

  final ContinueCycleMode mode;

  /// 旧滚动计划：补全本周期安排。
  static Future<bool> showCompleteCycle(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) =>
            const ContinueCycleDialog(mode: ContinueCycleMode.completeCurrent),
      ) ==
      true;

  /// 全量计划：继续安排下一周期。
  static Future<bool> showNextCycle(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) =>
            const ContinueCycleDialog(mode: ContinueCycleMode.nextCycle),
      ) ==
      true;

  /// 兼容旧入口（等同“继续安排下一周期”）。
  static Future<bool> show(BuildContext context) => showNextCycle(context);

  @override
  ConsumerState<ContinueCycleDialog> createState() => _ContinueCycleDialogState();
}

class _ContinueCycleDialogState extends ConsumerState<ContinueCycleDialog> {
  late final String _today = shanghaiToday();
  String? _start;
  String? _end;
  bool _busy = false;

  bool get _completing => widget.mode == ContinueCycleMode.completeCurrent;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerDataProvider).data;
    if (data == null) return const SizedBox.shrink();
    final cycleStart = data.profile.resolvedPlanStart(_today);
    final cycleEnd = data.profile.resolvedPlanEnd(_today);
    if (_completing) {
      return _buildComplete(context, data, cycleStart, cycleEnd);
    }
    return _buildNextCycle(context, data, cycleStart, cycleEnd);
  }

  Widget _buildComplete(
    BuildContext context,
    PlannerData data,
    String cycleStart,
    String cycleEnd,
  ) {
    final full = isFullPeriodPlan(data.planning);
    final completion = completePlanPeriod(data, today: _today);
    final summary = capacity.summarizePeriodCapacity(
      data.profile,
      cycleStart,
      cycleEnd,
    );
    final coverage = _coverageText(data);
    final body = <Widget>[
      Text('当前规划：$cycleStart 至 $cycleEnd'),
      const SizedBox(height: 8),
      if (full)
        const PlannerNotice(
          '当前已经是全周期计划，补全只会补齐仍然缺失的安排。',
          tone: PlannerNoticeTone.info,
        )
      else
        const PlannerNotice(
          '这是一次性升级：确认后本周期剩余日期都会生成正式每日安排，'
          '之后不再需要按窗口细化。',
          tone: PlannerNoticeTone.info,
        ),
      const SizedBox(height: 12),
      PlannerStat(label: '当前已有安排覆盖', value: coverage),
      PlannerStat(label: '已有安排保持不变', value: '${completion.protectedBlocks} 段'),
      PlannerStat(
        label: '本次新增安排',
        value:
            '${completion.addedBlocks} 段 · ${duration(completion.scheduledMinutes)}',
      ),
      PlannerStat(
        label: '仍未安排',
        value: duration(completion.unscheduledMinutes),
        tone: completion.unscheduledMinutes > 0 ? PlannerColors.orange : null,
      ),
      const SizedBox(height: 12),
      _capacityAssumptions(summary),
      for (final impact in completion.realDeadlineImpacts)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: PlannerNotice(impact, tone: PlannerNoticeTone.warning),
        ),
      for (final gap in completion.gaps)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: PlannerNotice(gap, tone: PlannerNoticeTone.warning),
        ),
      const SizedBox(height: 8),
      const Text(
        '已有安排、固定事件、历史学习记录和已完成事项保持不变；'
        '不会编造不存在的内容或改变真实截止日期。',
        style: TextStyle(color: PlannerColors.muted, fontSize: 12),
      ),
    ];
    return _dialog(
      context,
      title: '补全本周期安排',
      body: body,
      confirmLabel: full || completion.alreadyComplete ? '确认' : '确认补全并改为全周期计划',
      expected: data,
      next: completion.data,
      success:
          '已补全本周期安排：新增 ${completion.addedBlocks} 段，共 '
          '${duration(completion.scheduledMinutes)}。',
      blocked: null,
    );
  }

  Widget _buildNextCycle(
    BuildContext context,
    PlannerData data,
    String cycleStart,
    String cycleEnd,
  ) {
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
    final base = applyFullPeriodCycle(
      extended,
      today: _today,
      start: _start!,
      end: _end!,
    );
    final preview = generatePlanBlocks(base, from: _start!, to: _end!);
    final summary = capacity.summarizePeriodCapacity(
      data.profile,
      _start!,
      _end!,
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
    final uncovered = preview.unscheduledMinutes > 0
        ? preview.gaps
        : const <String>[];
    final body = <Widget>[
      Text('当前规划：$cycleStart 至 $cycleEnd'),
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
        value:
            '${preview.blocks} 段 · ${duration(preview.scheduledMinutes)}',
      ),
      PlannerStat(
        label: '仍未安排',
        value: duration(preview.unscheduledMinutes),
        tone: preview.unscheduledMinutes > 0 ? PlannerColors.orange : null,
      ),
      const SizedBox(height: 12),
      _capacityAssumptions(summary),
      for (final gap in uncovered)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: PlannerNotice(gap, tone: PlannerNoticeTone.warning),
        ),
      const SizedBox(height: 8),
      const Text(
        '已有安排、固定事件、历史学习记录和已完成事项保持不变。',
        style: TextStyle(color: PlannerColors.muted, fontSize: 12),
      ),
    ];
    return _dialog(
      context,
      title: '继续安排下一周期',
      body: body,
      confirmLabel: '确认并生成安排',
      expected: data,
      next: preview.data,
      success:
          '已生成下一周期安排：${preview.blocks} 段，共 '
          '${duration(preview.scheduledMinutes)}。',
      blocked: null,
    );
  }

  Widget _dialog(
    BuildContext context, {
    required String title,
    required List<Widget> body,
    required String confirmLabel,
    required PlannerData expected,
    required PlannerData next,
    required String success,
    required String? blocked,
  }) => AlertDialog(
    key: const ValueKey('cycle-dialog'),
    title: Text(title),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...body,
            if (blocked != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: PlannerNotice(blocked, tone: PlannerNoticeTone.error),
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
        key: const ValueKey('cycle-confirm'),
        onPressed: _busy || blocked != null
            ? null
            : () async {
                setState(() => _busy = true);
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final before = jsonEncode(expected.toJson());
                try {
                  await ref.read(plannerSessionProvider).edit((current) {
                    if (jsonEncode(current.toJson()) != before) {
                      throw StateError('计划已更新，请重新打开预览');
                    }
                    return next;
                  });
                  if (navigator.mounted) navigator.pop(true);
                  messenger.showSnackBar(SnackBar(content: Text(success)));
                } catch (error) {
                  if (mounted) setState(() => _busy = false);
                  messenger.showSnackBar(
                    SnackBar(content: Text('安排失败：$error')),
                  );
                }
              },
        icon: const Icon(Icons.event_repeat),
        label: Text(confirmLabel),
      ),
    ],
  );

  /// 容量假设说明（基线、范围、估算日、休息日），让用户看到完整周期建立在什么之上。
  Widget _capacityAssumptions(capacity.PeriodCapacitySummary summary) {
    final profile = ref.read(plannerDataProvider).data?.profile;
    if (profile == null) return const SizedBox.shrink();
    final label = capacity.capacityAssumptionLabel(profile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('容量假设', style: Theme.of(context).textTheme.titleSmall),
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${summary.from} 至 ${summary.to}：共 ${summary.dayCount} 天，'
            '可安排 ${duration(summary.totalMinutes)}；'
            '${summary.restDays} 天为 0 容量，'
            '${summary.estimatedDays} 天为按模板/基线生成的估算值。',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        for (final conflict in summary.weekConflicts)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: PlannerNotice(
              conflict.code == capacity.CapacityConflictCode.weekTotalExceeded
                  ? '包含 ${conflict.date ?? ''} 的一周：日期/逐日覆盖合计 '
                        '${duration(conflict.resolved)}，超过周总量 '
                        '${duration(conflict.total)}。'
                  : '某周的周总量 ${duration(conflict.total)} 无法分配到'
                        '非休息日（仅能安排 ${duration(conflict.resolved)}）。',
              tone: PlannerNoticeTone.warning,
            ),
          ),
      ],
    );
  }

  String _coverageText(PlannerData data) {
    if (data.blocks.isEmpty) return '暂无每日安排';
    var last = data.blocks.first.date;
    var first = data.blocks.first.date;
    for (final block in data.blocks) {
      if (block.date.compareTo(last) > 0) last = block.date;
      if (block.date.compareTo(first) < 0) first = block.date;
    }
    return '$first 至 $last';
  }
}
