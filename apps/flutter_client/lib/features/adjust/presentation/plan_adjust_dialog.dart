import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/domain/planner_format.dart' show duration;
import '../data/plan_adjust_api.dart';

/// AI 调整方案的预览对话框（契约 §3）：目标所需时长、周期 / 强度 / 工作量变化、
/// 日程影响、截止风险与提醒，用户确认后才会写入数据。
///
/// 取消（含点击遮罩 / 返回键）返回 false，不产生任何写入。
///
/// 视觉：Mist Ink / 雾蓝墨水。白底 + 14px 圆角 + 发丝边框；表头 / 表尾各一条
/// 发丝分隔线，表尾按钮右对齐；内容区独立滚动，按钮始终可见。
class PlanAdjustDialog extends StatelessWidget {
  const PlanAdjustDialog({required this.preview, super.key});

  final PlanAdjustPreview preview;

  /// 每个列表最多展示的条数，其余折叠为「另有 N 条」。
  static const int maxListRows = 10;

  static Future<bool> show(
    BuildContext context,
    PlanAdjustPreview preview,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => PlanAdjustDialog(preview: preview),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(
      640.0,
      math.max(280.0, MediaQuery.sizeOf(context).width - 64),
    );
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      titlePadding: EdgeInsets.zero,
      actionsPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.all(PlannerSpace.xl),
      content: _DialogFrame(
        width: width,
        title: '预览 AI 调整方案',
        subtitle: '确认后才会写入新计划；取消不会改动任何数据。',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _verdictBanner(),
            const SizedBox(height: PlannerSpace.md),
            Text(
              preview.assessment,
              key: const Key('plan-adjust-assessment'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
            _sectionTitle(context, '总学习时长'),
            PlannerStat(
              label: '目标所需总时长',
              value:
                  '${hoursText(preview.hours.requiredMinMinutes)}–'
                  '${hoursText(preview.hours.requiredMaxMinutes)} 小时',
            ),
            PlannerStat(
              label: '当前计划总时长',
              value: '${hoursText(preview.hours.currentMinutes)} 小时',
            ),
            PlannerStat(
              label: '调整后总时长',
              value: '${hoursText(preview.hours.nextMinutes)} 小时',
              valueKey: const Key('plan-adjust-next-hours'),
            ),
            PlannerStat(
              label: '调整后剩余工作量',
              value: '${hoursText(preview.hours.remainingMinutes)} 小时',
            ),
            _sectionTitle(context, '规划周期'),
            PlannerStat(
              label: '原周期',
              value:
                  '${preview.cycle.startDate} 至 '
                  '${preview.cycle.previousEndDate}',
            ),
            PlannerStat(
              label: '新周期',
              value:
                  '${preview.cycle.startDate} 至 ${preview.cycle.endDate}'
                  '（${_deltaDaysLabel(preview.cycle.deltaDays)}）',
              valueKey: const Key('plan-adjust-cycle-new'),
            ),
            PlannerStat(
              label: '周期长度',
              value:
                  '${preview.cycle.previousDays} 天 → '
                  '${preview.cycle.days} 天',
            ),
            PlannerStat(
              label: '剩余天数',
              value: '${preview.cycle.remainingDays} 天',
            ),
            _sectionTitle(context, '学习强度'),
            PlannerStat(
              label: '每周可用时长',
              value: _intensityLabel(preview.intensity),
              valueKey: const Key('plan-adjust-intensity'),
            ),
            if (preview.intensity.reason.isNotEmpty)
              _mutedText(preview.intensity.reason),
            ..._workloadSection(context),
            _sectionTitle(context, '日程影响'),
            PlannerStat(
              label: '保持不变（保护）',
              value: '${preview.schedule.protectedBlocks} 段',
            ),
            PlannerStat(
              label: '释放并重排',
              value:
                  '${preview.schedule.releasedBlocks} 段 · '
                  '${duration(preview.schedule.releasedMinutes)}',
            ),
            PlannerStat(
              label: '新排入',
              value:
                  '${preview.schedule.addedBlocks} 段 · '
                  '${duration(preview.schedule.addedMinutes)}',
            ),
            PlannerStat(
              label: '仍未安排',
              value: duration(preview.schedule.unscheduledMinutes),
              tone: preview.schedule.unscheduledMinutes > 0
                  ? PlannerColors.orange
                  : null,
            ),
            ..._deadlineRiskSection(context),
            ..._warningSection(context),
            ..._noteSection(context),
          ],
        ),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('plan-adjust-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            const SizedBox(width: PlannerSpace.sm),
            FilledButton.icon(
              key: const Key('plan-adjust-confirm'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check, size: 17),
              label: const Text('确认并应用'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verdictBanner() {
    final (color, background, border) = switch (preview.verdict) {
      PlanAdjustVerdict.reasonable => (
        PlannerColors.green,
        const Color(0xffeef7f2),
        const Color(0xffcfe7db),
      ),
      PlanAdjustVerdict.tooLight => (
        PlannerColors.orange,
        const Color(0xfffdf6e8),
        const Color(0xffecd9b0),
      ),
      PlanAdjustVerdict.tooHeavy => (
        PlannerColors.danger,
        const Color(0xfffcefed),
        const Color(0xfff0ccc7),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PlannerSpace.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(PlannerRadius.control),
      ),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined, size: 18, color: color),
          const SizedBox(width: PlannerSpace.sm),
          Text('AI 审查结论', style: TextStyle(color: color, fontSize: 12.5)),
          const SizedBox(width: PlannerSpace.sm),
          Expanded(
            child: Text(
              preview.verdict.label,
              key: const Key('plan-adjust-verdict'),
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- 工作量变化

  List<Widget> _workloadSection(BuildContext context) {
    final workload = preview.workload;
    if (workload.updatedTasks.isEmpty && workload.newTasks.isEmpty) {
      return const [];
    }
    final updated = workload.updatedTasks
        .take(maxListRows)
        .map(_updatedRow)
        .toList();
    final created = workload.newTasks.take(maxListRows).map(_newRow).toList();
    return [
      _sectionTitle(context, '工作量变化'),
      if (updated.isNotEmpty) ...[
        _listHeading('调整事项'),
        ...updated,
        if (workload.updatedTasks.length > maxListRows)
          _moreLabel(workload.updatedTasks.length - maxListRows),
      ],
      if (created.isNotEmpty) ...[
        _listHeading('新增事项'),
        ...created,
        if (workload.newTasks.length > maxListRows)
          _moreLabel(workload.newTasks.length - maxListRows),
      ],
    ];
  }

  Widget _updatedRow(PlanAdjustUpdatedTask task) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: PlannerSpace.sm),
              Text(
                '${hoursText(task.previousMinutes)} → '
                '${hoursText(task.minutes)} 小时',
                style: tabularFigures.copyWith(
                  fontSize: 12.5,
                  color: PlannerColors.muted,
                ),
              ),
            ],
          ),
          if (task.tagNames.isNotEmpty || task.reason.isNotEmpty)
            _mutedText(
              [
                if (task.tagNames.isNotEmpty) '标签：${task.tagNames.join('、')}',
                if (task.reason.isNotEmpty) task.reason,
              ].join(' · '),
            ),
        ],
      ),
    );
  }

  Widget _newRow(PlanAdjustNewTask task) {
    final meta = [
      if (task.tagNames.isNotEmpty) '标签：${task.tagNames.join('、')}',
      if (task.deadline != null && task.deadline!.isNotEmpty)
        '${task.deadlineKind == ItemDateKind.planEnd ? '本期边界' : '截止'} '
            '${task.deadline}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: PlannerSpace.sm),
              Text(
                '新增 ${hoursText(task.minutes)} 小时',
                style: tabularFigures.copyWith(
                  fontSize: 12.5,
                  color: PlannerColors.muted,
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty || task.reason.isNotEmpty)
            _mutedText(
              [
                if (meta.isNotEmpty) meta.join(' · '),
                if (task.reason.isNotEmpty) task.reason,
              ].join(' · '),
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- 风险 / 提醒 / 说明

  List<Widget> _deadlineRiskSection(BuildContext context) {
    if (preview.deadlineRisks.isEmpty) return const [];
    return [
      _sectionTitle(context, '截止风险'),
      for (final risk in preview.deadlineRisks)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${risk.title} · 截止 ${risk.deadline}',
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
              const SizedBox(width: PlannerSpace.sm),
              Text(
                '未排 ${duration(risk.unscheduledMinutes)}',
                style: tabularFigures.copyWith(
                  fontSize: 12.5,
                  color: PlannerColors.orange,
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _warningSection(BuildContext context) {
    if (preview.warnings.isEmpty) return const [];
    return [
      _sectionTitle(context, '提醒'),
      for (final warning in preview.warnings)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: PlannerColors.orange,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning,
                  style: const TextStyle(
                    color: PlannerColors.orange,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _noteSection(BuildContext context) {
    if (preview.notes.isEmpty) return const [];
    return [
      _sectionTitle(context, '说明'),
      for (final note in preview.notes)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _mutedText(note),
        ),
    ];
  }

  // ------------------------------------------------------------------ 小工具

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(top: PlannerSpace.lg, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 13.5,
        height: 1.5,
        fontWeight: FontWeight.w600,
        color: PlannerColors.text,
      ),
    ),
  );

  Widget _listHeading(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(
      title,
      style: const TextStyle(
        color: PlannerColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
  );

  Widget _mutedText(String value) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      value,
      style: const TextStyle(
        color: PlannerColors.muted,
        fontSize: 12.5,
        height: 1.5,
      ),
    ),
  );

  Widget _moreLabel(int count) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      '另有 $count 条',
      style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
    ),
  );

  String _intensityLabel(PlanAdjustIntensity intensity) {
    final previous = intensity.previousWeeklyMinutes;
    final next = intensity.weeklyMinutes;
    final previousLabel = previous == null || previous <= 0
        ? '未设置'
        : duration(previous);
    final nextLabel = next == null ? '未设置' : duration(next);
    final change = previous != null && previous > 0 && next != null
        ? '（${_percentChange(previous, next)}）'
        : '';
    return '$previousLabel → $nextLabel$change';
  }

  String _percentChange(int previous, int next) {
    final percent = ((next - previous) / previous * 100).round();
    return '${percent >= 0 ? '+' : ''}$percent%';
  }

  String _deltaDaysLabel(int delta) {
    if (delta == 0) return '周期不变';
    return '${delta > 0 ? '+' : ''}$delta 天';
  }
}

/// 统一的对话框外壳：20–24 内边距、表头 / 表尾发丝分隔线、按钮右对齐。
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.width,
    required this.title,
    required this.body,
    required this.actions,
    this.subtitle,
  });

  final double width;
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hairline = plannerHairline(context);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlannerSpace.xl,
              20,
              PlannerSpace.xl,
              14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: PlannerColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(height: hairline, color: PlannerColors.border),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                PlannerSpace.xl,
                18,
                PlannerSpace.xl,
                18,
              ),
              child: body,
            ),
          ),
          Container(height: hairline, color: PlannerColors.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlannerSpace.xl,
              14,
              PlannerSpace.xl,
              16,
            ),
            child: actions,
          ),
        ],
      ),
    );
  }
}

/// 分钟换算成小时：整数小时不带小数，否则保留一位小数。
String hoursText(int minutes) {
  if (minutes <= 0) return '0';
  final hours = minutes / 60;
  return hours == hours.roundToDouble()
      ? '${hours.round()}'
      : hours.toStringAsFixed(1);
}
