import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/application/study_timer.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/task_study_timer.dart'
    show showExtraStudyPauseFollowUp;
import 'tasks_dialogs.dart';

/// Flat task directory with optional multi-tag filtering.
class TaskDirectory extends ConsumerStatefulWidget {
  const TaskDirectory({required this.data, required this.editable, super.key});

  final PlannerData data;
  final bool editable;

  @override
  ConsumerState<TaskDirectory> createState() => _TaskDirectoryState();
}

class _TaskDirectoryState extends ConsumerState<TaskDirectory> {
  final Set<String> _selectedTagIds = {};

  @override
  void didUpdateWidget(covariant TaskDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    final existing = widget.data.tags.map((tag) => tag.id).toSet();
    _selectedTagIds.removeWhere((id) => !existing.contains(id));
  }

  Future<void> _editTask({Task? task}) async {
    final saved = await TaskDirectoryEditorDialog.show(context, task: task);
    if (saved == true && mounted) {
      showPlannerMessage(context, task == null ? '事项已添加' : '事项已保存');
    }
  }

  Future<void> _manageTags() async {
    await TagManagementDialog.show(context);
  }

  Future<void> _deleteTask(Task task) async {
    final confirmed = await confirmAction(
      context,
      title: '删除事项',
      message: '删除「${task.title}」后无法恢复，请确认。',
      confirmLabel: '确认删除',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(plannerSessionProvider).deleteTask(task.id);
      if (mounted) showPlannerMessage(context, '已删除「${task.title}」');
    } catch (error) {
      if (mounted) {
        showPlannerMessage(
          context,
          error is StateError ? error.message : '删除失败：$error',
          tone: PlannerNoticeTone.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsById = {for (final tag in widget.data.tags) tag.id: tag};
    final filtered =
        widget.data.tasks.where((task) {
          return _selectedTagIds.isEmpty ||
              task.tagIds.any(_selectedTagIds.contains);
        }).toList()..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '全部事项',
          count: filtered.length,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlannerIconAction(
                key: const Key('manage-tags-button'),
                tooltip: '管理标签',
                icon: Icons.sell_outlined,
                onPressed: widget.editable ? _manageTags : null,
              ),
              const SizedBox(width: PlannerSpace.sm),
              FilledButton.icon(
                key: const Key('new-task-button'),
                onPressed: widget.editable ? () => _editTask() : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建事项'),
              ),
            ],
          ),
        ),
        if (widget.data.tags.isNotEmpty) ...[
          const SizedBox(height: PlannerSpace.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '标签',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: PlannerColors.subtle,
                ),
              ),
              for (final tag in widget.data.tags)
                PlannerTag(
                  key: Key('task-filter-tag-${tag.id}'),
                  label: tag.name,
                  color: _tagColor(tag.color),
                  selected: _selectedTagIds.contains(tag.id),
                  onTap: () => setState(() {
                    _selectedTagIds.contains(tag.id)
                        ? _selectedTagIds.remove(tag.id)
                        : _selectedTagIds.add(tag.id);
                  }),
                ),
              if (_selectedTagIds.isNotEmpty)
                TextButton.icon(
                  key: const Key('clear-tag-filter-button'),
                  onPressed: () => setState(_selectedTagIds.clear),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.close, size: 13),
                  label: const Text('清除', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
        const SizedBox(height: PlannerSpace.md),
        if (filtered.isEmpty)
          _EmptyDirectory(
            icon: _selectedTagIds.isNotEmpty
                ? Icons.filter_alt_off_outlined
                : Icons.checklist_outlined,
            title: _selectedTagIds.isNotEmpty ? '没有匹配事项' : '还没有事项',
            hint: _selectedTagIds.isNotEmpty
                ? '清除标签筛选，或为事项添加所选标签。'
                : '直接创建事项即可开始安排和记录学习。',
            onAction: widget.editable
                ? (_selectedTagIds.isNotEmpty
                      ? () => setState(_selectedTagIds.clear)
                      : () => _editTask())
                : null,
            actionLabel: _selectedTagIds.isNotEmpty ? '清除筛选' : '新建事项',
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _TaskRow(
                    task: filtered[i],
                    tags: [
                      for (final id in filtered[i].tagIds)
                        if (tagsById[id] case final tag?) tag,
                    ],
                    editable: widget.editable,
                    onEdit: () => _editTask(task: filtered[i]),
                    onDelete: () => _deleteTask(filtered[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.tags,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });

  final Task task;
  final List<Tag> tags;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final archived = task.status == TaskStatus.archived;
    final completed = task.status == TaskStatus.completed;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: editable ? onEdit : null,
        hoverColor: PlannerColors.hover,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PlannerSpace.lg,
            12,
            PlannerSpace.sm,
            12,
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: archived || completed
                              ? PlannerColors.subtle
                              : PlannerColors.text,
                          decoration: completed
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: PlannerColors.subtle,
                        ),
                      ),
                    ),
                    if (completed)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 13,
                          color: PlannerColors.green,
                        ),
                      ),
                    if (archived)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: PlannerTag(label: '已归档', dense: true),
                      ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      for (final tag in tags.take(2))
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: PlannerTag(
                            label: tag.name,
                            color: _tagColor(tag.color),
                            dense: true,
                          ),
                        ),
                      if (tags.length > 2)
                        PlannerTag(label: '+${tags.length - 2}', dense: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: PlannerSpace.sm),
              _TaskExtraTimerButton(task: task, editable: editable),
              PopupMenuButton<_TaskMenuAction>(
                key: Key('task-menu-${task.id}'),
                tooltip: '编辑或删除事项',
                enabled: editable,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 150),
                icon: const Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: PlannerColors.muted,
                ),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _TaskMenuAction.edit,
                    height: 38,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 16),
                        SizedBox(width: 10),
                        Text('编辑事项'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _TaskMenuAction.delete,
                    height: 38,
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: PlannerColors.danger,
                        ),
                        SizedBox(width: 10),
                        Text(
                          '删除事项',
                          style: TextStyle(color: PlannerColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (action) =>
                    action == _TaskMenuAction.edit ? onEdit() : onDelete(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _tagColor(String? hex) {
  if (hex == null || hex.length < 7) return PlannerColors.muted;
  final value = int.tryParse(hex.substring(1), radix: 16);
  return value == null ? PlannerColors.muted : Color(0xff000000 | value);
}

class _TaskExtraTimerButton extends ConsumerWidget {
  const _TaskExtraTimerButton({required this.task, required this.editable});
  final Task task;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (task.status == TaskStatus.archived) return const SizedBox.shrink();
    final timer = ref.watch(studyTimerProvider);
    final date = shanghaiToday();
    final active = timer.activeTaskId == task.id;
    final hasExtraToday = timer.elapsedFor(task.id, date) > Duration.zero;
    final enabled = editable && timer.ready && !timer.busy;
    final tooltip = active
        ? '暂停计时'
        : task.status == TaskStatus.completed
        ? '复习计时'
        : hasExtraToday
        ? '继续加学计时'
        : '开始加学计时';
    return PlannerIconAction(
      key: Key('task-extra-timer-${task.id}'),
      tooltip: tooltip,
      icon: active ? Icons.pause : Icons.alarm,
      iconSize: 17,
      tone: active ? PlannerColors.orange : PlannerColors.muted,
      onPressed: enabled
          ? () async {
              try {
                if (active) {
                  await timer.pause();
                  if (context.mounted) {
                    showExtraStudyPauseFollowUp(context, ref, task.id);
                  }
                } else {
                  await timer.startExtra(task.id);
                }
              } catch (error) {
                if (context.mounted) {
                  showPlannerMessage(
                    context,
                    error is StateError ? error.message : '$error',
                    tone: PlannerNoticeTone.error,
                  );
                }
              }
            }
          : null,
    );
  }
}

enum _TaskMenuAction { edit, delete }

class _EmptyDirectory extends StatelessWidget {
  const _EmptyDirectory({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onAction,
    required this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onAction;
  final String actionLabel;

  @override
  Widget build(BuildContext context) => Card(
    child: PlannerEmpty(
      icon: icon,
      message: title,
      hint: hint,
      action: OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
    ),
  );
}
