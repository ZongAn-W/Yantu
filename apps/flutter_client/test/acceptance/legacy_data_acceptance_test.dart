// Independent acceptance (WS-V): old-data compatibility for the Dart model layer.
//
// Verifies requirement §11 legacy semantics on the Lead-frozen model files only:
// - old JSON without any new field loads with legacy defaults (gross_buffer, no
//   overrides, legacy_unknown logs, empty ad-hoc list);
// - explicit zeros and explicit empty maps are preserved and distinguishable from
//   missing keys (requirement §5.2.1);
// - a new client always serializes its capability markers so the server can protect
//   new data from old writers;
// - ad-hoc logs / entities round-trip with a null task id and stable references.
//
// This file does not modify implementation source; it only reads committed fixtures.
// Run from apps/flutter_client: flutter test --no-pub test/acceptance/legacy_data_acceptance_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

JsonMap legacyJson() =>
    jsonDecode(File('test/fixtures/planner_v1.json').readAsStringSync())
        as JsonMap;

void main() {
  final legacy = legacyJson();

  group('旧数据兼容（需求 §11）', () {
    test('旧 JSON（没有任何新字段）解析为旧语义默认值', () {
      final data = PlannerData.fromJson(legacy);
      expect(data.profile.capacityBasis, CapacityBasis.grossBuffer);
      expect(data.profile.weeklyBaselineMinutes, isNull);
      expect(data.profile.weeklyRangeMinMinutes, isNull);
      expect(data.profile.weeklyRangeMaxMinutes, isNull);
      expect(data.profile.weekCapacityOverrides, isNull);
      expect(data.profile.dateCapacityOverrides, isNull);
      expect(data.adHocLearnings, isEmpty);
      final log = data.logs.single;
      expect(log.relation, TimeLogRelation.legacyUnknown);
      expect(log.taskId, isNotNull);
      expect(log.sessionId, isNull);
      expect(log.adHocId, isNull);
      expect(log.quotaMinutes, isNull);
      expect(log.source, LogSource.manual);
    });

    test('新客户端序列化始终带能力标记（旧写入方保护依据）', () {
      final json = PlannerData.fromJson(legacy).toJson();
      expect(json.containsKey('ad_hoc_learnings'), isTrue,
          reason: '新客户端即使没有临时学习也要发送该键，服务端才能区分旧写入方');
      expect(json['ad_hoc_learnings'], isEmpty);
      expect((json['profile'] as Map)['capacity_basis'], 'gross_buffer',
          reason: '旧数据按 gross_buffer 旧口径回写，不悄悄升级为净值');
      // 旧数据不能凭空长出覆盖配置，也不能把旧 weekly_minutes 改写成别的形式。
      expect((json['profile'] as Map).containsKey('week_capacity_overrides'),
          isFalse);
      expect((json['profile'] as Map).containsKey('date_capacity_overrides'),
          isFalse);
      expect((json['profile'] as Map)['weekly_minutes'], legacy['profile']['weekly_minutes']);
    });

    test('旧 weekly_minutes 的 0 值保留为休息日，不回退每日上限', () {
      final raw = legacyJson();
      ((raw['profile'] as Map)['weekly_minutes'] as Map)['0'] = 0;
      final data = PlannerData.fromJson(raw);
      expect(data.profile.weekMinutes['0'], 0,
          reason: '显式 0 表示休息日，不能被 daily_limit 默认值替换');
      expect(data.profile.weekMinutes.length, 7);
      expect(data.profile.weekMinutes['1'], legacy['profile']['weekly_minutes']['1']);
    });

    test('显式 0 覆盖与显式空覆盖保留，删除键不等于零容量', () {
      final raw = legacyJson();
      (raw['profile'] as Map)['capacity_basis'] = 'net';
      (raw['profile'] as Map)['date_capacity_overrides'] = {
        '2026-10-18': 0,
        '2026-10-19': 90,
      };
      (raw['profile'] as Map)['week_capacity_overrides'] = {
        '2026-10-19': {
          'total_minutes': 100,
          'days': {'1': 0},
        },
      };
      final data = PlannerData.fromJson(raw);
      expect(data.profile.dateCapacityOverrides, {'2026-10-18': 0, '2026-10-19': 90});
      final week = data.profile.weekCapacityOverrides!['2026-10-19']!;
      expect(week.totalMinutes, 100);
      expect(week.days!['1'], 0);
      final roundtrip = PlannerData.fromJson(
          jsonDecode(jsonEncode(data.toJson())) as JsonMap);
      expect(roundtrip.profile.capacityBasis, CapacityBasis.net);
      expect(roundtrip.profile.dateCapacityOverrides, {'2026-10-18': 0, '2026-10-19': 90});
      expect(roundtrip.profile.weekCapacityOverrides!['2026-10-19']!.days!['1'], 0);

      // 空 map 表示“显式清空全部覆盖”，与缺失键语义不同（删除键=恢复上层）。
      (raw['profile'] as Map)['date_capacity_overrides'] = <String, int>{};
      final cleared = PlannerData.fromJson(raw);
      expect(cleared.profile.dateCapacityOverrides, isEmpty);
      expect(cleared.toJson()['profile']['date_capacity_overrides'], <String, int>{});
    });

    test('临时学习日志 task_id 可为 null，关系/会话/实体引用完整往返', () {
      final raw = legacyJson();
      raw['logs'] = [
        {
          'id': 'log-adhoc-1',
          'user_id': raw['profile']['user_id'],
          'task_id': null,
          'block_id': null,
          'date': '2026-10-18',
          'minutes': 20,
          'started_at': '2026-10-18T01:00:00.000Z',
          'ended_at': '2026-10-18T01:20:00.000Z',
          'source': 'timer',
          'relation': 'ad_hoc',
          'session_id': 'session-1',
          'ad_hoc_id': 'adhoc-1',
          'quota_minutes': null,
        },
        {
          'id': 'log-scheduled-1',
          'user_id': raw['profile']['user_id'],
          'task_id': raw['tasks'][0]['id'],
          'block_id': null,
          'date': '2026-10-18',
          'minutes': 30,
          'started_at': '2026-10-18T02:00:00.000Z',
          'ended_at': '2026-10-18T02:30:00.000Z',
          'source': 'timer',
          'relation': 'scheduled',
          'session_id': 'session-2',
          'quota_minutes': 60,
        },
      ];
      raw['ad_hoc_learnings'] = [
        {
          'id': 'adhoc-1',
          'user_id': raw['profile']['user_id'],
          'title': '摄影构图',
          'subject_id': null,
          'created_at': '2026-10-18T01:00:00.000Z',
          'updated_at': '2026-10-18T01:20:00.000Z',
          'archived': false,
        },
      ];
      final data = PlannerData.fromJson(raw);
      expect(data.logs, hasLength(2));
      final adHoc = data.logs.firstWhere((log) => log.id == 'log-adhoc-1');
      expect(adHoc.taskId, isNull);
      expect(adHoc.relation, TimeLogRelation.adHoc);
      expect(adHoc.adHocId, 'adhoc-1');
      expect(adHoc.sessionId, 'session-1');
      final scheduled = data.logs.firstWhere((log) => log.id == 'log-scheduled-1');
      expect(scheduled.relation, TimeLogRelation.scheduled);
      expect(scheduled.quotaMinutes, 60);
      expect(data.adHocLearnings.single.title, '摄影构图');
      expect(data.adHocLearnings.single.archived, isFalse);

      final json = data.toJson();
      expect(json['logs'][0]['task_id'], isNull,
          reason: 'task_id 必须显式输出 null，不能被 includeIfNull 丢掉');
      expect(json['logs'][0]['relation'], 'ad_hoc');
      expect(json['logs'][0]['session_id'], 'session-1');
      expect(json['ad_hoc_learnings'][0]['title'], '摄影构图');
    });
  });
}
