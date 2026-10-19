import 'dart:math' as math;

import '../../../shared/models/planner_models.dart';

/// 容量数值的来源，用于界面展示“这个数字是怎么来的”。
///
/// 与 TypeScript 排程核心保持一致（JSON snake_case）：
/// `date_override` > `week_day_override` > `week_total` > `baseline` >
/// `template` > `legacy_default`。
enum CapacitySource {
  dateOverride,
  weekDayOverride,
  weekTotal,
  template,
  baseline,
  legacyDefault,
}

String capacitySourceName(CapacitySource source) => switch (source) {
  CapacitySource.dateOverride => 'date_override',
  CapacitySource.weekDayOverride => 'week_day_override',
  CapacitySource.weekTotal => 'week_total',
  CapacitySource.template => 'template',
  CapacitySource.baseline => 'baseline',
  CapacitySource.legacyDefault => 'legacy_default',
};

String capacitySourceLabel(CapacitySource source) => switch (source) {
  CapacitySource.dateOverride => '具体日期设置',
  CapacitySource.weekDayOverride => '本周具体安排',
  CapacitySource.weekTotal => '本周总量建议',
  CapacitySource.baseline => '默认周容量基线',
  CapacitySource.template => '默认每周模板',
  CapacitySource.legacyDefault => '旧版每日上限',
};

/// 容量冲突：必须显式提示用户，不能静默选择一边。
enum CapacityConflictCode { weekTotalExceeded, weekTotalUnallocated }

String capacityConflictCodeName(CapacityConflictCode code) => switch (code) {
  CapacityConflictCode.weekTotalExceeded => 'WEEK_TOTAL_EXCEEDED',
  CapacityConflictCode.weekTotalUnallocated => 'WEEK_TOTAL_UNALLOCATED',
};

class CapacityConflict {
  const CapacityConflict({
    required this.code,
    this.date,
    required this.total,
    required this.resolved,
  });

  final CapacityConflictCode code;

  /// 冲突指向的具体日期（如某天的覆盖值之和超过周总量）。
  final String? date;

  /// 用户设定的周总量。
  final int total;

  /// 按当前规则实际能解析出的总量。
  final int resolved;
}

/// 某一自然日解析后的容量。
///
/// [minutes] 已应用净/总口径（gross_buffer 扣机动、net 不扣），但未扣已占用分钟；
/// 调用方只扣一次。
class DayCapacity {
  const DayCapacity({
    required this.date,
    required this.monday,
    required this.minutes,
    required this.rawMinutes,
    required this.source,
    required this.estimated,
    required this.weekBudgetMinutes,
  });

  /// 该自然日日期（YYYY-MM-DD）。
  final String date;

  /// 该自然日所属自然周的周一日期（上海时区周一到周日）。
  final String monday;

  /// 应用口径后的净学习预算分钟（未扣已占用）。
  final int minutes;

  /// 应用口径前的分钟数（模板/覆盖原始值）。
  final int rawMinutes;

  final CapacitySource source;

  /// 该值是程序按周总量/模板生成的建议，而不是用户逐日确认的值。
  final bool estimated;

  /// 该周已确认的总预算（周覆盖总量或采用基线），否则为 null。
  final int? weekBudgetMinutes;

  JsonMap toJson() => {
    'date': date,
    'monday': monday,
    'minutes': minutes,
    'raw_minutes': rawMinutes,
    'source': capacitySourceName(source),
    'estimated': estimated,
    'week_budget_minutes': weekBudgetMinutes,
  };
}

/// 一个自然周（周一至周日）的容量解析结果。
class WeekCapacity {
  const WeekCapacity({
    required this.monday,
    required this.days,
    required this.sources,
    required this.estimated,
    required this.budgetOverrideMinutes,
    required this.conflicts,
  });

  /// 周一日期的自然周键。
  final String monday;

  /// 七个日期（周一到周日）到应用口径后分钟数的映射。
  final Map<String, int> days;

  /// 七个日期到容量来源的映射。
  final Map<String, CapacitySource> sources;

  /// 七个日期到“是否为程序建议值”的映射。
  final Map<String, bool> estimated;

  /// 该周已确认的总预算（周覆盖总量或采用基线）；仅逐日覆盖时为 null。
  final int? budgetOverrideMinutes;

  final List<CapacityConflict> conflicts;

