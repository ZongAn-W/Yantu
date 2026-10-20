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
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/planner_dialogs.dart';
import '../../shell/app_shell.dart';
import 'capacity_overrides_dialog.dart';
import 'delete_account_dialog.dart';

/// Web `/settings` — study information and scheduling boundaries,
/// data management, account and sync state.
///
/// 视觉：Mist Ink / 雾蓝墨水。内容最大宽度 720 居中，每个设置分组一张
/// 白底发丝边框卡片（12px 圆角、20px 内边距、20px 组间距），危险操作单独
/// 卡片并用 danger 色文字 + 描边按钮，不做大面积红色填充。
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

/// 「时间粒度」是 30 / 60 两种合法值（与 `validateSettingsDraft` 一致）。
/// 历史 / 演示数据可能带其它值，界面必须先归一化再渲染，否则 Dropdown
/// 的 `value` 不在 `items` 里会触发框架断言。
const _granularityOptions = [30, 60];

/// 正文强调值：13.5 / 1.5。
const _strongStyle = TextStyle(
  fontSize: 13.5,
  height: 1.5,
  fontWeight: FontWeight.w600,
  color: PlannerColors.text,
);

/// 设置行主标签：13.5 / 1.5。
const _rowLabelStyle = TextStyle(
  fontSize: 13.5,
  height: 1.5,
  fontWeight: FontWeight.w500,
  color: PlannerColors.text,
);

/// 设置行辅助说明 / 元信息：12 muted。
const _helperStyle = TextStyle(
  fontSize: 12,
  height: 1.5,
  color: PlannerColors.muted,
);

