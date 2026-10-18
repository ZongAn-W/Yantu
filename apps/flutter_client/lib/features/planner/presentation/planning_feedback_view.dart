import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/planner_session.dart';
import '../domain/planner_format.dart';
import '../domain/planning_feedback.dart';

class PlanningFeedbackView extends ConsumerWidget {
  const PlanningFeedbackView({
    required this.task,
    required this.data,
    required this.editable,
    super.key,
  });
  final Task task;
  final PlannerData data;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pace = calibratePace(task, data.logs);
    final feedback = task.planning?['feedback'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (feedback is Map) ...[
          const SizedBox(height: 8),
          Text(
            '内容进度：${feedback['content_units'] ?? 0} ${pace.unit ?? '单位'} · '
            '${feedback['content_completed'] == true ? '内容已完成' : '内容尚未完成'}',
          ),
          if (!pace.sufficient)
            const Text(
              '速度仍为估算，至少需要 3 段有效计时和内容进度。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
        ],
        if (pace.deviates ||
            feedback is Map && feedback['difficulty'] == 'hard') ...[
          const SizedBox(height: 8),
          PlannerNotice(
            pace.deviates
                ? '根据 ${pace.samples} 段计时，每${pace.unit ?? '单位'}约 '
                      '${pace.observedMinutesPerUnit!.round()} 分钟，原估算 '
                      '${pace.expectedMinutesPerUnit!.round()} 分钟。建议重新评估范围与预算。'
                : '已记录当前内容有困难，建议重新评估学习方法和练习范围。',
            tone: PlannerNoticeTone.warning,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: editable ? () => context.go('/interview') : null,
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('重新评估学习策略'),
              ),
              TextButton.icon(
                onPressed: editable ? () => context.go('/adjust') : null,
                icon: const Icon(Icons.tune_outlined, size: 18),
                label: const Text('到调整页调整后续计划'),
              ),
            ],
          ),
        ],
        TextButton.icon(
          onPressed: editable ? () => _record(context, ref, pace.unit) : null,
          icon: const Icon(Icons.rate_review_outlined, size: 18),
          label: const Text('记录内容进度与困难'),
        ),
      ],
    );
  }

  Future<void> _record(
    BuildContext context,
    WidgetRef ref,
    String? unit,
  ) async {
    final feedback = task.planning?['feedback'];
    var units = feedback is Map ? '${feedback['content_units'] ?? 0}' : '0';
    var completed = feedback is Map && feedback['content_completed'] == true;
    var difficulty = feedback is Map
        ? feedback['difficulty'] as String? ?? 'manageable'
        : 'manageable';
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('内容进度与困难'),
          content: SizedBox(
            width: 400,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(task.title),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: units,
                      onChanged: (value) => units = value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '累计完成内容${unit == null ? '（单位数）' : '（$unit）'}',
                      ),
                      validator: (value) {
                        final number = double.tryParse(value ?? '');
                        return number == null || !number.isFinite || number < 0
                            ? '填写有效的非负数量'
                            : null;
                      },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('事项内容已完成'),
                      value: completed,
                      onChanged: (value) => setState(() => completed = value!),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: difficulty,
                      decoration: const InputDecoration(labelText: '当前难度'),
                      items: const [
                        DropdownMenuItem(value: 'easy', child: Text('进展顺利')),
                        DropdownMenuItem(
                          value: 'manageable',
                          child: Text('按预期推进'),
                        ),
                        DropdownMenuItem(value: 'hard', child: Text('遇到困难')),
                      ],
                      onChanged: (value) => setState(() => difficulty = value!),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('保存反馈'),
            ),
          ],
        ),
      ),
    );
    final value = double.tryParse(units);
    if (result != true || value == null) return;
    try {
      await ref
          .read(plannerSessionProvider)
          .edit(
            (data) => recordPlanningFeedback(
              data,
              task.id,
              contentUnits: value,
              contentCompleted: completed,
              difficulty: difficulty,
              sampledAt: nowIso(),
            ),
          );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('反馈未保存，请重试：$error')));
      }
    }
  }
}
