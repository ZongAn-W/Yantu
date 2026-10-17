import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../application/planner_session.dart';
import '../domain/planner_format.dart';
import '../domain/scheduler/planner_scheduler.dart' as scheduler;
import '../domain/study_day.dart' as day_ops;
import '../domain/study_day.dart' show unscheduledTaskMinutes;

/// Records the accumulated minutes of one task on one day.
///
/// The value is the day total, matching the Web "记录实际用时" dialog: writing it
/// again corrects the day instead of adding to it.
class RecordTimeDialog extends ConsumerStatefulWidget {
  const RecordTimeDialog({required this.date, this.taskId, super.key});

  final String date;
  final String? taskId;

  static Future<void> show(
    BuildContext context, {
    required String date,
    String? taskId,
  }) => showDialog<void>(
    context: context,
    builder: (context) => RecordTimeDialog(date: date, taskId: taskId),
  );

  @override
  ConsumerState<RecordTimeDialog> createState() => _RecordTimeDialogState();
}

class _RecordTimeDialogState extends ConsumerState<RecordTimeDialog> {
  late String _subjectId;
  late String _taskId;
  late TextEditingController _minutes;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = ref.read(plannerSessionProvider).data;
    final task = widget.taskId == null
        ? null
        : data.tasks.where((item) => item.id == widget.taskId).firstOrNull;
    _subjectId = task?.subjectId ?? data.subjects.first.id;
    _taskId =
        task?.id ??
        data.tasks
            .where(
              (item) =>
                  item.subjectId == _subjectId &&
                  item.status != TaskStatus.archived,
            )
            .firstOrNull
            ?.id ??
        '';
    _minutes = TextEditingController(
      text: '${day_ops.taskDayMinutes(data, _taskId, widget.date)}',
    );
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _selectTask(String taskId) {
    final data = ref.read(plannerSessionProvider).data;
    setState(() {
      _taskId = taskId;
      _minutes.text = '${day_ops.taskDayMinutes(data, taskId, widget.date)}';
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final parsed = int.tryParse(_minutes.text.trim());
    if (parsed == null || parsed < 0 || parsed > 1440) {
      setState(() => _error = '请输入 0 至 1440 的整数分钟');
      return;
    }
    if (_taskId.isEmpty) {
      setState(() => _error = '请先创建并选择事项');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(plannerSessionProvider)
          .recordDayMinutes(_taskId, widget.date, parsed);
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
    final task = data.tasks.where((item) => item.id == _taskId).firstOrNull;
    final planned = task == null
        ? 0
        : day_ops.taskDayPlannedMinutes(data, task.id, widget.date);
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    final subjects = data.subjects
        .where(
          (subject) => data.tasks.any(
            (item) =>
                item.subjectId == subject.id &&
                item.status != TaskStatus.archived,
          ),
        )
        .toList();
    return AlertDialog(
      title: const Text('记录实际用时'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('${widget.date} · 当天累计用时'),
                ],
              ),
              const SizedBox(height: 12),
              if (task != null)
                Row(
                  children: [
                    SubjectChip(
                      name: _subjectName(data, task.subjectId),
                      color: subjectColor(
                        task.subjectId,
                        data.subjects
                            .where((item) => item.id == task.subjectId)
                            .firstOrNull
                            ?.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: subjects.any((s) => s.id == _subjectId)
                      ? _subjectId
                      : subjects.firstOrNull?.id,
                  decoration: const InputDecoration(labelText: '课程'),
                  items: [
                    for (final subject in subjects)
                      DropdownMenuItem(
                        value: subject.id,
                        child: Text(subject.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          final next = data.tasks
                              .where(
                                (item) =>
                                    item.subjectId == value &&
                                    item.status != TaskStatus.archived,
                              )
                              .firstOrNull;
                          setState(() {
                            _subjectId = value;
                            if (next != null) _selectTask(next.id);
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: data.tasks.any((item) => item.id == _taskId)
                      ? _taskId
                      : null,
                  decoration: const InputDecoration(labelText: '事项'),
                  items: [
                    for (final item in data.tasks.where(
                      (item) =>
                          item.subjectId == _subjectId &&
                          item.status != TaskStatus.archived,
                    ))
                      DropdownMenuItem(value: item.id, child: Text(item.title)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) _selectTask(value);
                        },
                ),
              ],
              const SizedBox(height: 16),
              TimeProgressTrack(
                planned: planned,
                actual: minutes,
                color: subjectColor(
                  task?.subjectId ?? _subjectId,
                  data.subjects
                      .where(
                        (item) => item.id == (task?.subjectId ?? _subjectId),
                      )
                      .firstOrNull
                      ?.color,
                ),
                semanticsLabel: '记录用时与计划对比',
              ),
              const SizedBox(height: 6),
              Text(
                planned == 0
                    ? '今天未安排此事项，可直接记录用时'
                    : minutes > planned
                    ? '超出计划 ${duration(minutes - planned)}'
                    : minutes >= planned
                    ? '已达到计划时长'
                    : minutes == 0
                    ? '尚未记录用时'
                    : '距计划还差 ${duration(planned - minutes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _minutes,
                autofocus: true,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '实际用时（分钟）',
                  helperText: '再次填写会修正当天总时长，不会重复相加',
                ),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final preset in const [30, 60, 90, 120])
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _minutes.text = '$preset';
                              _error = null;
                            }),
                      child: Text(duration(preset)),
                    ),
                  if (planned > 0 && planned <= 1440)
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _minutes.text = '$planned';
                              _error = null;
                            }),
                      icon: const Icon(Icons.check, size: 15),
                      label: Text('按计划填写 · ${duration(planned)}'),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
          label: const Text('保存实际用时'),
        ),
      ],
    );
  }

  String _subjectName(PlannerData data, String subjectId) =>
      data.subjects
          .where((subject) => subject.id == subjectId)
          .firstOrNull
          ?.name ??
      subjectId;
}

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
  late String _date;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = widget.blocks.first.date;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(plannerSessionProvider).moveTaskDay(widget.blocks, _date);
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