/// 成段说明：13 / 1.6。
const _bodyStyle = TextStyle(
  fontSize: 13,
  height: 1.6,
  color: PlannerColors.muted,
);

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
  final _startMinute = TextEditingController();
  final _endMinute = TextEditingController();
  final _weekly = <String, TextEditingController>{};
  String? _profileId;
  int _granularity = 30;

  /// profile 里不在可选列表中的时间粒度（例如历史数据 / 演示数据里的 15），
  /// 用于在界面上解释「已归一」这件事。
  int? _unsupportedGranularity;
  GoalType _goalType = GoalType.other;
  bool _targetConfirmed = false;
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
    _startMinute.text = '${draft.studyStartMinute}';
    _endMinute.text = '${draft.studyEndMinute}';
    // 先把 profile 粒度归一到合法选项，保证与下拉 items 永远一致。
    _unsupportedGranularity =
        _granularityOptions.contains(draft.granularityMinutes)
        ? null
        : draft.granularityMinutes;
    _granularity = _normalizeGranularity(draft.granularityMinutes);
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
  }

  /// 未知粒度归一到最近的合法选项；等距时取较小值（保留更细的排程粒度）。
  static int _normalizeGranularity(int minutes) {
    if (_granularityOptions.contains(minutes)) return minutes;
    var best = _granularityOptions.first;
    var bestDistance = (minutes - best).abs();
    for (final option in _granularityOptions.skip(1)) {
      final distance = (minutes - option).abs();
      if (distance < bestDistance) {
        best = option;
        bestDistance = distance;
      }
    }
    return best;
  }

  ProfileSettingsDraft _draft(PlannerData data) =>
      ProfileSettingsDraft.from(data.profile, today: shanghaiToday()).copyWith(
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
        studyStartMinute: _number(_startMinute, data.profile.studyStartMinute),
        studyEndMinute: _number(_endMinute, data.profile.studyEndMinute),
        granularityMinutes: _granularity,
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
      // 保存设置只写入本机 profile；未来安排的重排由调整页的 AI 一键调整负责。
      await ref
          .read(plannerSessionProvider)
          .edit((current) => applySettings(current, draft));
      if (mounted) {
        setState(() => _notice = '学习目标与规划已保存；如需按新容量或周期重排未来安排，请到调整页使用一键调整后续计划。');
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
    final snapshot = ref.watch(plannerDataProvider);
    final data = snapshot.data;
    _seed(data);
    return PlannerPage(
      title: '设置',
      subtitle: '调整计划边界，保持排程符合你的实际生活。',
      maxWidth: 720,
      actions: [_SyncBadge(status: snapshot.status)],
      children: [
        if (_notice != null) ...[
          PlannerNotice(_notice!, tone: PlannerNoticeTone.success),
          const SizedBox(height: PlannerSpace.lg),
        ],
        if (_profileError != null) ...[
          PlannerNotice(_profileError!, tone: PlannerNoticeTone.error),
          const SizedBox(height: PlannerSpace.lg),
        ],
        _accountPanel(),
        const SizedBox(height: PlannerSpace.lg),
        _dangerPanel(snapshot),
        const SizedBox(height: PlannerSpace.lg),
        if (snapshot.ready && !snapshot.blocked && data != null) ...[
          _goalPanel(),
          const SizedBox(height: PlannerSpace.lg),
          _boundaryPanel(data),
          const SizedBox(height: PlannerSpace.lg),
          _dataPanel(snapshot),
          const SizedBox(height: PlannerSpace.lg),
          _connectionPanel(snapshot),
        ] else ...[
          _planUnavailablePanel(snapshot),
          if (snapshot.ready) ...[
            const SizedBox(height: PlannerSpace.lg),
            _dataPanel(snapshot),
            const SizedBox(height: PlannerSpace.lg),
            _connectionPanel(snapshot),
          ],
        ],
      ],
    );
  }

  // ------------------------------------------------------------- 账号 / 危险区

  Widget _accountPanel() {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    return PlannerPanel(
      title: '账号管理',
      subtitle: '标签、事项、每日计划和实际学习记录保存在服务器，本机保留离线副本。',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (user == null)
            const Text('未登录', style: _helperStyle)
          else
            Row(
              children: [
                _AccountAvatar(name: user.username),
                const SizedBox(width: PlannerSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.username, style: _strongStyle),
                      const SizedBox(height: 2),
                      Text(user.email, style: _helperStyle),
                    ],
                  ),
                ),
              ],
            ),
          if (auth.error != null) ...[
            const SizedBox(height: PlannerSpace.md),
            PlannerNotice(auth.error!, tone: PlannerNoticeTone.error),
          ],
          if (auth.deletionPending) ...[
            const SizedBox(height: PlannerSpace.md),
            const PlannerNotice(
              '注销结果尚未确认，计时和同步已暂停。请联网后再次点击“注销账号”确认结果。',
              tone: PlannerNoticeTone.warning,
            ),
          ],
          const SizedBox(height: PlannerSpace.md),
          const _PanelDivider(),
          _SettingRow(
            title: '登录状态',
            description: '退出后返回登录页；本机离线副本和待同步修改会保留。',
            trailing: AsyncActionButton(
              key: const ValueKey('settings-sign-out'),
              label: '退出登录',
              icon: Icons.logout,
              filled: false,
              enabled: user != null && !auth.loading,
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
            ),
          ),
        ],
      ),
    );
  }

  /// 危险操作单独成卡：danger 色文字 + 描边按钮，不做大面积红色填充。
  Widget _dangerPanel(PlannerSnapshot snapshot) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: PlannerColors.danger,
                ),
                const SizedBox(width: PlannerSpace.sm),
                Text(
                  '危险区域',
                  style: const TextStyle(
                    fontSize: 15,
                    height: 22 / 15,
                    fontWeight: FontWeight.w600,
                    color: PlannerColors.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: PlannerSpace.sm),
            const Text(
              '注销后将永久删除账号和学习数据，且无法恢复。如需保留记录，请先在数据管理中导出本地数据。',
              style: _bodyStyle,
            ),
            const SizedBox(height: PlannerSpace.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('settings-delete-account'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: PlannerColors.danger,
                  side: BorderSide(
                    color: PlannerColors.danger.withValues(alpha: 0.45),
                  ),
                ),
                onPressed: user == null || auth.loading || auth.deletingAccount
                    ? null
                    : () => DeleteAccountDialog.show(
                        context,
                        onExport: snapshot.data == null
                            ? null
                            : () =>
                                  ref.read(plannerSessionProvider).exportJson(),
                      ),
                icon: const Icon(Icons.person_remove_outlined, size: 16),
                label: const Text('注销账号'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------- 学习目标与规划

  Widget _goalPanel() {
    final goalTypeValue = goalTypeLabels.containsKey(_goalType)
        ? _goalType
        : GoalType.other;
    return PlannerPanel(
      title: '学习目标与规划',
      subtitle: '目标与周期决定排程边界；保存后可在调整页让 AI 重排未来安排。',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _FormSectionDivider(label: '目标'),
          TextField(
            controller: _goalText,
            minLines: 1,
            maxLines: 3,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: '学习目标',
              hintText: '例如：从零学习 Python，能独立处理 CSV 并完成数据分析',
              counterText: '',
            ),
          ),
          const SizedBox(height: PlannerSpace.md),
          DropdownButtonFormField<GoalType>(
            initialValue: goalTypeValue,
            decoration: const InputDecoration(labelText: '目标类型'),
            items: [
              for (final entry in goalTypeLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) =>
                setState(() => _goalType = value ?? GoalType.other),
          ),
          const SizedBox(height: PlannerSpace.md),
          TextField(
            controller: _goalSubtype,
            decoration: const InputDecoration(
              labelText: '具体考试或学习领域（可选）',
              helperText: '例如：考研、雅思、线性代数、Python',
            ),
          ),
          const _FormSectionDivider(label: '日期与周期'),
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
              const SizedBox(width: PlannerSpace.sm),
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
              title: const Text(
                '这个日期已经确认',
                style: TextStyle(fontSize: 13.5, height: 1.5),
              ),
              subtitle: const Text(
                '未确认时按“预计目标日期”展示，以正式通知为准。',
                style: _helperStyle,
              ),
              onChanged: (value) =>
                  setState(() => _targetConfirmed = value ?? false),
            ),
          const SizedBox(height: PlannerSpace.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final start = DateField(
                label: '规划开始日期',
                value: _planStart.text,
                onChanged: (value) => setState(() => _planStart.text = value),
              );
              final end = DateField(
                label: '规划结束日期',
                value: _planEnd.text,
                onChanged: (value) => setState(() => _planEnd.text = value),
              );
              // 320 宽时并排会把日期文本挤成两行，改为纵向堆叠。
              if (constraints.maxWidth < 400) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    start,
                    const SizedBox(height: PlannerSpace.md),
                    end,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: start),
                  const SizedBox(width: PlannerSpace.md),
                  Expanded(child: end),
                ],
              );
            },
          ),
          const SizedBox(height: PlannerSpace.sm),
          const Text(
            '目标日期是希望达成结果的日期，可以不设置；规划结束日期是本次排程的边界。',
            style: _helperStyle,
          ),
          const _FormSectionDivider(label: '当前基础'),
          TextField(
            controller: _progress,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '当前基础与进度',
              hintText: '例如：学过矩阵，特征值和二次型还没开始',
            ),
          ),
          const SizedBox(height: PlannerSpace.md),
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
            const SizedBox(height: PlannerSpace.md),
            TextField(
              controller: _school,
              decoration: const InputDecoration(labelText: '院校或机构（可选）'),
            ),
            const SizedBox(height: PlannerSpace.md),
            TextField(
              controller: _program,
              decoration: const InputDecoration(labelText: '专业或方向（可选）'),
            ),
          ],
          const SizedBox(height: PlannerSpace.xl),
          Align(
            alignment: Alignment.centerRight,
            child: AsyncActionButton(
              label: '保存学习目标与规划',
              icon: Icons.save_outlined,
              onPressed: _saveProfile,
              onError: (error) => setState(
                () => _profileError = error is StateError
                    ? error.message
                    : '$error',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ 每日可用时间与边界

  Widget _boundaryPanel(PlannerData data) {
    final net = data.profile.capacityBasis == CapacityBasis.net;
    final assumptions = capacity.capacityAssumptionLabel(data.profile);
    // 防御：任何入口进来的粒度都要先落到合法选项上，Dropdown 的 value 才安全。
    final granularity = _granularityOptions.contains(_granularity)
        ? _granularity
        : _granularityOptions.first;
    return PlannerPanel(
      title: '每日可用时间与排程边界',
      subtitle: net
          ? '一周七天的净学习时间：输入的就是真正能用于学习的净预算，程序不再机械扣除机动。某天为 0 时该天不生成学习安排。'
          : '一周七天的可用学习时间；某天为 0 时该天不生成学习安排。旧计划沿用总预算口径。',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: PlannerSpace.md,
            runSpacing: PlannerSpace.md,
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
          const _FormSectionDivider(label: '排程粒度与时间窗口'),
          DropdownButtonFormField<int>(
            initialValue: granularity,
            decoration: const InputDecoration(labelText: '时间粒度（分钟）'),
            items: [
              for (final option in _granularityOptions)
                DropdownMenuItem(value: option, child: Text('$option')),
            ],
            onChanged: (value) => setState(() {
              _granularity = value ?? _granularityOptions.first;
              // 用户显式选择后，归一提示不再适用。
              _unsupportedGranularity = null;
            }),
          ),
          if (_unsupportedGranularity != null)
            Padding(
              padding: const EdgeInsets.only(top: PlannerSpace.sm),
              child: Text(
                '当前计划使用 $_unsupportedGranularity 分钟时间粒度，不在可选范围（30 / 60）内；'
                '已归一到最近的 $granularity 分钟显示，保存后按新粒度排程。',
                style: _helperStyle.copyWith(color: PlannerColors.orange),
              ),
            ),
          if (!net) ...[
            const SizedBox(height: PlannerSpace.md),
            _NumberField(
              controller: _buffer,
              label: '每日机动时间（分钟）',
              helper: '30 至 180，排程至少保留 30 分钟',
            ),
          ],
          const SizedBox(height: PlannerSpace.md),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: _startMinute,
                  label: '学习开始（分钟）',
                  helper: '480 = 08:00',
                ),
              ),
              const SizedBox(width: PlannerSpace.md),
              Expanded(
                child: _NumberField(
                  controller: _endMinute,
                  label: '学习结束（分钟）',
                  helper: '1320 = 22:00',
                ),
              ),
            ],
          ),
          const SizedBox(height: PlannerSpace.sm),
          const Text(
            '每天只安排事项和时长，不指定学习开始时间。可用学习时间按每周模板与日期覆盖计算。',
            style: _helperStyle,
          ),
          const Divider(height: PlannerSpace.xl),
          Row(
            children: [
              Expanded(
                child: Text(
                  '容量假设与例外',
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: PlannerSpace.xs),
          if (assumptions.isNotEmpty)
            Text(
              assumptions,
              key: const ValueKey('settings-capacity-assumptions'),
              style: _helperStyle,
            )
          else
            const Text(
              '当前按默认每周模板逐日计算容量。',
              key: ValueKey('settings-capacity-assumptions'),
              style: _helperStyle,
            ),
          const SizedBox(height: PlannerSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('settings-capacity-editor'),
              onPressed: () => CapacityOverridesDialog.show(context),
              icon: const Icon(Icons.tune_outlined, size: 16),
              label: const Text('管理特定周与日期容量'),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ 数据管理

  Widget _dataPanel(PlannerSnapshot snapshot) => PlannerPanel(
    title: '数据管理',
    subtitle: 'JSON 包含标签、事项、每日安排、学习记录和重排快照。恢复后先保存在本机，再检查云端版本并同步。',
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingRow(
          title: '导出本地数据',
          description: '把本机计划保存为 JSON 文件，用于备份或迁移。',
          trailing: AsyncActionButton(
            label: '导出本地数据',
            icon: Icons.download_outlined,
            filled: false,
            enabled: snapshot.data != null,
            onPressed: () => _action(
              '已导出本地数据。',
              () => ref.read(plannerSessionProvider).exportJson(),
            ),
          ),
        ),
        const _PanelDivider(),
        _SettingRow(
          title: '从 JSON 恢复',
          description: '用备份文件替换本机计划，当前有效数据会另存为最近备份。',
          trailing: AsyncActionButton(
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
        ),
        const _PanelDivider(),
        _SettingRow(
          title: '恢复最近备份',
          description: '回退到上一次自动备份的本机计划，当前记录会另存保留。',
          trailing: AsyncActionButton(
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
        ),
        if (snapshot.blocked) ...[
          const _PanelDivider(),
          _SettingRow(
            title: '重新读取数据',
            description: '本机数据读取失败，恢复后重新读取。',
            trailing: AsyncActionButton(
              label: '重新读取数据',
              icon: Icons.refresh,
              filled: false,
              onPressed: () => _action(
                '已重新读取本机数据。',
                () => ref.read(plannerSessionProvider).reload(),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  // ------------------------------------------------------------------ 服务器

  Widget _connectionPanel(PlannerSnapshot snapshot) {
    return PlannerPanel(
      title: '服务器连接',
      subtitle: '本机计划会与云端双向同步；冲突时保留本机修改并请你选择。',
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlannerStat(
            label: '同步状态',
            value: syncLabels[snapshot.status] ?? '等待同步',
            tone: syncTone(snapshot.status),
          ),
          PlannerStat(label: '云端版本', value: '${snapshot.revision}'),
          PlannerStat(label: '待同步修改', value: snapshot.pending ? '有' : '无'),
          if (snapshot.message.isNotEmpty) ...[
            const SizedBox(height: PlannerSpace.md),
            PlannerNotice(
              snapshot.message,
              tone: snapshot.status == SyncStatus.error
                  ? PlannerNoticeTone.error
                  : PlannerNoticeTone.info,
            ),
          ],
          if (snapshot.busy) ...[
            const SizedBox(height: PlannerSpace.md),
            const LinearProgressIndicator(semanticsLabel: '正在同步'),
          ],
          const SizedBox(height: PlannerSpace.md),
          Wrap(
            spacing: PlannerSpace.md,
            runSpacing: PlannerSpace.md,
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
            const _FormSectionDivider(label: '同步冲突'),
            const Text(
              '本机修改已保留。请选择同时修改内容的保留方式；其他独立修改会一并合并。',
              style: _helperStyle,
            ),
            for (final conflict in snapshot.conflicts)
              Padding(
                padding: const EdgeInsets.only(top: PlannerSpace.xs),
                child: Text('• $conflict', style: _helperStyle),
              ),
            const SizedBox(height: PlannerSpace.md),
            Wrap(
              spacing: PlannerSpace.md,
              runSpacing: PlannerSpace.md,
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

  // ------------------------------------------------------------ 计划不可用状态

  Widget _planUnavailablePanel(PlannerSnapshot snapshot) => PlannerPanel(
    title: '学习计划',
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!snapshot.ready) ...[
          const LinearProgressIndicator(semanticsLabel: '正在读取本机计划'),
          const SizedBox(height: PlannerSpace.md),
          const Text('正在读取本机计划…', style: _bodyStyle),
        ] else
          PlannerNotice(
            snapshot.message.isNotEmpty
                ? snapshot.message
                : snapshot.blocked
                ? '本地数据读取失败，已停止编辑和同步。请重新读取数据或从 JSON 备份恢复。'
                : '还没有读取到学习计划。可重试同步或从 JSON 备份恢复。',
            tone: snapshot.blocked || snapshot.status == SyncStatus.error
                ? PlannerNoticeTone.error
                : PlannerNoticeTone.info,
          ),
      ],
    ),
  );
}

/// 顶栏右上角的同步状态胶囊：小圆点 + 12.5 文本，替代整条状态横幅。
class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: PlannerColors.surface,
      border: Border.all(
        color: PlannerColors.border,
        width: plannerHairline(context),
      ),
      borderRadius: BorderRadius.circular(PlannerRadius.control),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(color: syncTone(status), size: 6),
        const SizedBox(width: 6),
        Text(
          syncLabels[status] ?? '等待同步',
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.2,
            color: PlannerColors.muted,
          ),
        ),
      ],
    ),
  );
}

/// 账号首字母圆形徽标，避免引入额外头像资源。
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PlannerColors.blueSoft,
        shape: BoxShape.circle,
        border: Border.all(
          color: PlannerColors.border,
          width: plannerHairline(context),
        ),
      ),
      child: Text(
        initial.toUpperCase(),
        style: const TextStyle(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: PlannerColors.blue,
        ),
      ),
    );
  }
}

/// 一行设置：左侧主标签 + 辅助说明，右侧控件；行高约 52。
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    this.description,
    required this.trailing,
  });

  final String title;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 52),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: _rowLabelStyle),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(description!, style: _helperStyle),
                ],
              ],
            ),
          ),
          const SizedBox(width: PlannerSpace.lg),
          trailing,
        ],
      ),
    ),
  );
}

/// 卡片内部发丝分隔线。
class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: plannerHairline(context),
    color: PlannerColors.border,
  );
}

/// 表单小节标题 + 右侧发丝延长线，用轻结构替代嵌套卡片。
class _FormSectionDivider extends StatelessWidget {
  const _FormSectionDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: PlannerSpace.xl,
      bottom: PlannerSpace.md,
    ),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: PlannerColors.subtle,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: PlannerSpace.md),
        const Expanded(child: _PanelDivider()),
      ],
    ),
  );
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
