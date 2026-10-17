import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/features/planner/application/onboarding_controller.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

JsonMap legacyPlanJson() {
  final base = plannerFixture();
  final json = JsonMap.from(jsonDecode(jsonEncode(base.toJson())) as Map);
  final profile = JsonMap.from(json['profile'] as Map);
  for (final key in [
    'goal_text',
    'goal_type',
    'goal_subtype',
    'target_date',
    'target_date_confirmed',
    'plan_start_date',
    'plan_end_date',
    'weekly_minutes',
    'constraints',
  ]) {
    profile.remove(key);
  }
  profile['exam_date'] = '2027-06-01';
  profile['exam_end_date'] = '2027-06-01';
  json['profile'] = profile;
  return json;
}

void main() {
  test('a legacy plan without the new fields still reads its exam date', () {
    final data = PlannerData.fromJson(legacyPlanJson());
    expect(data.profile.resolvedTargetDate, '2027-06-01');
    expect(data.profile.resolvedPlanEnd('2026-10-17'), '2027-06-01');
    // 历史日期不是用户刚刚确认的目标日期。
    expect(data.profile.targetDateConfirmed, isFalse);
  });

  test('an explicitly empty target date does not fall back to the legacy field', () {
    final source = legacyPlanJson();
    final profile = JsonMap.from(source['profile'] as Map);
    profile['target_date'] = '';
    profile['plan_end_date'] = '2026-11-13';
    source['profile'] = profile;
    final data = PlannerData.fromJson(source);
    expect(data.profile.resolvedTargetDate, isEmpty);

    final nulled = JsonMap.from(source);
    final nullProfile = JsonMap.from(profile)..['target_date'] = null;
    nulled['profile'] = nullProfile;
    expect(PlannerData.fromJson(nulled).profile.resolvedTargetDate, isEmpty);
  });

  test('one date is stored in one place after a new value is written', () {
    final source = legacyPlanJson();
    final data = PlannerData.fromJson(source);
    final draft = ProfileSettingsDraft.from(
      data.profile,
      today: '2027-01-04',
    );
    final updated = applySettings(
      data,
      draft.copyWith(
        targetDate: '2027-02-02',
        targetDateConfirmed: true,
      ),
    );
    expect(updated.profile.targetDate, '2027-02-02');
    expect(updated.profile.resolvedTargetDate, '2027-02-02');
    expect(updated.profile.examDate, isEmpty);
    expect(updated.profile.examEndDate, isEmpty);
    expect(updated.profile.targetDateConfirmed, isTrue);
  });

  test('clearing the target date survives export, import and re-reading', () {
    final data = PlannerData.fromJson(legacyPlanJson());
    expect(data.profile.resolvedTargetDate, '2027-06-01');
    final draft = ProfileSettingsDraft.from(
      data.profile,
      today: '2027-01-04',
    );
    final cleared = applySettings(
      data,
      draft.copyWith(targetDate: '', targetDateConfirmed: true),
    );
    expect(cleared.profile.resolvedTargetDate, isEmpty);
    expect(cleared.profile.targetDateConfirmed, isFalse);
    expect(cleared.profile.examDate, isEmpty);
    expect(cleared.profile.examEndDate, isEmpty);

    // 导出 → 导入：清空结果保留，旧日期不会回来。
    final restored = parsePlannerJson(jsonEncode(cleared.toJson()));
    expect(restored.profile.resolvedTargetDate, isEmpty);
    expect(restored.profile.examDate, isEmpty);
    expect(restored.profile.targetDate, isEmpty);
    // 同时保留规划周期。
    expect(restored.profile.resolvedPlanEnd('2027-01-04'), '2027-06-01');
  });

  test('an incomplete weekly configuration is not treated as a reliable week', () {
    final source = legacyPlanJson();
    final profile = JsonMap.from(source['profile'] as Map)
      ..['weekly_minutes'] = {'1': 90, '2': 90};
    source['profile'] = profile;
    final data = PlannerData.fromJson(source);
    expect(data.profile.weekMinutes.values.toSet(), {data.profile.dailyLimitMinutes});

    final full = JsonMap.from(source);
    final fullProfile = JsonMap.from(profile)
      ..['weekly_minutes'] = {
        '0': 0,
        '1': 90,
        '2': 90,
        '3': 0,
        '4': 90,
        '5': 90,
        '6': 180,
      };
    full['profile'] = fullProfile;
    final reliable = PlannerData.fromJson(full);
    expect(reliable.profile.weekMinutes, {
      '0': 0,
      '1': 90,
      '2': 90,
      '3': 0,
      '4': 90,
      '5': 90,
      '6': 180,
    });
  });
}
