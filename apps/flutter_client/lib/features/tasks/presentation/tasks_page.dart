import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/domain/study_day.dart' as day_ops;
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';

/// Web `/tasks` — filter, create, edit, schedule, complete and delete tasks.
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _search = TextEditingController();
  String _subject = 'all';
  String _status = 'all';
  String _priority = 'all';
  String? _deadline;
  bool _showFuture = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = shanghaiToday();
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        final query = _search.text.trim().toLowerCase();
        final visible = <Task>[];
        for (final task in data.tasks) {
          if (_subject != 'all' && task.subjectId != _subject) continue;
          if (_status != 'all' && task.status.name != _status) continue;
          if (_priority != 'all' && '${task.priority}' != _priority) continue;
          if (_deadline != null && task.deadline.compareTo(_deadline!) > 0) {
            continue;
          }
          if (query.isNotEmpty) {
            final haystack =
                '${task.title} ${task.description ?? ''} '
                        '${subjectNameOf(data, task.subjectId)}'
                    .toLowerCase();
            if (!haystack.contains(query)) continue;
          }
          visible.add(task);
        }
        visible.sort((a, b) {
          final byDeadline = a.deadline.compareTo(b.deadline);
          return byDeadline != 0
              ? byDeadline
              : b.priority.compareTo(a.priority);
        });
        final future = [
          for (final task in visible)
            if ((task.earliestDate ?? '').compareTo(today) > 0) task,
        ];
        final current = [
          for (final task in visible)
            if (!future.contains(task)) task,
        ];
        final displayed = _showFuture ? visible : current;
        return PlannerPage(
          title: '事项管理',
          subtitle: '${current.length} 个当前事项 · ${future.length} 个后续事项',
          actions: [
            AsyncActionButton(
              label: '新建事项',
              icon: Icons.add,
              enabled: snapshot.editable,
              onPressed: () => TaskEditorDialog.show(context),
            ),
          ],
          children: [
            _FilterBar(
              search: _search,
              subjects: data.subjects,
              subject: _subject,
              status: _status,
              priority: _priority,
              deadline: _deadline,
              onSearchChanged: () => setState(() {}),
              onSubject: (value) => setState(() => _subject = value),
              onStatus: (value) => setState(() => _status = value),
              onPriority: (value) => setState(() => _priority = value),
              onDeadline: (value) => setState(() => _deadline = value),
            ),
            if (future.isNotEmpty) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _showFuture,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('显示后续事项（${future.length}）'),
                onChanged: (value) =>
                    setState(() => _showFuture = value ?? false),
              ),
            ],
            const SizedBox(height: 8),
            if (displayed.isEmpty)
              const PlannerEmpty(
                message: '没有匹配事项，可以修改筛选条件或新建事项。',
                hint: '默认隐藏尚未到开始日期的后续事项。',
              ),
            for (final task in displayed)
              _TaskCard(
                key: ValueKey(task.id),
                task: task,
                data: data,
                editable: snapshot.editable,
              ),
            const SizedBox(height: 8),
            Text(
              '显示 ${displayed.length} 个事项 · 共 ${visible.length} 个匹配事项',
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.search,
    required this.subjects,
    required this.subject,
    required this.status,
    required this.priority,
    required this.deadline,
    required this.onSearchChanged,
    required this.onSubject,
    required this.onStatus,
    required this.onPriority,
    required this.onDeadline,
  });

  final TextEditingController search;
  final List<Subject> subjects;
  final String subject;
  final String status;
  final String priority;
  final String? deadline;
  final VoidCallback onSearchChanged;
  final ValueChanged<String> onSubject;
  final ValueChanged<String> onStatus;
  final ValueChanged<String> onPriority;
  final ValueChanged<String?> onDeadline;

  @override
  Widget build(BuildContext context) => PlannerPanel(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: constraints.maxWidth,
              child: TextField(
                controller: search,
                decoration: const InputDecoration(
                  labelText: '搜索事项',
                  hintText: '搜索事项名称、说明或课程',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => onSearchChanged(),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                initialValue: subject,
                decoration: const InputDecoration(labelText: '课程'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全部课程')),
                  for (final item in subjects)
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
                ],
                onChanged: (value) => onSubject(value ?? 'all'),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: '状态'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全部状态')),
                  for (final entry in statusLabels.entries)
                    DropdownMenuItem(
                      value: entry.key.name,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => onStatus(value ?? 'all'),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: DropdownButtonFormField<String>(
                initialValue: priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('全部优先级')),
                  for (final value in const [3, 2, 1])
                    DropdownMenuItem(
                      value: '$value',
                      child: Text(priorityLabels[value]!),
                    ),
                ],
                onChanged: (value) => onPriority(value ?? 'all'),
              ),
            ),
            SizedBox(
              width: constraints.maxWidth,
              child: DateField(
                label: '截止日期之前（留空不过滤）',
                value: deadline ?? '',
                onChanged: (value) => onDeadline(value.isEmpty ? null : value),
              ),
            ),
            if (deadline != null)
              TextButton.icon(
                onPressed: () => onDeadline(null),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('清除日期筛选'),
              ),
          ],
        );
      },
    ),
  );
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({
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
    final course = data.subjects
        .where((subject) => subject.id == task.subjectId)
        .firstOrNull;
    final color = subjectColor(task.subjectId, course?.color);
    final logged = day_ops.taskTotalMinutes(data, task.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PlannerPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                SubjectChip(name: course?.name ?? task.subjectId, color: color),
                Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                _StatusBadge(status: task.status),
                if (task.isFixed)
                  const Tooltip(
                    message: '固定事项',
                    child: Icon(Icons.lock_outline, size: 14),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final progress = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${duration(logged)} / ${duration(task.estimatedMinutes)}',
                      style: tabularFigures,
                    ),
                    const SizedBox(height: 6),
                    TimeProgressTrack(
                      planned: task.estimatedMinutes,
                      actual: task.completedMinutes,
                      color: color,
                      semanticsLabel: '${task.title}时间投入进度',
                    ),
                  ],
                );
                final deadline = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.deadline, style: tabularFigures),
                    Text(
                      '${priorityLabels[task.priority]}优先级',
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: '编辑事项',
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: editable
                          ? () => TaskEditorDialog.show(context, taskId: task.id)
                          : null,
                    ),
                    IconButton(
                      tooltip: '安排事项日期和时长',
                      icon: const Icon(Icons.event_available_outlined, size: 18),
                      onPressed: editable && task.status != TaskStatus.completed
                          ? () => ScheduleTaskDialog.show(context, task.id)
                          : null,
                    ),
                    IconButton(
                      tooltip: '手动标记完成',
                      icon: const Icon(Icons.check, size: 18),
                      onPressed: editable && task.status != TaskStatus.completed
                          ? () => CompleteTaskDialog.show(context, task.id)
                          : null,
                    ),
                    IconButton(
                      tooltip: '删除事项',
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: PlannerColors.danger,
                      ),
                      onPressed: editable
                          ? () async {
                              final confirmed = await confirmAction(
                                context,
                                title: '删除事项',
                                message:
                                    '删除“${task.title}”及关联每日计划与学习记录？'
                                    '该操作会同步到服务器，客户端无法撤销。',
                                confirmLabel: '确认删除',
                                destructive: true,
                              );
                              if (!confirmed || !context.mounted) return;
                              await ref
                                  .read(plannerSessionProvider)
                                  .deleteTask(task.id);
                            }
                          : null,
                    ),
                  ],
                );
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      progress,
                      const SizedBox(height: 8),
                      deadline,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerLeft, child: actions),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: progress),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: deadline),
                    actions,
                  ],
                );
              },
            ),
            if ((task.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('学习范围与完成标准'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        task.description!,
                        style: const TextStyle(
                          color: PlannerColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final tone = switch (status) {
      TaskStatus.completed => PlannerColors.green,
      TaskStatus.conflict => PlannerColors.danger,
      TaskStatus.delayed => PlannerColors.orange,
      TaskStatus.inProgress => PlannerColors.blue,
      TaskStatus.notStarted => PlannerColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        statusLabels[status]!,
        style: TextStyle(color: tone, fontSize: 12),
      ),
    );
  }
}
