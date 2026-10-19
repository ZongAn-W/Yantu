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

String subjectNameOf(PlannerData data, String subjectId) =>
    data.subjects
        .where((subject) => subject.id == subjectId)
        .firstOrNull
        ?.name ??
    subjectId;

String? subjectColorOf(PlannerData data, String subjectId) => data.subjects
    .where((subject) => subject.id == subjectId)
    .firstOrNull
    ?.color;

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
    this.initialSubjectId = '',
    super.key,
  });

  final String? taskId;
  final bool quickStart;
  final String initialTitle;
  final String initialSubjectId;

  static Future<bool> showQuickStart(
    BuildContext context, {
    String initialTitle = '',
    String initialSubjectId = '',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => TaskEditorDialog(
          quickStart: true,
          initialTitle: initialTitle,
          initialSubjectId: initialSubjectId,
        ),
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
  late TextEditingController _course;
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
        subjectId: widget.initialSubjectId,
        deadlineKind: ItemDateKind.planEnd,
      );
    }
    _title = TextEditingController(text: _draft.title);
    _description = TextEditingController(text: _draft.description);
    _course = TextEditingController(
      text: subjectNameOf(data, _draft.subjectId),
    );
    _estimated = TextEditingController(text: '${_draft.estimatedMinutes}');
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _course.dispose();
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
                const Text(
                  '填写课程和事项名称即可保存。预计时长、优先级和日期暂用下方初始值，可按需调整；保存后不会自动安排日程。',
                ),
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
              TextField(
                controller: _course,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: '课程',
                  helperText: '可输入已有课程名或新课程名',
                  suffixIcon: PopupMenuButton<String>(
                    tooltip: '选择已有课程',
                    icon: const Icon(Icons.arrow_drop_down),
                    onSelected: _saving
                        ? null
                        : (value) => setState(() {
                            _course.text = value;
                            _draft = _draft.copyWith(
                              subjectId: resolveSubjectId(data, value),
                            );
                          }),
                    itemBuilder: (context) => [
                      for (final subject in data.subjects)
                        PopupMenuItem(
                          value: subject.name,
                          child: Text(subject.name),
                        ),
                    ],
                  ),
                ),
                onChanged: (value) => setState(() {
                  _draft = _draft.copyWith(
                    subjectId: resolveSubjectId(data, value),
                  );
                  _error = null;
                }),
              ),
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

/// 今日“开始学习”入口：把三类学习关系摆在同一处，用户无需先绕去设置或新建事项。
///
/// - 今日原定学习：按今天已有的安排开始计时；
/// - 已有事项加学：今天没有安排也能学，完成后复习也走这里；
/// - 全新临时学习：只需名称即可计时，不创建正式事项、预算、截止日期或日程。
class StartStudyDialog extends ConsumerStatefulWidget {
  const StartStudyDialog({super.key});

  static Future<void> show(BuildContext context) async {
    final data = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(plannerSessionProvider).data;
    if (data.tasks.isEmpty) {
      await AdHocStudyDialog.show(context);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => const StartStudyDialog(),
    );
  }

  @override
  ConsumerState<StartStudyDialog> createState() => _StartStudyDialogState();
}

class _StartStudyDialogState extends ConsumerState<StartStudyDialog> {
  bool _showArrangements = false;
  bool _busy = false;
  String? _error;

  Future<void> _startArranged(String taskId, String date) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(studyTimerProvider).start(taskId, date);
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

  Future<void> _openPicker() async {
    final started = await TaskPickerDialog.showExtraStudy(context);
    if (started && mounted) Navigator.pop(context);
  }