  JsonMap toJson() => {
    'monday': monday,
    'days': days,
    'sources': {
      for (final entry in sources.entries)
        entry.key: capacitySourceName(entry.value),
    },
    'estimated': estimated,
    'budget_override_minutes': budgetOverrideMinutes,
    'conflicts': [
      for (final conflict in conflicts)
        {
          'code': capacityConflictCodeName(conflict.code),
          if (conflict.date != null) 'date': conflict.date,
          'total': conflict.total,
          'resolved': conflict.resolved,
        },
    ],
  };
}

int _finite(int value) => value < 0 ? 0 : value;

String _dateOnly(DateTime value) =>
    '${value.toUtc().year.toString().padLeft(4, '0')}-'
    '${value.toUtc().month.toString().padLeft(2, '0')}-'
    '${value.toUtc().day.toString().padLeft(2, '0')}';

DateTime? _parseDate(String date) {
  if (!RegExp(
    r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$',
  ).hasMatch(date)) {
    return null;
  }
  return DateTime.tryParse('${date}T00:00:00Z');
}

/// 周几索引，与 TS `getUTCDay` 一致：0 为周日，6 为周六。
int capacityWeekdayIndex(String date) {
  final parsed = _parseDate(date);
  if (parsed == null) return 0;
  return parsed.weekday % 7;
}

/// 上海时区（UTC+8 自然日）自然周的周一日期。
String capacityWeekMonday(String date) {
  final parsed = _parseDate(date);
  if (parsed == null) return date;
  final offset = (parsed.weekday % 7 + 6) % 7;
  return _dateOnly(parsed.subtract(Duration(days: offset)));
}

String capacityAddDays(String date, int days) {
  final parsed = _parseDate(date);
  if (parsed == null) return date;
  return _dateOnly(parsed.add(Duration(days: days)));
}

/// 周一优先的星期顺序，用于最大余数分配的并列裁决。
const _mondayFirstOrder = [1, 2, 3, 4, 5, 6, 0];

/// 旧数据没有可靠七天模板时，每周模板按每日上限补齐。
Map<String, int> _templateOf(Profile profile) {
  final stored = profile.weeklyMinutes;
  if (isReliableWeek(stored)) {
    return {for (var day = 0; day < 7; day++) '$day': _finite(stored!['$day']!)};
  }
  final fallback = _finite(profile.dailyLimitMinutes);
  return {for (var day = 0; day < 7; day++) '$day': fallback};
}

bool _hasReliableTemplate(Profile profile) => isReliableWeek(profile.weeklyMinutes);

/// 采用口径：gross_buffer（旧语义，扣一次机动）或 net（输入即净学习预算）。
///
/// - `gross_buffer`（旧数据/旧计划）：保持历史行为 `max(0, min(480, raw) - max(30, buffer))`，
///   不使用每日上限，避免旧 golden / 旧计划输出变化。
/// - `net`（新数据）：`max(0, min(dailyLimitMinutes 或 480, raw))`，不再机械扣机动。
int applyCapacityBasis(Profile profile, int rawMinutes) {
  final raw = _finite(rawMinutes);
  if (profile.capacityBasis == CapacityBasis.net) {
    final configured = _finite(profile.dailyLimitMinutes);
    final dailyLimit = configured > 0 ? configured : legacyDailyCapMinutes;
    return math.min(dailyLimit, raw);
  }
  return math.max(
    0,
    math.min(legacyDailyCapMinutes, raw) -
        math.max(30, _finite(profile.bufferMinutes)),
  );
}

/// 旧 gross 语义下每日上限常量（用于保持与历史 golden 完全一致）。
const legacyDailyCapMinutes = 480;

/// 净容量口径下允许的轻量时间：最终分块可小于 30 分钟，最小 10 分钟。
bool supportsLightweightScheduling(Profile profile) =>
    profile.capacityBasis == CapacityBasis.net;

/// 是否使用新的灵活容量语义（净口径或任一基线/范围/覆盖）。
///
/// 旧 gross_buffer 数据且没有任何新字段时保持旧的排程顺序与数值，
/// 以确保旧计划、旧 golden 与共享排期契约逐字节不变。
bool usesFlexibleCapacity(Profile profile) =>
    profile.capacityBasis == CapacityBasis.net ||
    profile.weeklyBaselineMinutes != null ||
    profile.weeklyRangeMinMinutes != null ||
    profile.weeklyRangeMaxMinutes != null ||
    (profile.weekCapacityOverrides?.isNotEmpty ?? false) ||
    (profile.dateCapacityOverrides?.isNotEmpty ?? false);

