import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/domain/capacity.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/planner_dialogs.dart' show DateField;
import '../../planner/presentation/planning_details.dart';
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
  bool _freeText = false;
  String? _answerError;
  int _weeklyVersion = 0;
  String? _previewConstraints;

  /// 周容量输入方式：true = 大致周容量范围（推荐），false = 默认每周模板。
  bool _useRange = false;
  int? _rangeMin;
  int? _rangeMax;

  /// 采用保守基线需要用户明确确认（不是逐日确认）。
  bool _baselineConfirmed = false;

  /// 旧的全量总预算口径计划（重新规划时保留旧标签与语义）。
  bool _legacyGross = false;
  final _rangeMinController = TextEditingController();
  final _rangeMaxController = TextEditingController();

  @override
  void dispose() {
    _answer.dispose();
    _revision.dispose();
    _rangeMinController.dispose();
    _rangeMaxController.dispose();
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
      if ((stage == 'schedule' || stage == 'constraints') && session != null) {
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
        _target = session.constraintsConfirmed
            ? target
            : target.isNotEmpty
            ? target
            : session.recommendations.targetDate;
        _weekly = {
          ...(session.constraintsConfirmed
              ? session.profile.weeklyMinutes
              : session.recommendations.weeklyMinutes.isNotEmpty
              ? session.recommendations.weeklyMinutes
              : session.profile.weeklyMinutes),
        };
        final currentProfileJson =
            session.currentPlan?['profile'] is Map
            ? JsonMap.from(session.currentPlan!['profile'] as Map)
            : const <String, dynamic>{};
        _legacyGross =
            session.replanning &&
            currentProfileJson['capacity_basis'] != 'net' &&
            currentProfileJson['weekly_baseline_minutes'] == null &&
            currentProfileJson['week_capacity_overrides'] == null &&
            currentProfileJson['date_capacity_overrides'] == null;
        _useRange =
            currentProfileJson['weekly_range_min_minutes'] != null ||
            currentProfileJson['weekly_range_max_minutes'] != null;
        _rangeMin = (currentProfileJson['weekly_range_min_minutes'] as num?)
            ?.toInt();
        _rangeMax = (currentProfileJson['weekly_range_max_minutes'] as num?)
            ?.toInt();
        if (_useRange) {
          _ensureRangeDefaults();
        }
        _baselineConfirmed =
            currentProfileJson['weekly_baseline_minutes'] != null;
        _rangeMinController.text = '${_rangeMin ?? ''}';
        _rangeMaxController.text = '${_rangeMax ?? ''}';
        _previewConstraints = session.preview == null ? null : _constraintsKey;
        _weeklyVersion++;
      }
      _seededStage = stage;
    }
    if (session != null) {
      final questionKey = jsonEncode([
        session.answers.length,
        session.question,
        session.questionType,
        session.effectiveQuestionType,
        session.effectiveQuestionOptions,
      ]);
      if (_seededQuestion != questionKey) {
        _seededQuestion = questionKey;
        _selectedAnswers.clear();
        _otherSelected = false;
        _freeText = false;
        _answerError = null;
        _answer.clear();
      }
    }
    final index = switch (stage) {
      'courses' => 1,
      'constraints' => 2,
      'items' => 3,
      'schedule' || 'complete' => 4,
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
                          '确认条件',
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
                    if (stage == 'schedule' || stage == 'constraints')
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
  ) {
    final options = session.effectiveQuestionOptions;
    final multiple = session.effectiveQuestionMultiple;
    final usingChoices = options.isNotEmpty && !_freeText;
    return Column(
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
            '第 ${session.answers.length + 1} 问${usingChoices && multiple ? ' · 可多选' : ''}',
            style: const TextStyle(color: PlannerColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            session.question,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          if (options.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        _freeText = !_freeText;
                        _answerError = null;
                      }),
                icon: Icon(_freeText ? Icons.list_alt : Icons.edit_outlined),
                label: Text(_freeText ? '改用选项' : '直接填写'),
              ),
            ),
          if (usingChoices) ...[
            if (multiple)
              Column(
                children: [
                  for (final option in options)
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
                    for (final option in options)
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
          if (!usingChoices || _otherSelected)
            TextFormField(
              key: ValueKey('answer-$_seededQuestion-$usingChoices'),
              controller: _answer,
              enabled: !busy,
              autofocus: !usingChoices,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: usingChoices ? '其他回答' : '你的回答',
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
                        // 只提交当前回答方式中的内容，保留的隐藏草稿不参与提交。
                        if (!_form.currentState!.validate()) return;
                        final selected = usingChoices
                            ? options.where(_selectedAnswers.contains).toList()
                            : const <String>[];
                        final customText = !usingChoices || _otherSelected
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
  }

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
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(item.estimatedMinutes / 60).toStringAsFixed(1)} 小时 · ${item.earliestDate ?? '待定'} 至 ${item.deadline}\n${item.description}${item.completionCriteria.isEmpty ? '' : '\n完成标准：${item.completionCriteria}'}',
                    ),
                    WorkloadDetails(planning: item.planning),
                  ],
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
                      'target': courses ? 'interview' : 'constraints',
                    }),
              icon: const Icon(Icons.arrow_back),
              label: Text(courses ? '返回访谈' : '返回时间条件'),
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
              label: Text(courses ? '确认课程，设置时间条件' : '确认事项，预览安排'),
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

  /// 只有“大致周容量范围”模式需要用户明确确认采用的保守基线。
  bool get _capacityNeedsConfirmation =>
      _netCapacity && _useRange && !_baselineConfirmed;

  Map<String, dynamic> get _constraintsPayload => {
    'start_date': _start,
    'end_date': _end,
    'target_date': (_target ?? '').isEmpty ? null : _target,
    'weekly_minutes': {
      for (var day = 0; day < 7; day++) '$day': _weekly?['$day'] ?? 0,
    },
    'capacity_basis': _netCapacity ? 'net' : 'gross_buffer',
    if (_netCapacity && _useRange) ...{
      'weekly_range_min_minutes': _rangeMin,
      'weekly_range_max_minutes': _rangeMax,
      'weekly_baseline_minutes': _adoptedBaseline,
    },
  };

  /// 新计划使用净学习时间口径；只有旧的全量总预算口径计划保留旧标签。
  bool get _netCapacity => !_legacyGross;

  /// 采用值 = 用户给出的容量范围下限（保守值），max 只用于较高容量情景说明。
  int? get _adoptedBaseline {
    if (!_useRange) return null;
    final min = _rangeMin;
    if (min == null || min <= 0) return null;
    return min;
  }

  /// 模板模式下的周总量 = 一周七天之和，作为已确认的默认模板。
  int get _templateTotal => [
    for (var day = 0; day < 7; day++) _weekly?['$day'] ?? 0,
  ].fold<int>(0, (sum, value) => sum + value);

  void _ensureRangeDefaults() {
    final total = _templateTotal;
    final min = _rangeMin;
    final max = _rangeMax;
    if (min == null || min <= 0) {
      _rangeMin = total > 0 ? (total * 0.75).round() : 300;
    }
    if (max == null || max <= 0) {
      _rangeMax = total > 0 ? total : 600;
    }
    if ((_rangeMax ?? 0) < (_rangeMin ?? 0)) {
      _rangeMax = _rangeMin;
    }
  }

  /// 周期容量估算：与解析核心同一口径（净/总口径、基线与估算）。
  int _periodCapacity(OnboardingSession session) {
    if (_start == null || _end == null || _start!.isEmpty || _end!.isEmpty) {
      return 0;
    }
    final base = Profile(
      userId: 'onboarding-preview',
      planStartDate: _start!,
      planEndDate: _end!,
      weeklyMinutes: {
        for (var day = 0; day < 7; day++) '$day': _weekly?['$day'] ?? 0,
      },
      dailyLimitMinutes: 480,
      granularityMinutes: 30,
      bufferMinutes: 30,
      subjectLimitMinutes: 240,
      studyStartMinute: 480,
      studyEndMinute: 1320,
      foundation: '',
      capacityBasis: _netCapacity ? CapacityBasis.net : CapacityBasis.grossBuffer,
      weeklyBaselineMinutes: _adoptedBaseline,
      weeklyRangeMinMinutes: _useRange ? _rangeMin : null,
      weeklyRangeMaxMinutes: _useRange ? _rangeMax : null,
    );
    return summarizePeriodCapacity(base, _start!, _end!).totalMinutes;
  }

  String get _constraintsKey => jsonEncode(_constraintsPayload);

  Widget _schedule(OnboardingSession session, OnboardingFlow flow, bool busy) {
    final constraints = session.stage == 'constraints';
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
    final previewValid =
        session.preview != null && _previewConstraints == _constraintsKey;
    final hasHardErrors = planningEntries(
      session.preview?['issues'],
    ).any((issue) => issue['severity'] == 'error');
    final capacity = _periodCapacity(session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          constraints ? '确认本次规划条件' : '预览并确认每日安排',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        if (!constraints)
          Text(
            '${session.courses.length} 门课程 · ${session.items.length} 个事项 · 总预算 ${(budget / 60).toStringAsFixed(1)} 小时',
          ),
        if (constraints)
          Text(
            session.profile.goalText.isNotEmpty
                ? session.profile.goalText
                : '本次课程：${session.courses.map((c) => c.name).join('、')}',
          ),
        if (!constraints) PlanningRouteView(planning: session.planning),
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
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('大致周容量范围')),
                  ButtonSegment(value: false, label: Text('按天填写模板')),
                ],
                selected: {_useRange},
                onSelectionChanged: busy
                    ? null
                    : (values) => setState(() {
                        _useRange = values.single;
                        if (_useRange) {
                          _ensureRangeDefaults();
                          _rangeMinController.text = '${_rangeMin ?? ''}';
                          _rangeMaxController.text = '${_rangeMax ?? ''}';
                        }
                      }),
              ),
              const SizedBox(height: 8),
              Text(
                _netCapacity
                    ? '按净学习时间填写：输入的就是真正能用于学习的净预算，程序不会再机械扣除七天机动。'
                    : '旧计划沿用总预算口径：安排前会先扣除每日机动时间。',
                style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
              ),
              if (_useRange) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: TextFormField(
                        key: const ValueKey('weekly-range-min'),
                        controller: _rangeMinController,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '每周最少能学',
                          suffixText: '分钟',
                        ),
                        validator: (value) {
                          final minutes = int.tryParse(value ?? '');
                          return minutes == null ||
                                  minutes < 0 ||
                                  minutes > 10080
                              ? '填写0至10080分钟'
                              : null;
                        },
                        onChanged: (value) => setState(
                          () => _rangeMin = int.tryParse(value) ?? _rangeMin,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: TextFormField(
                        key: const ValueKey('weekly-range-max'),
                        controller: _rangeMaxController,
                        enabled: !busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '每周最多能学',
                          suffixText: '分钟',
                        ),
                        validator: (value) {
                          final minutes = int.tryParse(value ?? '');
                          if (minutes == null || minutes < 0 || minutes > 10080) {
                            return '填写0至10080分钟';
                          }
                          if (_rangeMin != null && minutes < _rangeMin!) {
                            return '上限不能小于下限';
                          }
                          return null;
                        },
                        onChanged: (value) => setState(
                          () => _rangeMax = int.tryParse(value) ?? _rangeMax,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_adoptedBaseline != null) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    key: const ValueKey('weekly-baseline-confirm'),
                    value: _baselineConfirmed,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: busy
                        ? null
                        : (value) =>
                              setState(() => _baselineConfirmed = value ?? false),
                    title: Text(
                      '采用保守基线 ${duration(_adoptedBaseline!)} 作为初始排程依据',
                    ),
                    subtitle: const Text(
                      '取范围下限，避免高估容量导致计划无法执行；'
                      '较高容量情景只用于说明可达范围，不用于本次排程。'
                      '程序据此生成的每日建议不代表你逐日确认。',
                    ),
                  ),
                  if (!_baselineConfirmed)
                    const PlannerNotice(
                      '请确认采用的周容量基线后再继续。',
                      tone: PlannerNoticeTone.info,
                    ),
                ],
              ] else ...[
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
                            suffixText: _netCapacity ? '净分钟' : '分钟',
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
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _netCapacity
              ? '只给周总量时，程序按模板比例生成每日建议，不会存成你逐日确认的分配；'
                    '单门课程每天最多4小时。'
              : '每日预留30分钟机动，单门课程每天最多4小时。',
          style: const TextStyle(color: PlannerColors.muted),
        ),
        const SizedBox(height: 8),
        Text(
          '本次将一次生成 $_start 至 $_end 的全周期每日安排（含首尾），不会只生成近期窗口。',
          style: const TextStyle(color: PlannerColors.muted),
        ),
        if (constraints) ...[
          const SizedBox(height: 16),
          if (planningEntries(session.currentPlan?['fixed_events']).isEmpty)
            const Text(
              '当前没有固定课程、考试或休息占用。',
              style: TextStyle(color: PlannerColors.muted),
            )
          else
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '现有固定占用 ${planningEntries(session.currentPlan?['fixed_events']).length} 项',
              ),
              children: [
                for (final event in planningEntries(
                  session.currentPlan?['fixed_events'],
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(planningText(event['title'])),
                    subtitle: Text(
                      '${event['date']} · ${clockTime((event['start_minute'] as num? ?? 0).toInt())} · '
                      '${duration((event['duration_minutes'] as num? ?? 0).toInt())} · '
                      '${switch (event['repeat']) {
                        'daily' => '每天',
                        'weekly' => '每周',
                        _ => '单次',
                      }}',
                    ),
                  ),
              ],
            ),
        ],
        if (!constraints && _end!.isNotEmpty && budget > capacity) ...[
          const SizedBox(height: 12),
          PlannerNotice(
            '事项预算超出可用时间约 ${((budget - capacity) / 60).toStringAsFixed(1)} 小时，部分内容可能无法排入。',
            tone: PlannerNoticeTone.warning,
          ),
        ],
        if (!constraints && session.preview != null && !previewValid) ...[
          const SizedBox(height: 12),
          const PlannerNotice(
            '时间条件已修改，请重新试排后确认。',
            tone: PlannerNoticeTone.warning,
          ),
        ],
        if (!constraints && previewValid)
          PlanningPreviewView(preview: session.preview!),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => flow.act({
                      'type': 'back',
                      'target': constraints ? 'courses' : 'items',
                    }),
              icon: const Icon(Icons.arrow_back),
              label: Text(constraints ? '返回修改课程' : '返回修改事项'),
            ),
            if (!constraints)
              OutlinedButton.icon(
                onPressed:
                    busy || _capacityNeedsConfirmation
                    ? null
                    : () async {
                        if (!_form.currentState!.validate()) return;
                        final key = _constraintsKey;
                        if (await flow.act({
                              'type': 'preview_schedule',
                              ..._constraintsPayload,
                            }) &&
                            mounted) {
                          setState(() => _previewConstraints = key);
                        }
                      },
                icon: const Icon(Icons.preview_outlined),
                label: Text(previewValid ? '重新试排' : '试排并检查'),
              ),
            FilledButton.icon(
              onPressed:
                  busy ||
                      _capacityNeedsConfirmation ||
                      (!constraints && (!previewValid || hasHardErrors))
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) return;
                      final ok = await flow.act({
                        'type': constraints ? 'set_constraints' : 'finish',
                        ..._constraintsPayload,
                        if (!constraints)
                          'preview_token': session.preview!['token'],
                      });
                      if (ok && !constraints && mounted && widget.embedded) {
                        context.go('/');
                      }
                    },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                constraints
                    ? '确认条件，生成事项'
                    : session.replanning
                    ? '确认并更新每日计划'
                    : '确认并生成每日计划',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
