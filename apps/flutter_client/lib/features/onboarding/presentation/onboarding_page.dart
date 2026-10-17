import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/api_models.dart';
import '../../planner/application/onboarding_controller.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/planner_dialogs.dart' show DateField;

const _days = [
  ('1', '周一'),
  ('2', '周二'),
  ('3', '周三'),
  ('4', '周四'),
  ('5', '周五'),
  ('6', '周六'),
  ('0', '周日'),
];

/// Web steps 1..6 of the profile wizard plus the AI draft confirmation step.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _school = TextEditingController();
  final _program = TextEditingController();
  final _progress = TextEditingController();
  final _constraints = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _school.dispose();
    _program.dispose();
    _progress.dispose();
    _constraints.dispose();
    super.dispose();
  }

  void _seed(OnboardingProfile profile) {
    if (_seeded) return;
    _seeded = true;
    _school.text = profile.targetSchool;
    _program.text = profile.targetProgram;
    _progress.text = profile.currentProgress;
    _constraints.text = profile.constraintsText;
  }

  OnboardingProfile _collect(OnboardingProfile base) => base.copyWith(
    targetSchool: _school.text.trim(),
    targetProgram: _program.text.trim(),
    currentProgress: _progress.text.trim(),
    constraintsText: _constraints.text.trim(),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    _seed(state.profile);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final progress = (state.step / 7 * 100).round();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.auto_awesome,
                                  size: 15,
                                  color: PlannerColors.blue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'AI 备考规划',
                                  style: text.labelLarge?.copyWith(
                                    color: PlannerColors.blue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('先把你的目标说清楚', style: text.headlineSmall),
                            const SizedBox(height: 4),
                            const Text(
                              'AI 会根据考试时间、当前进度和真实可用时间生成可调整的课程与事项。',
                              style: TextStyle(color: PlannerColors.muted),
                            ),
                          ],
                        ),
                        Text(
                          state.step < 7 ? '第 ${state.step} / 6 步' : '确认计划',
                          style: tabularFigures,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 6,
                      backgroundColor: PlannerColors.border,
                      semanticsLabel: '备考资料填写进度 $progress%',
                    ),
                    const SizedBox(height: 20),
                    PlannerPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _stepBody(state, controller),
                          if (state.error != null) ...[
                            const SizedBox(height: 16),
                            PlannerNotice(
                              state.error!,
                              tone: PlannerNoticeTone.error,
                            ),
                          ],
                          const SizedBox(height: 20),
                          _actions(state, controller),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody(OnboardingState state, OnboardingController controller) {
    final profile = state.profile;
    switch (state.step) {
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '你准备参加什么考试？',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                for (final kind in const ['考研', '考公', '其他'])
                  ChoiceChip(
                    label: Text(kind),
                    selected: profile.examType == kind,
                    onSelected: (_) => controller.updateProfile(
                      profile.copyWith(examType: kind),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '后续课程和事项会围绕这个考试类型生成。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('考试日期', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DateField(
              label: '正式考试日期',
              value: profile.examDate,
              firstDate: shanghaiToday(),
              onChanged: (value) =>
                  controller.updateProfile(profile.copyWith(examDate: value)),
            ),
            const SizedBox(height: 8),
            const Text(
              '如果日期尚未公布，先填预计日期，之后可以重新生成计划。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('你的目标', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextFormField(
              controller: _school,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '目标院校／单位',
                hintText: '例如：上海交通大学',
                counterText: '',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '请填写目标院校或单位' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _program,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '专业／岗位方向',
                hintText: '例如：计算机技术、行政执法',
                counterText: '',
              ),
            ),
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '你现在学到哪里了？',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _progress,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: '当前进度',
                hintText: '例如：高数刚学完极限，英语词汇完成约 30%，还没有开始政治。',
                counterText: '',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '请填写当前进度' : null,
            ),
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '每周每天能学多久？',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (key, label) in _days)
                  SizedBox(
                    width: 150,
                    child: TextFormField(
                      initialValue: '${profile.weeklyMinutes[key] ?? 0}',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: label,
                        suffixText: '分钟',
                      ),
                      onChanged: (value) => controller.updateProfile(
                        profile.copyWith(
                          weeklyMinutes: {
                            ...profile.weeklyMinutes,
                            key: int.tryParse(value) ?? 0,
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '只填写真正能用于学习的时间，计划会自动保留机动时间。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ],
        );
      case 6:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '还有哪些限制？',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _constraints,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: '固定课程、休息时间和学习偏好',
                hintText: '例如：周三晚上有课；早上效率高；希望每次学习不超过 90 分钟。',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '填写越具体，AI 给出的事项和每日建议越容易落地。',
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ],
        );
      default:
        return _DraftStep(state: state, controller: controller);
    }
  }

  Widget _actions(OnboardingState state, OnboardingController controller) {
    final busy = state.loading;
    if (state.step == 7) {
      return Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => controller.goTo(6),
            child: const Text('返回修改资料'),
          ),
          FilledButton.icon(
            onPressed: busy || (state.draft?.items.isEmpty ?? true)
                ? null
                : () => controller.confirmDraft(),
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(busy ? '正在生成每日计划…' : '确认并生成每日计划'),
          ),
        ],
      );
    }
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 8,
      children: [
        if (state.step > 1)
          OutlinedButton.icon(
            onPressed: busy ? null : controller.back,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('上一步'),
          ),
        if (state.step < 6)
          FilledButton.icon(
            onPressed: busy
                ? null
                : () {
                    final valid = _formKey.currentState?.validate() ?? true;
                    if (!valid) return;
                    controller.updateProfile(_collect(state.profile));
                    controller.next();
                  },
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('下一步'),
          ),
        if (state.step == 6)
          FilledButton.icon(
            onPressed: busy
                ? null
                : () {
                    final valid = _formKey.currentState?.validate() ?? true;
                    if (!valid) return;
                    controller.updateProfile(_collect(state.profile));
                    controller.submitProfile();
                  },
            icon: busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(busy ? 'AI 正在分析…' : '生成课程与事项'),
          ),
      ],
    );
  }
}

