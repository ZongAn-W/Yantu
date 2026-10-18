import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_state.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../auth/application/auth_controller.dart';
import '../../planner/application/onboarding_controller.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/capacity.dart' as capacity;
import '../../planner/domain/plan_cycle.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/constraint_dialog.dart';
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';
import '../../shell/app_shell.dart';
import 'capacity_overrides_dialog.dart';

/// Web `/settings` — study information, scheduling boundaries, course priority,
/// data management, account and sync state.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

const _weekDays = [
  ('1', '周一'),
  ('2', '周二'),
  ('3', '周三'),
  ('4', '周四'),
  ('5', '周五'),
  ('6', '周六'),
  ('0', '周日'),
];

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _goalText = TextEditingController();
  final _goalSubtype = TextEditingController();
  final _targetDate = TextEditingController();
  final _planStart = TextEditingController();
  final _planEnd = TextEditingController();
  final _school = TextEditingController();
  final _program = TextEditingController();
  final _progress = TextEditingController();
  final _constraints = TextEditingController();
  final _buffer = TextEditingController();
  final _subjectLimit = TextEditingController();
  final _startMinute = TextEditingController();
  final _endMinute = TextEditingController();
  final _weekly = <String, TextEditingController>{};
  String? _profileId;
  int _granularity = 30;
  GoalType _goalType = GoalType.other;
  bool _targetConfirmed = false;
  Map<String, int> _priorities = const {};
  String? _profileError;
  String? _notice;
  int _weekVersion = 0;

  @override
  void dispose() {
    for (final controller in [
      _goalText,
      _goalSubtype,
      _targetDate,
      _planStart,
      _planEnd,
      _school,
      _program,
      _progress,
      _constraints,
      _buffer,
      _subjectLimit,
      _startMinute,
      _endMinute,
      ..._weekly.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Loads the form from the current plan, but only when the account changes so
  /// typing is never overwritten by a background sync.
  void _seed(PlannerData? data) {
    if (data == null || _profileId == data.profile.userId) return;
    _profileId = data.profile.userId;
    final draft = ProfileSettingsDraft.from(
      data.profile,
      today: shanghaiToday(),
    );
    _goalText.text = draft.goalText;
    _goalSubtype.text = draft.goalSubtype;
    _targetDate.text = draft.targetDate;
    _targetConfirmed = draft.targetDateConfirmed;
    _planStart.text = draft.planStartDate;
    _planEnd.text = draft.planEndDate;
    _school.text = draft.targetSchool;
    _program.text = draft.targetProgram;
    _progress.text = draft.currentProgress;
    _constraints.text = data.profile.constraints;
    _buffer.text = '${draft.bufferMinutes}';
    _subjectLimit.text = '${draft.subjectLimitMinutes}';
    _startMinute.text = '${draft.studyStartMinute}';
    _endMinute.text = '${draft.studyEndMinute}';
    _granularity = draft.granularityMinutes;
    _goalType = draft.goalType;
    for (final entry in _weekly.values) {
      entry.dispose();
    }
    _weekly.clear();
    for (final (key, _) in _weekDays) {
      _weekly[key] = TextEditingController(
        text: '${draft.weeklyMinutes[key] ?? 0}',
      );
    }
    _weekVersion++;
    _priorities = {
      for (final subject in data.subjects) subject.id: subject.priority,
    };
  }

  ProfileSettingsDraft _draft(PlannerData data) => ProfileSettingsDraft.from(
    data.profile,
    today: shanghaiToday(),
  ).copyWith(
    goalText: _goalText.text.trim(),
    goalType: _goalType,
    goalSubtype: _goalSubtype.text.trim(),
    targetDate: _targetDate.text.trim(),
    targetDateConfirmed: _targetConfirmed,
    planStartDate: _planStart.text.trim(),
    planEndDate: _planEnd.text.trim(),
    targetSchool: _school.text.trim(),
    targetProgram: _program.text.trim(),
    currentProgress: _progress.text.trim(),
    constraintsText: _constraints.text.trim(),
    weeklyMinutes: {
      for (final (key, _) in _weekDays)
        key: int.tryParse(_weekly[key]?.text.trim() ?? '') ?? 0,
    },
    bufferMinutes: _number(_buffer, data.profile.bufferMinutes),
    subjectLimitMinutes: _number(
      _subjectLimit,
      data.profile.subjectLimitMinutes,
    ),
    studyStartMinute: _number(_startMinute, data.profile.studyStartMinute),
    studyEndMinute: _number(_endMinute, data.profile.studyEndMinute),
    granularityMinutes: _granularity,
    priorities: _priorities,
  );

  static int _number(TextEditingController controller, int fallback) =>
      int.tryParse(controller.text.trim()) ?? fallback;

  Future<void> _saveProfile() async {
    final data = ref.read(plannerSessionProvider).data;
    final draft = _draft(data);
    final error = validateSettingsDraft(draft);
    if (error != null) {
      setState(() => _profileError = error);
      return;
    }
    setState(() {
      _profileError = null;
      _notice = null;
    });
    try {
      final today = shanghaiToday();
      final planned = applySettings(data, draft);
      final affects = settingsAffectSchedule(data, draft);
      var next = planned;
      if (affects) {
        // 容量或周期变化会重新评估受影响的未来安排：先预览，再确认。
        final adjustment = reschedulePlan(
          planned,
          today: today,
          start: draft.planStartDate,
          end: draft.planEndDate,
        );
        if (!mounted) return;
        final confirmed = await ScheduleChangeDialog.show(
          context,
          before: data,
          adjustment: adjustment,
          start: draft.planStartDate,
          end: draft.planEndDate,
        );
        if (!confirmed) return;
        next = adjustment.data;
      }
      // 预览期间计划可能已变化：用当前数据重新校验，避免旧快照覆盖新进度。
      final expected = jsonEncode(data.toJson());
      await ref.read(plannerSessionProvider).edit((current) {
        if (jsonEncode(current.toJson()) != expected) {
          throw StateError('计划已更新，请重新预览后再应用');
        }
        return next;
      });
      if (mounted) {
        setState(
          () => _notice = affects
              ? '学习目标与规划已保存，并按新的容量重新安排了未来日程。'
              : '学习目标与规划已保存到本机。',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _profileError = error is StateError ? error.message : '$error',
        );
      }
    }
  }

  Future<void> _action(String success, Future<void> Function() run) async {
    try {
      await run();
      if (mounted) setState(() => _notice = success);
    } catch (error) {
      if (mounted) {
        setState(
          () => _profileError = error is StateError ? error.message : '$error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlannerPageState(
      builder: (context, snapshot) {
        final data = snapshot.data!;
        _seed(data);
        final text = Theme.of(context).textTheme;
        return PlannerPage(
          title: '设置',
          subtitle: '调整计划边界，保持排程符合你的实际生活。',
          actions: [
            PlannerPanel(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: syncTone(snapshot.status),
                  ),
                  const SizedBox(width: 6),
                  Text(syncLabels[snapshot.status] ?? '等待同步'),
                ],
              ),
            ),
          ],
          children: [
            if (_notice != null) ...[
              PlannerNotice(_notice!, tone: PlannerNoticeTone.success),
              const SizedBox(height: 12),
            ],
            if (_profileError != null) ...[
              PlannerNotice(_profileError!, tone: PlannerNoticeTone.error),
              const SizedBox(height: 12),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1000;
                final left = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _goalPanel(data, text),
                    const SizedBox(height: 16),
                    _boundaryPanel(data, text),
                  ],
                );
                final right = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _priorityPanel(data, text),
                    const SizedBox(height: 16),
                    _dataPanel(snapshot, text),
                    const SizedBox(height: 16),
                    _connectionPanel(snapshot, text),
                  ],
                );
                if (!wide) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 16), right],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    const SizedBox(width: 16),
                    Expanded(child: right),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _goalPanel(PlannerData data, TextTheme text) => PlannerPanel(
    title: '学习目标与规划',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _goalText,
          minLines: 1,
          maxLines: 3,
          maxLength: 2000,
          decoration: const InputDecoration(
            labelText: '学习目标',
            hintText: '例如：从零学习 Python，能独立处理 CSV 并完成数据分析',
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<GoalType>(
          initialValue: _goalType,
          decoration: const InputDecoration(labelText: '目标类型'),
          items: [
            for (final entry in goalTypeLabels.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) =>
              setState(() => _goalType = value ?? GoalType.other),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _goalSubtype,
          decoration: const InputDecoration(
            labelText: '具体考试或学习领域（可选）',
            helperText: '例如：考研、雅思、线性代数、Python',
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: '目标日期（可选）',
                value: _targetDate.text,
                onChanged: (value) => setState(() {
                  _targetDate.text = value;
                  if (value.isEmpty) _targetConfirmed = false;
                }),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _targetDate.text.isEmpty
                  ? null
                  : () => setState(() {
                      _targetDate.clear();
                      _targetConfirmed = false;
                    }),
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('清空日期'),
            ),
          ],
        ),
        if (_targetDate.text.isNotEmpty)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _targetConfirmed,
            title: const Text('这个日期已经确认'),
            subtitle: const Text('未确认时按“预计目标日期”展示，以正式通知为准。'),
            onChanged: (value) =>
                setState(() => _targetConfirmed = value ?? false),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DateField(
                label: '规划开始日期',
                value: _planStart.text,
                onChanged: (value) => setState(() => _planStart.text = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DateField(
                label: '规划结束日期',
                value: _planEnd.text,
                onChanged: (value) => setState(() => _planEnd.text = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '目标日期是希望达成结果的日期，可以不设置；规划结束日期是本次排程的边界。',
          style: TextStyle(color: PlannerColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _progress,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '当前基础与进度',
            hintText: '例如：学过矩阵，特征值和二次型还没开始',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _constraints,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '其他约束与偏好（可选）',
            hintText: '例如：周三和周日休息，不看视频课',
          ),
        ),
        if (_goalType == GoalType.exam) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _school,
            decoration: const InputDecoration(
              labelText: '院校或机构（可选）',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _program,
            decoration: const InputDecoration(
              labelText: '专业或方向（可选）',
            ),
          ),
        ],
        const SizedBox(height: 12),
        AsyncActionButton(
          label: '保存学习目标与规划',
          icon: Icons.save_outlined,
          onPressed: _saveProfile,
          onError: (error) => setState(
            () => _profileError = error is StateError ? error.message : '$error',
          ),
        ),
      ],
    ),
  );

  Widget _boundaryPanel(PlannerData data, TextTheme text) {
    final net = data.profile.capacityBasis == CapacityBasis.net;
    final assumptions = capacity.capacityAssumptionLabel(data.profile);
    return PlannerPanel(
      title: '每日可用时间与排程边界',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            net
                ? '一周七天的净学习时间：输入的就是真正能用于学习的净预算，程序不再机械扣除机动。某天为 0 时该天不生成学习安排。'
                : '一周七天的可用学习时间；某天为 0 时该天不生成学习安排。旧计划沿用总预算口径。',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (key, label) in _weekDays)
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    key: ValueKey('settings-weekly-$_weekVersion-$key'),
                    controller: _weekly[key],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: label,
                      suffixText: net ? '净分钟' : '分钟',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _granularity,
            decoration: const InputDecoration(labelText: '时间粒度（分钟）'),
            items: const [
              DropdownMenuItem(value: 30, child: Text('30')),
              DropdownMenuItem(value: 60, child: Text('60')),
            ],
            onChanged: (value) => setState(() => _granularity = value ?? 30),
          ),
          const SizedBox(height: 12),
          if (!net) ...[
            _NumberField(
              controller: _buffer,
              label: '每日机动时间（分钟）',
              helper: '30 至 180，排程至少保留 30 分钟',
            ),
            const SizedBox(height: 12),
          ],
          _NumberField(
            controller: _subjectLimit,
            label: '单科每日上限（分钟）',
            helper: '60 至 480，实际排程最多按 240 分钟计算',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: _startMinute,
                  label: '学习开始（分钟）',
                  helper: '480 = 08:00',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  controller: _endMinute,
                  label: '学习结束（分钟）',
                  helper: '1320 = 22:00',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '每天只安排事项和时长，不指定学习开始时间。固定课程、考试和休息可保留具体时间。',
            style: TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
          const Divider(height: 24),
          Text('容量假设与例外', style: text.titleSmall),
          const SizedBox(height: 4),
          if (assumptions.isNotEmpty)
            Text(
              assumptions,
              key: const ValueKey('settings-capacity-assumptions'),
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            )
          else
            const Text(
              '当前按默认每周模板逐日计算容量。',
              key: ValueKey('settings-capacity-assumptions'),
              style: TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('settings-capacity-editor'),
              onPressed: () => CapacityOverridesDialog.show(context),
              icon: const Icon(Icons.tune_outlined),
              label: const Text('管理特定周与日期容量'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priorityPanel(PlannerData data, TextTheme text) => PlannerPanel(
    title: '课程优先级',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final subject in data.subjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: SubjectChip(
                    name: subject.name,
                    color: subjectColor(subject.id, subject.color),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<int>(
                    initialValue: _priorities[subject.id] ?? subject.priority,
                    decoration: const InputDecoration(labelText: '优先级'),
                    items: const [
                      DropdownMenuItem(value: 3, child: Text('高')),
                      DropdownMenuItem(value: 2, child: Text('中高')),
                      DropdownMenuItem(value: 1, child: Text('普通')),
                    ],
                    onChanged: (value) => setState(() {
                      _priorities = {
                        ..._priorities,
                        subject.id: value ?? subject.priority,
                      };
                    }),
                  ),
                ),
              ],
            ),
          ),
        const Text(
          '优先级影响排程顺序：同一天内优先安排高优先级课程。',
          style: TextStyle(color: PlannerColors.muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _dataPanel(PlannerSnapshot snapshot, TextTheme text) => PlannerPanel(
    title: '数据管理',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('JSON 包含课程、事项、每日安排、学习记录和重排快照。恢复后先保存在本机，再检查云端版本并同步。'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            AsyncActionButton(
              label: '导出本地数据',
              icon: Icons.download_outlined,
              filled: false,
              enabled: snapshot.data != null,
              onPressed: () => _action(
                '已导出本地数据。',
                () => ref.read(plannerSessionProvider).exportJson(),
              ),
            ),
            AsyncActionButton(
              label: '从 JSON 恢复',
              icon: Icons.upload_outlined,
              filled: false,
              enabled: !snapshot.busy,
              onPressed: () async {
                final confirmed = await confirmAction(
                  context,
                  title: '从 JSON 恢复？',
                  message: '确认文件后会替换本机计划。当前有效数据会保存为最近备份；云端冲突会另行提示。',
                  confirmLabel: '选择恢复文件',
                );
                if (!confirmed) return;
                await _action(
                  'JSON 已恢复到本机，等待同步。',
                  () => ref.read(plannerSessionProvider).importJson(),
                );
              },
            ),
            AsyncActionButton(
              label: '恢复最近备份',
              icon: Icons.restore,
              filled: false,
              enabled: !snapshot.busy,
              onPressed: () async {
                final confirmed = await confirmAction(
                  context,
                  title: '恢复最近备份？',
                  message: '当前记录会另存保留，恢复的计划会标记为待同步。',
                  confirmLabel: '恢复备份',
                );
                if (!confirmed) return;
                await _action(
                  '已从备份恢复，等待同步。',
                  () => ref.read(plannerSessionProvider).recover(),
                );
              },
            ),
            if (snapshot.blocked)
              AsyncActionButton(
                label: '重新读取数据',
                icon: Icons.refresh,
                filled: false,
                onPressed: () => _action(
                  '已重新读取本机数据。',
                  () => ref.read(plannerSessionProvider).reload(),
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _connectionPanel(PlannerSnapshot snapshot, TextTheme text) {
    final auth = ref.watch(authControllerProvider);
    return PlannerPanel(
      title: '服务器连接',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlannerStat(
            label: '账号',
            value: auth.user?.username ?? auth.user?.email ?? '未登录',
          ),
          PlannerStat(
            label: '同步状态',
            value: syncLabels[snapshot.status] ?? '等待同步',
            tone: syncTone(snapshot.status),
          ),
          PlannerStat(label: '云端版本', value: '${snapshot.revision}'),
          PlannerStat(label: '待同步修改', value: snapshot.pending ? '有' : '无'),
          if (snapshot.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            PlannerNotice(
              snapshot.message,
              tone: snapshot.status == SyncStatus.error
                  ? PlannerNoticeTone.error
                  : PlannerNoticeTone.info,
            ),
          ],
          if (snapshot.busy) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(semanticsLabel: '正在同步'),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AsyncActionButton(
                label: '重试同步',
                icon: Icons.sync,
                filled: false,
                enabled: !snapshot.busy && !snapshot.blocked,
                onPressed: () => _action(
                  '同步已完成。',
                  () => ref.read(plannerSessionProvider).sync(),
                ),
              ),
              AsyncActionButton(
                label: '重新读取学习目标',
                icon: Icons.refresh,
                filled: false,
                onPressed: () => _action(
                  '已重新读取学习目标。',
                  () => ref.read(onboardingStatusProvider.notifier).refresh(),
                ),
              ),
            ],
          ),
          if (snapshot.conflicts.isNotEmpty) ...[
            const Divider(height: 24),
            Text('同步冲突', style: text.titleSmall),
            const SizedBox(height: 4),
            const Text('本机修改已保留。请选择同时修改内容的保留方式；其他独立修改会一并合并。'),
            for (final conflict in snapshot.conflicts)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('• $conflict'),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AsyncActionButton(
                  label: '冲突项保留本机',
                  icon: Icons.phone_android_outlined,
                  enabled: !snapshot.busy,
                  onPressed: () => _action(
                    '已按本机版本合并并重新同步。',
                    () => ref
                        .read(plannerSessionProvider)
                        .resolveConflict(useLocal: true),
                  ),
                ),
                AsyncActionButton(
                  label: '冲突项使用云端',
                  icon: Icons.cloud_outlined,
                  filled: false,
                  enabled: !snapshot.busy,
                  onPressed: () => _action(
                    '已按云端版本合并并重新同步。',
                    () => ref
                        .read(plannerSessionProvider)
                        .resolveConflict(useLocal: false),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, helperText: helper),
  );
}