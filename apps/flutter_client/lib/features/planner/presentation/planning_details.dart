import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/plan_cycle.dart';
import '../domain/planner_format.dart';

List<JsonMap> planningEntries(dynamic value) => value is List
    ? value.whereType<Map>().map((entry) => JsonMap.from(entry)).toList()
    : const [];

String planningText(dynamic value) => value is String ? value : '';

/// `planning` 元数据里的容量假设说明（服务端写入 `planning.capacity`）。
///
/// 旧计划没有该字段时返回空列表，界面只显示周期覆盖信息。
List<String> planningCapacityLines(JsonMap? planning) {
  final raw = planning?['capacity'];
  if (raw is! Map) return const [];
  final data = JsonMap.from(raw);
  final lines = <String>[];
  final basis = capacityText(data['basis']);
  if (basis.isNotEmpty) {
    lines.add(
      basis == 'net'
          ? '容量口径：净学习时间（输入即净预算，不再机械扣除机动）'
          : '容量口径：总预算口径（旧数据语义，每日先扣机动时间）',
    );
  }
  final adopted = data['adopted_weekly_minutes'];
  final source = capacityText(data['source']);
  if (adopted is num) {
    lines.add(
      '采用周容量：${duration(adopted.toInt())}'
      '${switch (source) {
        'baseline' => '（用户确认的保守基线）',
        'range_min' => '（容量范围下限）',
        'template' => '（默认每周模板）',
        'legacy_default' => '（旧版每日上限）',
        _ => '',
      }}',
    );
  }
  final range = data['weekly_range_minutes'];
  if (range is Map && range['min'] is num && range['max'] is num) {
    lines.add(
      '大致周容量范围：${duration((range['min'] as num).toInt())}–'
      '${duration((range['max'] as num).toInt())}；较高容量情景下可达到更高覆盖',
    );
  }
  final estimatedWeeks = data['estimated_weeks'] ?? data['weeks_estimated'];
  if (estimatedWeeks is num && estimatedWeeks > 0) {
    lines.add('其中 ${estimatedWeeks.toInt()} 周为按模板/基线生成的估算分配，不是逐日确认');
  }
  final weekOverrides = data['week_override_count'];
  final dateOverrides = data['date_override_count'];
  if (weekOverrides is num && weekOverrides > 0) {
    lines.add('已设置 ${weekOverrides.toInt()} 个特定周容量');
  }
  if (dateOverrides is num && dateOverrides > 0) {
    lines.add('已设置 ${dateOverrides.toInt()} 个特定日期容量（0 分钟表示休息）');
  }
  if (capacityText(data['partial_week_rule']).isNotEmpty) {
    lines.add('与周期部分相交的周按完整自然周分配，周期只使用相交日期，不会重复收取整周预算');
  }
  final conflicts = data['conflicts'];
  if (conflicts is List) {
    for (final conflict in conflicts.whereType<Map>()) {
      final code = capacityText(conflict['code']);
      lines.add(
        code == 'WEEK_TOTAL_EXCEEDED'
            ? '容量设置冲突：某周日期/逐日覆盖合计 ${duration((conflict['resolved'] as num? ?? 0).toInt())}，'
                  '超过周总量 ${duration((conflict['total'] as num? ?? 0).toInt())}'
            : '容量设置冲突：某周周总量无法分配到非休息日'
                  '（仅能安排 ${duration((conflict['resolved'] as num? ?? 0).toInt())}）',
      );
    }
  }
  final assumptions = data['assumptions'];
  if (assumptions is List) {
    for (final item in assumptions.whereType<String>()) {
      lines.add(item);
    }
  }
  return lines;
}

String capacityText(dynamic value) => value is String ? value : '';