/// Step 7: review and edit the AI draft before it becomes the plan.
class _DraftStep extends StatelessWidget {
  const _DraftStep({required this.state, required this.controller});

  final OnboardingState state;
  final OnboardingController controller;

  @override
  Widget build(BuildContext context) {
    final draft = state.draft!;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check, size: 15, color: PlannerColors.green),
            const SizedBox(width: 6),
            Text('AI 分析完成', style: text.labelLarge),
          ],
        ),
        const SizedBox(height: 6),
        Text('确认你的课程与事项', style: text.titleMedium),
        const SizedBox(height: 8),
        Text(draft.analysisSummary),
        if (draft.assumptions.isNotEmpty || draft.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final note in draft.assumptions)
                Text(
                  '假设：$note',
                  style: const TextStyle(
                    color: PlannerColors.muted,
                    fontSize: 12,
                  ),
                ),
              for (final note in draft.warnings)
                Text(
                  '提醒：$note',
                  style: const TextStyle(
                    color: PlannerColors.orange,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        for (final course in draft.courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PlannerPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          course.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${draft.items.where((item) => item.courseId == course.id).length} 个事项',
                        style: const TextStyle(
                          color: PlannerColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  if (course.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      course.description,
                      style: const TextStyle(
                        color: PlannerColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  for (final item in draft.items.where(
                    (entry) => entry.courseId == course.id,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: item.title,
                                  decoration: const InputDecoration(
                                    labelText: '事项名称',
                                  ),
                                  onChanged: (value) => controller.updateDraft(
                                    draft.copyWith(
                                      items: [
                                        for (final entry in draft.items)
                                          entry.id == item.id
                                              ? entry.copyWith(title: value)
                                              : entry,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 120,
                                child: TextFormField(
                                  initialValue: '${item.estimatedMinutes}',
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: '预算',
                                    suffixText: '分',
                                  ),
                                  onChanged: (value) => controller.updateDraft(
                                    draft.copyWith(
                                      items: [
                                        for (final entry in draft.items)
                                          entry.id == item.id
                                              ? entry.copyWith(
                                                  estimatedMinutes:
                                                      int.tryParse(value) ??
                                                      entry.estimatedMinutes,
                                                )
                                              : entry,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '删除 ${item.title}',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: () => controller.updateDraft(
                                  draft.copyWith(
                                    items: [
                                      for (final entry in draft.items)
                                        if (entry.id != item.id) entry,
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            initialValue: item.description,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: '学习范围与完成标准',
                            ),
                            onChanged: (value) => controller.updateDraft(
                              draft.copyWith(
                                items: [
                                  for (final entry in draft.items)
                                    entry.id == item.id
                                        ? entry.copyWith(description: value)
                                        : entry,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.earliestDate ?? '未定'} 至 ${item.deadline}',
                            style: tabularFigures.copyWith(
                              fontSize: 11,
                              color: PlannerColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextButton.icon(
                    onPressed: () => controller.updateDraft(
                      draft.copyWith(
                        items: [
                          ...draft.items,
                          ItemDraft(
                            id: 'item-${DateTime.now().microsecondsSinceEpoch}',
                            courseId: course.id,
                            title: '新事项',
                            description: '',
                            completionCriteria: '',
                            estimatedMinutes: 120,
                            earliestDate: shanghaiToday(),
                            deadline: state.profile.examDate,
                            priority: 2,
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加事项'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