/// 排程时间粒度（用于对齐开始时间）；旧语义至少 30 分钟。
///
/// 新净口径允许配置更细的粒度（最小 10 分钟），用于轻量时间安排。
int schedulingQuantum(Profile profile) => profile.capacityBasis == CapacityBasis.net
    ? math.min(30, math.max(lightweightMinimumMinutes, _finite(profile.granularityMinutes)))
    : math.max(30, _finite(profile.granularityMinutes));

/// 净口径下允许的最短学习分块。
const lightweightMinimumMinutes = 10;

/// 该周采用的容量预算：周覆盖总量 > 采用基线（或范围下限）。
int? _adoptedWeekBudget(Profile profile, WeekCapacityOverride? override) {
  if (override != null) {
    final total = override.totalMinutes;
    if (total != null) return _finite(total);
    // 只逐日覆盖的周没有周总预算。
    return null;
  }
  final baseline = profile.weeklyBaselineMinutes ?? profile.weeklyRangeMinMinutes;
  return baseline == null ? null : _finite(baseline);
}

/// 只给总量时按模板权重生成逐日建议（整数最大余数法，周一优先裁决）。
Map<int, int> distributeWeeklyTotal(
  int total,
  Map<int, int> weights,
) {
  final eligible = <int>[];
  var weightSum = 0;
  for (final day in _mondayFirstOrder) {
    final weight = weights[day] ?? 0;
    if (weight > 0) {
      eligible.add(day);
      weightSum += weight;
    }
  }
  final result = {for (final day in _mondayFirstOrder) day: 0};
  if (total <= 0 || weightSum <= 0) return result;
  final bases = <int, int>{};
  final remainders = <int, int>{};
  var assigned = 0;
  for (final day in eligible) {
    final weight = weights[day]!;
    final base = total * weight ~/ weightSum;
    bases[day] = base;
    remainders[day] = total * weight % weightSum;
    assigned += base;
  }
  var leftover = total - assigned;
  final order = [...eligible]
    ..sort((a, b) {
      final remainder = remainders[b]!.compareTo(remainders[a]!);
      if (remainder != 0) return remainder;
      return _mondayFirstOrder.indexOf(a).compareTo(
        _mondayFirstOrder.indexOf(b),
      );
    });
  for (var index = 0; index < leftover && index < order.length; index++) {
    bases[order[index]] = bases[order[index]]! + 1;
  }
  return {for (final day in _mondayFirstOrder) day: bases[day] ?? 0};
}

class _ResolvedDay {
  _ResolvedDay(this.rawMinutes, this.source, this.estimated);
  final int rawMinutes;
  final CapacitySource source;
  final bool estimated;
}

class _ResolvedWeek {
  _ResolvedWeek({
    required this.monday,
    required this.byWeekday,
    required this.budgetOverrideMinutes,
    required this.conflicts,
  });
  final String monday;
  final Map<int, _ResolvedDay> byWeekday;
  final int? budgetOverrideMinutes;
  final List<CapacityConflict> conflicts;
}

Map<String, int> _explicitWeekDays(WeekCapacityOverride override) {
  final result = <String, int>{};
  final days = override.days;
  if (days == null) return result;
  for (final entry in days.entries) {
    final day = int.tryParse(entry.key);
    if (day == null || day < 0 || day > 6) continue;
    result['$day'] = _finite(entry.value);
  }
  return result;
}

Map<String, int> _dateOverridesInWeek(Profile profile, String monday) {
  final result = <String, int>{};
  final overrides = profile.dateCapacityOverrides;
  if (overrides == null) return result;
  for (var index = 0; index < 7; index++) {
    final date = capacityAddDays(monday, index);
    final value = overrides[date];
    if (value != null) result[date] = _finite(value);
  }
  return result;
}

