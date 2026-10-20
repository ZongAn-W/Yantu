import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../core/sync/sync_state.dart';
import '../../../shared/models/planner_models.dart';
import '../../dashboard/presentation/today_scroll.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/capacity.dart' as capacity;
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/progress_metrics.dart';
import '../../planner/domain/scheduler/planner_scheduler.dart' show newUuid;
import '../../planner/presentation/planner_page_state.dart';
import '../../settings/presentation/capacity_overrides_dialog.dart';
import '../data/plan_adjust_api.dart';
import 'plan_adjust_dialog.dart';

/// Web `/adjust` — 把影响后续排程的四类信息放在一页：人物画像、事项完成度、
/// 近期可用时间与当前规划周期，并提供一次「一键调整后续计划」的 AI 预览与确认。
///
/// 调整由服务端 AI 基于画像、学习进度、近期学习时间与当前计划生成方案：
/// 先在预览对话框展示目标所需时长、周期 / 强度 / 工作量变化与日程影响，
/// 用户确认后才由服务端原子写入并推进 revision。历史、已完成、固定和有实际
/// 用时的记录由服务端保护，事项与真实截止日期不会被删除或改写。
///
/// 视觉：Mist Ink / 雾蓝墨水。左栏（约 2/3）放人物画像与近期学习时间，
/// 右栏（380）放学习进度与唯一主操作「一键调整」；< 1100 宽改为单栏。
class AdjustPlanPage extends ConsumerStatefulWidget {
  const AdjustPlanPage({super.key});

  @override
  ConsumerState<AdjustPlanPage> createState() => _AdjustPlanPageState();
}

/// 页面正文级说明：13 / 1.6，不再用 11–12px 密集小字。
TextStyle _bodyStyle(PlannerTokens tokens) =>
    TextStyle(fontSize: 13, height: 1.6, color: tokens.muted);

/// 辅助说明 / 元信息：12.5 / 1.5。
TextStyle _metaStyle(PlannerTokens tokens) =>
    TextStyle(fontSize: 12.5, height: 1.5, color: tokens.muted);

/// 表单字段标签：12.5 muted，和值形成弱对比。
TextStyle _labelStyle(PlannerTokens tokens) =>
    TextStyle(fontSize: 12.5, height: 1.4, color: tokens.muted);

class _AdjustPlanPageState extends ConsumerState<AdjustPlanPage> {
  bool _applying = false;

