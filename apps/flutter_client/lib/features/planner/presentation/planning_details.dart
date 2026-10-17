import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/planner_format.dart';

List<JsonMap> planningEntries(dynamic value) => value is List
    ? value.whereType<Map>().map((entry) => JsonMap.from(entry)).toList()
    : const [];

String planningText(dynamic value) => value is String ? value : '';

String? detailedUntil(JsonMap? planning) {
  final value = planning?['detailed_until'];
  return value is String && value.isNotEmpty ? value : null;
}

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
    final until = detailedUntil(planning);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: !compact,
      title: const Text('学习路线', style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: until == null ? null : Text('每日安排细化至 $until，其后按路线继续推进'),
      children: [
        if (planning?['needs_review'] == true)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: PlannerNotice(
              '进度或条件有变化，请核对后续范围与估算。',
              tone: PlannerNoticeTone.warning,
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
          ('uncovered', '尚未覆盖'),
        ])
          if (planning![key] is List && (planning![key] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$label：${(planning![key] as List).map((e) => e is Map ? e['message'] ?? e['title'] ?? '' : e).join('；')}',
                ),
              ),
            ),
      ],
    );
  }
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Divider(height: 32),
      Text('本次安排预览', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        '已排入 ${duration((preview['scheduled_minutes'] as num? ?? 0).toInt())} · '
        '未安排 ${duration((preview['unscheduled_minutes'] as num? ?? 0).toInt())}'
        '${preview['capacity_minutes'] is num ? ' · 可用 ${duration((preview['capacity_minutes'] as num).toInt())}' : ''}',
      ),
      if ((preview['deferred_minutes'] as num? ??
              preview['forecast_minutes'] as num? ??
              0) >
          0)
        Text(
          '远期待细化 ${duration((preview['deferred_minutes'] as num? ?? preview['forecast_minutes'] as num).toInt())}，未计入近期每日任务。',
        ),
      if (planningText(preview['detailed_until']).isNotEmpty)
        Text('近期每日安排至 ${preview['detailed_until']}；其后的路线尚未细化到每日。'),
      Text('保留 ${preview['protected_blocks'] ?? 0} 条历史、实际用时或固定安排。'),
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
          tilePadding: EdgeInsets.zero,
          title: const Text('近期每日时长'),
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
