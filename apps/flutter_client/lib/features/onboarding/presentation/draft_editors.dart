import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/models/api_models.dart';
import '../../planner/presentation/planner_dialogs.dart' show DateField;

Future<CourseDraft?> editCourseDraft(
  BuildContext context,
  CourseDraft course,
) async {
  final name = TextEditingController(text: course.name);
  final description = TextEditingController(text: course.description);
  final form = GlobalKey<FormState>();
  var priority = course.priority;
  final result = await showDialog<CourseDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('编辑课程'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: '课程名称'),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: description,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: '课程说明'),
                  ),
                  const SizedBox(height: 12),
                  priorityField(
                    priority,
                    (value) => setState(() => priority = value),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  context,
                  course.copyWith(
                    name: name.text.trim(),
                    description: description.text.trim(),
                    priority: priority,
                  ),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  // The dialog's closing animation still reads its text controllers.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  name.dispose();
  description.dispose();
  return result;
}

Future<ItemDraft?> editItemDraft(
  BuildContext context,
  ItemDraft item,
  List<CourseDraft> courses,
) async {
  final title = TextEditingController(text: item.title);
  final description = TextEditingController(text: item.description);
  final criteria = TextEditingController(text: item.completionCriteria);
  final minutes = TextEditingController(text: '${item.estimatedMinutes}');
  final form = GlobalKey<FormState>();
  var courseId = item.courseId;
  var start = item.earliestDate;
  var deadline = item.deadline;
  var priority = item.priority;
  String? error;
  final result = await showDialog<ItemDraft>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('编辑学习事项'),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: courseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '所属课程'),
                    items: [
                      for (final course in courses)
                        DropdownMenuItem(
                          value: course.id,
                          child: Text(
                            course.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => courseId = value!,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: '事项名称'),
                    validator: _required,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: description,
                    maxLength: 4000,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: '学习内容'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: criteria,
                    maxLength: 1000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '完成标准'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: minutes,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: '总时间预算',
                      suffixText: '分钟',
                    ),
                    validator: (value) {
                      final m = int.tryParse(value ?? '');
                      return m == null || m < 30 || m > 100000
                          ? '填写30至100000分钟'
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DateField(
                    label: '事项开始日期',
                    value: start ?? '',
                    onChanged: (value) => setState(() => start = value),
                  ),
                  const SizedBox(height: 12),
                  DateField(
                    label: '事项截止日期',
                    value: deadline,
                    onChanged: (value) => setState(() => deadline = value),
                  ),
                  const SizedBox(height: 12),
                  priorityField(
                    priority,
                    (value) => setState(() => priority = value),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              if (start != null && start!.compareTo(deadline) > 0) {
                setState(() => error = '开始日期不能晚于截止日期');
                return;
              }
              Navigator.pop(
                context,
                item.copyWith(
                  courseId: courseId,
                  title: title.text.trim(),
                  description: description.text.trim(),
                  completionCriteria: criteria.text.trim(),
                  estimatedMinutes: int.parse(minutes.text),
                  earliestDate: start,
                  deadline: deadline,
                  priority: priority,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  title.dispose();
  description.dispose();
  criteria.dispose();
  minutes.dispose();
  return result;
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? '名称不能为空' : null;

Widget priorityField(int value, ValueChanged<int> onChanged) =>
    DropdownButtonFormField<int>(
      initialValue: value,
      decoration: const InputDecoration(labelText: '优先级'),
      items: const [
        DropdownMenuItem(value: 1, child: Text('低')),
        DropdownMenuItem(value: 2, child: Text('中')),
        DropdownMenuItem(value: 3, child: Text('高')),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