_ResolvedWeek _resolveWeek(Profile profile, String monday) {
  final template = _templateOf(profile);
  final reliableTemplate = _hasReliableTemplate(profile);
  final templateSource = reliableTemplate
      ? CapacitySource.template
      : CapacitySource.legacyDefault;
  final override = profile.weekCapacityOverrides?[monday];
  final explicitDays = override == null
      ? const <String, int>{}
      : _explicitWeekDays(override);
  final dateOverrides = _dateOverridesInWeek(profile, monday);
  final budget = _adoptedWeekBudget(profile, override);
  final resolved = <int, _ResolvedDay>{};
  final conflicts = <CapacityConflict>[];

  if (budget == null) {
    if (override == null) {
      // 无周覆盖、无基线：逐日默认模板。
      for (final day in _mondayFirstOrder) {
        resolved[day] = _ResolvedDay(
          template['$day']!,
          templateSource,
          false,
        );
      }
    } else {
      // 只有逐日覆盖：显式日优先，其余沿用模板。
      for (final day in _mondayFirstOrder) {
        final explicit = explicitDays['$day'];
        if (explicit != null) {
          resolved[day] = _ResolvedDay(
            explicit,
            CapacitySource.weekDayOverride,
            false,
          );
        } else {
          resolved[day] = _ResolvedDay(
            template['$day']!,
            templateSource,
            false,
          );
        }
      }
    }
  } else {
    // 周总量：先扣除显式日与日期覆盖，再按模板权重分配剩余。
    final fixedByWeekday = <int, int>{};
    for (final entry in explicitDays.entries) {
      final day = int.parse(entry.key);
      fixedByWeekday[day] = entry.value;
    }
    var fixedSum = 0;
    for (var index = 0; index < 7; index++) {
      final date = capacityAddDays(monday, index);
      final weekday = capacityWeekdayIndex(date);
      final dateOverride = dateOverrides[date];
      if (dateOverride != null) {
        // 具体日期覆盖优先，并计入该周总预算。
        fixedByWeekday[weekday] = dateOverride;
      }
      fixedSum += fixedByWeekday[weekday] ?? 0;
    }
    final remaining = budget - fixedSum;
    final weights = <int, int>{};
    for (final day in _mondayFirstOrder) {
      if (fixedByWeekday.containsKey(day)) continue;
      final weight = template['$day']!;
      if (weight > 0) weights[day] = weight;
    }
    final distributed = remaining > 0
        ? distributeWeeklyTotal(remaining, weights)
        : <int, int>{for (final day in _mondayFirstOrder) day: 0};
    if (remaining < 0) {
      conflicts.add(
        CapacityConflict(
          code: CapacityConflictCode.weekTotalExceeded,
          total: budget,
          resolved: fixedSum,
        ),
      );
    } else if (remaining > 0 && distributed.values.every((value) => value == 0)) {
      conflicts.add(
        CapacityConflict(
          code: CapacityConflictCode.weekTotalUnallocated,
          total: budget,
          resolved: fixedSum,
        ),
      );
    }
    final distributedSource = override == null
        ? CapacitySource.baseline
        : CapacitySource.weekTotal;
    final distributedEstimated =
        override == null || override.totalMinutes != null;
    for (final day in _mondayFirstOrder) {
      final fixed = fixedByWeekday[day];
      if (fixed != null) {
        final date = capacityAddDays(
          monday,
          _mondayFirstOrder.indexOf(day),
        );
        final isDateOverride = dateOverrides.containsKey(date);
        resolved[day] = _ResolvedDay(
          fixed,
          isDateOverride
              ? CapacitySource.dateOverride
              : CapacitySource.weekDayOverride,
          false,
        );
      } else {
        resolved[day] = _ResolvedDay(
          distributed[day] ?? 0,
          distributedSource,
          distributedEstimated,
        );
      }
    }
  }

  // 日期覆盖始终优先于周覆盖/基线/模板，即使该周没有周总预算。
  if (dateOverrides.isNotEmpty) {
    for (final entry in dateOverrides.entries) {
      final weekday = capacityWeekdayIndex(entry.key);
      final existing = resolved[weekday];
      if (existing != null &&
          existing.source == CapacitySource.dateOverride) {
        continue;
      }
      resolved[weekday] = _ResolvedDay(
        entry.value,
        CapacitySource.dateOverride,
        false,
      );
    }
  }
  // 规划周期只与某周部分相交时，仍按完整 7 天解析，由调用方取相交日期；
  // 不对相邻周期重复收取整周预算，也不重新归一化。
  return _ResolvedWeek(
    monday: monday,
    byWeekday: resolved,
    budgetOverrideMinutes: budget,
    conflicts: conflicts,
  );
}

DayCapacity resolveDayCapacity(Profile profile, String date) {
  final monday = capacityWeekMonday(date);
  final week = _resolveWeek(profile, monday);
  final weekday = capacityWeekdayIndex(date);
  final day = week.byWeekday[weekday]!;
  return DayCapacity(
    date: date,
    monday: monday,
    minutes: applyCapacityBasis(profile, day.rawMinutes),
    rawMinutes: day.rawMinutes,
    source: day.source,
    estimated: day.estimated,
    weekBudgetMinutes: week.budgetOverrideMinutes,
  );
}

