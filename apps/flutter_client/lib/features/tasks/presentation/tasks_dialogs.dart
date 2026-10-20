import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/planner_format.dart';

class TaskDirectoryEditorDialog extends ConsumerStatefulWidget {
  const TaskDirectoryEditorDialog({this.task, super.key});
  final Task? task;

  static Future<bool?> show(BuildContext context, {Task? task}) =>
      showDialog<bool>(
        context: context,
        builder: (context) => TaskDirectoryEditorDialog(task: task),
      );

  @override
  ConsumerState<TaskDirectoryEditorDialog> createState() =>
      _TaskDirectoryEditorDialogState();
}

class _TaskDirectoryEditorDialogState
    extends ConsumerState<TaskDirectoryEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _newTag;
  late final Set<String> _tagIds;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.task != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task?.title ?? '');
    _description = TextEditingController(text: widget.task?.description ?? '');
    _newTag = TextEditingController();
    _tagIds = {...?widget.task?.tagIds};
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _newTag.dispose();
    super.dispose();
  }

  Future<void> _addTag() async {
    try {
      final id = await ref
          .read(plannerSessionProvider)
          .createTag(name: _newTag.text);
      if (!mounted) return;
      setState(() {
        _tagIds.add(id);
        _newTag.clear();
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError ? error.message : '$error');
      }
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写事项名称');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = ref.read(plannerSessionProvider);
      final base = widget.task == null
          ? TaskDraft.blank(session.data, shanghaiToday())
          : TaskDraft.from(widget.task!);
      final draft = base.copyWith(
        title: title,
        description: _description.text.trim(),
        tagIds: _tagIds.toList(growable: false),
      );
      if (widget.task == null) {
        await session.createTask(draft);
      } else {
        await session.updateTask(widget.task!.id, draft);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError ? error.message : '保存失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerSessionProvider).data;
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '标签（选填）',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (_tagIds.isNotEmpty)
                    TextButton.icon(
                      key: const Key('clear-task-tags-button'),
                      onPressed: _saving ? null : () => setState(_tagIds.clear),
                      icon: const Icon(Icons.close, size: 15),
                      label: const Text('清除全部'),
                    ),
                ],
              ),
              if (data.tags.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '暂无标签，可以直接保存未标记事项。',
                    style: TextStyle(color: PlannerColors.muted, fontSize: 12),
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in data.tags)
                      FilterChip(
                        key: Key('task-tag-${tag.id}'),
                        label: Text(tag.name),
                        selected: _tagIds.contains(tag.id),
                        avatar: _tagDot(tag),
                        onSelected: _saving
                            ? null
                            : (selected) => setState(() {
                                selected
                                    ? _tagIds.add(tag.id)
                                    : _tagIds.remove(tag.id);
                              }),
                      ),
                  ],
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('new-task-tag-field'),
                      controller: _newTag,
                      enabled: !_saving,
                      maxLength: 24,
                      decoration: const InputDecoration(
                        labelText: '新标签名称',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    key: const Key('add-task-tag-button'),
                    tooltip: '创建并添加标签',
                    onPressed: _saving ? null : _addTag,
                    icon: const Icon(Icons.add_circle_outline),
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

class TagManagementDialog extends ConsumerStatefulWidget {
  const TagManagementDialog({super.key});
  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const TagManagementDialog(),
  );

  @override
  ConsumerState<TagManagementDialog> createState() =>
      _TagManagementDialogState();
}

class _TagManagementDialogState extends ConsumerState<TagManagementDialog> {
  final _newName = TextEditingController();
  String? _error;
  bool _busy = false;
  static const _colors = [
    '#4565c7',
    '#1f7a5a',
    '#c2761f',
    '#7a6bd0',
    '#2b7f9e',
    '#8a5a2b',
  ];

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      await ref.read(plannerSessionProvider).createTag(name: _newName.text);
      if (mounted)
        setState(() {
          _newName.clear();
          _error = null;
          _busy = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _error = error is StateError ? error.message : '$error';
          _busy = false;
        });
    }
  }

  Future<void> _rename(Tag tag) async {
    final controller = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '标签名称', counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    try {
      await ref.read(plannerSessionProvider).renameTag(tag.id, name);
    } catch (error) {
      if (mounted)
        setState(() => _error = error is StateError ? error.message : '$error');
    }
  }

  Future<void> _delete(Tag tag) async {
    final count = ref
        .read(plannerSessionProvider)
        .data
        .tasks
        .where((task) => task.tagIds.contains(tag.id))
        .length;
    final confirmed = await confirmAction(
      context,
      title: '删除标签',
      message: count == 0
          ? '删除「${tag.name}」？'
          : '「${tag.name}」当前用于 $count 个事项。删除后只会解除这个标签，事项、日程、学习记录和其他标签都会保留。',
      confirmLabel: '删除标签',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(plannerSessionProvider).deleteTag(tag.id);
  }

  Future<void> _recolor(Tag tag, String? color) async {
    await ref.read(plannerSessionProvider).recolorTag(tag.id, color);
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(plannerSessionProvider).data.tags;
    return AlertDialog(
      title: const Text('标签管理'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tags.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('还没有标签'))
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final tag in tags)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _tagDot(tag, size: 14),
                        title: Text(tag.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PopupMenuButton<String?>(
                              tooltip: '修改颜色',
                              onSelected: (color) =>
                                  _recolor(tag, color == 'none' ? null : color),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'none',
                                  child: Text('默认颜色'),
                                ),
                                for (final color in _colors)
                                  PopupMenuItem(
                                    value: color,
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: _color(color),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(color),
                                      ],
                                    ),
                                  ),
                              ],
                              icon: const Icon(Icons.palette_outlined),
                            ),
                            IconButton(
                              tooltip: '重命名',
                              onPressed: () => _rename(tag),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: '删除标签',
                              onPressed: () => _delete(tag),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: PlannerColors.danger,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('new-managed-tag-field'),
                    controller: _newName,
                    enabled: !_busy,
                    maxLength: 24,
                    decoration: const InputDecoration(
                      labelText: '新标签',
                      counterText: '',
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                IconButton(
                  tooltip: '创建标签',
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (_error != null)
              PlannerNotice(_error!, tone: PlannerNoticeTone.error),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

Widget _tagDot(Tag tag, {double size = 10}) {
  final color = tag.color == null ? PlannerColors.blue : _color(tag.color!);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

Color _color(String hex) =>
    Color(0xff000000 | int.parse(hex.substring(1), radix: 16));
