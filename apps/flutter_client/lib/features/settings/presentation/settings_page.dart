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
import '../../planner/presentation/planner_dialogs.dart';
import '../../planner/presentation/planner_page_state.dart';
import '../../shell/app_shell.dart';

/// Web `/settings` — study information, scheduling boundaries, course priority,
/// data management, account and sync state.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _school = TextEditingController();
  final _program = TextEditingController();
  final _examDate = TextEditingController();
  final _examEndDate = TextEditingController();
  final _dailyLimit = TextEditingController();
  final _buffer = TextEditingController();
  final _subjectLimit = TextEditingController();
  final _startMinute = TextEditingController();
  final _endMinute = TextEditingController();
  String? _profileId;
  int _granularity = 30;
  Map<String, int> _priorities = const {};
  String? _profileError;
  String? _notice;

  @override
  void dispose() {
    for (final controller in [
      _school,
      _program,
      _examDate,
      _examEndDate,
      _dailyLimit,
      _buffer,
      _subjectLimit,
      _startMinute,
      _endMinute,
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
    final draft = ProfileSettingsDraft.from(data.profile);
    _school.text = draft.targetSchool;
    _program.text = draft.targetProgram;
    _examDate.text = draft.examDate;
    _examEndDate.text = draft.examEndDate;
    _dailyLimit.text = '${draft.dailyLimitMinutes}';
    _buffer.text = '${draft.bufferMinutes}';
    _subjectLimit.text = '${draft.subjectLimitMinutes}';
    _startMinute.text = '${draft.studyStartMinute}';
    _endMinute.text = '${draft.studyEndMinute}';
    _granularity = draft.granularityMinutes;
    _priorities = {
      for (final subject in data.subjects) subject.id: subject.priority,
    };
  }

  ProfileSettingsDraft _draft(PlannerData data) => ProfileSettingsDraft.from(
    data.profile,
  ).copyWith(
    targetSchool: _school.text.trim(),
    targetProgram: _program.text.trim(),
    examDate: _examDate.text.trim(),
    examEndDate: _examEndDate.text.trim(),
    dailyLimitMinutes: _number(_dailyLimit, data.profile.dailyLimitMinutes),
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
      await ref
          .read(plannerSessionProvider)
          .edit((current) => applySettings(current, draft));
      if (mounted) setState(() => _notice = '备考信息与排程边界已保存到本机。');
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
                    _studyInfoPanel(data, text),
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

  Widget _studyInfoPanel(PlannerData data, TextTheme text) => PlannerPanel(
    title: '备考信息',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _school,
          decoration: const InputDecoration(labelText: '目标院校'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _program,
          decoration: const InputDecoration(labelText: '目标方向'),
        ),
        const SizedBox(height: 12),
        DateField(
          label: '初试第一天',
          value: _examDate.text,
          onChanged: (value) => setState(() => _examDate.text = value),
        ),
        const SizedBox(height: 12),
        DateField(
          label: '初试第二天',
          value: _examEndDate.text,
          onChanged: (value) => setState(() => _examEndDate.text = value),
        ),
        const SizedBox(height: 8),
        const Text(
          '2027-12-25：政治、英语一　·　2027-12-26：数学一、408',
          style: TextStyle(color: PlannerColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        AsyncActionButton(
          label: '保存备考信息与边界',
          icon: Icons.save_outlined,
          onPressed: _saveProfile,
          onError: (error) => setState(
            () => _profileError = error is StateError ? error.message : '$error',
          ),
        ),
      ],
    ),
  );

  Widget _boundaryPanel(PlannerData data, TextTheme text) => PlannerPanel(
    title: '排程边界',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NumberField(
          controller: _dailyLimit,
          label: '每日学习上限（分钟）',
          helper: '60 至 1440，实际排程最多按 480 分钟计算',
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
        _NumberField(
          controller: _buffer,
          label: '每日机动时间（分钟）',
          helper: '30 至 180，排程至少保留 30 分钟',
        ),
        const SizedBox(height: 12),
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
      ],
    ),
  );

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
          '政治计划从 2027 年 7 月开始逐步加入。',
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
                label: '重新读取备考资料',
                icon: Icons.refresh,
                filled: false,
                onPressed: () => _action(
                  '已重新读取备考资料。',
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
