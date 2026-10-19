import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/planner_format.dart';

/// Edits an item in the directory: only name, note and course are editable.
/// Scheduling fields keep their existing values (or the domain defaults for a
/// new item) and are intentionally not shown here.
class TaskDirectoryEditorDialog extends ConsumerStatefulWidget {
  const TaskDirectoryEditorDialog({this.task, this.subjectId, super.key});

  final Task? task;
  final String? subjectId;

  static Future<bool?> show(
    BuildContext context, {
    Task? task,
    String? subjectId,
  }) => showDialog<bool>(
    context: context,
    builder: (context) =>
        TaskDirectoryEditorDialog(task: task, subjectId: subjectId),
  );

  @override
  ConsumerState<TaskDirectoryEditorDialog> createState() =>
      _TaskDirectoryEditorDialogState();
}

class _TaskDirectoryEditorDialogState
    extends ConsumerState<TaskDirectoryEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _subjectId;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final data = ref.read(plannerSessionProvider).data;
    _title = TextEditingController(text: widget.task?.title ?? '');
    _description = TextEditingController(text: widget.task?.description ?? '');
    final requested = widget.subjectId ?? widget.task?.subjectId;
    _subjectId = data.subjects.any((subject) => subject.id == requested)
        ? requested!
        : data.subjects.isEmpty
        ? ''
        : data.subjects.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写事项名称');
      return;
    }
    if (_subjectId.isEmpty) {
      setState(() => _error = '请选择所属课程');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = ref.read(plannerSessionProvider);
      final data = session.data;
      final base = widget.task == null
          ? TaskDraft.blank(data, shanghaiToday())
          : TaskDraft.from(widget.task!);
      final draft = base.copyWith(
        title: title,
        description: _description.text.trim(),
        subjectId: _subjectId,
      );
      if (widget.task == null) {
        await session.createTask(draft);
      } else {
        await session.updateTask(widget.task!.id, draft);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is StateError ? error.message : '保存失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
    final subjects = data.subjects;
    return AlertDialog(
      title: Text(_editing ? '编辑事项' : '新建事项'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('task-title-field'),
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
                key: const Key('task-description-field'),
                controller: _description,
                enabled: !_saving,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: '说明（选填）',
                  helperText: '说明保存在事项数据里，但不会显示在目录列表中',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('task-course-field'),
                initialValue: _subjectId,
                decoration: const InputDecoration(labelText: '所属课程'),
                items: [
                  for (final subject in subjects)
                    DropdownMenuItem(
                      value: subject.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: subjectColor(subject.id, subject.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              subject.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _subjectId = value ?? ''),
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
        FilledButton(
          key: const Key('task-save-button'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

/// One available course accent for the create-course dialog.
class _CourseColor {
  const _CourseColor(this.hex, this.name);

  final String hex;
  final String name;

  Color get color => Color(0xff000000 | int.parse(hex.substring(1), radix: 16));
}

const _courseColors = [
  _CourseColor('#4565c7', '靛蓝'),
  _CourseColor('#1f7a5a', '松绿'),
  _CourseColor('#c2761f', '琥珀'),
  _CourseColor('#7a6bd0', '紫罗兰'),
  _CourseColor('#2b7f9e', '青蓝'),
  _CourseColor('#8a5a2b', '赭石'),
];

/// Creates an empty course folder from the directory page.
class CourseEditorDialog extends ConsumerStatefulWidget {
  const CourseEditorDialog({super.key});

  static Future<bool?> show(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (context) => const CourseEditorDialog(),
  );

  @override
  ConsumerState<CourseEditorDialog> createState() => _CourseEditorDialogState();
}

class _CourseEditorDialogState extends ConsumerState<CourseEditorDialog> {
  final _name = TextEditingController();
  _CourseColor _color = _courseColors.first;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写课程名称');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(plannerSessionProvider)
          .createCourse(name: name, color: _color.hex);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is StateError ? error.message : '创建失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建课程'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('course-name-field'),
                controller: _name,
                autofocus: true,
                enabled: !_saving,
                maxLength: 24,
                decoration: const InputDecoration(
                  labelText: '课程名称',
                  counterText: '',
                  hintText: '例如：概率论与数理统计',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 16),
              Text(
                '课程颜色',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final option in _courseColors)
                    Tooltip(
                      message: option.name,
                      child: Semantics(
                        label: option.name,
                        selected: option == _color,
                        button: true,
                        child: InkResponse(
                          key: Key('course-color-${option.hex}'),
                          onTap: _saving
                              ? null
                              : () => setState(() {
                                  _color = option;
                                  _error = null;
                                }),
                          radius: 24,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: option.color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: option == _color
                                    ? PlannerColors.text
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: option == _color
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 17,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.folder_outlined,
                    size: 16,
                    color: PlannerColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '创建后会得到一个空课程文件夹，可继续添加事项',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PlannerColors.muted,
                      ),
                    ),
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
        FilledButton(
          key: const Key('course-save-button'),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('创建课程'),
        ),
      ],
    );
  }
}