  bool get _movable {
    final data = ref.read(plannerSessionProvider).data;
    final first = widget.blocks.first;
    final task = data.tasks
        .where((item) => item.id == first.taskId)
        .firstOrNull;
    if (task == null || task.status == TaskStatus.archived) return false;
    if (day_ops.taskDayMinutes(data, task.id, first.date) > 0) return false;
    return widget.blocks.every(
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

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
    final task = data.tasks
        .where((item) => item.id == widget.blocks.first.taskId)
        .firstOrNull;
    final planned = widget.blocks.fold<int>(
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
              enabled: _movable && !_saving,
              onChanged: (value) => setState(() => _date = value),
            ),
            const SizedBox(height: 8),
            const Text(
              '只调整日期，不指定学习开始时间。实际学习用时请使用“记录用时”。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
            if (!_movable) ...[
              const SizedBox(height: 8),
              const Text(
                '已记录用时、已完成或固定的计划保留在原日期。',
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
          onPressed: !_movable || _saving ? null : _save,
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
  const TaskEditorDialog({this.taskId, super.key});

  final String? taskId;

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
        await session.createTask(draft);
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

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
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

/// "标记事项完成" dialog: records the last session and completes the task.
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
  final _minutes = TextEditingController(text: '0');
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final parsed = int.tryParse(_minutes.text.trim());
    if (parsed == null || parsed < 0 || parsed > 1440) {
      setState(() => _error = '请输入 0 至 1440 的整数分钟');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(plannerSessionProvider)
          .completeTask(
            widget.taskId,
            actualMinutes: parsed,
            date: shanghaiToday(),
          );
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
            TextField(
              controller: _minutes,
              autofocus: true,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '本次实际学习时长（分钟）'),
            ),
            const SizedBox(height: 8),
            const Text(
              '仅把你填写的时长计入进度；标记完成会停止安排这项事项。',
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

/// "创建固定事件" dialog, including the timed-mode overlap check.
class FixedEventDialog extends ConsumerStatefulWidget {
  const FixedEventDialog({this.date, super.key});

  final String? date;

  static Future<void> show(BuildContext context, {String? date}) =>
      showDialog<void>(
        context: context,
        builder: (context) => FixedEventDialog(date: date),
      );

  @override
  ConsumerState<FixedEventDialog> createState() => _FixedEventDialogState();
}

class _FixedEventDialogState extends ConsumerState<FixedEventDialog> {
  late String _date;
  final _title = TextEditingController();
  final _minutes = TextEditingController(text: '60');
  TimeOfDay _time = const TimeOfDay(hour: 12, minute: 0);
  FixedEventKind _kind = FixedEventKind.rest;
  EventRepeat _repeat = EventRepeat.none;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = widget.date ?? shanghaiToday();
  }

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final minutes = int.tryParse(_minutes.text.trim());
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写事件名称');
      return;
    }
    if (minutes == null || minutes < 30 || minutes > 840) {
      setState(() => _error = '时长需要在 30 至 840 分钟之间');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = ref.read(plannerSessionProvider).data;
    final event = FixedEvent(
      id: scheduler.newUuid(),
      userId: data.profile.userId,
      title: _title.text.trim(),
      date: _date,
      startMinute: _time.hour * 60 + _time.minute,
      durationMinutes: minutes,
      kind: _kind,
      repeat: _repeat,
      createdAt: nowIso(),
      updatedAt: nowIso(),
    );
    try {
      await ref.read(plannerSessionProvider).createFixedEvent(event);
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
    return AlertDialog(
      title: const Text('创建固定事件'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                enabled: !_saving,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: '事件名称',
                  counterText: '',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              DateField(
                label: '日期',
                value: _date,
                enabled: !_saving,
                onChanged: (value) => setState(() => _date = value),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('开始时间'),
                subtitle: Text(_time.format(context)),
                trailing: const Icon(Icons.schedule),
                onTap: _saving
                    ? null
                    : () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _time,
                          helpText: '开始时间',
                        );
                        if (picked != null) setState(() => _time = picked);
                      },
              ),
              TextField(
                controller: _minutes,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: '时长（分钟）'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FixedEventKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: '类型'),
                items: [
                  for (final kind in FixedEventKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(fixedEventKindLabels[kind]!),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _kind = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<EventRepeat>(
                initialValue: _repeat,
                decoration: const InputDecoration(labelText: '重复'),
                items: [
                  for (final repeat in EventRepeat.values)
                    DropdownMenuItem(
                      value: repeat,
                      child: Text(fixedEventRepeatLabels[repeat]!),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _repeat = value!),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
          icon: const Icon(Icons.lock_outline, size: 18),
          label: const Text('保存固定事件'),
        ),
      ],
    );
  }
}

class DailyReviewDialog extends ConsumerStatefulWidget {
  const DailyReviewDialog({required this.date, super.key});

  final String date;

  static Future<void> show(BuildContext context, {required String date}) =>
      showDialog<void>(
        context: context,
        builder: (context) => DailyReviewDialog(date: date),
      );

  @override
  ConsumerState<DailyReviewDialog> createState() => _DailyReviewDialogState();
}

class _DailyReviewDialogState extends ConsumerState<DailyReviewDialog> {
  late List<day_ops.TaskDayReview> _entries;
  late final List<day_ops.TaskDayReview> _originalEntries;
  late final String _originalFeedback;
  final _feedback = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = ref.read(plannerSessionProvider).data;
    _originalEntries = day_ops.dailyReviewEntries(data, widget.date);
    _entries = [..._originalEntries];
    _originalFeedback = data.dailyFeedback?[widget.date] ?? '';
    _feedback.text = _originalFeedback;
  }

  void _updateEntry(day_ops.TaskDayReview value) => setState(() {
    _entries = [
      for (final entry in _entries)
        entry.taskId == value.taskId ? value : entry,
    ];
  });

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = ref.read(plannerSessionProvider);
      await session.saveDailyReview(
        widget.date,
        original: _originalEntries,
        edited: _entries,
        originalFeedback: _originalFeedback,
        feedback: _feedback.text,
      );
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
    return AlertDialog(
      title: Text('${widget.date} · 结束今天'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('记录今天完成到哪里；本机先保存，服务端结算在下一阶段接入。'),
              const SizedBox(height: 12),
              if (_entries.isEmpty)
                const PlannerEmpty(
                  message: '今天没有安排，无需结算。',
                  icon: Icons.event_available_outlined,
                ),
              for (final entry in _entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${subjectNameOf(data, data.tasks.where((t) => t.id == entry.taskId).firstOrNull?.subjectId ?? '')} · '
                        '${data.tasks.where((t) => t.id == entry.taskId).firstOrNull?.title ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: '${entry.actualMinutes}',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: '实际用时',
                              ),
                              enabled: !_saving,
                              onChanged: (value) => _updateEntry(
                                entry.copyWith(
                                  actualMinutes: int.tryParse(value) ?? 0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<CompletionStatus>(
                              initialValue: entry.completionStatus,
                              decoration: const InputDecoration(
                                labelText: '完成程度',
                              ),
                              items: [
                                for (final status in CompletionStatus.values)
                                  DropdownMenuItem(
                                    value: status,
                                    child: Text(
                                      completionStatusLabels[status]!,
                                    ),
                                  ),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (value) => _updateEntry(
                                      entry.copyWith(completionStatus: value!),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: entry.feedback,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: '卡点或反馈',
                          hintText: '可选',
                        ),
                        onChanged: (value) =>
                            _updateEntry(entry.copyWith(feedback: value)),
                      ),
                    ],
                  ),
                ),
              TextField(
                controller: _feedback,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '今天整体反馈',
                  hintText: '例如：上午效率低，复合函数求导仍不熟。',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
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
          onPressed: _saving || _entries.isEmpty ? null : _save,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('保存今日记录'),
        ),
      ],
    );
  }
}

/// Shared preview/confirm dialog for the local domain replanning.
class ReplanDialog extends ConsumerStatefulWidget {
  const ReplanDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const ReplanDialog(),
  );

  @override
  ConsumerState<ReplanDialog> createState() => _ReplanDialogState();
}

class _ReplanDialogState extends ConsumerState<ReplanDialog> {
  ReplanMode _mode = ReplanMode.unfinished;
  ReplanPreview? _preview;
  String? _error;
  bool _busy = true;

  /// Captured while the element is still mounted: `ref` must not be used from
  /// `dispose`, and an unconfirmed preview must never leak into the coordinator.
  late final PlannerSession _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(plannerSessionProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  @override
  void dispose() {
    _session.cancelReplan();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = _session.data;
      final excess = day_ops.dayStats(data, shanghaiToday()).excess;
      final preview = await _session.previewReplan(
        today: shanghaiToday(),
        mode: _mode,
        excessMinutes: excess,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _busy = false;
        });
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

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.confirmReplan();
      if (mounted) {
        Navigator.pop(context);
        showPlannerMessage(
          context,
          '调整已确认并保存到本机，随后同步到云端。',
          tone: PlannerNoticeTone.success,
        );
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
    final preview = _preview;
    final excess = day_ops.dayStats(data, shanghaiToday()).excess;
    final added = preview?.changes
        .where((change) => change.type == ChangeType.added)
        .length;
    final deleted = preview?.changes
        .where((change) => change.type == ChangeType.deleted)
        .length;
    return AlertDialog(
      title: const Text('重排预览'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('保守调整 · 确认前不会修改计划'),
            const SizedBox(height: 12),
            SegmentedButton<ReplanMode>(
              segments: const [
                ButtonSegment(
                  value: ReplanMode.unfinished,
                  label: Text('未完成顺延 · 未来14天'),
                ),
                ButtonSegment(
                  value: ReplanMode.overcompleted,
                  label: Text('超额提前 · 未来7天'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (values) {
                      setState(() => _mode = values.single);
                      _generate();
                    },
            ),
            if (_mode == ReplanMode.overcompleted) ...[
              const SizedBox(height: 8),
              Text(
                '今日可用超额容量：${duration(excess)}，仅小范围提前事项。',
                style: const TextStyle(
                  color: PlannerColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              PlannerNotice(_error!, tone: PlannerNoticeTone.error),
            if (!_busy && preview != null) ...[
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text('顺延 ${preview.postponed.length}'),
                  Text('提前 ${preview.advanced.length}'),
                  Text('新增 ${added ?? 0}'),
                  Text('删除 ${deleted ?? 0}'),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    Text('事项变化', style: Theme.of(context).textTheme.titleSmall),
                    if (preview.changes.isEmpty)
                      const PlannerEmpty(
                        message: '没有需要调整的时间块。',
                        icon: Icons.check_circle_outline,
                      ),
                    for (final change in preview.changes)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          data.tasks
                                  .where(
                                    (task) =>
                                        task.id ==
                                        (change.after ?? change.before)?.taskId,
                                  )
                                  .firstOrNull
                                  ?.title ??
                              '',
                        ),
                        subtitle: Text(
                          '${change.before?.date ?? '新增'} → '
                          '${change.after?.date ?? '删除'} · '
                          '${duration((change.after ?? change.before)!.durationMinutes)}',
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '每日学习时长',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final change in preview.dailyChanges)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(change.date),
                        subtitle: Text(
                          '${duration(change.beforeMinutes)} → '
                          '${duration(change.afterMinutes)}',
                        ),
                      ),
                    if (preview.conflicts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            size: 18,
                            color: PlannerColors.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '容量冲突',
                            style: TextStyle(color: PlannerColors.orange),
                          ),
                        ],
                      ),
                      for (final conflict in preview.conflicts)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${conflict.title} · ${duration(conflict.minutes)}',
                          ),
                          subtitle: Text(conflict.reason),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消调整'),
        ),
        FilledButton.icon(
          onPressed: _busy || preview == null ? null : _confirm,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('确认调整'),
        ),
      ],
    );
  }
}