  /// 一键调整：让服务端 AI 生成方案，预览确认后原子应用并拉取新计划。
  ///
  /// 本机存在未同步修改时不允许发起，避免服务端基于旧 revision 调整；
  /// 取消预览不会写入任何数据，失败时保留原计划。
  Future<void> _applyAdjustment() async {
    if (_applying) return;
    final snapshot = ref.read(plannerDataProvider);
    final data = snapshot.data;
    if (data == null) return;
    if (snapshot.pending) {
      showPlannerMessage(
        context,
        '本机修改尚未同步，请等待同步完成后再调整',
        tone: PlannerNoticeTone.warning,
      );
      return;
    }
    final expectedRevision = snapshot.revision;
    final api = ref.read(planAdjustApiProvider);
    setState(() => _applying = true);
    try {
      final preview = await api.create(
        expectedRevision: expectedRevision,
        requestId: newUuid(),
      );
      if (!mounted) return;
      final confirmed = await PlanAdjustDialog.show(context, preview);
      if (!mounted || !confirmed) return;
      // 预览期间云端计划可能已被其他端修改；revision 以发起预览时的快照为准，
      // 服务端校验不一致会返回 409 并要求重新预览。
      await api.confirm(preview.id, expectedRevision: expectedRevision);
      if (!mounted) return;
      try {
        await ref.read(plannerSessionProvider).sync();
      } catch (error) {
        if (!mounted) return;
        showPlannerMessage(
          context,
          '调整已提交，正在同步新计划：${_errorMessage(error)}',
          tone: PlannerNoticeTone.warning,
        );
        return;
      }
      final afterSync = ref.read(plannerDataProvider);
      if (afterSync.pending ||
          afterSync.status == SyncStatus.error ||
          afterSync.status == SyncStatus.offline ||
          afterSync.status == SyncStatus.conflict) {
        if (!mounted) return;
        showPlannerMessage(
          context,
          '调整已提交，但本机尚未完成同步：${afterSync.message}',
          tone: PlannerNoticeTone.warning,
        );
        return;
      }
      if (!mounted) return;
      showPlannerMessage(
        context,
        'AI 已按目标、学习进度与近期学习时间重排后续计划。',
        tone: PlannerNoticeTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      showPlannerMessage(
        context,
        _errorMessage(error),
        tone: PlannerNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  /// 服务端 409 / 校验失败已经带有可读中文消息，直接展示；其他异常退回字符串。
  String _errorMessage(Object error) {
    if (error is StateError) return error.message;
    final message = '$error';
    return message.isEmpty ? '调整失败，请稍后重试' : message;
  }

  /// 打开容量编辑器；返回 true 表示容量已保存，提示用户回到本页用 AI 调整。
  Future<void> _editCapacity() async {
    final changed = await CapacityOverridesDialog.show(context);
    if (!mounted) return;
    if (!changed) return;
    showPlannerMessage(
      context,
      '可用时间已更新，可继续用「一键调整后续计划」让 AI 调整未来安排。',
      tone: PlannerNoticeTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final today = shanghaiToday();
        final metrics = progressMetrics(
          data,
          date: today,
          month: today.substring(0, 7),
        );
        return PlannerPage(
          title: '调整学习计划',
          subtitle: '画像、进度、时间有变化后，让 AI 审查并调整后续安排。',
          children: [_content(context, snapshot, data, metrics, today)],
        );
      },
    );
  }

  /// 主体：桌面为左栏（约 2/3）+ 右栏（380）两栏；< 1100 逻辑像素改为单栏。
  Widget _content(
    BuildContext context,
    PlannerSnapshot snapshot,
    PlannerData data,
    ProgressMetrics metrics,
    String today,
  ) {
    final profile = _profilePanel(context, data.profile, today);
    final progress = _progressPanel(context, data, metrics);
    final time = _capacityPanel(data, today);
    final apply = _applyPanel(snapshot, data, metrics, today);
    if (MediaQuery.sizeOf(context).width < 1100) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          profile,
          const SizedBox(height: PlannerSpace.xl),
          progress,
          const SizedBox(height: PlannerSpace.xl),
          time,
          const SizedBox(height: PlannerSpace.xl),
          apply,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              profile,
              const SizedBox(height: PlannerSpace.lg),
              time,
            ],
          ),
        ),
        const SizedBox(width: PlannerSpace.xl),
        SizedBox(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              progress,
              const SizedBox(height: PlannerSpace.lg),
              apply,
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- 人物画像

  Widget _profilePanel(BuildContext context, Profile profile, String today) {
    final text = Theme.of(context).textTheme;
    final target = profile.resolvedTargetDate;
    final targetLabel = target.isEmpty
        ? '未设置'
        : profile.targetDateConfirmed
        ? target
        : '预计 $target';
    final goal = profile.goalSubtype.isNotEmpty
        ? profile.goalSubtype
        : profile.goalText.isNotEmpty
        ? profile.goalText
        : '尚未填写';
    final school = [
      profile.targetSchool,
      profile.targetProgram,
    ].where((value) => value.isNotEmpty).join(' · ');
    final assumption = capacity.capacityAssumptionLabel(profile);
    final goalTypeLabel = goalTypeLabels[profile.goalType];
    return PlannerPanel(
      key: const Key('adjust-profile'),
      title: '人物画像',
      subtitle: '来自目标访谈与设置，可继续补充',
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: PlannerSpace.sm,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                goalHeadline(profile),
                style: text.titleSmall?.copyWith(fontSize: 14.5, height: 1.45),
              ),
              if (goalTypeLabel != null)
                PlannerTag(label: goalTypeLabel, color: context.tokens.accent),
              Text(
                goalStatusLine(profile, today),
                style: _metaStyle(
                  context.tokens,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: PlannerSpace.lg),
          _ProfileField(label: '目标', value: goal),
          _ProfileField(label: '目标日期', value: targetLabel),
          _ProfileField(label: '院校专业', value: school.isEmpty ? '未填写' : school),
          _ProfileField(
            label: '当前进度',
            value: profile.foundation.isEmpty ? '未填写' : profile.foundation,
          ),
          _ProfileField(
            label: '时间约束',
            value: profile.constraints.isEmpty ? '未填写' : profile.constraints,
          ),
          if (assumption.isNotEmpty)
            _ProfileField(label: '可用时间口径', value: assumption),
          const SizedBox(height: PlannerSpace.sm),
          const _PanelDivider(),
          const SizedBox(height: PlannerSpace.md),
          Wrap(
            spacing: PlannerSpace.sm,
            runSpacing: PlannerSpace.sm,
            children: [
              OutlinedButton.icon(
                key: const Key('adjust-interview'),
                onPressed: () => context.go('/interview'),
                icon: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('继续访谈完善画像'),
              ),
              OutlinedButton.icon(
                key: const Key('adjust-settings'),
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings_outlined, size: 16),
                label: const Text('修改目标与规划'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- 学习进度

  Widget _progressPanel(
    BuildContext context,
    PlannerData data,
    ProgressMetrics metrics,
  ) {
    final tokens = context.tokens;
    final tagNames = {for (final tag in data.tags) tag.id: tag.name};
    final tasks =
        [
          for (final task in data.tasks)
            if (task.status != TaskStatus.archived) task,
        ]..sort((a, b) {
          final deadline = a.deadline.compareTo(b.deadline);
          if (deadline != 0) return deadline;
          return a.title.compareTo(b.title);
        });
    final shown = tasks.take(6).toList();
    final status = metrics.lagging
        ? '落后于计划节奏'
        : metrics.forecast == null
        ? '记录学习后可估算节奏'
        : '按当前节奏推进';
    final tone = metrics.lagging
        ? tokens.warning
        : metrics.forecast == null
        ? null
        : tokens.success;
    return PlannerPanel(
      key: const Key('adjust-progress'),
      title: '学习进度',
      subtitle: '最多展示 6 个未归档事项',
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MetricTile(
                  label: '累计实际学习',
                  value: duration(metrics.totalActual),
                  valueKey: const Key('adjust-total-actual'),
                ),
              ),
              const SizedBox(width: PlannerSpace.lg),
              Expanded(
                child: MetricTile(
                  label: '剩余工作量',
                  value: duration(metrics.remainingMinutes),
                ),
              ),
            ],
          ),
          const SizedBox(height: PlannerSpace.md),
          PlannerStat(label: '进度状态', value: status, tone: tone),
          const SizedBox(height: PlannerSpace.md),
          const _PanelDivider(),
          if (shown.isEmpty) ...[
            const PlannerEmpty(
              message: '还没有学习事项。',
              hint: '先完成学习目标访谈，再在今日页「全部事项」中创建事项。',
              icon: Icons.list_alt_outlined,
            ),
          ] else ...[
            for (var index = 0; index < shown.length; index++) ...[
              if (index > 0) const _PanelDivider(),
              _TaskProgressRow(
                task: shown[index],
                tagNames: [
                  for (final id in shown[index].tagIds)
                    if (tagNames[id] case final name?) name,
                ],
              ),
            ],
            if (tasks.length > shown.length) ...[
              const SizedBox(height: PlannerSpace.sm),
              Text(
                '另有 ${tasks.length - shown.length} 个事项未展示，可在今日页「全部事项」中查看。',
                style: _metaStyle(context.tokens),
              ),
            ],
          ],
          const SizedBox(height: PlannerSpace.sm),
          Wrap(
            spacing: PlannerSpace.xs,
            runSpacing: PlannerSpace.xs,
            children: [
              TextButton.icon(
                key: const Key('adjust-progress-view'),
                onPressed: () => context.go('/calendar'),
                icon: const Icon(Icons.bar_chart_outlined, size: 16),
                label: const Text('查看完整进度'),
              ),
              TextButton.icon(
                key: const Key('adjust-tasks-manage'),
                onPressed: () {
                  TodayItemsScrollRequest.request();
                  context.go('/');
                },
                icon: const Icon(Icons.list_alt_outlined, size: 16),
                label: const Text('查看全部事项'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- 近期学习时间

  Widget _capacityPanel(PlannerData data, String today) {
    final profile = data.profile;
    final days = [
      for (var index = 0; index < 7; index++) addDate(today, index),
    ];
    final scheduledByDate = <String, int>{};
    for (final block in data.blocks) {
      scheduledByDate.update(
        block.date,
        (value) => value + block.durationMinutes,
        ifAbsent: () => block.durationMinutes,
      );
    }
    final recentFrom = addDate(today, -6);
    final recentActual = data.logs
        .where(
          (log) =>
              log.date.compareTo(recentFrom) >= 0 &&
              log.date.compareTo(today) <= 0,
        )
        .fold<int>(0, (sum, log) => sum + log.minutes);
    final assumption = capacity.capacityAssumptionLabel(profile);
    return PlannerPanel(
      key: const Key('adjust-capacity'),
      title: '近期学习时间',
      subtitle: '今天起 7 天 · 可用净分钟与已排分钟',
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final date in days)
            _DayCapacityStat(
              key: Key('adjust-capacity-day-$date'),
              date: date,
              available: capacity.resolveDayCapacity(profile, date).minutes,
              scheduled: scheduledByDate[date] ?? 0,
            ),
          const SizedBox(height: PlannerSpace.md),
          const _PanelDivider(),
          const SizedBox(height: PlannerSpace.sm),
          PlannerStat(
            label: '最近 7 天实际用时',
            value: duration(recentActual),
            valueKey: const Key('adjust-recent-actual'),
          ),
          if (assumption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: PlannerSpace.xs),
              child: Text(
                '容量口径：$assumption',
                style: _metaStyle(context.tokens),
              ),
            ),
          const SizedBox(height: PlannerSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('adjust-capacity-edit'),
              onPressed: _editCapacity,
              icon: const Icon(Icons.tune_outlined, size: 16),
              label: const Text('调整可用时间'),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- 一键调整

  Widget _applyPanel(
    PlannerSnapshot snapshot,
    PlannerData data,
    ProgressMetrics metrics,
    String today,
  ) {
    final profile = data.profile;
    final start = profile.resolvedPlanStart(today);
    final end = profile.resolvedPlanEnd(today);
    final ended = today.compareTo(end) > 0;
    final remainingDays = ended ? 0 : daysBetween(today, end) + 1;
    final pendingTasks = [
      for (final task in data.tasks)
        if (task.status != TaskStatus.archived &&
            task.status != TaskStatus.completed &&
            task.estimatedMinutes > task.completedMinutes)
          task,
    ];
    final enabled = snapshot.editable && !ended && !_applying;
    return PlannerPanel(
      title: '一键调整',
      subtitle: ended ? '本期规划周期已结束' : 'AI 审查目标所需时长与当前计划是否匹配',
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '本次规划周期：$start 至 $end',
            key: const Key('adjust-cycle-range'),
            style: tabularFigures.copyWith(
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: PlannerSpace.md),
          PlannerStat(label: '剩余天数', value: ended ? '已结束' : '$remainingDays 天'),
          PlannerStat(label: '待安排事项', value: '${pendingTasks.length} 个'),
          PlannerStat(
            label: '剩余工作量',
            value: duration(metrics.remainingMinutes),
          ),
          if (ended) ...[
            const SizedBox(height: PlannerSpace.md),
            const PlannerNotice(
              '本期规划周期已结束，请先在今日页继续安排下一周期。',
              tone: PlannerNoticeTone.warning,
            ),
          ],
          const SizedBox(height: PlannerSpace.md),
          const _PanelDivider(),
          const SizedBox(height: PlannerSpace.md),
          Text(
            'AI 会审查目标所需时长与当前计划是否匹配，必要时调整周期、强度和工作量，'
            '可能需要 1–2 分钟。历史日期、已完成安排和有实际用时的记录'
            '保持不变；事项范围与真实截止日期不会被改写。',
            style: _bodyStyle(context.tokens),
          ),
          const SizedBox(height: PlannerSpace.lg),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              key: const Key('adjust-apply'),
              onPressed: enabled ? _applyAdjustment : null,
              icon: Icon(
                _applying ? Icons.hourglass_top : Icons.auto_fix_high,
                size: 18,
              ),
              label: Text(_applying ? 'AI 正在调整…' : '一键调整后续计划'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 面板内部的发丝分隔线：比默认 Divider 更薄，避免密集列表出现重线条。
class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: plannerHairline(context),
    color: context.tokens.border,
  );
}

/// 画像中的一段文字信息：标签在上、值在下，长文本自然换行，窄屏不横向溢出。
class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle(context.tokens)),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.55,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

/// 某一天：可用净分钟与已经排入的分钟；已排超过可用时用橙色提示。
class _DayCapacityStat extends StatelessWidget {
  const _DayCapacityStat({
    required this.date,
    required this.available,
    required this.scheduled,
    super.key,
  });

  final String date;
  final int available;
  final int scheduled;

  @override
  Widget build(BuildContext context) => PlannerStat(
    label: '${monthDayLabel(date)} ${weekdayLabel(date)}',
    value: '可排 ${duration(available)} · 已排 ${duration(scheduled)}',
    tone: scheduled > available ? context.tokens.warning : null,
  );
}

/// 一个未归档事项的完成度：完成分钟 / 预算分钟、百分比与日期语义。
class _TaskProgressRow extends StatelessWidget {
  const _TaskProgressRow({required this.task, required this.tagNames});

  final Task task;
  final List<String> tagNames;

  @override
  Widget build(BuildContext context) {
    final estimated = task.estimatedMinutes;
    final completed = task.completedMinutes;
    // 实际完成分钟可能超过预算，进度条与百分比都封顶到 100%。
    final ratio = estimated <= 0
        ? 0.0
        : (completed / estimated).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    final dateLabel = task.deadlineKind == ItemDateKind.deadline
        ? '真实截止'
        : '本期边界';
    final deadline = task.deadline.isEmpty
        ? '$dateLabel 未设置'
        : '$dateLabel ${task.deadline}';
    final meta = [
      if (tagNames.isNotEmpty) tagNames.join('、'),
      statusLabels[task.status] ?? '进行中',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: PlannerSpace.sm,
            runSpacing: 2,
            children: [
              Text(
                task.title,
                key: Key('adjust-task-title-${task.id}'),
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(meta, style: _metaStyle(context.tokens)),
            ],
          ),
          const SizedBox(height: 6),
          TimeProgressTrack(
            planned: estimated,
            actual: completed,
            color: context.tokens.accent,
            semanticsLabel: '${task.title}完成度',
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: PlannerSpace.md,
            runSpacing: 2,
            children: [
              Text(
                '完成 ${duration(completed)} / 预算 ${duration(estimated)} · '
                '$percent%',
                style: tabularFigures.copyWith(fontSize: 12.5),
              ),
              Text(deadline, style: _metaStyle(context.tokens)),
            ],
          ),
        ],
      ),
    );
  }
}
