import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/capacity.dart' as capacity;
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/planner_dialogs.dart' show DateField;

/// 容量假设与例外编辑器。
///
/// 支持：
/// - 大致周容量范围 + 经用户确认的保守基线；
/// - 特定自然周覆盖（只给周总量，或逐日覆盖）；
/// - 特定日期覆盖（0 = 休息；删除 = 恢复上层规则）；
/// - 显式展示每个值的来源（具体日期/本周逐日/周总量/基线/模板/估算）。
///
/// 保存只写入容量设置，不自动重排未来安排：需要按新容量重排时，由用户在
/// 调整页发起 AI「一键调整后续计划」。
class CapacityOverridesDialog extends ConsumerStatefulWidget {
  const CapacityOverridesDialog({super.key});

  static Future<bool> show(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => const CapacityOverridesDialog(),
      ) ==
      true;

  @override
  ConsumerState<CapacityOverridesDialog> createState() =>
      _CapacityOverridesDialogState();
}

class _CapacityOverridesDialogState
    extends ConsumerState<CapacityOverridesDialog> {
  final _rangeMin = TextEditingController();
  final _rangeMax = TextEditingController();
  CapacityBasis _basis = CapacityBasis.grossBuffer;
  bool _useRange = false;
  bool _baselineConfirmed = false;
  bool _acceptedConflicts = false;
  final _weeks = <String, WeekCapacityOverride>{};
  final _dates = <String, int>{};
  String? _saveError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(plannerDataProvider).data?.profile;
    if (profile == null) return;
    _basis = profile.capacityBasis;
    _useRange =
        profile.weeklyRangeMinMinutes != null ||
        profile.weeklyRangeMaxMinutes != null;
    _rangeMin.text = '${profile.weeklyRangeMinMinutes ?? ''}';
    _rangeMax.text = '${profile.weeklyRangeMaxMinutes ?? ''}';
    _baselineConfirmed = profile.weeklyBaselineMinutes != null;
    _weeks.addAll(profile.weekCapacityOverrides ?? const {});
    _dates.addAll(profile.dateCapacityOverrides ?? const {});
  }

  @override
  void dispose() {
    _rangeMin.dispose();
    _rangeMax.dispose();
    super.dispose();
  }

  int? get _rangeMinValue => int.tryParse(_rangeMin.text.trim());
  int? get _rangeMaxValue => int.tryParse(_rangeMax.text.trim());

  /// 采用值 = 范围下限（保守值）；模板模式下没有周总量基线。
  int? get _adoptedBaseline {
    if (!_useRange) return null;
    final min = _rangeMinValue;
    if (min == null || min <= 0) return null;
    return min;
  }

  Profile _nextProfile(Profile current) {
    final weekly = {
      for (var day = 0; day < 7; day++)
        '$day': current.weekMinutes['$day'] ?? 0,
    };
    var dailyLimit = current.dailyLimitMinutes;
    if (_basis == CapacityBasis.net) {
      final peak = weekly.values.fold<int>(0, (a, b) => a > b ? a : b);
      var distributedPeak = 0;
      if (_adoptedBaseline != null) {
        final distributed = capacity.distributeWeeklyTotal(_adoptedBaseline!, {
          for (var day = 0; day < 7; day++) day: weekly['$day'] ?? 0,
        });
        for (final value in distributed.values) {
          if (value > distributedPeak) distributedPeak = value;
        }
      }
      dailyLimit = [
        current.dailyLimitMinutes,
        peak,
        distributedPeak,
        30,
      ].reduce((a, b) => a > b ? a : b);
    }
    return current.copyWith(
      capacityBasis: _basis,
      weeklyBaselineMinutes: _adoptedBaseline,
      weeklyRangeMinMinutes: _useRange ? _rangeMinValue : null,
      weeklyRangeMaxMinutes: _useRange ? _rangeMaxValue : null,
      weekCapacityOverrides: _weeks.isEmpty ? null : Map.of(_weeks),
      dateCapacityOverrides: _dates.isEmpty ? null : Map.of(_dates),
      dailyLimitMinutes: dailyLimit,
    );
  }

  List<String> get _validationErrors {
    final errors = <String>[];
    if (_useRange) {
      final min = _rangeMinValue;
      final max = _rangeMaxValue;
      if (min == null || min < 0 || min > 10080) {
        errors.add('周容量范围下限需要是 0 至 10080 分钟');
      }
      if (max == null || max < 0 || max > 10080) {
        errors.add('周容量范围上限需要是 0 至 10080 分钟');
      }
      if (min != null && max != null && min > max) {
        errors.add('周容量范围下限不能大于上限');
      }
      if (_adoptedBaseline != null && !_baselineConfirmed) {
        errors.add('请确认采用的保守周容量基线');
      }
    }
    for (final entry in _weeks.entries) {
      if (entry.value.totalMinutes != null &&
          (entry.value.totalMinutes! < 0 ||
              entry.value.totalMinutes! > 10080)) {
        errors.add('特定周（${entry.key}）的总量需要在 0 至 10080 分钟之间');
      }
      for (final day in (entry.value.days ?? const {}).entries) {
        if (day.value < 0 || day.value > 1440) {
          errors.add('特定周（${entry.key}）的日容量需要在 0 至 1440 分钟之间');
        }
      }
    }
    for (final entry in _dates.entries) {
      if (entry.value < 0 || entry.value > 1440) {
        errors.add('特定日期（${entry.key}）的容量需要在 0 至 1440 分钟之间');
      }
    }
    return errors;
  }

  /// 当前设置会产生的周冲突（显式提示，不静默选择一边）。
  List<String> _conflicts(Profile profile) {
    final result = <String>[];
    final mondays = <String>{..._weeks.keys};
    for (final date in _dates.keys) {
      mondays.add(capacity.capacityWeekMonday(date));
    }
    for (final monday in mondays.toList()..sort()) {
      for (final conflict
          in capacity.resolveWeekCapacity(profile, monday).conflicts) {
        result.add(
          conflict.code == capacity.CapacityConflictCode.weekTotalExceeded
              ? '包含 $monday 的一周：日期/逐日覆盖合计 '
                    '${capacity.durationText(conflict.resolved)}，超过周总量 '
                    '${capacity.durationText(conflict.total)}'
              : '包含 $monday 的一周：周总量 '
                    '${capacity.durationText(conflict.total)} 无法分配到非休息日'
                    '（仅能安排 ${capacity.durationText(conflict.resolved)}）',
        );
      }
    }
    return result;
  }

  Future<void> _save() async {
    final data = ref.read(plannerDataProvider).data;
    if (data == null) return;
    final errors = _validationErrors;
    if (errors.isNotEmpty) {
      setState(() => _saveError = errors.first);
      return;
    }
    final nextProfile = _nextProfile(data.profile);
    final conflicts = _conflicts(nextProfile);
    if (conflicts.isNotEmpty && !_acceptedConflicts) {
      setState(() => _saveError = '容量设置存在冲突，请先调整或勾选“接受该容量设置冲突”。');
      return;
    }
    setState(() {
      _saveError = null;
      _busy = true;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 只写入容量设置；不用本地重排算法自动改未来安排，重排交给调整页的 AI。
      await ref
          .read(plannerSessionProvider)
          .edit(
            (current) =>
                current.copyWith(profile: _nextProfile(current.profile)),
          );
      if (navigator.mounted) navigator.pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('容量已保存；请到调整页使用一键调整后续计划重排未来安排。')),
      );
    } catch (error) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(plannerDataProvider).data;
    if (data == null) return const SizedBox.shrink();
    final nextProfile = _nextProfile(data.profile);
    final conflicts = _conflicts(nextProfile);
    final errors = _validationErrors;
    final width = _dialogWidth(context, 640);
    return AlertDialog(
      contentPadding: EdgeInsets.zero,
      content: _DialogFrame(
        width: width,
        title: '容量假设与例外',
        subtitle: '保存只写入容量设置；需要重排未来安排时，到调整页使用一键调整。',
        body: _buildEditor(context, data, nextProfile, conflicts, errors),
        actions: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            const SizedBox(width: PlannerSpace.sm),
            FilledButton.icon(
              key: const ValueKey('capacity-save'),
              onPressed: _busy || errors.isNotEmpty ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 17),
              label: const Text('保存容量'),
            ),
          ],
        ),
      ),
    );
  }

  /// 对话框宽度：桌面固定，窄屏时给两侧留 32 的呼吸空间。
  static double _dialogWidth(BuildContext context, double preferred) {
    final available = MediaQuery.sizeOf(context).width - 64;
    return available < preferred ? available : preferred;
  }

  Widget _buildEditor(
    BuildContext context,
    PlannerData data,
    Profile nextProfile,
    List<String> conflicts,
    List<String> errors,
  ) {
    final info = capacity.capacityAssumptionLabel(nextProfile);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('容量口径'),
        const SizedBox(height: PlannerSpace.sm),
        PlannerSegmented<CapacityBasis>(
          value: _basis,
          items: const [
            (CapacityBasis.net, '净学习时间（推荐）'),
            (CapacityBasis.grossBuffer, '旧版总预算'),
          ],
          onChanged: (value) => setState(() => _basis = value),
        ),
        Padding(
          padding: const EdgeInsets.only(top: PlannerSpace.sm),
          child: Text(
            '净口径：你填写的就是真正用于学习的净时间，程序不再机械扣除机动。'
            '旧版总预算：每日安排前先扣除机动时间。切换口径会改变容量；'
            '保存后如需重排未来安排，请到调整页使用一键调整后续计划。',
            style: _dialogBodyStyle(context),
          ),
        ),
        const Divider(height: PlannerSpace.xl),
        const _SectionLabel('默认周容量'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _useRange,
          onChanged: (value) => setState(() => _useRange = value ?? false),
          title: const Text('使用“大致周容量范围”+ 保守基线'),
        ),
        if (_useRange) ...[
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('capacity-range-min'),
                  controller: _rangeMin,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '每周最少能学',
                    suffixText: '分钟',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('capacity-range-max'),
                  controller: _rangeMax,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '每周最多能学',
                    suffixText: '分钟',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (_adoptedBaseline != null)
            CheckboxListTile(
              key: const ValueKey('capacity-baseline-confirm'),
              value: _baselineConfirmed,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) =>
                  setState(() => _baselineConfirmed = value ?? false),
              title: Text('采用保守基线 ${duration(_adoptedBaseline!)} 作为初始排程依据'),
              subtitle: const Text(
                '取范围下限，较高容量情景只用于说明可达范围；'
                '程序按模板比例生成的每日建议不代表逐日确认。',
              ),
            ),
        ] else
          Text(
            '未设置周基线：按现有每周模板 ${_templateSummary(data.profile)} 逐日计算。',
            style: _dialogBodyStyle(context),
          ),
        if (info.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(info, style: _dialogHelperStyle(context)),
          ),
        const Divider(height: PlannerSpace.xl),
        Row(
          children: [
            const Expanded(child: _SectionLabel('特定周覆盖（键为周一日期）')),
            TextButton.icon(
              onPressed: _busy ? null : _addWeek,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加特定周'),
            ),
          ],
        ),
        if (_weeks.isEmpty)
          Text('暂无特定周覆盖：所有周使用默认周容量。', style: _dialogHelperStyle(context)),
        for (final entry
            in (_weeks.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          _weekRow(entry.key, entry.value),
        const Divider(height: PlannerSpace.xl),
        Row(
          children: [
            const Expanded(child: _SectionLabel('特定日期覆盖（0 = 休息；删除 = 恢复上层规则）')),
            TextButton.icon(
              onPressed: _busy ? null : _addDate,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加日期'),
            ),
          ],
        ),
        if (_dates.isEmpty)
          Text('暂无特定日期覆盖。', style: _dialogHelperStyle(context)),
        for (final entry
            in (_dates.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('${entry.key} ${weekdayLabel(entry.key)}'),
            subtitle: Text(
              entry.value == 0
                  ? '休息日（0 分钟，不回退默认容量）'
                  : '净容量 ${duration(entry.value)} · 来源：具体日期覆盖',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '编辑',
                  onPressed: _busy ? null : () => _editDate(entry.key),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除覆盖（恢复上层规则）',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _dates.remove(entry.key)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        if (conflicts.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final conflict in conflicts)
            PlannerNotice(conflict, tone: PlannerNoticeTone.warning),
          CheckboxListTile(
            key: const ValueKey('capacity-accept-conflicts'),
            value: _acceptedConflicts,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (value) =>
                setState(() => _acceptedConflicts = value ?? false),
            title: const Text('我已了解并接受该容量设置冲突'),
          ),
        ],
        for (final error in errors)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error,
              style: _dialogHelperStyle(
                context,
              ).copyWith(color: context.tokens.warning),
            ),
          ),
        if (_saveError != null) ...[
          const SizedBox(height: 8),
          PlannerNotice(_saveError!, tone: PlannerNoticeTone.error),
        ],
      ],
    );
  }

  Widget _weekRow(String monday, WeekCapacityOverride override) {
    final days = override.days ?? const <String, int>{};
    final names = {
      '1': '一',
      '2': '二',
      '3': '三',
      '4': '四',
      '5': '五',
      '6': '六',
      '0': '日',
    };
    final summary = <String>[
      if (override.totalMinutes != null)
        '周总量 ${duration(override.totalMinutes!)}',
      if (days.isNotEmpty)
        '逐日：${days.entries.map((entry) => '周${names[entry.key]} ${duration(entry.value)}').join('、')}',
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('$monday 起的一周 ${weekdayLabel(monday)}'),
      subtitle: Text(
        summary.isEmpty
            ? '未设置具体容量'
            : '$summary · 来源：${override.totalMinutes != null ? '本周总量（逐日分配为程序建议）' : '本周逐日覆盖'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '编辑',
            onPressed: _busy ? null : () => _editWeek(monday),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除覆盖（恢复默认周容量）',
            onPressed: _busy
                ? null
                : () => setState(() => _weeks.remove(monday)),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  String _templateSummary(Profile profile) {
    final names = {
      '1': '周一',
      '2': '周二',
      '3': '周三',
      '4': '周四',
      '5': '周五',
      '6': '周六',
      '0': '周日',
    };
    return names.entries
        .map(
          (entry) =>
              '${entry.value} ${duration(profile.weekMinutes[entry.key] ?? 0)}',
        )
        .join('，');
  }

  Future<void> _addWeek() => _editWeek(_defaultMonday());

  String _defaultMonday() {
    final today = shanghaiToday();
    return capacity.capacityWeekMonday(today);
  }

  Future<void> _editWeek(String mondayKey) async {
    var date = mondayKey;
    final initialTotal = _weeks[mondayKey]?.totalMinutes;
    final days = Map<String, int>.from(_weeks[mondayKey]?.days ?? const {});
    final totalController = TextEditingController(
      text: initialTotal?.toString() ?? '',
    );
    final controllers = {
      for (final key in ['1', '2', '3', '4', '5', '6', '0'])
        key: TextEditingController(
          text: days.containsKey(key) ? '${days[key]}' : '',
        ),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: _DialogFrame(
            width: _dialogWidth(context, 520),
            title: '特定周容量',
            subtitle: '周键使用周一日期（上海时区），周一到周日为一周。',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateField(
                  label: '该周周一',
                  value: date,
                  onChanged: (value) => setInner(() => date = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('capacity-week-total'),
                  controller: totalController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '整周总量（可只填它，留空表示不设总量）',
                    suffixText: '分钟',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '也可以逐日给出明确值（留空表示该天跟随模板）；'
                  '同时设置周总量时，会先扣除逐日明确值再按模板比例分配剩余。',
                  style: _dialogHelperStyle(context),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in {
                      '1': '周一',
                      '2': '周二',
                      '3': '周三',
                      '4': '周四',
                      '5': '周五',
                      '6': '周六',
                      '0': '周日',
                    }.entries)
                      SizedBox(
                        width: 150,
                        child: TextField(
                          key: ValueKey('capacity-week-day-${entry.key}'),
                          controller: controllers[entry.key],
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: entry.value,
                            suffixText: '分钟',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            actions: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: PlannerSpace.sm),
                FilledButton(
                  key: const ValueKey('capacity-week-save'),
                  onPressed: () {
                    final parsed = DateTime.tryParse('${date}T00:00:00Z');
                    if (parsed == null || parsed.weekday != DateTime.monday) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('请把周键设置为周一日期')),
                      );
                      return;
                    }
                    final explicitDays = <String, int>{};
                    for (final entry in controllers.entries) {
                      final text = entry.value.text.trim();
                      if (text.isEmpty) continue;
                      final value = int.tryParse(text);
                      if (value == null || value < 0 || value > 1440) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${entry.key} 的容量需要是 0 至 1440'),
                          ),
                        );
                        return;
                      }
                      explicitDays[entry.key] = value;
                    }
                    final totalText = totalController.text.trim();
                    final totalValue = totalText.isEmpty
                        ? null
                        : int.tryParse(totalText);
                    if (totalValue != null &&
                        (totalValue < 0 || totalValue > 10080)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('周总量需要是 0 至 10080 分钟')),
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('保存该周'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) {
      return;
    }
    final explicitDays = <String, int>{};
    for (final entry in controllers.entries) {
      final text = entry.value.text.trim();
      if (text.isEmpty) continue;
      explicitDays[entry.key] = int.parse(text);
    }
    final totalText = totalController.text.trim();
    final total = totalText.isEmpty ? null : int.parse(totalText);
    final parsed = DateTime.parse('${date}T00:00:00Z');
    final weekKey = capacity.capacityWeekMonday(date);
    if (parsed.weekday != DateTime.monday) return;
    setState(() {
      if (total == null && explicitDays.isEmpty) {
        _weeks.remove(weekKey);
      } else {
        _weeks[weekKey] = WeekCapacityOverride(
          totalMinutes: total,
          days: explicitDays.isEmpty ? null : explicitDays,
        );
      }
    });
  }

  Future<void> _addDate() async {
    final minutes = TextEditingController();
    var date = shanghaiToday();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: _DialogFrame(
            width: _dialogWidth(context, 420),
            title: '特定日期容量',
            subtitle: '当天净容量（分钟）；0 表示当天休息。',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateField(
                  label: '日期',
                  value: date,
                  onChanged: (value) => setInner(() => date = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '当天净容量',
                    suffixText: '分钟（0 表示休息）',
                  ),
                ),
                const SizedBox(height: PlannerSpace.md),
                Text(
                  '清空或删除该日期覆盖会恢复上层规则（本周/默认），不等于设为 0。',
                  style: _dialogHelperStyle(context),
                ),
              ],
            ),
            actions: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: PlannerSpace.sm),
                FilledButton(
                  onPressed: () {
                    final value = int.tryParse(minutes.text.trim());
                    if (value == null || value < 0 || value > 1440) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('容量需要是 0 至 1440 分钟')),
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final value = int.tryParse(minutes.text.trim());
    if (saved != true || value == null || !mounted) return;
    setState(() => _dates[date] = value);
  }

  Future<void> _editDate(String existing) async {
    final minutes = TextEditingController(text: '${_dates[existing]}');
    var date = existing;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: _DialogFrame(
            width: _dialogWidth(context, 420),
            title: '编辑日期容量',
            subtitle: '当天净容量（分钟）；0 表示当天休息。',
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DateField(
                  label: '日期',
                  value: date,
                  onChanged: (value) => setInner(() => date = value),
                ),
                const SizedBox(height: PlannerSpace.md),
                TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '当天净容量',
                    suffixText: '分钟（0 表示休息）',
                  ),
                ),
              ],
            ),
            actions: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: PlannerSpace.sm),
                FilledButton(
                  onPressed: () {
                    final value = int.tryParse(minutes.text.trim());
                    if (value == null || value < 0 || value > 1440) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('容量需要是 0 至 1440 分钟')),
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final value = int.tryParse(minutes.text.trim());
    if (saved != true || value == null || !mounted) return;
    setState(() {
      if (date != existing) _dates.remove(existing);
      _dates[date] = value;
    });
  }
}