WeekCapacity resolveWeekCapacity(Profile profile, String monday) {
  final week = _resolveWeek(profile, monday);
  final days = <String, int>{};
  final sources = <String, CapacitySource>{};
  final estimated = <String, bool>{};
  for (var index = 0; index < 7; index++) {
    final date = capacityAddDays(monday, index);
    final weekday = capacityWeekdayIndex(date);
    final day = week.byWeekday[weekday]!;
    days[date] = applyCapacityBasis(profile, day.rawMinutes);
    sources[date] = day.source;
    estimated[date] = day.estimated;
  }
  return WeekCapacity(
    monday: monday,
    days: days,
    sources: sources,
    estimated: estimated,
    budgetOverrideMinutes: week.budgetOverrideMinutes,
    conflicts: week.conflicts,
  );
}

/// 解析 [from]..[to] 每一天的容量（含首尾）。
List<DayCapacity> resolvePeriodCapacity(
  Profile profile,
  String from,
  String to,
) {
  final result = <DayCapacity>[];
  for (var date = from; date.compareTo(to) <= 0; date = capacityAddDays(date, 1)) {
    result.add(resolveDayCapacity(profile, date));
    if (result.length > 4000) break;
  }
  return result;
}

/// 一个规划周期的容量假设摘要，用于全周期预览/详情展示。
class PeriodCapacitySummary {
  const PeriodCapacitySummary({
    required this.from,
    required this.to,
    required this.days,
    required this.restDays,
    required this.estimatedDays,
    required this.totalMinutes,
    required this.weekConflicts,
  });

  final String from;
  final String to;
  final List<DayCapacity> days;
  final int restDays;
  final int estimatedDays;
  final int totalMinutes;
  final List<CapacityConflict> weekConflicts;

  int get dayCount => days.length;
}

/// 汇总周期容量假设；预览可据此说明基线、范围和估算日期。
PeriodCapacitySummary summarizePeriodCapacity(
  Profile profile,
  String from,
  String to,
) {
  final days = resolvePeriodCapacity(profile, from, to);
  var restDays = 0;
  var estimatedDays = 0;
  var total = 0;
  for (final day in days) {
    if (day.minutes <= 0) restDays++;
    if (day.estimated) estimatedDays++;
    total += day.minutes;
  }
  final conflicts = <CapacityConflict>[];
  final seenWeeks = <String>{};
  for (final day in days) {
    if (!seenWeeks.add(day.monday)) continue;
    conflicts.addAll(resolveWeekCapacity(profile, day.monday).conflicts);
  }
  return PeriodCapacitySummary(
    from: from,
    to: to,
    days: days,
    restDays: restDays,
    estimatedDays: estimatedDays,
    totalMinutes: total,
    weekConflicts: conflicts,
  );
}

/// 周容量范围/基线的一句话口径说明（无未设置项时返回空串）。
String capacityAssumptionLabel(Profile profile) {
  final parts = <String>[];
  switch (profile.capacityBasis) {
    case CapacityBasis.net:
      parts.add('按净学习时间计算，不再扣除机动时间');
    case CapacityBasis.grossBuffer:
      parts.add(
        '旧版总预算口径，每日先扣除 ${math.max(30, _finite(profile.bufferMinutes))} 分钟机动',
      );
  }
  final baseline =
      profile.weeklyBaselineMinutes ?? profile.weeklyRangeMinMinutes;
  if (profile.weeklyRangeMinMinutes != null &&
      profile.weeklyRangeMaxMinutes != null) {
    parts.add(
      '大致周容量 ${durationText(profile.weeklyRangeMinMinutes!)}–${durationText(profile.weeklyRangeMaxMinutes!)}',
    );
    parts.add('排程采用保守基线 ${durationText(baseline ?? 0)}');
  } else if (baseline != null) {
    parts.add('默认周容量基线 ${durationText(baseline)}');
  }
  if (profile.weekCapacityOverrides?.isNotEmpty ?? false) {
    parts.add('${profile.weekCapacityOverrides!.length} 个特定周已单独设置');
  }
  if (profile.dateCapacityOverrides?.isNotEmpty ?? false) {
    parts.add('${profile.dateCapacityOverrides!.length} 个特定日期已单独设置');
  }
  return parts.join('；');
}

/// 纯字符串时长，供不依赖 Flutter 的域代码使用。
String durationText(int minutes) {
  final total = minutes < 0 ? 0 : minutes;
  if (total >= 60) {
    return '${total ~/ 60}小时${total % 60 != 0 ? '${total % 60}分' : ''}';
  }
  return '$total分钟';
}