/// Route metadata explains the two-level plan without adding another task tree.
class PlanningRouteView extends StatelessWidget {
  const PlanningRouteView({
    required this.planning,
    this.compact = false,
    super.key,
  });
  final JsonMap? planning;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (planning == null) return const SizedBox.shrink();
    final routes = planningEntries(planning!['route']);
    final milestones = planningEntries(planning!['milestones']);
    final until = planningText(planning!['detailed_until']);
    final full = isFullPeriodPlan(planning);
    final capacityLines = planningCapacityLines(planning);
    final subtitle = full
        ? (until.isEmpty
              ? '每日安排已覆盖整个规划周期'
              : '每日安排已覆盖整个规划周期（至 $until）')
        : until.isEmpty
        ? '当前为滚动计划，每日安排会随周期逐步补齐'
        : '滚动计划：每日安排细化至 $until，可补全本周期安排';
    return ExpansionTile(
      key: const ValueKey('planning-route'),
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: !compact,
      title: const Text('学习路线', style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      children: [
        if (planning?['needs_review'] == true)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: PlannerNotice(
              '进度或条件有变化，请核对后续范围与估算。',
              tone: PlannerNoticeTone.warning,
            ),
          ),
        for (final line in capacityLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(line, style: const TextStyle(fontSize: 12)),
            ),
          ),
        for (final route in routes)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    planningText(route['title']),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (planningText(
                        route['starts_on'] ?? route['start_date'],
                      ).isNotEmpty ||
                      planningText(
                        route['ends_on'] ?? route['end_date'],
                      ).isNotEmpty)
                    Text(
                      '${planningText(route['starts_on'] ?? route['start_date']).isEmpty ? '待定' : route['starts_on'] ?? route['start_date']} 至 ${planningText(route['ends_on'] ?? route['end_date']).isEmpty ? '待定' : route['ends_on'] ?? route['end_date']}',
                      style: const TextStyle(color: PlannerColors.muted),
                    ),
                  if (planningText(route['objective']).isNotEmpty)
                    Text(planningText(route['objective'])),
                  if (planningText(route['outcome']).isNotEmpty)
                    Text('阶段成果：${route['outcome']}'),
                  if (planningText(route['check']).isNotEmpty)
                    Text('检查条件：${route['check']}'),
                ],
              ),
            ),
          ),
        for (final milestone in milestones)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined, size: 20),
            title: Text(planningText(milestone['title'])),
            subtitle: Text(
              [
                if (planningText(
                  milestone['date_value'] ?? milestone['date'],
                ).isNotEmpty)
                  '${milestone['date_value'] ?? milestone['date']}',
                switch (milestone['source_kind'] ?? milestone['date_kind']) {
                  'user' => '用户提供',
                  'verified' => '资料已核实',
                  'unknown' => '日期待定',
                  _ => '建议目标',
                },
                if (planningText(milestone['basis']).isNotEmpty)
                  '${milestone['basis']}',
              ].join(' · '),
            ),
          ),
        for (final (key, label) in [
          ('assumptions', '估算前提'),
          ('risks', '需要留意'),
          ('uncovered', '尚未覆盖/本期范围外'),
          ('unscheduled', '未能排入'),
        ])
          if (planning![key] is List && (planning![key] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$label：${_entryLabels(planning![key] as List)}',
                ),
              ),
            ),
      ],
    );
  }

  /// 结构化条目转成可读文本；条目可带 minutes 表示缺口分钟数。
  String _entryLabels(List entries) => entries
      .map((entry) {
        if (entry is! Map) return '$entry';
        final message = planningText(entry['message'] ?? entry['title']);
        final minutes = entry['minutes'];
        final suffix = minutes is num && minutes > 0
            ? '（${duration(minutes.toInt())}）'
            : '';
        return '$message$suffix';
      })
      .join('；');
}

class WorkloadDetails extends StatelessWidget {
  const WorkloadDetails({required this.planning, super.key});
  final JsonMap? planning;

  @override
  Widget build(BuildContext context) {
    if (planning == null) return const SizedBox.shrink();
    final workload = planning!['workload'] is Map
        ? JsonMap.from(planning!['workload'] as Map)
        : <String, dynamic>{};
    final activity = planning!['activity'] is Map
        ? JsonMap.from(planning!['activity'] as Map)
        : <String, dynamic>{};
    final dependencies = planningEntries(planning!['dependencies']);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final component in planningEntries(workload['components']))
            Text(
              '${component['selected'] == false ? '备选，未计入：' : ''}${planningText(component['label'])} '
              '${component['quantity'] ?? ''} ${planningText(component['unit'])} × '
              '${component['minutes_per_unit'] ?? ''} 分钟',
            ),
          if (planningText(workload['source']).isNotEmpty)
            Text('估算依据：${workload['source']}'),
          if (planningText(workload['confidence']).isNotEmpty)
            Text(
              '估算可信度：${switch (workload['confidence']) {
                'high' => '较高',
                'medium' => '一般',
                'low' => '待校准',
                _ => workload['confidence'],
              }}',
            ),
          if (planningText(workload['calibration']).isNotEmpty)
            Text('校准方式：${workload['calibration']}'),
          if (activity['kind'] == 'recurring')
            Text(
              '持续练习：每周 ${activity['sessions_per_week'] ?? '?'} 次，每次 '
              '${activity['session_minutes'] ?? '?'} 分钟；'
              '${activity['starts_on'] ?? '待定'} 至 ${activity['ends_on'] ?? '待定'}'
              '${activity['state'] == 'paused'
                  ? '（已暂停）'
                  : activity['state'] == 'ended'
                  ? '（已结束）'
                  : ''}',
            ),
          if (dependencies.isNotEmpty)
            Text(
              '前置条件：${dependencies.length} 项，其中 '
              '${dependencies.where((d) => d['mode'] == 'confirmed').length} 项需要确认内容完成',
            ),
        ],
      ),
    );
  }
}

class PlanningPreviewView extends StatelessWidget {
  const PlanningPreviewView({required this.preview, super.key});
  final JsonMap preview;

