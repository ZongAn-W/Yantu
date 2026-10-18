import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/capacity.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

/// 与 TypeScript 排程核心共享的容量解析 fixture，双方结果必须逐字段一致。
///
/// fixture 由仓库根目录 `packages/planner-engine/fixtures/capacity-cases.json` 提供，
/// 路径约定与现有 golden 测试一致（flutter test 的工作目录是客户端包根目录）。
const fixturePath =
    '../../packages/planner-engine/fixtures/capacity-cases.json';

JsonMap _profileJson(JsonMap defaults, JsonMap overrides) => {
  'user_id': 'fixture-user',
  'goal_text': '',
  'goal_type': 'other',
  'goal_subtype': '',
  'target_date': '',
  'target_date_confirmed': false,
  'plan_start_date': '2026-10-19',
  'plan_end_date': '2027-12-31',
  'constraints': '',
  'target_school': '',
  'target_program': '',
  'exam_date': '',
  'exam_end_date': '',
  'daily_limit_minutes': defaults['daily_limit_minutes'],
  'granularity_minutes': defaults['granularity_minutes'],
  'buffer_minutes': defaults['buffer_minutes'],
  'subject_limit_minutes': 240,
  'study_start_minute': 0,
  'study_end_minute': 1440,
  'foundation': '',
  ...overrides,
};

void main() {
  final fixture =
      jsonDecode(File(fixturePath).readAsStringSync()) as Map<String, dynamic>;
  final defaults = JsonMap.from(fixture['defaults'] as Map);

  test('fixture covers the documented Monday-first order', () {
    expect(
      (fixture['week_order_monday_first'] as List).cast<int>(),
      [1, 2, 3, 4, 5, 6, 0],
    );
  });

  for (final raw in fixture['cases'] as List) {
    final row = JsonMap.from(raw as Map);
    group(row['name'] as String, () {
      final profile = Profile.fromJson(
        _profileJson(defaults, JsonMap.from(row['profile'] as Map)),
      );
      test('day resolution matches TypeScript reference', () {
        for (final day in (row['days'] as List).cast<Map>()) {
          final expected = JsonMap.from(day);
          final date = expected['date'] as String;
          expect(
            resolveDayCapacity(profile, date).toJson(),
            expected,
            reason: '日期 $date 的容量解析结果必须与共享 fixture 一致',
          );
        }
      });
      test('week budget and conflicts match TypeScript reference', () {
        for (final week in (row['weeks'] as List).cast<Map>()) {
          final expected = JsonMap.from(week);
          final monday = expected['monday'] as String;
          final resolved = resolveWeekCapacity(profile, monday);
          expect(resolved.monday, monday);
          expect(
            resolved.budgetOverrideMinutes,
            expected['budget_minutes'],
            reason: '周 $monday 的预算必须与 fixture 一致',
          );
          expect(
            resolved.days.values.fold<int>(0, (sum, value) => sum + value),
            expected['resolved_minutes'],
            reason: '周 $monday 的逐日分配之和必须精确等于 resolved_minutes',
          );
          expect(
            [
              for (final conflict in resolved.conflicts)
                {
                  'code': capacityConflictCodeName(conflict.code),
                  'total': conflict.total,
                  'resolved': conflict.resolved,
                },
            ],
            expected['conflicts'],
            reason: '周 $monday 的冲突必须与 fixture 一致',
          );
        }
      });
    });
  }

  group('partial period intersection rule', () {
    test('only intersecting days are used, week budget is not renormalized', () {
      final profile = Profile.fromJson(
        _profileJson(defaults, {
          'capacity_basis': 'net',
          'weekly_minutes': {
            '0': 60,
            '1': 60,
            '2': 60,
            '3': 60,
            '4': 60,
            '5': 60,
            '6': 60,
          },
          'week_capacity_overrides': {
            '2026-10-19': {'total_minutes': 140},
          },
        }),
      );
      final week = resolveWeekCapacity(profile, '2026-10-19');
      expect(week.days.values.fold<int>(0, (sum, value) => sum + value), 140);
      // 周期从周三开始：只使用相交的三天，不重新分配整周预算。
      final period = resolvePeriodCapacity(profile, '2026-10-21', '2026-10-23');
      expect(period.map((day) => day.date).toList(), [
        '2026-10-21',
        '2026-10-22',
        '2026-10-23',
      ]);
      for (final day in period) {
        expect(day.minutes, week.days[day.date]);
        expect(day.weekBudgetMinutes, 140);
      }
      // 相邻周期不会重复收取整周预算：下一周没有覆盖，按模板解析。
      final adjacent = resolvePeriodCapacity(profile, '2026-10-26', '2026-10-27');
      expect(adjacent.every((day) => day.weekBudgetMinutes == null), isTrue);
    });
  });

  group('capacity assumptions', () {
    test('source and estimated flags distinguish suggestions from confirmed', () {
      final profile = Profile.fromJson(
        _profileJson(defaults, {
          'capacity_basis': 'net',
          'weekly_minutes': {
            '0': 60,
            '1': 60,
            '2': 60,
            '3': 60,
            '4': 60,
            '5': 60,
            '6': 60,
          },
          'date_capacity_overrides': {
            '2026-10-19': 0,
            '2026-10-20': 90,
          },
        }),
      );
      final zero = resolveDayCapacity(profile, '2026-10-19');
      expect(zero.minutes, 0);
      expect(zero.source, CapacitySource.dateOverride);
      expect(zero.estimated, isFalse);
      final numeric = resolveDayCapacity(profile, '2026-10-20');
      expect(numeric.minutes, 90);
      expect(numeric.source, CapacitySource.dateOverride);
      expect(capacityAssumptionLabel(profile), contains('净学习时间'));
    });

    test('explicit zero never falls back to the upper rule', () {
      final profile = Profile.fromJson(
        _profileJson(defaults, {
          'capacity_basis': 'net',
          'weekly_minutes': {
            '0': 60,
            '1': 60,
            '2': 60,
            '3': 60,
            '4': 60,
            '5': 60,
            '6': 60,
          },
          'date_capacity_overrides': {'2026-10-19': 0},
        }),
      );
      expect(resolveDayCapacity(profile, '2026-10-19').minutes, 0);
      // 删除覆盖键 = 恢复上层规则，不是设为 0。
      final cleared = profile.copyWith(dateCapacityOverrides: null);
      expect(resolveDayCapacity(cleared, '2026-10-19').minutes, 60);
    });
  });
}
