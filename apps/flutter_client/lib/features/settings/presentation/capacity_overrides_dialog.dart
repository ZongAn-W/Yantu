import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/planner_session.dart';
import '../../planner/domain/capacity.dart' as capacity;
import '../../planner/domain/plan_cycle.dart';
import '../../planner/domain/planner_format.dart';
import '../../planner/presentation/planner_dialogs.dart' show DateField;

/// 容量假设与例外编辑器。
///
/// 支持：
/// - 大致周容量范围 + 经用户确认的保守基线；
/// - 特定自然周覆盖（只给周总量，或逐日覆盖）；
/// - 特定日期覆盖（0 = 休息；删除 = 恢复上层规则）；
/// - 显式展示每个值的来源（具体日期/本周逐日/周总量/基线/模板/估算）；
/// - 保存前用 `reschedulePlan` 生成影响预览：保留/移动/未安排/真实截止日期影响，
///   预览后计划或 revision 变化会失效并要求重新预览。
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
  bool _previewing = false;
  ScheduleAdjustment? _adjustment;
  PlannerData? _expected;
  String? _previewError;
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
    final weekly = {for (var day = 0; day < 7; day++) '$day': current.weekMinutes['$day'] ?? 0};
    var dailyLimit = current.dailyLimitMinutes;
    if (_basis == CapacityBasis.net) {
      final peak = weekly.values.fold<int>(0, (a, b) => a > b ? a : b);
      var distributedPeak = 0;
      if (_adoptedBaseline != null) {
        final distributed = capacity.distributeWeeklyTotal(
          _adoptedBaseline!,
          {for (var day = 0; day < 7; day++) day: weekly['$day'] ?? 0},
        );
        for (final value in distributed.values) {
          if (value > distributedPeak) distributedPeak = value;
        }
      }
      dailyLimit = [current.dailyLimitMinutes, peak, distributedPeak, 30]
          .reduce((a, b) => a > b ? a : b);
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
          (entry.value.totalMinutes! < 0 || entry.value.totalMinutes! > 10080)) {
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
      for (final conflict in capacity
          .resolveWeekCapacity(profile, monday)
          .conflicts) {
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

  Future<void> _preview() async {
    final data = ref.read(plannerDataProvider).data;
    if (data == null) return;
    final errors = _validationErrors;
    if (errors.isNotEmpty) {
      setState(() => _previewError = errors.first);
      return;
    }
    final nextProfile = _nextProfile(data.profile);
    final next = data.copyWith(profile: nextProfile);
    final conflicts = _conflicts(nextProfile);
    if (conflicts.isNotEmpty && !_acceptedConflicts) {
      setState(
        () => _previewError = '容量设置存在冲突，请先调整或勾选“接受该容量设置冲突”。',
      );
      return;
    }
    final today = shanghaiToday();
    setState(() {
      _previewError = null;
      _busy = true;
    });
    try {
      final adjustment = reschedulePlan(
        next,
        today: today,
        start: nextProfile.resolvedPlanStart(today),
        end: nextProfile.resolvedPlanEnd(today),
      );
      if (!mounted) return;
      setState(() {
        _adjustment = adjustment;
        _expected = data;
        _previewing = true;
      });
    } catch (error) {
      if (mounted) setState(() => _previewError = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final adjustment = _adjustment;
    final expected = _expected;
    if (adjustment == null || expected == null) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final before = jsonEncode(expected.toJson());
      await ref.read(plannerSessionProvider).edit((current) {
        if (jsonEncode(current.toJson()) != before) {
          throw StateError('计划已更新，请重新预览容量影响');
        }
        return adjustment.data;
      });
      if (navigator.mounted) navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '容量设置已保存：保留 ${adjustment.protectedBlocks} 段，'
            '重新排入 ${adjustment.placedBlocks} 段'
            '${adjustment.unscheduledMinutes > 0 ? '，仍有 ${duration(adjustment.unscheduledMinutes)} 未安排' : ''}。',
          ),
        ),
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
    return AlertDialog(
      title: Text(_previewing ? '容量变化影响预览' : '容量假设与例外'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: _previewing
              ? _buildPreview(context)
              : _buildEditor(context, data, nextProfile, conflicts, errors),
        ),
      ),
      actions: _previewing
          ? [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _previewing = false),
                child: const Text('返回修改'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _apply,
                icon: const Icon(Icons.check),
                label: const Text('确认应用'),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                onPressed: _busy || errors.isNotEmpty ? null : _preview,
                icon: const Icon(Icons.preview_outlined),
                label: const Text('预览容量影响'),
              ),
            ],
    );
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
        Text('容量口径', style: Theme.of(context).textTheme.titleSmall),
        SegmentedButton<CapacityBasis>(
          segments: const [
            ButtonSegment(
              value: CapacityBasis.net,
              label: Text('净学习时间（推荐）'),
            ),
            ButtonSegment(
              value: CapacityBasis.grossBuffer,
              label: Text('旧版总预算'),
            ),
          ],
          selected: {_basis},
          onSelectionChanged: (values) =>
              setState(() => _basis = values.single),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '净口径：你填写的就是真正用于学习的净时间，程序不再机械扣除机动。'
            '旧版总预算：每日安排前先扣除机动时间。切换口径会改变容量并显示影响预览。',
            style: TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
        ),
        const Divider(height: 24),
        Text('默认周容量', style: Theme.of(context).textTheme.titleSmall),
        Row(
          children: [
            Checkbox(
              value: _useRange,
              onChanged: (value) => setState(() => _useRange = value ?? false),
            ),
            const Expanded(child: Text('使用“大致周容量范围”+ 保守基线')),
          ],
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
              title: Text(
                '采用保守基线 ${duration(_adoptedBaseline!)} 作为初始排程依据',
              ),
              subtitle: const Text(
                '取范围下限，较高容量情景只用于说明可达范围；'
                '程序按模板比例生成的每日建议不代表逐日确认。',
              ),
            ),
        ] else
          Text(
            '未设置周基线：按现有每周模板 ${_templateSummary(data.profile)} 逐日计算。',
          ),
        if (info.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              info,
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '特定周覆盖（键为周一日期）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _addWeek,
              icon: const Icon(Icons.add),
              label: const Text('添加特定周'),
            ),
          ],
        ),
        if (_weeks.isEmpty)
          const Text(
            '暂无特定周覆盖：所有周使用默认周容量。',
            style: TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
        for (final entry in (_weeks.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))))
          _weekRow(entry.key, entry.value),
        const Divider(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                '特定日期覆盖（0 = 休息；删除 = 恢复上层规则）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _addDate,
              icon: const Icon(Icons.add),
              label: const Text('添加日期'),
            ),
          ],
        ),
        if (_dates.isEmpty)
          const Text(
            '暂无特定日期覆盖。',
            style: TextStyle(color: PlannerColors.muted, fontSize: 12),
          ),
        for (final entry in (_dates.entries.toList()
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
              style: const TextStyle(color: PlannerColors.orange, fontSize: 12),
            ),
          ),
        if (_previewError != null) ...[
          const SizedBox(height: 8),
          PlannerNotice(_previewError!, tone: PlannerNoticeTone.error),
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
            onPressed: _busy ? null : () => setState(() => _weeks.remove(monday)),
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
        .map((entry) => '${entry.value} ${duration(profile.weekMinutes[entry.key] ?? 0)}')
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
    final days = Map<String, int>.from(
      _weeks[mondayKey]?.days ?? const {},
    );
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
          title: const Text('特定周容量'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('周键使用周一日期（上海时区），周一到周日为一周。'),
                  const SizedBox(height: 8),
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
                    style: const TextStyle(
                      color: PlannerColors.muted,
                      fontSize: 12,
                    ),
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
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
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
                      SnackBar(content: Text('${entry.key} 的容量需要是 0 至 1440')),
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
          title: const Text('特定日期容量'),
          content: SizedBox(
            width: 420,
            child: Column(
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
                const SizedBox(height: 8),
                const Text(
                  '清空或删除该日期覆盖会恢复上层规则（本周/默认），不等于设为 0。',
                  style: TextStyle(color: PlannerColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
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
          title: const Text('编辑日期容量'),
          content: SizedBox(
            width: 420,
            child: Column(
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
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
    );
    final value = int.tryParse(minutes.text.trim());
    if (saved != true || value == null || !mounted) return;
    setState(() {
      if (date != existing) _dates.remove(existing);
      _dates[date] = value;
    });
  }

  Widget _buildPreview(BuildContext context) {
    final adjustment = _adjustment!;
    final changed = adjustment.changedDays;
    final shown = changed.length > 14 ? changed.sublist(0, 14) : changed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('确认后会按新容量重新安排可调整的未来安排；历史、固定、已完成和有实际用时的记录保持不变。'),
        const SizedBox(height: 12),
        PlannerStat(
          label: '保持不变（历史/固定/已完成/已有记录）',
          value: '${adjustment.protectedBlocks} 段',
        ),
        PlannerStat(
          label: '移动/释放的未来安排',
          value:
              '${adjustment.releasedBlocks} 段 · ${duration(adjustment.releasedMinutes)}',
        ),
        PlannerStat(
          label: '重新排入',
          value:
              '${adjustment.placedBlocks} 段 · ${duration(adjustment.placedMinutes)}',
        ),
        PlannerStat(
          label: '仍未安排',
          value: duration(adjustment.unscheduledMinutes),
          tone: adjustment.unscheduledMinutes > 0 ? PlannerColors.orange : null,
        ),
        if (adjustment.realDeadlineImpacts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('真实截止日期影响', style: Theme.of(context).textTheme.titleSmall),
          for (final impact in adjustment.realDeadlineImpacts)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: PlannerNotice(impact, tone: PlannerNoticeTone.warning),
            ),
        ],
        if (shown.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('每日计划时长', style: Theme.of(context).textTheme.titleSmall),
          for (final date in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${monthDayLabel(date)} ${weekdayLabel(date)}'),
                  ),
                  Text(
                    '${duration(adjustment.beforeLoad[date] ?? 0)} → '
                    '${duration(adjustment.afterLoad[date] ?? 0)}',
                    style: tabularFigures,
                  ),
                ],
              ),
            ),
          if (changed.length > shown.length)
            Text(
              '另有 ${changed.length - shown.length} 天发生变化。',
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
        ],
        if (adjustment.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final note in adjustment.notes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
              ),
            ),
        ],
      ],
    );
  }
}