  Future<void> _openAdHoc() async {
    final started = await AdHocStudyDialog.show(context);
    if (started && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
    final date = shanghaiToday();
    final timer = ref.watch(studyTimerProvider);
    final groups = day_ops.groupDailyBlocks(
      data.blocks.where((block) => block.date == date),
      data.tasks,
    );
    final taskById = {for (final task in data.tasks) task.id: task};
    final Widget body;
    if (!_showArrangements) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (timer.activeTaskId != null || timer.activeAdHocId != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: PlannerNotice(
                '当前已有计时在运行。选择其他学习内容会先结束当前这一段并可靠保存。',
                tone: PlannerNoticeTone.info,
              ),
            ),
          ListTile(
            key: const Key('start-study-scheduled'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available_outlined),
            title: const Text('今日原定学习'),
            subtitle: const Text('按今天的安排开始计时，按该安排的额度计入原定执行'),
            onTap: () => setState(() => _showArrangements = true),
          ),
          ListTile(
            key: const Key('start-study-extra'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.school_outlined),
            title: const Text('已有事项加学'),
            subtitle: const Text('今天没有安排也可以直接学；已完成事项在这里复习计时'),
            onTap: _openPicker,
          ),
          ListTile(
            key: const Key('start-study-adhoc'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('全新临时学习'),
            subtitle: const Text('填写名称即可计时，不强制预算、截止日期或正式日程'),
            onTap: _openAdHoc,
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() => _showArrangements = false),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('返回选择学习关系'),
          ),
          if (groups.isEmpty)
            const PlannerEmpty(
              icon: Icons.event_busy_outlined,
              message: '今天没有原定安排，可以选择“已有事项加学”或“全新临时学习”。',
            ),
          for (final group in groups)
            () {
              final task = taskById[group.first.taskId];
              if (task == null) return const SizedBox.shrink();
              final planned = group.fold<int>(
                0,
                (sum, block) => sum + block.durationMinutes,
              );
              final achieved = day_ops.scheduledMinutesForTaskDay(
                data,
                task.id,
                date,
              );
              final done = achieved >= planned;
              return ListTile(
                key: Key('start-arranged-${task.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_circle_outline),
                title: Text(
                  '${subjectNameOf(data, task.subjectId)} · ${task.title}',
                ),
                subtitle: Text(
                  '原定 ${duration(planned)} · 已达成 ${duration(achieved)}'
                  '${done ? ' · 已完成' : ''}',
                ),
                trailing: FilledButton(
                  onPressed: _busy ? null : () => _startArranged(task.id, date),
                  child: Text(done ? '继续计时' : '开始计时'),
                ),
              );
            }(),
        ],
      );
    }
    return AlertDialog(
      title: const Text('开始计时'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              body,
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
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 选择已有事项：默认突出可执行事项，支持搜索、课程与状态筛选。
///
/// 加学模式用于“今日没有安排的已有事项”，包括已完成事项的复习计时；
/// 关联模式把临时学习的真实记录关联到已有事项（历史仍保留临时学习关系）。
enum TaskPickerMode { extraStudy, linkAdHoc }

class TaskPickerDialog extends ConsumerStatefulWidget {
  const TaskPickerDialog({required this.mode, this.adHocId, super.key});

  final TaskPickerMode mode;
  final String? adHocId;

  static Future<bool> showExtraStudy(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) =>
            const TaskPickerDialog(mode: TaskPickerMode.extraStudy),
      ) ==
      true;

  static Future<bool> showLinkAdHoc(
    BuildContext context,
    String adHocId,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) =>
            TaskPickerDialog(mode: TaskPickerMode.linkAdHoc, adHocId: adHocId),
      ) ==
      true;

  @override
  ConsumerState<TaskPickerDialog> createState() => _TaskPickerDialogState();
}

class _TaskPickerDialogState extends ConsumerState<TaskPickerDialog> {
  final _search = TextEditingController();
  String _subject = 'all';
  String _status = 'actionable';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Task> _visible(PlannerData data) {
    final query = _search.text.trim().toLowerCase();
    final tasks = <Task>[];
    for (final task in data.tasks) {
      if (task.status == TaskStatus.archived) continue;
      if (_subject != 'all' && task.subjectId != _subject) continue;
      switch (_status) {
        case 'actionable':
          if (task.status == TaskStatus.completed) continue;
        case 'completed':
          if (task.status != TaskStatus.completed) continue;
        default:
          break;
      }
      if (query.isNotEmpty) {
        final haystack =
            '${task.title} ${task.description ?? ''} '
                    '${subjectNameOf(data, task.subjectId)}'
                .toLowerCase();
        if (!haystack.contains(query)) continue;
      }
      tasks.add(task);
    }
    tasks.sort((a, b) {
      // Actionable first (in progress, then deadline), completed review last.
      final doneA = a.status == TaskStatus.completed ? 1 : 0;
      final doneB = b.status == TaskStatus.completed ? 1 : 0;
      if (doneA != doneB) return doneA - doneB;
      final byDeadline = a.deadline.compareTo(b.deadline);
      if (byDeadline != 0) return byDeadline;
      return b.priority.compareTo(a.priority);
    });
    // Avoid dumping the whole long-term list at once.
    return tasks.length > 50 ? tasks.sublist(0, 50) : tasks;
  }

