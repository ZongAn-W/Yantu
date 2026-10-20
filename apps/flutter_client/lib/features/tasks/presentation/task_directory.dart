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

/// 「全部事项」目录：课程 → 事项的文件夹式目录。
///
/// 这是合并后「今日」页的下半部分，自身不滚动（由页面统一滚动）。搜索与
/// 课程筛选已移除，只保留「新建课程」。每个事项行在「⋯」之前有一个加学计时
/// 闹钟：未计时显示 ⏰，本事项计时中显示 ⏸，暂停后回到 ⏰。闹钟记录为「加学」
/// 关系（已完成事项为「复习计时」），计时中的事项会同步显示在今日加学里。
class TaskDirectory extends ConsumerStatefulWidget {
  const TaskDirectory({required this.data, required this.editable, super.key});

  final PlannerData data;
  final bool editable;

  @override
  ConsumerState<TaskDirectory> createState() => _TaskDirectoryState();
}

class _TaskDirectoryState extends ConsumerState<TaskDirectory> {
  Future<void> _openNewCourse() async {
    final created = await CourseEditorDialog.show(context);
    if (created != true || !mounted) return;
    showPlannerMessage(context, '课程已创建');
  }

  Future<void> _openTaskEditor({Task? task, String? subjectId}) async {
    final saved = await TaskDirectoryEditorDialog.show(
      context,
      task: task,
      subjectId: subjectId,
    );
    if (saved != true || !mounted) return;
    showPlannerMessage(context, task == null ? '事项已添加' : '事项已保存');
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
      if (!mounted) return;
      showPlannerMessage(context, '已删除「${task.title}」');
    } catch (error) {
      if (!mounted) return;
      showPlannerMessage(
        context,
        error is StateError ? error.message : '删除失败：$error',
        tone: PlannerNoticeTone.error,
      );
    }
  }

  List<_CourseGroup> _groups() {
    final data = widget.data;
    return [
      for (final subject in data.subjects)
        _CourseGroup(
          subject: subject,
          tasks: data.tasks
              .where((task) => task.subjectId == subject.id)
              .toList(growable: false),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final editable = widget.editable;
    final groups = _groups();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(
              header: true,
              child: Text(
                '全部事项',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              key: const Key('new-course-button'),
              onPressed: editable ? _openNewCourse : null,
              icon: const Icon(Icons.add, size: 17),
              label: const Text('新建课程'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 12 : 14),
        if (widget.data.subjects.isEmpty)
          _EmptyDirectory(
            icon: Icons.folder_open_outlined,
            title: '还没有课程',
            hint: '先新建一门课程，再往课程里添加事项。',
            onAction: editable ? _openNewCourse : null,
            actionLabel: '新建课程',
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth.clamp(0.0, 1200.0);
              final twoColumns = groups.length > 1 && contentWidth >= 760;
              final itemIndent = compact ? 15.0 : 65.0;
              if (twoColumns) {
                return _twoColumnBoard(
                  groups,
                  editable: editable,
                  itemIndent: itemIndent,
                  compact: compact,
                );
              }
              return _singleColumnBoard(
                groups,
                editable: editable,
                itemIndent: itemIndent,
                compact: compact,
              );
            },
          ),
      ],
    );
  }

  Widget _singleColumnBoard(
    List<_CourseGroup> groups, {
    required bool editable,
    required double itemIndent,
    required bool compact,
  }) {
    final gap = compact ? 12.0 : 16.0;
    return Column(
      key: const Key('tasks-single-column'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          _CourseFolder(
            group: groups[index],
            editable: editable,
            compact: compact,
            itemIndent: itemIndent,
            onAddTask: (subjectId) => _openTaskEditor(subjectId: subjectId),
            onEditTask: (task) => _openTaskEditor(task: task),
            onDeleteTask: _deleteTask,
          ),
          if (index != groups.length - 1) SizedBox(height: gap),
        ],
      ],
    );
  }

  Widget _twoColumnBoard(
    List<_CourseGroup> groups, {
    required bool editable,
    required double itemIndent,
    required bool compact,
  }) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (var index = 0; index < groups.length; index++) {
      final card = _CourseFolder(
        group: groups[index],
        editable: editable,
        compact: compact,
        itemIndent: itemIndent,
        onAddTask: (subjectId) => _openTaskEditor(subjectId: subjectId),
        onEditTask: (task) => _openTaskEditor(task: task),
        onDeleteTask: _deleteTask,
      );
      (index.isEven ? left : right).add(card);
    }
    Widget column(List<Widget> cards) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < cards.length; index++) ...[
          cards[index],
          if (index != cards.length - 1) const SizedBox(height: 18),
        ],
      ],
    );
    return Row(
      key: const Key('tasks-two-columns'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column(left)),
        const SizedBox(width: 18),
        Expanded(child: column(right)),
      ],
    );
  }
}

