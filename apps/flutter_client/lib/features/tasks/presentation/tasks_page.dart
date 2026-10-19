import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/presentation/planner_page_state.dart';
import 'tasks_dialogs.dart';

/// `/tasks` — a course-first directory of learning items.
///
/// Courses are the visual unit. Items live directly inside a course folder and
/// only show their title; descriptions are maintained in the editor but never
/// rendered in this list. Wide layouts use two independent column flows so an
/// uneven course never leaves a gap in the opposite column.
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _search = TextEditingController();
  String _subjectFilter = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openNewCourse() async {
    final created = await CourseEditorDialog.show(context);
    if (created != true || !mounted) return;
    setState(() {
      _search.clear();
      _subjectFilter = 'all';
    });
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

  @override
  Widget build(BuildContext context) {
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        return _TasksDirectory(
          data: data,
          editable: snapshot.editable,
          search: _search,
          subjectFilter: _subjectFilter,
          onSearchChanged: () => setState(() {}),
          onClearSearch: () => setState(_search.clear),
          onSubjectFilter: (value) => setState(() => _subjectFilter = value),
          onNewCourse: _openNewCourse,
          onAddTask: (subjectId) => _openTaskEditor(subjectId: subjectId),
          onEditTask: (task) => _openTaskEditor(task: task),
          onDeleteTask: _deleteTask,
        );
      },
    );
  }
}

class _TasksDirectory extends StatelessWidget {
  const _TasksDirectory({
    required this.data,
    required this.editable,
    required this.search,
    required this.subjectFilter,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSubjectFilter,
    required this.onNewCourse,
    required this.onAddTask,
    required this.onEditTask,
    required this.onDeleteTask,
  });

  final PlannerData data;
  final bool editable;
  final TextEditingController search;
  final String subjectFilter;
  final VoidCallback onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onSubjectFilter;
  final VoidCallback onNewCourse;
  final ValueChanged<String> onAddTask;
  final ValueChanged<Task> onEditTask;
  final ValueChanged<Task> onDeleteTask;

  String get _query => search.text.trim();

  bool get _searching => _query.isNotEmpty;

  bool get _filtering => subjectFilter != 'all';

  List<_CourseGroup> _groups() {
    final query = _query.toLowerCase();
    final groups = <_CourseGroup>[];
    for (final subject in data.subjects) {
      if (_filtering && subject.id != subjectFilter) continue;
      final allTasks = data.tasks
          .where((task) => task.subjectId == subject.id)
          .toList(growable: false);
      if (query.isEmpty) {
        groups.add(
          _CourseGroup(
            subject: subject,
            tasks: allTasks,
            total: allTasks.length,
          ),
        );
        continue;
      }
      final courseHit = subject.name.toLowerCase().contains(query);
      final tasks = courseHit
          ? allTasks
          : allTasks
                .where((task) => task.title.toLowerCase().contains(query))
                .toList(growable: false);
      if (tasks.isNotEmpty) {
        groups.add(
          _CourseGroup(subject: subject, tasks: tasks, total: allTasks.length),
        );
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compact = viewportWidth < 900;
    final horizontal = compact ? 16.0 : 24.0;
    final groups = _groups();
    final filterSubject = data.subjects
        .where((subject) => subject.id == subjectFilter)
        .firstOrNull;
    final filterLabel = filterSubject?.name ?? '全部课程';

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            constraints.maxWidth.clamp(0.0, 1200.0) - horizontal * 2;
        final twoColumns = groups.length > 1 && contentWidth >= 760;
        final itemIndent = compact ? 15.0 : 65.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            compact ? 16 : 20,
            horizontal,
            24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DirectoryHeader(
                    compact: compact,
                    search: search,
                    filter: _CourseFilterButton(
                      data: data,
                      selectedId: subjectFilter,
                      onSelected: onSubjectFilter,
                    ),
                    editable: editable,
                    onSearchChanged: onSearchChanged,
                    onClearSearch: onClearSearch,
                    onNewCourse: onNewCourse,
                  ),
                  SizedBox(height: compact ? 16 : 20),
                  if (data.subjects.isEmpty)
                    _EmptyDirectory(
                      icon: Icons.folder_open_outlined,
                      title: '还没有课程',
                      hint: '先新建一门课程，再往课程里添加事项。',
                      onAction: editable ? onNewCourse : null,
                      actionLabel: '新建课程',
                    )
                  else if (groups.isEmpty)
                    _EmptyDirectory(
                      icon: Icons.search_outlined,
                      title: '没有找到与「$_query」匹配的事项',
                      hint: _filtering
                          ? '当前筛选「$filterLabel」下没有匹配事项，可以换个关键词、清除搜索，或切换回全部课程。'
                          : '可以换个关键词，或清除搜索查看全部课程与事项。',
                      secondaryLabel: _filtering ? '切换全部课程' : null,
                      onSecondary: _filtering
                          ? () => onSubjectFilter('all')
                          : null,
                      onAction: onClearSearch,
                      actionLabel: '清除搜索',
                    )
                  else if (twoColumns)
                    _twoColumnBoard(
                      groups,
                      editable: editable,
                      itemIndent: itemIndent,
                      compact: compact,
                    )
                  else
                    _singleColumnBoard(
                      groups,
                      editable: editable,
                      itemIndent: itemIndent,
                      compact: compact,
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
            searching: _searching,
            onAddTask: onAddTask,
            onEditTask: onEditTask,
            onDeleteTask: onDeleteTask,
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
        searching: _searching,
        onAddTask: onAddTask,
        onEditTask: onEditTask,
        onDeleteTask: onDeleteTask,
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

class _DirectoryHeader extends StatelessWidget {
  const _DirectoryHeader({
    required this.compact,
    required this.search,
    required this.filter,
    required this.editable,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onNewCourse,
  });

  final bool compact;
  final TextEditingController search;
  final Widget filter;
  final bool editable;
  final VoidCallback onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onNewCourse;

  @override
  Widget build(BuildContext context) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('事项管理', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          '按课程分组查看和管理学习事项',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: PlannerColors.muted),
        ),
      ],
    );
    final newCourse = FilledButton.icon(
      key: const Key('new-course-button'),
      onPressed: editable ? onNewCourse : null,
      icon: const Icon(Icons.add, size: 17),
      label: const Text('新建课程'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    final searchField = _SearchField(
      controller: search,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '事项管理',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              newCourse,
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '按课程分组查看和管理学习事项',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: PlannerColors.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 8),
              filter,
            ],
          ),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 12,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 220),
          child: titleBlock,
        ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(width: 220, child: searchField),
            filter,
            newCourse,
          ],
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextField(
        key: const Key('tasks-search-field'),
        controller: controller,
        onChanged: (_) => onChanged(),
        style: const TextStyle(fontSize: 13),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索事项',
          hintStyle: const TextStyle(fontSize: 13, color: PlannerColors.muted),
          prefixIcon: const Icon(
            Icons.search,
            size: 17,
            color: PlannerColors.muted,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('clear-search-button'),
                  tooltip: '清除搜索',
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 30,
            minHeight: 30,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PlannerColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PlannerColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: PlannerColors.blue),
          ),
        ),
      ),
    );
  }
}