/// 对话框正文：13 / 1.6。
TextStyle _dialogBodyStyle(BuildContext context) =>
    TextStyle(fontSize: 13, height: 1.6, color: context.tokens.muted);

/// 对话框辅助说明 / 元信息：12.5 / 1.5。
TextStyle _dialogHelperStyle(BuildContext context) =>
    TextStyle(fontSize: 12.5, height: 1.5, color: context.tokens.muted);

/// 对话框小节标题：13.5 w600。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(
      fontSize: 13.5,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: context.tokens.text,
    ),
  );
}

/// 统一对话框外壳：20–24 内边距、表头 / 表尾发丝分隔线、按钮右对齐、内容独立滚动。
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.width,
    required this.title,
    required this.body,
    required this.actions,
    this.subtitle,
  });

  final double width;
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hairline = plannerHairline(context);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlannerSpace.xl,
              20,
              PlannerSpace.xl,
              14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: _dialogHelperStyle(context)),
                ],
              ],
            ),
          ),
          Container(height: hairline, color: context.tokens.border),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                PlannerSpace.xl,
                18,
                PlannerSpace.xl,
                18,
              ),
              child: body,
            ),
          ),
          Container(height: hairline, color: context.tokens.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlannerSpace.xl,
              14,
              PlannerSpace.xl,
              16,
            ),
            child: actions,
          ),
        ],
      ),
    );
  }
}