class _CourseGroup {
  const _CourseGroup({required this.subject, required this.tasks});

  final Subject subject;
  final List<Task> tasks;
}

class _CourseFolder extends StatelessWidget {
  const _CourseFolder({
    required this.group,
    required this.editable,
    required this.compact,
    required this.itemIndent,
    required this.onAddTask,
    required this.onEditTask,
    required this.onDeleteTask,
  });

  final _CourseGroup group;
  final bool editable;
  final bool compact;
  final double itemIndent;
  final ValueChanged<String> onAddTask;
  final ValueChanged<Task> onEditTask;
  final ValueChanged<Task> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    final subject = group.subject;
    final accent = subjectColor(subject.id, subject.color);
    final spine = Color.lerp(accent, Colors.white, 0.52)!;
    final countText = '${group.tasks.length} 个事项';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PlannerColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding: EdgeInsets.fromLTRB(compact ? 13 : 16, 11, 6, 11),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 34 : 38,
                      height: compact ? 34 : 38,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(compact ? 9 : 10),
                      ),
                      child: Icon(
                        _courseIcon(subject.name),
                        color: Colors.white,
                        size: compact ? 17 : 19,
                      ),
                    ),
                    SizedBox(width: compact ? 10 : 11),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              subject.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 15 : 15.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            countText,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: PlannerColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      key: Key('course-add-${subject.id}'),
                      onPressed: editable ? () => onAddTask(subject.id) : null,
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('添加事项'),
                      style: TextButton.styleFrom(
                        foregroundColor: PlannerColors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: TextStyle(
                          fontSize: compact ? 12 : 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: const Color(0xFFE9EEF4)),
              if (group.tasks.isEmpty)
                _EmptyCourse(compact: compact)
              else
                for (var index = 0; index < group.tasks.length; index++) ...[
                  if (index > 0)
                    Container(height: 1, color: const Color(0xFFE9EEF4)),
                  _TaskRow(
                    task: group.tasks[index],
                    editable: editable,
                    indent: itemIndent,
                    compact: compact,
                    onEdit: onEditTask,
                    onDelete: onDeleteTask,
                  ),
                ],
            ],
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: spine),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.editable,
    required this.indent,
    required this.compact,
    required this.onEdit,
    required this.onDelete,
  });

  final Task task;
  final bool editable;
  final double indent;
  final bool compact;
  final ValueChanged<Task> onEdit;
  final ValueChanged<Task> onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        indent,
        compact ? 10 : 12,
        4,
        compact ? 10 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              task.title,
              style: TextStyle(
                fontSize: compact ? 14 : 14.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          _TaskExtraTimerButton(
            task: task,
            editable: editable,
            compact: compact,
          ),
          PopupMenuButton<_TaskMenuAction>(
            key: Key('task-menu-${task.id}'),
            tooltip: '编辑或删除事项',
            enabled: editable,
            padding: EdgeInsets.zero,
            icon: const Icon(
              Icons.more_horiz,
              size: 20,
              color: PlannerColors.muted,
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _TaskMenuAction.edit,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.edit_outlined, size: 18),
                  title: Text('编辑事项'),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: _TaskMenuAction.delete,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: PlannerColors.danger,
                  ),
                  title: Text(
                    '删除事项',
                    style: TextStyle(color: PlannerColors.danger),
                  ),
                  dense: true,
                ),
              ),
            ],
            onSelected: (action) {
              switch (action) {
                case _TaskMenuAction.edit:
                  onEdit(task);
                case _TaskMenuAction.delete:
                  onDelete(task);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// 事项行的加学计时按钮：未计时 ⏰、本事项计时中 ⏸、暂停 ⏰。
///
/// 开始/继续时调用 [StudyTimer.startExtra]，记录为加学（已完成事项为复习）；
/// 计时中的事项会出现在今日页上方的「今日加学」。已归档事项不提供入口。
class _TaskExtraTimerButton extends ConsumerWidget {
  const _TaskExtraTimerButton({
    required this.task,
    required this.editable,
    required this.compact,
  });

  final Task task;
  final bool editable;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (task.status == TaskStatus.archived) return const SizedBox.shrink();
    final timer = ref.watch(studyTimerProvider);
    final date = shanghaiToday();
    final active = timer.activeTaskId == task.id;
    final hasExtraToday = timer.elapsedFor(task.id, date) > Duration.zero;
    final enabled = editable && timer.ready && !timer.busy;
    final tooltip = switch (task.status) {
      _ when active => '暂停计时',
      TaskStatus.completed => '复习计时',
      _ when hasExtraToday => '继续加学计时',
      _ => '开始加学计时',
    };
    final size = compact ? 38.0 : 32.0;
    return IconButton(
      key: Key('task-extra-timer-${task.id}'),
      tooltip: tooltip,
      onPressed: enabled
          ? () => _toggle(context, ref, timer, active: active)
          : null,
      icon: Icon(
        active ? Icons.pause : Icons.alarm,
        size: compact ? 21 : 20,
        color: active ? PlannerColors.blue : PlannerColors.muted,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    StudyTimer timer, {
    required bool active,
  }) async {
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
      if (!context.mounted) return;
      showPlannerMessage(
        context,
        error is StateError ? error.message : '$error',
        tone: PlannerNoticeTone.error,
      );
    }
  }
}

enum _TaskMenuAction { edit, delete }

class _EmptyCourse extends StatelessWidget {
  const _EmptyCourse({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 96 : 104),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_open_outlined,
            size: 18,
            color: PlannerColors.muted,
          ),
          const SizedBox(height: 6),
          Text(
            '这门课程还没有事项',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: PlannerColors.muted),
          ),
          const SizedBox(height: 3),
          Text(
            '可使用上方「添加事项」创建第一个事项',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PlannerColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

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
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PlannerColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 42),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFEEF3F8),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: PlannerColors.muted),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 5),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: PlannerColors.muted,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

IconData _courseIcon(String name) {
  final value = name.toLowerCase();
  if (value.contains('高数') ||
      value.contains('数学') ||
      value.contains('微积分') ||
      value.contains('线代') ||
      value.contains('概率')) {
    return Icons.functions;
  }
  if (value.contains('英语') ||
      value.contains('外语') ||
      value.contains('语言') ||
      value.contains('翻译')) {
    return Icons.translate;
  }
  if (value.contains('数据结构') || value.contains('算法')) {
    return Icons.account_tree_outlined;
  }
  if (value.contains('网络')) return Icons.public;
  if (value.contains('操作系统')) return Icons.desktop_windows_outlined;
  if (value.contains('组成') || value.contains('计算机系统')) {
    return Icons.memory;
  }
  if (value.contains('政治')) return Icons.account_balance_outlined;
  if (value.contains('物理') || value.contains('化学')) {
    return Icons.science_outlined;
  }
  return Icons.menu_book_outlined;
}