class _CourseFilterButton extends StatelessWidget {
  const _CourseFilterButton({
    required this.data,
    required this.selectedId,
    required this.onSelected,
  });

  final PlannerData data;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = data.subjects
        .where((subject) => subject.id == selectedId)
        .firstOrNull;
    final counts = <String, int>{
      for (final subject in data.subjects)
        subject.id: data.tasks
            .where((task) => task.subjectId == subject.id)
            .length,
    };
    return PopupMenuButton<String>(
      key: const Key('course-filter-button'),
      tooltip: '课程筛选',
      onSelected: onSelected,
      constraints: const BoxConstraints(minWidth: 220, maxHeight: 360),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'all',
          child: _CourseMenuRow(
            label: '全部课程',
            count: data.tasks.length,
            selected: selectedId == 'all',
          ),
        ),
        for (final subject in data.subjects)
          PopupMenuItem<String>(
            value: subject.id,
            child: _CourseMenuRow(
              label: subject.name,
              count: counts[subject.id] ?? 0,
              selected: selectedId == subject.id,
              color: subjectColor(subject.id, subject.color),
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: PlannerColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: subjectColor(selected.id, selected.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              selected?.name ?? '全部课程',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: PlannerColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseMenuRow extends StatelessWidget {
  const _CourseMenuRow({
    required this.label,
    required this.count,
    required this.selected,
    this.color,
  });

  final String label;
  final int count;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: selected
                ? const Icon(Icons.check, size: 15, color: PlannerColors.blue)
                : null,
          ),
          if (color != null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          if (color != null) const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(fontSize: 11, color: PlannerColors.muted),
          ),
        ],
      ),
    );
  }
}

class _CourseGroup {
  const _CourseGroup({
    required this.subject,
    required this.tasks,
    required this.total,
  });

  final Subject subject;
  final List<Task> tasks;
  final int total;
}

class _CourseFolder extends StatelessWidget {
  const _CourseFolder({
    required this.group,
    required this.editable,
    required this.compact,
    required this.itemIndent,
    required this.searching,
    required this.onAddTask,
    required this.onEditTask,
    required this.onDeleteTask,
  });

  final _CourseGroup group;
  final bool editable;
  final bool compact;
  final double itemIndent;
  final bool searching;
  final ValueChanged<String> onAddTask;
  final ValueChanged<Task> onEditTask;
  final ValueChanged<Task> onDeleteTask;

  @override
  Widget build(BuildContext context) {
    final subject = group.subject;
    final accent = subjectColor(subject.id, subject.color);
    final spine = Color.lerp(accent, Colors.white, 0.52)!;
    final countText = searching && group.tasks.length != group.total
        ? '${group.tasks.length} / ${group.total} 个事项'
        : '${group.total} 个事项';

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
    this.onSecondary,
    this.secondaryLabel,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onAction;
  final String actionLabel;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;

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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (secondaryLabel != null && onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
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