  @override
  Widget build(BuildContext context) {
    final capacity = preview['capacity'] is Map
        ? JsonMap.from(preview['capacity'] as Map)
        : null;
    final impact = preview['capacity_impact'] is Map
        ? JsonMap.from(preview['capacity_impact'] as Map)
        : null;
    final mode = capacityText(preview['mode']);
    final detailedUntil = capacityText(preview['detailed_until']);
    return Column(
      key: const ValueKey('planning-preview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text('本次安排预览', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          '${mode == 'full' ? '全周期覆盖' : '本次覆盖'}'
          '${detailedUntil.isEmpty ? '' : '（至 $detailedUntil）'} · '
          '已排入 ${duration((preview['scheduled_minutes'] as num? ?? 0).toInt())} · '
          '未安排 ${duration((preview['unscheduled_minutes'] as num? ?? 0).toInt())}',
        ),
        if ((preview['protected_blocks'] as num? ?? 0) > 0)
          Text(
            '保留 ${(preview['protected_blocks'] as num).toInt()} 条历史、实际用时或固定安排。',
            style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
        if (capacity != null) _capacityAssumptions(context, capacity),
        if (impact != null) _capacityImpact(context, impact),
        for (final issue in planningEntries(preview['issues'])) ...[
          const SizedBox(height: 8),
          PlannerNotice(
            [
              planningText(issue['message']),
              if (planningText(issue['date']).isNotEmpty) '${issue['date']}',
              if (planningText(issue['repair']).isNotEmpty) '${issue['repair']}',
            ].join(' · '),
            tone: issue['severity'] == 'error'
                ? PlannerNoticeTone.error
                : issue['severity'] == 'warning'
                ? PlannerNoticeTone.warning
                : PlannerNoticeTone.info,
          ),
        ],
        if (planningEntries(preview['days']).isNotEmpty)
          ExpansionTile(
            key: const ValueKey('planning-preview-days'),
            tilePadding: EdgeInsets.zero,
            title: const Text('每日安排预览'),
            children: [
              for (final day in planningEntries(preview['days']))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(planningText(day['date'])),
                  subtitle: planningEntries(day['items']).isEmpty
                      ? null
                      : Text(
                          planningEntries(day['items'])
                              .map(
                                (item) =>
                                    '${planningText(item['title'])} ${duration((item['minutes'] as num? ?? 0).toInt())}',
                              )
                              .join('；'),
                        ),
                  trailing: Text(duration((day['minutes'] as num? ?? 0).toInt())),
                ),
            ],
          ),
      ],
    );
  }

  Widget _capacityAssumptions(BuildContext context, JsonMap capacity) {
    final lines = <String>[];
    final basis = capacityText(capacity['basis']);
    if (basis.isNotEmpty) {
      lines.add(
        basis == 'net'
            ? '容量口径：净学习时间，不再机械扣除每天机动时间'
            : '容量口径：总预算口径（每日先扣机动时间）',
      );
    }
    final adopted = capacity['adopted_weekly_minutes'];
    final source = capacityText(capacity['source']);
    if (adopted is num) {
      lines.add(
        '采用周容量 ${duration(adopted.toInt())}'
        '${switch (source) {
          'baseline' => '（保守基线）',
          'range_min' => '（容量范围下限）',
          'template' => '（默认模板）',
          'legacy_default' => '（旧版每日上限）',
          _ => '',
        }}',
      );
    }
    final range = capacity['weekly_range_minutes'];
    if (range is Map && range['min'] is num && range['max'] is num) {
      lines.add(
        '范围 ${duration((range['min'] as num).toInt())}–'
        '${duration((range['max'] as num).toInt())}，'
        '较高容量情景是可达范围说明，不用于本次排程',
      );
    }
    final estimated = capacity['estimated_weeks'];
    if (estimated is num && estimated > 0) {
      lines.add('$estimated 周为程序建议分配，不是用户逐日确认');
    }
    final assumptions = capacity['assumptions'];
    if (assumptions is List) {
      for (final item in assumptions.whereType<String>()) {
        lines.add(item);
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('容量假设', style: Theme.of(context).textTheme.titleSmall),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _capacityImpact(BuildContext context, JsonMap impact) {
    final kept = (impact['kept_blocks'] as num? ?? 0).toInt();
    final keptMinutes = (impact['kept_minutes'] as num? ?? 0).toInt();
    final released = (impact['released_blocks'] as num? ?? 0).toInt();
    final releasedMinutes = (impact['released_minutes'] as num? ?? 0).toInt();
    final added = (impact['added_blocks'] as num? ?? 0).toInt();
    final addedMinutes = (impact['added_minutes'] as num? ?? 0).toInt();
    final unscheduled = (impact['unscheduled_minutes'] as num? ?? 0).toInt();
    final atRisk = planningEntries(impact['deadline_at_risk']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('排程影响', style: Theme.of(context).textTheme.titleSmall),
        Text(
          '保留 $kept 段（${duration(keptMinutes)}）· '
          '移动/释放 $released 段（${duration(releasedMinutes)}）· '
          '重新排入 $added 段（${duration(addedMinutes)}）· '
          '未安排 ${duration(unscheduled)}',
          style: const TextStyle(fontSize: 12),
        ),
        for (final item in atRisk)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: PlannerNotice(
              '真实截止日期受影响：「${planningText(item['title'])}」'
              '${planningText(item['deadline'])} 前仍有 '
              '${duration((item['unscheduled_minutes'] as num? ?? 0).toInt())} 未安排。',
              tone: PlannerNoticeTone.warning,
            ),
          ),
      ],
    );
  }
}
