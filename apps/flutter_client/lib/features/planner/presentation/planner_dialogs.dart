import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/planner_date_picker.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../../shared/models/task_lifecycle.dart';
import '../application/planner_session.dart';
import '../application/study_timer.dart';
import '../domain/planner_format.dart';
import '../domain/study_day.dart' as day_ops;

/// Moves one task day to another date, mirroring the Web "调整事项日期" dialog.
class MoveTaskDayDialog extends ConsumerStatefulWidget {
  const MoveTaskDayDialog({required this.blocks, super.key});

  final List<ScheduleBlock> blocks;

  static Future<void> show(BuildContext context, List<ScheduleBlock> blocks) =>
      showDialog<void>(
        context: context,
        builder: (context) => MoveTaskDayDialog(blocks: blocks),
      );

  @override
  ConsumerState<MoveTaskDayDialog> createState() => _MoveTaskDayDialogState();
}

class _MoveTaskDayDialogState extends ConsumerState<MoveTaskDayDialog> {
  late final List<String> _blockIds;
  late final String _sourceDate;
  late String _date;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _sourceDate = widget.blocks.first.date;
    _date = _sourceDate;
    _blockIds = [for (final block in widget.blocks) block.id];
  }

  /// Current authoritative records resolved by stable id.
  ///
  /// The dialog only carries move intent and record identifiers; the snapshot it
  /// opened with is not treated as the current plan.
  List<ScheduleBlock> _currentBlocks(PlannerData data) {
    final byId = {for (final block in data.blocks) block.id: block};
    return [
      for (final id in _blockIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  bool _movable(PlannerData data, List<ScheduleBlock> blocks) {
    if (blocks.length != _blockIds.length) return false;
    final first = blocks.first;
    final timer = ref.read(studyTimerProvider);
    if (timer.isRunning(first.taskId, first.date) ||
        timer.elapsedFor(first.taskId, first.date) > Duration.zero) {
      return false;
    }
    final task = data.tasks
        .where((item) => item.id == first.taskId)
        .firstOrNull;
    if (task == null || task.isArchived) return false;
    if (day_ops.taskDayMinutes(data, task.id, first.date) > 0) return false;
    return blocks.every(
      (block) =>
          !block.isFixed &&
          block.status != BlockStatus.completed &&
          block.actualMinutes == 0 &&
          data.tasks
                  .where((item) => item.id == block.taskId)
                  .firstOrNull
                  ?.isFixed !=
              true,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(plannerSessionProvider)
          .moveTaskDayByIds(_blockIds, _date, sourceDate: _sourceDate);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError ? error.message : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
    final blocks = _currentBlocks(data);
    final missing = blocks.length != _blockIds.length;
    final changed = blocks.any((block) => block.date != _sourceDate);
    final movable = !missing && !changed && _movable(data, blocks);
    final display = blocks.isEmpty ? widget.blocks : blocks;
    final task = data.tasks
        .where((item) => item.id == display.first.taskId)
        .firstOrNull;
    final planned = display.fold<int>(
      0,
      (sum, block) => sum + block.durationMinutes,
    );
    return AlertDialog(
      title: const Text('调整事项日期'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${task?.title ?? ''} · ${duration(planned)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DateField(
              label: '安排日期',
              value: _date,
              enabled: movable && !_saving,
              onChanged: (value) => setState(() => _date = value),
            ),
            const SizedBox(height: 8),
            Text(
              '只调整日期，不指定学习开始时间。',
              style: TextStyle(color: context.tokens.muted, fontSize: 12),
            ),
            if (missing) ...[
              const SizedBox(height: 8),
              const PlannerNotice(
                '部分安排已不存在，请关闭后在最新计划上重新移动。',
                tone: PlannerNoticeTone.error,
              ),
            ] else if (changed) ...[
              const SizedBox(height: 8),
              const PlannerNotice(
                '安排已更新，请关闭后重新打开移动窗口。',
                tone: PlannerNoticeTone.warning,
              ),
            ] else if (!movable) ...[
              const SizedBox(height: 8),
              Text(
                '计时中、已有学习用时、已完成或固定的计划保留在原日期。',
                style: TextStyle(color: context.tokens.muted, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              PlannerNotice(_error!, tone: PlannerNoticeTone.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: !movable || _saving ? null : _save,
          icon: const Icon(Icons.event_outlined, size: 18),
          label: const Text('保存日期'),
        ),
      ],
    );
  }
}

/// Shared `YYYY-MM-DD` form field with the platform date picker.
class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.firstDate,
    this.lastDate,
    this.errorText,
    this.helperText,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? firstDate;
  final String? lastDate;
  final String? errorText;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final parsed = DateTime.tryParse(value);
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final now = DateTime.now();
              final picked = await showPlannerDatePicker(
                context,
                initialDate: parsed ?? now,
                firstDate:
                    DateTime.tryParse(firstDate ?? '') ??
                    DateTime(now.year - 2),
                lastDate:
                    DateTime.tryParse(lastDate ?? '') ?? DateTime(now.year + 5),
                title: label,
              );
              if (picked != null) {
                onChanged(dateOnly(picked));
              }
            },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          helperText: helperText,
          enabled: enabled,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(value.isEmpty ? '请选择日期' : value, style: tabularFigures),
      ),
    );
  }
}