  Future<void> _pick(Task task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final timer = ref.read(studyTimerProvider);
      if (widget.mode == TaskPickerMode.extraStudy) {
        await timer.startExtra(task.id);
      } else {
        final adHocId = widget.adHocId;
        if (adHocId == null) throw StateError('临时学习已不存在，请刷新后重试');
        final result = await ref
            .read(plannerSessionProvider)
            .linkAdHocToTask(adHocId: adHocId, taskId: task.id);
        await timer.adoptAdHocConversion(adHocId, result.taskId);
        if (mounted) {
          showPlannerMessage(context, '已关联到「${task.title}」，历史记录仍保留临时学习关系。');
        }
      }
      if (mounted) Navigator.pop(context, true);
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
    final tasks = _visible(data);
    final today = shanghaiToday();
    final taskById = {for (final task in data.tasks) task.id: task};
    return AlertDialog(
      title: Text(
        widget.mode == TaskPickerMode.extraStudy ? '选择要加学的事项' : '关联到已有事项',
      ),
      content: SizedBox(
        width: 560,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('task-picker-search'),
              controller: _search,
              decoration: const InputDecoration(
                labelText: '搜索事项',
                hintText: '事项名称、说明或课程',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                DropdownButton<String>(
                  key: const Key('task-picker-subject'),
                  value: _subject,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('全部课程')),
                    for (final subject in data.subjects)
                      DropdownMenuItem(
                        value: subject.id,
                        child: Text(subject.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _subject = value ?? 'all'),
                ),
                DropdownButton<String>(
                  key: const Key('task-picker-status'),
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: 'actionable', child: Text('可执行事项')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('已完成（可复习）'),
                    ),
                    DropdownMenuItem(value: 'all', child: Text('全部状态')),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'actionable'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: tasks.isEmpty
                  ? const PlannerEmpty(
                      message: '没有匹配的事项，可以修改筛选条件；全新内容请用临时学习。',
                      icon: Icons.search_off,
                    )
                  : ListView(
                      children: [
                        for (final task in tasks)
                          ListTile(
                            key: Key('task-picker-item-${task.id}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${subjectNameOf(data, task.subjectId)} · ${task.title}',
                            ),
                            subtitle: Text(
                              '${statusLabels[task.status] ?? ''} · '
                              '已学 ${duration(day_ops.taskTotalMinutes(data, task.id))} / '
                              '预算 ${duration(task.estimatedMinutes)}'
                              '${day_ops.taskIsPlannedOn(data, task.id, today) ? ' · 今日已安排' : ''}',
                            ),
                            trailing: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.play_arrow),
                            onTap: _busy ? null : () => _pick(task),
                          ),
                        if (taskById.isNotEmpty && tasks.length >= 50)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              '只显示前 50 个匹配事项，可用搜索缩小范围。',
                              style: TextStyle(
                                color: PlannerColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              PlannerNotice(_error!, tone: PlannerNoticeTone.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 全新临时学习：名称即可开始，课程/分类可选，不伪造预算或截止日期。
class AdHocStudyDialog extends ConsumerStatefulWidget {
  const AdHocStudyDialog({this.initialTitle, super.key});

  final String? initialTitle;

  static Future<bool> show(
    BuildContext context, {
    String? initialTitle,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AdHocStudyDialog(initialTitle: initialTitle),
      ) ==
      true;

  @override
  ConsumerState<AdHocStudyDialog> createState() => _AdHocStudyDialogState();
}

class _AdHocStudyDialogState extends ConsumerState<AdHocStudyDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle ?? '',
  );
  String _subject = '';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写临时学习名称');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(studyTimerProvider)
          .startAdHoc(
            title: title,
            subjectId: _subject.isEmpty ? null : _subject,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : '$error';
        });
      }
    }
  }

  Future<void> _createTask() async {
    final started = await TaskEditorDialog.showQuickStart(
      context,
      initialTitle: _title.text.trim(),
      initialSubjectId: _subject,
    );
    if (started && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
    return AlertDialog(
      title: const Text('今天想学什么？'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('输入内容名称即可开始计时，不需要先制定完整计划。'),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ad-hoc-title'),
                controller: _title,
                autofocus: true,
                enabled: !_busy,
                maxLength: 150,
                decoration: InputDecoration(
                  labelText: '学习内容名称',
                  hintText: '例如：背英语单词',
                  counterText: '',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('ad-hoc-subject'),
                initialValue: _subject,
                decoration: const InputDecoration(labelText: '课程/分类（可选）'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('不指定课程')),
                  for (final subject in data.subjects)
                    DropdownMenuItem(
                      value: subject.id,
                      child: Text(subject.name),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _subject = value ?? ''),
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
        TextButton(
          key: const Key('ad-hoc-create-task'),
          onPressed: _busy ? null : _createTask,
          child: const Text('创建正式事项'),
        ),
        FilledButton.icon(
          key: const Key('ad-hoc-start'),
          onPressed: _busy ? null : _start,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 18),
          label: const Text('开始计时'),
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

/// 把临时学习转为正式事项：确认课程/范围/估算/日期意图后，原日志与 session 标识
/// 保持不变（不复制分钟），随后用现有“安排时间块”预览对剩余周期的影响。
class AdHocConvertDialog extends ConsumerStatefulWidget {
  const AdHocConvertDialog({required this.adHocId, super.key});

  final String adHocId;

  static Future<void> show(BuildContext context, String adHocId) =>
      showDialog<void>(
        context: context,
        builder: (context) => AdHocConvertDialog(adHocId: adHocId),
      );

  @override
  ConsumerState<AdHocConvertDialog> createState() => _AdHocConvertDialogState();
}

class _AdHocConvertDialogState extends ConsumerState<AdHocConvertDialog> {
  late TaskDraft _draft;
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _estimated;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = ref.read(plannerSessionProvider).data;
    final entity = data.adHocLearnings
        .where((item) => item.id == widget.adHocId)
        .firstOrNull;
    final today = shanghaiToday();
    _draft = TaskDraft.blank(data, today).copyWith(
      title: entity?.title ?? '',
      subjectId: entity?.subjectId ?? TaskDraft.blank(data, today).subjectId,
      deadline: data.profile.resolvedPlanEnd(today),
      earliestDate: today,
    );
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
    if (_busy) return;
    final data = ref.read(plannerSessionProvider).data;
    final draft = _draft.copyWith(
      title: _title.text,
      description: _description.text.trim(),
      estimatedMinutes: int.tryParse(_estimated.text.trim()) ?? 0,
    );
    final error = validateTaskDraft(draft);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(plannerSessionProvider);
      final result = await session.convertAdHocToTask(
        adHocId: widget.adHocId,
        draft: draft,
      );
      await ref
          .read(studyTimerProvider)
          .adoptAdHocConversion(widget.adHocId, result.taskId);
      if (!mounted) return;
      final host = Navigator.of(context);
      final task = data.tasks
          .where((item) => item.id == result.taskId)
          .firstOrNull;
      host.pop();
      final navigatorContext = host.context;
      if (navigatorContext.mounted) {
        final name =
            task?.title ??
            ref
                .read(plannerSessionProvider)
                .data
                .tasks
                .where((item) => item.id == result.taskId)
                .firstOrNull
                ?.title ??
            draft.title;
        showPlannerMessage(
          navigatorContext,
          '已转为正式事项「${name.trim()}」：原计时记录和秒数保持不变。',
        );
        await ScheduleTaskDialog.show(navigatorContext, result.taskId);
      }
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
    final entity = data.adHocLearnings
        .where((item) => item.id == widget.adHocId)
        .firstOrNull;
    return AlertDialog(
      title: const Text('转为正式事项'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PlannerNotice(
                entity == null
                    ? '临时学习已不存在，请刷新后重试。'
                    : '已记录的临时学习用时（共 ${duration(day_ops.adHocTotalMinutes(data, entity.id))}）'
                          '会保留在历史中，只把归属更新为新事项，不会复制分钟。',
                tone: PlannerNoticeTone.info,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('ad-hoc-convert-title'),
                controller: _title,
                enabled: !_busy,
                maxLength: 150,
                decoration: const InputDecoration(
                  labelText: '事项名称',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                enabled: !_busy,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: '学习范围与完成标准',
                  hintText: '例如：了解曝光三要素并完成 3 组练习',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _draft.subjectId,
                decoration: const InputDecoration(labelText: '课程'),
                items: [
                  for (final subject in data.subjects)
                    DropdownMenuItem(
                      value: subject.id,
                      child: Text(subject.name),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(
                        () => _draft = _draft.copyWith(subjectId: value),
                      ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _estimated,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '预计总时长（分钟）',
                  helperText: '新增正式范围会占用剩余周期的容量',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 8),
              DateField(
                label: '开始日期',
                value: _draft.earliestDate,
                enabled: !_busy,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(earliestDate: value),
                ),
              ),
              const SizedBox(height: 8),
              DateField(
                label: '截止日期',
                value: _draft.deadline,
                enabled: !_busy,
                firstDate: _draft.earliestDate,
                onChanged: (value) =>
                    setState(() => _draft = _draft.copyWith(deadline: value)),
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
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const Key('ad-hoc-convert-save'),
          onPressed: _busy || entity == null ? null : _save,
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('转为正式事项并安排'),
        ),
      ],
    );
  }
}
