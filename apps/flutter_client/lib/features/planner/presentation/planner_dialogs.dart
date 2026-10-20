import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/planner_session.dart';
import '../application/study_timer.dart';
import '../domain/planner_format.dart';
import '../domain/planning_feedback.dart';
import '../domain/study_day.dart' as day_ops;
import '../domain/study_day.dart' show unscheduledTaskMinutes;
import '../../tasks/presentation/tasks_dialogs.dart' show TagManagementDialog;

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
    if (task == null || task.status == TaskStatus.archived) return false;
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
            const Text(
              '只调整日期，不指定学习开始时间。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
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
              const Text(
                '计时中、已有学习用时、已完成或固定的计划保留在原日期。',
                style: TextStyle(color: PlannerColors.muted, fontSize: 12),
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
              final picked = await showDatePicker(
                context: context,
                initialDate: parsed ?? now,
                firstDate:
                    DateTime.tryParse(firstDate ?? '') ??
                    DateTime(now.year - 2),
                lastDate:
                    DateTime.tryParse(lastDate ?? '') ?? DateTime(now.year + 5),
                helpText: label,
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

/// Task create/edit form.
class TaskEditorDialog extends ConsumerStatefulWidget {
  const TaskEditorDialog({
    this.taskId,
    this.quickStart = false,
    this.initialTitle = '',
    super.key,
  });

  final String? taskId;
  final bool quickStart;
  final String initialTitle;
  static Future<bool> showQuickStart(
    BuildContext context, {
    String initialTitle = '',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) =>
            TaskEditorDialog(quickStart: true, initialTitle: initialTitle),
      ) ==
      true;

  static Future<void> show(BuildContext context, {String? taskId}) =>
      showDialog<void>(
        context: context,
        builder: (context) => TaskEditorDialog(taskId: taskId),
      );

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  late TaskDraft _draft;
  late TextEditingController _title;
  late TextEditingController _description;
  late TextEditingController _estimated;
  String? _error;
  bool _saving = false;
  String? _createdTaskId;

  @override
  void initState() {
    super.initState();
    final data = ref.read(plannerSessionProvider).data;
    final task = widget.taskId == null
        ? null
        : data.tasks.where((item) => item.id == widget.taskId).firstOrNull;
    _draft = task == null
        ? TaskDraft.blank(data, shanghaiToday())
        : TaskDraft.from(task);
    if (widget.quickStart) {
      _draft = _draft.copyWith(
        title: widget.initialTitle,
        deadlineKind: ItemDateKind.planEnd,
      );
    }
    _title = TextEditingController(text: _draft.title);
    _description = TextEditingController(text: _draft.description);
    _estimated = TextEditingController(text: '${_draft.estimatedMinutes}');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _estimated.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final data = ref.read(plannerSessionProvider).data;
    final draft = _draft.copyWith(
      title: _title.text,
      description: _description.text.trim(),
      estimatedMinutes: int.tryParse(_estimated.text.trim()) ?? 0,
    );
    final completed = widget.taskId == null
        ? 0
        : data.tasks
                  .where((item) => item.id == widget.taskId)
                  .firstOrNull
                  ?.completedMinutes ??
              0;
    final error = validateTaskDraft(draft, completedMinutes: completed);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = ref.read(plannerSessionProvider);
      if (widget.taskId == null) {
        final taskId = await session.createTask(draft);
        if (widget.quickStart) {
          if (mounted) {
            setState(() {
              _createdTaskId = taskId;
              _saving = false;
            });
          }
          return;
        }
      } else {
        await session.updateTask(widget.taskId!, draft);
      }
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

  Future<void> _startCreatedTask() async {
    if (_saving || _createdTaskId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(studyTimerProvider)
          .start(_createdTaskId!, shanghaiToday());
      if (mounted) Navigator.pop(context, true);
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
    if (_createdTaskId != null) {
      return AlertDialog(
        title: const Text('事项已创建'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title.text.trim()),
            const SizedBox(height: 8),
            const Text('今天还没有安排，立即计时会记录为加学。'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              PlannerNotice(_error!, tone: PlannerNoticeTone.error),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('完成'),
          ),
          FilledButton(
            key: const Key('quick-task-start'),
            onPressed: _saving ? null : _startCreatedTask,
            child: const Text('立即开始计时'),
          ),
        ],
      );
    }
    final editing = widget.taskId != null;
    final statuses = editing
        ? TaskStatus.values
        : TaskStatus.values
              .where(
                (s) => s != TaskStatus.completed && s != TaskStatus.archived,
              )
              .toList();
    return AlertDialog(
      title: Text(editing ? '编辑事项' : '新建事项'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.quickStart) ...[
                const Text('填写事项名称即可保存。标签、预计时长、优先级和日期均可按需调整；保存后不会自动安排日程。'),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _title,
                enabled: !_saving,
                maxLength: 150,
                decoration: const InputDecoration(
                  labelText: '事项名称',
                  counterText: '',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                enabled: !_saving,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: '学习范围与完成标准',
                  hintText: '例如：完成极限、导数和积分基础题；整理主要薄弱点。',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              if (data.tags.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      '标签（选填）',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      key: const Key('quick-task-manage-tags'),
                      onPressed: _saving
                          ? null
                          : () => TagManagementDialog.show(context),
                      icon: const Icon(Icons.sell_outlined, size: 16),
                      label: const Text('管理标签'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in data.tags)
                      FilterChip(
                        key: Key('quick-task-tag-${tag.id}'),
                        label: Text(tag.name),
                        selected: _draft.tagIds.contains(tag.id),
                        onSelected: _saving
                            ? null
                            : (selected) => setState(() {
                                final ids = {..._draft.tagIds};
                                selected ? ids.add(tag.id) : ids.remove(tag.id);
                                _draft = _draft.copyWith(tagIds: ids.toList());
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ] else ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('quick-task-manage-tags'),
                    onPressed: _saving
                        ? null
                        : () => TagManagementDialog.show(context),
                    icon: const Icon(Icons.sell_outlined, size: 16),
                    label: const Text('创建标签'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _draft.priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: [
                  for (final priority in const [3, 2, 1])
                    DropdownMenuItem(
                      value: priority,
                      child: Text(priorityLabels[priority]!),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _draft = _draft.copyWith(priority: value),
                      ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _estimated,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '预计总时长（分钟）',
                  helperText: '至少 30 分钟',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              DateField(
                label: '开始日期',
                value: _draft.earliestDate,
                enabled: !_saving,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(earliestDate: value),
                ),
              ),
              const SizedBox(height: 12),
              DateField(
                label: _draft.deadlineKind == ItemDateKind.planEnd
                    ? '本期安排边界'
                    : '真实截止日期',
                value: _draft.deadline,
                enabled: !_saving,
                firstDate: _draft.earliestDate,
                onChanged: (value) =>
                    setState(() => _draft = _draft.copyWith(deadline: value)),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ItemDateKind>(
                initialValue: _draft.deadlineKind,
                decoration: const InputDecoration(
                  labelText: '日期含义',
                  helperText: '本期安排边界会随新的规划周期延展，真实截止日期保持不变',
                ),
                items: [
                  for (final kind in ItemDateKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(itemDateKindLabels[kind]!),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _draft = _draft.copyWith(
                          deadlineKind: value ?? ItemDateKind.deadline,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskStatus>(
                initialValue: _draft.status,
                decoration: const InputDecoration(labelText: '状态'),
                items: [
                  for (final status in statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(statusLabels[status]!),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _draft = _draft.copyWith(status: value),
                      ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _draft.isFixed,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('固定事项（排入后不可自动移动）'),
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _draft = _draft.copyWith(isFixed: value ?? false),
                      ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                PlannerNotice(_error!, tone: PlannerNoticeTone.error),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('保存事项'),
        ),
      ],
    );
  }
}

/// "安排时间块" dialog: schedules part or all of a task onto one day.
class ScheduleTaskDialog extends ConsumerStatefulWidget {
  const ScheduleTaskDialog({required this.taskId, super.key});

  final String taskId;

  static Future<void> show(BuildContext context, String taskId) =>
      showDialog<void>(
        context: context,
        builder: (context) => ScheduleTaskDialog(taskId: taskId),
      );

  @override
  ConsumerState<ScheduleTaskDialog> createState() => _ScheduleTaskDialogState();
}

class _ScheduleTaskDialogState extends ConsumerState<ScheduleTaskDialog> {
  late String _date;
  final _minutes = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = ref.read(plannerSessionProvider).data;
    final task = data.tasks.firstWhere((item) => item.id == widget.taskId);
    final today = shanghaiToday();
    _date = (task.earliestDate ?? '').compareTo(today) > 0
        ? task.earliestDate!
        : today;
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final raw = _minutes.text.trim();
    final parsed = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && (parsed == null || parsed <= 0)) {
      setState(() => _error = '请填写大于零的安排时长');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await ref
          .read(plannerSessionProvider)
          .scheduleTask(taskId: widget.taskId, date: _date, minutes: parsed);
      if (!mounted) return;
      Navigator.pop(context);
      showPlannerMessage(
        context,
        outcome.message,
        tone: outcome.conflict
            ? PlannerNoticeTone.warning
            : PlannerNoticeTone.success,
      );
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
    final task = data.tasks.firstWhere((item) => item.id == widget.taskId);
    final remaining = unscheduledTaskMinutes(data, task, from: _date);
    return AlertDialog(
      title: const Text('安排时间块'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              task.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DateField(
              label: '安排日期',
              value: _date,
              enabled: !_saving,
              firstDate: task.earliestDate,
              lastDate: task.deadline,
              onChanged: (value) => setState(() => _date = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minutes,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '当天分配时长（分钟）',
                hintText: '留空安排全部剩余时长',
                helperText: '按 30 分钟拆分计入当天计划',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '当前可安排 ${duration(remaining)}',
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              '按30分钟拆分计入当天计划，不指定开始时间；容量不足会显示冲突。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
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
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.event_available_outlined, size: 18),
          label: const Text('拆分并安排'),
        ),
      ],
    );
  }
}

/// Completes the whole task without adding or editing measured study time.
class CompleteTaskDialog extends ConsumerStatefulWidget {
  const CompleteTaskDialog({required this.taskId, super.key});

  final String taskId;

  static Future<void> show(BuildContext context, String taskId) =>
      showDialog<void>(
        context: context,
        builder: (context) => CompleteTaskDialog(taskId: taskId),
      );

  @override
  ConsumerState<CompleteTaskDialog> createState() => _CompleteTaskDialogState();
}

class _CompleteTaskDialogState extends ConsumerState<CompleteTaskDialog> {
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final timer = ref.read(studyTimerProvider);
      if (timer.activeTaskId == widget.taskId) await timer.pause();
      await ref
          .read(plannerSessionProvider)
          .completeTask(widget.taskId, actualMinutes: 0, date: shanghaiToday());
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
    final task = data.tasks
        .where((item) => item.id == widget.taskId)
        .firstOrNull;
    return AlertDialog(
      title: const Text('标记事项完成'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              task?.title ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if ((task?.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task!.description!,
                style: const TextStyle(
                  color: PlannerColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '标记完成后，不再安排这项事项。已学时长保留计时记录。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
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
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('确认完成'),
        ),
      ],
    );
  }
}

/// 记录内容进度与困难：加学/复习停止后的可选后续，绝不自动完成内容或解锁依赖。
class ContentFeedbackDialog extends ConsumerStatefulWidget {
  const ContentFeedbackDialog({required this.taskId, super.key});

  final String taskId;

  static Future<void> show(BuildContext context, String taskId) =>
      showDialog<void>(
        context: context,
        builder: (context) => ContentFeedbackDialog(taskId: taskId),
      );

  @override
  ConsumerState<ContentFeedbackDialog> createState() =>
      _ContentFeedbackDialogState();
}

class _ContentFeedbackDialogState extends ConsumerState<ContentFeedbackDialog> {
  final _form = GlobalKey<FormState>();
  late String _units;
  late bool _completed;
  late String _difficulty;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = ref.read(plannerSessionProvider).data;
    final task = data.tasks
        .where((item) => item.id == widget.taskId)
        .firstOrNull;
    final feedback = task?.planning?['feedback'];
    _units = feedback is Map ? '${feedback['content_units'] ?? 0}' : '0';
    _completed = feedback is Map && feedback['content_completed'] == true;
    _difficulty = feedback is Map
        ? feedback['difficulty'] as String? ?? 'manageable'
        : 'manageable';
  }

  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    final value = double.tryParse(_units);
    if (value == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(plannerSessionProvider)
          .edit(
            (data) => recordPlanningFeedback(
              data,
              widget.taskId,
              contentUnits: value,
              contentCompleted: _completed,
              difficulty: _difficulty,
              sampledAt: nowIso(),
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
    final task = data.tasks
        .where((item) => item.id == widget.taskId)
        .firstOrNull;
    return AlertDialog(
      title: const Text('记录内容进度与困难'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(task?.title ?? ''),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('content-feedback-units'),
                initialValue: _units,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '累计完成内容（单位数）'),
                validator: (value) {
                  final number = double.tryParse(value ?? '');
                  return number == null || !number.isFinite || number < 0
                      ? '填写有效的非负数量'
                      : null;
                },
                onChanged: (value) => _units = value,
              ),
              CheckboxListTile(
                key: const Key('content-feedback-completed'),
                contentPadding: EdgeInsets.zero,
                title: const Text('事项内容已完成'),
                value: _completed,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _completed = value ?? false),
              ),
              DropdownButtonFormField<String>(
                initialValue: _difficulty,
                decoration: const InputDecoration(labelText: '当前难度'),
                items: const [
                  DropdownMenuItem(value: 'easy', child: Text('进展顺利')),
                  DropdownMenuItem(value: 'manageable', child: Text('按预期推进')),
                  DropdownMenuItem(value: 'hard', child: Text('遇到困难')),
                ],
                onChanged: _busy
                    ? null
                    : (value) =>
                          setState(() => _difficulty = value ?? 'manageable'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                PlannerNotice(_error!, tone: PlannerNoticeTone.error),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('跳过'),
        ),
        FilledButton(
          key: const Key('content-feedback-save'),
          onPressed: _busy ? null : _save,
          child: const Text('保存反馈'),
        ),
      ],
    );
  }
}
