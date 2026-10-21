import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planner_ui_vendor/planner_ui_vendor.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/application/planner_session.dart';
import 'tasks_dialogs.dart';

/// Global task actions: create an item and manage tags.
///
/// Icon-only so the same pair can live in the narrow-screen app bar and in the
/// desktop 「全部事项」 header without adding labels.
class TaskQuickActions extends ConsumerWidget {
  const TaskQuickActions({this.iconSize = 17, this.buttonSize = 30, super.key});

  final double iconSize;

  /// Tap target of each icon button; the app bar uses a slightly larger one.
  final double buttonSize;

  Future<void> _createTask(BuildContext context) async {
    final saved = await TaskDirectoryEditorDialog.show(context);
    if (saved == true && context.mounted) {
      showPlannerMessage(context, '事项已添加');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editable = ref.watch(plannerDataProvider).editable;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlannerIconAction(
          key: const Key('manage-tags-button'),
          tooltip: '管理标签',
          icon: LucideIcons.tags,
          iconSize: iconSize,
          size: buttonSize,
          onPressed: editable ? () => TagManagementDialog.show(context) : null,
        ),
        const SizedBox(width: PlannerSpace.sm),
        PlannerIconAction(
          key: const Key('new-task-button'),
          tooltip: '新建事项',
          icon: LucideIcons.plus,
          iconSize: iconSize,
          size: buttonSize,
          tone: context.tokens.accent,
          onPressed: editable ? () => _createTask(context) : null,
        ),
      ],
    );
  }
}
