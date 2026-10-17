import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/planner_dialogs.dart' show DateField;
import '../application/onboarding_flow.dart';
import '../domain/onboarding_options.dart';
import '../domain/onboarding_session.dart';
import 'draft_editors.dart';
import 'learning_context_view.dart';

const _maxInterviewAnswers = 50;
const _minAnswersToGenerate = 5;

const _days = [
  ('1', '周一'),
  ('2', '周二'),
  ('3', '周三'),
  ('4', '周四'),
  ('5', '周五'),
  ('6', '周六'),
  ('0', '周日'),
];

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({this.embedded = false, super.key});
  final bool embedded;
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _answer = TextEditingController();
  final _revision = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _start;
  String? _end;
  String? _target;
  Map<String, int>? _weekly;
  String? _seededStage;
  String? _seededQuestion;
  final _selectedAnswers = <String>{};
  bool _otherSelected = false;
  String? _answerError;
  int _weeklyVersion = 0;

  @override
  void dispose() {
    _answer.dispose();
    _revision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingFlowProvider);
    final flow = ref.read(onboardingFlowProvider.notifier);
    final session = state.session;
    final stage = session?.stage ?? 'interview';
    if (_seededStage != stage) {
      _revision.clear();
      if (stage == 'schedule' && session != null) {
        final today = shanghaiToday();
        _start = session.startDate.isNotEmpty
            ? session.startDate
            : session.profile.resolvedPlanStart(today);
        _end = session.endDate.isNotEmpty
            ? session.endDate
            : session.recommendations.planEndDate.isNotEmpty
            ? session.recommendations.planEndDate
            : session.profile.resolvedPlanEnd(today);
        final target = session.profile.resolvedTargetDate;
        _target = target.isNotEmpty
            ? target
            : session.recommendations.targetDate;
        _weekly = {
          ...(session.recommendations.weeklyMinutes.isNotEmpty
              ? session.recommendations.weeklyMinutes
              : session.profile.weeklyMinutes),
        };
        _weeklyVersion++;
      }
      _seededStage = stage;
    }
    if (session != null) {
      final questionKey = '${session.answers.length}:${session.question}';
      if (_seededQuestion != questionKey) {
        _seededQuestion = questionKey;
        _selectedAnswers.clear();
        _otherSelected = false;
        _answerError = null;
        _answer.clear();
      }
    }
    final index = switch (stage) {
      'courses' => 1,
      'items' => 2,
      'schedule' || 'complete' => 3,
      _ => 0,
    };
    // 访谈阶段的 AI 等待改用页面内固定高度的“AI 正在思考中…”提示；
    // 其他阶段继续使用原有的处理中加载条。
    final interviewThinking =
        state.waitingForAi &&
        session != null &&
        (stage == 'interview' || stage == 'checkpoint');
    final body = SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.embedded) ...[
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 16,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '访谈与规划',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (session != null && session.stage != 'complete')
                          TextButton.icon(
                            onPressed: state.loading
                                ? null
                                : () => _restart(flow),
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('重新访谈'),
                          ),
                      ],
                    ),
                    if (session?.replanning == true) ...[
                      const SizedBox(height: 12),
                      const PlannerNotice(
                        '新计划确认前，当前计划保持生效。',
                        tone: PlannerNoticeTone.info,
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                  if (stage != 'complete')
                    Wrap(
                      spacing: 20,
                      runSpacing: 8,
                      children: [
                        for (final (i, title) in [
                          '目标访谈',
                          '确认课程',
                          '确认事项',
                          '每日计划',
                        ].indexed)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                i < index
                                    ? Icons.check_circle_outline
                                    : i == index
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: i < index
                                    ? PlannerColors.green
                                    : i == index
                                    ? PlannerColors.blue
                                    : PlannerColors.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                title,
                                style: TextStyle(
                                  color: i == index
                                      ? PlannerColors.blue
                                      : PlannerColors.muted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  if (stage != 'complete') const SizedBox(height: 28),
                  if (session != null) ...[
                    if (stage != 'complete')
                      LearningContextView(
                        session: session,
                        busy: state.loading,
                        onAction: flow.act,
                      ),
                    if (stage == 'interview' || stage == 'checkpoint')
                      _interview(
                        session,
                        flow,
                        state.loading,
                        state.waitingForAi,
                      ),
                    if (stage == 'courses' || stage == 'items')
                      _draft(session, flow, state.loading),
                    if (stage == 'schedule')
                      _schedule(session, flow, state.loading),
                    if (stage == 'complete')
                      _planningHome(session, flow, state.loading),
                  ],
                  if (state.loading && !interviewThinking) ...[
                    const SizedBox(height: 24),
                    const LinearProgressIndicator(semanticsLabel: '正在处理学习规划'),
                    const SizedBox(height: 8),
                    Text(
                      session == null ? '正在读取规划进度…' : '正在处理，请稍候…',
                      style: const TextStyle(color: PlannerColors.muted),
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    PlannerNotice(state.error!, tone: PlannerNoticeTone.error),
                    if (state.planChanged)
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: state.loading
                              ? null
                              : () => flow.act({'type': 'refresh_plan'}),
                          icon: const Icon(Icons.sync),
                          label: const Text('更新当前计划进度，保留草稿'),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: state.loading ? null : flow.reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新读取已保存进度'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('不白学 · 学习规划')),
            body: body,
          );
  }

  Widget _planningHome(
    OnboardingSession session,
    OnboardingFlow flow,
    bool busy,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('当前目标', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(
        session.answers.isNotEmpty
            ? session.answers.first.answer
            : [
                session.profile.goalText,
                session.profile.goalSubtype,
                goalTypeLabelOf(session.profile.goalType),
              ].where((value) => value.isNotEmpty).join(' · '),
      ),
      const SizedBox(height: 8),
      Text(
        [
          session.profile.planStartDate.isNotEmpty
              ? '本次规划 ${session.profile.planStartDate} 至 ${session.profile.planEndDate}'
              : '',
          session.profile.targetDate.isNotEmpty
              ? '${session.profile.targetDateConfirmed ? '目标日期' : '预计目标日期'} ${session.profile.targetDate}'
              : '暂未设置目标日期',
          '已记录 ${session.answers.length} 个回答',
        ].where((value) => value.isNotEmpty).join(' · '),
        style: const TextStyle(color: PlannerColors.muted),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: busy || session.answers.length >= 50
                ? null
                : () => flow.act({'type': 'resume_interview'}),
            icon: const Icon(Icons.forum_outlined),
            label: const Text('继续访谈'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => _restart(flow),
            icon: const Icon(Icons.restart_alt),
            label: const Text('重新访谈'),
          ),
        ],
      ),
      if (session.answers.isNotEmpty) ...[
        const SizedBox(height: 24),
        ExpansionTile(
          title: const Text('已有访谈记录'),
          tilePadding: EdgeInsets.zero,
          children: [
            for (final answer in session.answers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(answer.question),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: SelectableText(answer.answer),
                ),
              ),
          ],
        ),
      ],
    ],
  );

  Future<void> _restart(OnboardingFlow flow) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新开始访谈？'),
        content: const Text('本轮访谈和未确认的草稿将重置。当前计划与学习记录保留，直到你确认新的计划。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await flow.act({'type': 'restart_interview'});
    }
  }

  Widget _interview(
    OnboardingSession session,
    OnboardingFlow flow,
    bool busy,
    bool thinking,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (session.answers.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('已回答 ${session.answers.length} 个问题'),
          children: [
            for (final (i, answer) in session.answers.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${i + 1}. ${answer.question}'),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 12),
                  child: SelectableText(answer.answer),
                ),
              ),
          ],
        ),
      const SizedBox(height: 16),
      if (session.answers.length >= _maxInterviewAnswers) ...[
        Text(
          '已达到 $_maxInterviewAnswers 题上限',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          '请根据当前回答生成科目，或重新访谈后再继续补充。',
          style: TextStyle(color: PlannerColors.muted),
        ),
        const SizedBox(height: 20),
      ] else ...[
        Text(
          '第 ${session.answers.length + 1} 问${session.questionMultiple ? ' · 可多选' : ''}',
          style: const TextStyle(color: PlannerColors.muted),
        ),
        const SizedBox(height: 8),
        Text(
          session.question,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        if (session.questionOptions.isNotEmpty) ...[
          if (session.questionMultiple)
            Column(
              children: [
                for (final option in session.questionOptions)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(option),
                    value: _selectedAnswers.contains(option),
                    onChanged: busy
                        ? null
                        : (checked) => setState(() {
                            if (checked == true) {
                              _selectedAnswers.add(option);
                            } else {
                              _selectedAnswers.remove(option);
                            }
                            _answerError = null;
                          }),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(otherOptionLabel),
                  value: _otherSelected,
                  onChanged: busy
                      ? null
                      : (checked) => setState(() {
                          _otherSelected = checked == true;
                          _answerError = null;
                        }),
                ),
              ],
            )
          else
            RadioGroup<String>(
              groupValue: _otherSelected
                  ? otherOptionKey
                  : _selectedAnswers.firstOrNull,
              onChanged: (value) {
                if (busy || value == null) return;
                setState(() {
                  _otherSelected = value == otherOptionKey;
                  _selectedAnswers.clear();
                  if (!_otherSelected) _selectedAnswers.add(value);
                  _answerError = null;
                });
              },
              child: Column(
                children: [
                  for (final option in session.questionOptions)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(option),
                      value: option,
                      enabled: !busy,
                    ),
                  RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(otherOptionLabel),
                    value: otherOptionKey,
                    enabled: !busy,
                  ),
                ],
              ),
            ),
          if (_answerError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _answerError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (session.questionOptions.isEmpty || _otherSelected)
          TextFormField(
            key: ValueKey('answer-${session.answers.length}'),
            controller: _answer,
            enabled: !busy,
            autofocus: session.questionOptions.isEmpty,
            minLines: 3,
            maxLines: 8,
            maxLength: 4000,
            decoration: InputDecoration(
              labelText: session.questionOptions.isEmpty ? '你的回答' : '其他回答',
              hintText: session.answers.isEmpty
                  ? '例如：从零学习 Python，能独立做简单的数据分析'
                  : null,
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '请先填写回答' : null,
          ),
        const SizedBox(height: 8),
      ],
      // 固定高度的等待提示，避免 AI 处理期间页面跳动或按钮错位。
      SizedBox(
        height: 28,
        child: thinking
            ? Semantics(
                liveRegion: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'AI 正在思考中…',
                      style: TextStyle(color: PlannerColors.muted),
                    ),
                  ],
                ),
              )
            : null,
      ),
      Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          if (session.answers.length >= _minAnswersToGenerate)
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      // 生成只使用服务端已保存的回答；当前未提交的输入不参与生成，也不触发必填校验。
                      if (await flow.act({'type': 'generate_courses'})) {
                        _answer.clear();
                        _selectedAnswers.clear();
                        _otherSelected = false;
                        _answerError = null;
                      }
                    },
              icon: const Icon(Icons.checklist_rtl),
              label: const Text('根据当前回答生成科目'),
            ),
          if (session.answers.length < _maxInterviewAnswers)
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      // 选项在解析会话时已归一化；“其他”入口由客户端统一提供。
                      // 只有“其他”入口可见时才提交输入框内容，切换回普通选项后隐藏的旧内容不会提交。
                      if (!_form.currentState!.validate()) return;
                      final selected = session.questionOptions
                          .where(_selectedAnswers.contains)
                          .toList();
                      final customText =
                          session.questionOptions.isEmpty || _otherSelected
                          ? _answer.text.trim()
                          : '';
                      final answer = [
                        ...selected,
                        if (customText.isNotEmpty) customText,
                      ].join('；');
                      if (answer.isEmpty) {
                        setState(() => _answerError = '请选择一个选项或填写其他回答');
                        return;
                      }
                      if (await flow.act({
                        'type': 'answer',
                        'answer': answer,
                      })) {
                        _answer.clear();
                      }
                    },
              icon: const Icon(Icons.arrow_forward),
              label: Text(session.answers.length < 4 ? '提交回答，继续' : '提交回答'),
            ),
        ],
      ),
    ],
  );

  Widget _draft(OnboardingSession session, OnboardingFlow flow, bool busy) {
    final courses = session.stage == 'courses';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          courses ? '确认你的课程' : '确认学习事项',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(session.summary),
        const SizedBox(height: 12),
        for (final note in session.assumptions)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '待核对：$note',
              style: const TextStyle(color: PlannerColors.muted),
            ),
          ),
        for (final warning in session.warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: PlannerNotice(warning, tone: PlannerNoticeTone.warning),
          ),
        const SizedBox(height: 12),
        for (final course in session.courses) ...[
          const Divider(height: 24),
          if (courses)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(course.name),
              subtitle: course.description.isEmpty
                  ? null
                  : Text(course.description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑 ${course.name}',
                    onPressed: busy
                        ? null
                        : () async {
                            final edited = await editCourseDraft(
                              context,
                              course,
                            );
                            if (edited != null && mounted) {
                              flow.editCourses([
                                for (final c in session.courses)
                                  c.id == course.id ? edited : c,
                              ]);
                            }
                          },
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: '删除 ${course.name}',
                    onPressed: busy || session.courses.length <= 1
                        ? null
                        : () => flow.editCourses(
                            session.courses
                                .where((c) => c.id != course.id)
                                .toList(),
                          ),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            )
          else ...[
            Text(course.name, style: Theme.of(context).textTheme.titleMedium),
            for (final item in session.items.where(
              (i) => i.courseId == course.id,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.title),
                subtitle: Text(
                  '${(item.estimatedMinutes / 60).toStringAsFixed(1)} 小时 · ${item.earliestDate ?? '待定'} 至 ${item.deadline}\n${item.description}${item.completionCriteria.isEmpty ? '' : '\n完成标准：${item.completionCriteria}'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '编辑 ${item.title}',
                      onPressed: busy
                          ? null
                          : () async {
                              final edited = await editItemDraft(
                                context,
                                item,
                                session.courses,
                              );
                              if (edited != null && mounted) {
                                flow.editItems([
                                  for (final i in session.items)
                                    i.id == item.id ? edited : i,
                                ]);
                              }
                            },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: '删除 ${item.title}',
                      onPressed: busy
                          ? null
                          : () => flow.editItems(
                              session.items
                                  .where((i) => i.id != item.id)
                                  .toList(),
                            ),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final item = await editItemDraft(
                          context,
                          ItemDraft(
                            id: 'item-${DateTime.now().microsecondsSinceEpoch}',
                            courseId: course.id,
                            title: '',
                            estimatedMinutes: 120,
                            earliestDate: shanghaiToday(),
                            deadline: session.endDate.isNotEmpty
                                ? session.endDate
                                : session.recommendations.planEndDate.isNotEmpty
                                ? session.recommendations.planEndDate
                                : session.profile.resolvedPlanEnd(
                                    shanghaiToday(),
                                  ),
                            deadlineKind: ItemDateKind.planEnd,
                          ),
                          session.courses,
                        );
                        if (item != null && mounted) {
                          flow.editItems([...session.items, item]);
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text('添加事项'),
              ),
            ),
          ],
        ],
        if (courses)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final course = await editCourseDraft(
                        context,
                        CourseDraft(
                          id: 'course-${DateTime.now().microsecondsSinceEpoch}',
                          name: '',
                        ),
                      );
                      if (course != null && mounted) {
                        flow.editCourses([...session.courses, course]);
                      }
                    },
              icon: const Icon(Icons.add),
              label: const Text('添加课程'),
            ),
          ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _revision,
          enabled: !busy,
          minLines: 2,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: '修改要求',
            hintText: courses
                ? '例如：专业课改为计算机组成原理，增加线性代数'
                : '例如：英语增加背单词，高数一轮复习增加到80小时',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    if (_revision.text.trim().isEmpty) return;
                    if (await flow.act({
                      'type': courses ? 'revise_courses' : 'revise_items',
                      'instruction': _revision.text.trim(),
                      ..._draftPayload(session),
                    })) {
                      _revision.clear();
                    }
                  },
            icon: const Icon(Icons.send_outlined),
            label: const Text('按要求修改'),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 10,
          children: [
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => flow.act({
                      'type': 'back',
                      'target': courses ? 'interview' : 'courses',
                    }),
              icon: const Icon(Icons.arrow_back),
              label: Text(courses ? '返回访谈' : '返回课程'),
            ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (await flow.act({
                            'type': courses ? 'save_courses' : 'save_items',
                            ..._draftPayload(session),
                          }) &&
                          mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('修改已保存')));
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存修改'),
            ),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => flow.act({
                      'type': courses ? 'confirm_courses' : 'confirm_items',
                      ..._draftPayload(session),
                    }),
              icon: const Icon(Icons.check),
              label: Text(courses ? '确认课程，生成事项' : '确认事项，设置日期'),
            ),
          ],
        ),
      ],
    );
  }

  Map<String, dynamic> _draftPayload(OnboardingSession session) =>
      session.stage == 'courses'
      ? {'courses': session.courses.map((c) => c.toJson()).toList()}
      : {'items': session.items.map((i) => i.toJson()).toList()};

  Widget _schedule(OnboardingSession session, OnboardingFlow flow, bool busy) {
    final today = shanghaiToday();
    _start ??= session.startDate.isNotEmpty
        ? session.startDate
        : session.profile.resolvedPlanStart(today);
    _end ??= session.endDate.isNotEmpty
        ? session.endDate
        : session.recommendations.planEndDate.isNotEmpty
        ? session.recommendations.planEndDate
        : session.profile.resolvedPlanEnd(today);
    _target ??= session.profile.resolvedTargetDate.isNotEmpty
        ? session.profile.resolvedTargetDate
        : session.recommendations.targetDate;
    _weekly ??= {
      ...(session.recommendations.weeklyMinutes.isNotEmpty
          ? session.recommendations.weeklyMinutes
          : session.profile.weeklyMinutes),
    };
    final budget = session.items.fold<int>(
      0,
      (sum, item) => sum + item.estimatedMinutes,
    );
    var capacity = 0;
    if (_end!.isNotEmpty && _end!.compareTo(_start!) >= 0) {
      for (
        var date = DateTime.parse(_start!);
        !date.isAfter(DateTime.parse(_end!));
        date = date.add(const Duration(days: 1))
      ) {
        capacity += ((_weekly!['${date.weekday % 7}'] ?? 0) - 30).clamp(0, 450);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('确认计划日期', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          '${session.courses.length} 门课程 · ${session.items.length} 个事项 · 总预算 ${(budget / 60).toStringAsFixed(1)} 小时',
        ),
        const SizedBox(height: 20),
        AbsorbPointer(
          absorbing: busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: 240,
                    child: DateField(
                      label: '计划开始日期',
                      value: _start!,
                      firstDate: shanghaiToday(),
                      onChanged: (value) => setState(() => _start = value),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DateField(
                      label: '规划结束日期',
                      value: _end!,
                      firstDate: _start ?? shanghaiToday(),
                      onChanged: (value) => setState(() => _end = value),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DateField(
                      label: '目标日期（可选）',
                      value: _target ?? '',
                      onChanged: (value) => setState(() => _target = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '规划结束日期是本次排程的边界；目标日期是你希望达成结果的日期，可以不设置。',
                style: TextStyle(color: PlannerColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (session.recommendations.planEndDate.isNotEmpty)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '建议规划结束：${session.recommendations.planEndDate}。${session.recommendations.planEndDateReason}',
                      style: const TextStyle(color: PlannerColors.muted),
                    ),
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => setState(
                              () => _end = session.recommendations.planEndDate,
                            ),
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('采用建议周期'),
                    ),
                  ],
                ),
              if (session.recommendations.targetDate.isNotEmpty) ...[
                Text(
                  '${session.recommendations.targetDateEstimated ? '预计目标日期' : '目标日期'}：${session.recommendations.targetDate}。${session.recommendations.targetDateReason}',
                  style: const TextStyle(color: PlannerColors.muted),
                ),
                if (session.recommendations.targetDateEstimated)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '以正式通知为准，你也可以清空目标日期。',
                      style: TextStyle(color: PlannerColors.muted),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => setState(
                                () => _target =
                                    session.recommendations.targetDate,
                              ),
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('采用建议目标日期'),
                      ),
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => setState(() => _target = ''),
                        icon: const Icon(Icons.clear, size: 18),
                        label: const Text('暂不设置目标日期'),
                      ),
                    ],
                  ),
                ),
              ] else
                const Text(
                  '暂不设置目标日期也可以生成计划，本次只安排一个有限的规划周期。',
                  style: TextStyle(color: PlannerColors.muted),
                ),
              const SizedBox(height: 24),
              Text('每周可用时间', style: Theme.of(context).textTheme.titleMedium),
              if (session.recommendations.weeklyMinutesReason.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '建议依据：${session.recommendations.weeklyMinutesReason}',
                  style: const TextStyle(color: PlannerColors.muted),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (key, label) in _days)
                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        key: ValueKey('weekly-$_weeklyVersion-$key'),
                        initialValue: '${_weekly![key] ?? 0}',
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: label,
                          suffixText: '分钟',
                        ),
                        validator: (value) {
                          final m = int.tryParse(value ?? '');
                          return m == null || m < 0 || m > 480
                              ? '填写0至480分钟'
                              : null;
                        },
                        onChanged: (value) => setState(
                          () => _weekly![key] = int.tryParse(value) ?? 0,
                        ),
                      ),
                    ),
                ],
              ),
              if (session.recommendations.weeklyMinutes.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _weekly = {
                              ...session.recommendations.weeklyMinutes,
                            };
                            _weeklyVersion++;
                          }),
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复推荐时间'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '每日预留30分钟机动，单门课程每天最多4小时。',
          style: TextStyle(color: PlannerColors.muted),
        ),
        if (_end!.isNotEmpty && budget > capacity) ...[
          const SizedBox(height: 12),
          PlannerNotice(
            '事项预算超出可用时间约 ${((budget - capacity) / 60).toStringAsFixed(1)} 小时，部分内容可能无法排入。',
            tone: PlannerNoticeTone.warning,
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => flow.act({'type': 'back', 'target': 'items'}),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回修改事项'),
            ),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) return;
                      final ok = await flow.act({
                        'type': 'finish',
                        'start_date': _start,
                        'end_date': _end,
                        'target_date': (_target ?? '').isEmpty ? null : _target,
                        'weekly_minutes': _weekly,
                      });
                      if (ok && mounted && widget.embedded) context.go('/');
                    },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(session.replanning ? '确认并更新每日计划' : '确认并生成每日计划'),
            ),
          ],
        ),
      ],
    );
  }
}
