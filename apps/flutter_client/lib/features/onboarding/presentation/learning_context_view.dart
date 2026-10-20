import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/onboarding_session.dart';

class LearningContextView extends StatelessWidget {
  const LearningContextView({
    required this.session,
    required this.busy,
    required this.onAction,
    super.key,
  });
  final OnboardingSession session;
  final bool busy;
  final Future<bool> Function(JsonMap) onAction;

  static const _labels = {
    'identity': '当前身份',
    'school': '报考院校',
    'college': '报考学院',
    'program': '报考专业',
    'degree': '学位类型',
    'baseline': '各科进度',
    'weakness': '薄弱环节',
    'diagnostic': '做题表现',
    'outcome': '学习目标',
    'availability': '可用时间',
    'materials': '学习资料',
    'constraints': '固定安排',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final timing = session.learningContext['timing'] as Map? ?? const {};
    final facts = session.learningContext['facts'] as Map? ?? const {};
    final research = session.research;
    final sources = research['sources'] as List? ?? const [];
    final verifiedFacts = research['facts'] as List? ?? const [];
    final status = research['status'] as String? ?? 'idle';
    final year = timing['exam_year'] as int?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (year != null)
          Row(
            children: [
              Icon(Icons.event_outlined, size: 18, color: tokens.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${timing['estimated'] == true ? '预计' : '已指定'} $year 年初试 · ${timing['admission_year']} 年入学',
                ),
              ),
              IconButton(
                tooltip: '修改初试年份',
                onPressed: busy ? null : () => _editYear(context, year),
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
            ],
          ),
        if (facts.isNotEmpty)
          ExpansionTile(
            key: const PageStorageKey('learner-context'),
            tilePadding: EdgeInsets.zero,
            title: const Text('当前学习情况'),
            children: [
              if (year != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      timing['reason'] as String? ?? '',
                      style: TextStyle(color: tokens.muted),
                    ),
                  ),
                ),
              for (final entry in facts.entries)
                if (_labels.containsKey(entry.key))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_labels[entry.key]!),
                    subtitle: SelectableText(
                      key: PageStorageKey('learner-fact-${entry.key}'),
                      (entry.value as Map)['value'] as String? ?? '',
                    ),
                  ),
            ],
          ),
        if (status != 'idle') ...[
          Row(
            children: [
              if (status == 'pending')
                const PlannerSpinner(size: 16)
              else
                Icon(
                  status == 'verified'
                      ? Icons.fact_check_outlined
                      : Icons.info_outline,
                  size: 18,
                  color: tokens.muted,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    research['message'] as String? ?? '',
                    style: TextStyle(color: tokens.muted),
                  ),
                ),
              ),
              if (status != 'pending')
                IconButton(
                  tooltip: '重新核实官方资料',
                  onPressed: busy
                      ? null
                      : () => onAction({'type': 'retry_research'}),
                  icon: const Icon(Icons.refresh, size: 20),
                ),
            ],
          ),
          if (sources.isNotEmpty)
            ExpansionTile(
              key: const PageStorageKey('official-research'),
              title: Text('官方资料（${sources.length}）'),
              tilePadding: EdgeInsets.zero,
              children: [
                for (final (i, fact) in verifiedFacts.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${fact['reference_only'] == true ? '参考：' : ''}${fact['statement']}',
                    ),
                    subtitle: SelectableText(
                      key: PageStorageKey('research-quote-$i'),
                      '${fact['applicable_year'] == null ? '' : '适用年份：${fact['applicable_year']}\n'}${fact['quote']}',
                    ),
                  ),
                for (final (i, source) in sources.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(source['title'] as String? ?? '官方来源'),
                    subtitle: SelectableText(
                      key: PageStorageKey('research-url-$i'),
                      source['url'] as String? ?? '',
                    ),
                    trailing: IconButton(
                      tooltip: '打开官方来源',
                      icon: const Icon(Icons.open_in_new, size: 20),
                      onPressed: () async {
                        final uri = Uri.tryParse(
                          source['url'] as String? ?? '',
                        );
                        if (uri == null || uri.scheme != 'https') return;
                        final opened = await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        ).catchError((_) => false);
                        if (!opened && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('暂时无法打开来源，可复制链接查看')),
                          );
                        }
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Future<void> _editYear(BuildContext context, int year) async {
    final currentYear = int.parse(shanghaiToday().substring(0, 4));
    var selected = year.clamp(currentYear, currentYear + 10);
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('初试年份'),
          content: SizedBox(
            width: 280,
            child: DropdownButtonFormField<int>(
              initialValue: selected,
              isExpanded: true,
              dropdownColor: context.tokens.surface,
              borderRadius: BorderRadius.circular(PlannerRadius.control),
              iconEnabledColor: context.tokens.muted,
              decoration: const InputDecoration(labelText: '参加初试的年份'),
              items: [
                for (var i = currentYear; i <= currentYear + 10; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text('$i 年初试 · ${i + 1} 年入学'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => selected = value);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await onAction({'type': 'set_exam_year', 'year': result});
    }
  }
}
