import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/merge_plans.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const String _stamp = '2026-10-18T01:00:00.000Z';

TimeLog _log({
  required String id,
  String? taskId,
  String? adHocId,
  String date = '2026-10-17',
  int minutes = 20,
  TimeLogRelation relation = TimeLogRelation.legacyUnknown,
  String? sessionId,
  int? quotaMinutes,
  String? blockId,
}) {
  final owner = plannerFixture().profile.userId;
  return TimeLog(
    id: id,
    userId: owner,
    taskId: taskId,
    blockId: blockId,
    date: date,
    minutes: minutes,
    startedAt: _stamp,
    endedAt: _stamp,
    source: LogSource.timer,
    relation: relation,
    sessionId: sessionId,
    adHocId: adHocId,
    quotaMinutes: quotaMinutes,
  );
}

AdHocLearning _adHoc({
  required String id,
  required String title,
  String? subjectId,
  bool archived = false,
  String? convertedTaskId,
}) {
  return AdHocLearning(
    id: id,
    userId: plannerFixture().profile.userId,
    title: title,
    subjectId: subjectId,
    createdAt: _stamp,
    updatedAt: _stamp,
    archived: archived,
    convertedTaskId: convertedTaskId,
  );
}

/// 覆盖全部新字段的新版文档：容量覆盖、净口径、三类日志、临时学习实体。
PlannerData richData() {
  final base = plannerFixture();
  final taskId = base.tasks.single.id;
  final subjectId = base.subjects.single.id;
  return base.copyWith(
    profile: base.profile.copyWith(
      capacityBasis: CapacityBasis.net,
      weeklyBaselineMinutes: 360,
      weeklyRangeMinMinutes: 300,
      weeklyRangeMaxMinutes: 480,
      weekCapacityOverrides: {
        '2026-10-19': const WeekCapacityOverride(
          totalMinutes: 180,
          days: {'1': 60, '3': 0},
        ),
      },
      dateCapacityOverrides: {'2026-10-22': 0, '2026-10-23': 90},
    ),
    tasks: [base.tasks.single.copyWith(completedMinutes: 80)],
    adHocLearnings: [
      _adHoc(id: 'adhoc-photo', title: '摄影构图'),
      _adHoc(
        id: 'adhoc-math',
        title: '线代复习',
        subjectId: subjectId,
        archived: true,
        convertedTaskId: taskId,
      ),
    ],
    logs: [
      base.logs.single.copyWith(
        relation: TimeLogRelation.scheduled,
        sessionId: 'session-1',
        quotaMinutes: 30,
      ),
      _log(
        id: 'log-extra',
        taskId: taskId,
        date: '2026-10-17',
        minutes: 30,
        relation: TimeLogRelation.extra,
        sessionId: 'session-1',
      ),
      _log(
        id: 'log-adhoc',
        taskId: null,
        adHocId: 'adhoc-photo',
        date: '2026-10-17',
        minutes: 20,
        relation: TimeLogRelation.adHoc,
        sessionId: 'session-2',
      ),
      _log(
        id: 'log-converted',
        taskId: taskId,
        adHocId: 'adhoc-math',
        date: '2026-10-18',
        minutes: 15,
        relation: TimeLogRelation.adHoc,
        sessionId: 'session-3',
        quotaMinutes: 0,
      ),
    ],
  );
}

PlannerData replaceLog(PlannerData data, TimeLog log) =>
    data.copyWith(logs: [for (final row in data.logs) row.id == log.id ? log : row]);

void main() {
  group('validatePlanner new fields', () {
    test('legacy JSON without any new field loads with legacy defaults', () {
      final data = plannerFixture();
      expect(data.adHocLearnings, isEmpty);
      expect(data.logs.map((log) => log.relation), [
        TimeLogRelation.legacyUnknown,
      ]);
      expect(data.logs.single.taskId, isNotNull);
      expect(data.logs.single.adHocId, isNull);
      expect(data.profile.capacityBasis, CapacityBasis.grossBuffer);
      expect(data.profile.weeklyBaselineMinutes, isNull);
      expect(data.profile.weekCapacityOverrides, isNull);
      expect(data.profile.dateCapacityOverrides, isNull);
      validatePlanner(data);
      // 旧 JSON 编码后再读仍通过；没有新字段的文档不能被拒绝。
      expect(parsePlannerJson(data.toJsonString()), data);
    });

    test('a valid document with all new fields passes validation', () {
      // 临时学习已下线：历史记录在解析/导入时被清理，清理后的文档必须通过校验。
      final data = purgeAdHocData(richData());
      validatePlanner(data);
      expect(parsePlannerJson(data.toJsonString()), data);
    });

    test('legacy ad-hoc records are deleted or converted on parse', () {
      final data = richData();
      final parsed = parsePlannerJson(data.toJsonString());
      // 纯临时学习（无正式事项）记录被删除；已转正式事项的记录保留用时并
      // 改写为加学关系；临时学习实体全部清空。
      expect(parsed.adHocLearnings, isEmpty);
      expect(parsed.logs.map((log) => log.id), isNot(contains('log-adhoc')));
      final converted = parsed.logs.singleWhere(
        (log) => log.id == 'log-converted',
      );
      expect(converted.relation, TimeLogRelation.extra);
      expect(converted.adHocId, isNull);
      expect(converted.taskId, data.tasks.single.id);
      expect(parsed.logs.every((log) => log.adHocId == null), isTrue);
    });

    test('logs must belong to exactly one owner and keep relations consistent', () {
      final base = richData();
      final taskId = base.tasks.single.id;
      final blockId = base.blocks.single.id;
      void rejects(PlannerData data) =>
          expect(() => validatePlanner(data), throwsA(isA<FormatException>()));

      // 两个归属都缺失：无法归属的孤立日志。
      rejects(base.copyWith(logs: [_log(id: 'orphan')]));
      // 临时学习引用不存在的实体。
      rejects(
        base.copyWith(
          logs: [
            _log(
              id: 'bad-adhoc',
              adHocId: 'missing',
              relation: TimeLogRelation.adHoc,
            ),
          ],
        ),
      );
      // relation=ad_hoc 却没有 ad_hoc_id。
      rejects(
        base.copyWith(
          logs: [
            _log(
              id: 'bad-relation',
              taskId: taskId,
              relation: TimeLogRelation.adHoc,
            ),
          ],
        ),
      );
      // 有 block 但没有正式事项。
      rejects(
        base.copyWith(
          logs: [
            _log(
              id: 'bad-block',
              adHocId: 'adhoc-photo',
              blockId: blockId,
            ),
          ],
        ),
      );
      // block 属于其他事项时不能挂在别的 task 上。
      rejects(
        base.copyWith(
          logs: [
            _log(
              id: 'bad-block-owner',
              taskId: 'other',
              blockId: blockId,
            ),
          ],
        ),
      );
      // session_id 存在时必须非空。
      rejects(
        base.copyWith(
          logs: [
            _log(id: 'empty-session', taskId: taskId, sessionId: ''),
          ],
        ),
      );
      // quota_minutes 不能为负。
      rejects(
        base.copyWith(
          logs: [
            _log(id: 'negative-quota', taskId: taskId, quotaMinutes: -1),
          ],
        ),
      );
    });

    test('temporary learning entities validate owner and references', () {
      final base = richData();
      final subjectId = base.subjects.single.id;
      final taskId = base.tasks.single.id;
      void rejects(PlannerData data) =>
          expect(() => validatePlanner(data), throwsA(isA<FormatException>()));

      rejects(
        base.copyWith(
          adHocLearnings: [
            base.adHocLearnings.first.copyWith(userId: 'someone-else'),
          ],
        ),
      );
      rejects(
        base.copyWith(
          adHocLearnings: [
            base.adHocLearnings.first.copyWith(title: '  '),
          ],
        ),
      );
      rejects(
        base.copyWith(
          adHocLearnings: [
            base.adHocLearnings.first.copyWith(subjectId: 'missing'),
          ],
        ),
      );
      rejects(
        base.copyWith(
          adHocLearnings: [
            base.adHocLearnings.first.copyWith(convertedTaskId: 'missing'),
          ],
        ),
      );
      // 合法引用（课程、转换后事项）通过，且列表里仍有日志引用的其他实体。
      validatePlanner(
        base.copyWith(
          adHocLearnings: [
            base.adHocLearnings.first.copyWith(
              subjectId: subjectId,
              convertedTaskId: taskId,
            ),
            base.adHocLearnings.last,
          ],
        ),
      );
    });

    test('capacity overrides validate dates, Monday keys and ranges', () {
      final base = richData();
      void rejects(Profile profile) =>
          expect(() => validatePlanner(base.copyWith(profile: profile)),
              throwsA(isA<FormatException>()));

      rejects(base.profile.copyWith(dateCapacityOverrides: {'2026-02-30': 0}));
      rejects(base.profile.copyWith(dateCapacityOverrides: {'2026-10-22': -1}));
      rejects(base.profile.copyWith(dateCapacityOverrides: {'2026-10-22': 1441}));
      // 周覆盖键必须是周一日期。
      rejects(
        base.profile.copyWith(
          weekCapacityOverrides: {
            '2026-10-20': const WeekCapacityOverride(totalMinutes: 60),
          },
        ),
      );
      rejects(
        base.profile.copyWith(
          weekCapacityOverrides: {
            '2026-10-19': const WeekCapacityOverride(days: {'7': 30}),
          },
        ),
      );
      rejects(
        base.profile.copyWith(
          weekCapacityOverrides: {
            '2026-10-19': const WeekCapacityOverride(days: {'1': 1441}),
          },
        ),
      );
      rejects(
        base.profile.copyWith(
          weekCapacityOverrides: {
            '2026-10-19': const WeekCapacityOverride(totalMinutes: 10081),
          },
        ),
      );
      rejects(base.profile.copyWith(weeklyBaselineMinutes: -1));
      rejects(base.profile.copyWith(weeklyRangeMaxMinutes: 10081));
      // 2026-10-19 是周一，0 值日与显式 0 日期合法。
      validatePlanner(base);
    });

    test('explicit zero and missing date overrides stay distinguishable', () {
      final json = plannerFixture().toJson();
      final profile = json['profile'] as Map<String, dynamic>;
      profile['date_capacity_overrides'] = {'2026-10-22': 0, '2026-10-23': 90};
      final data = parsePlannerJson(jsonEncode(json));
      expect(data.profile.dateCapacityOverrides, {'2026-10-22': 0, '2026-10-23': 90});
      expect(data.profile.dateCapacityOverrides!.containsKey('2026-10-20'), isFalse);
      // 显式 0 在编码后仍然存在，不会被当成“没有覆盖”。
      final reencoded = data.toJson();
      final encodedProfile = reencoded['profile'] as Map;
      expect(
        (encodedProfile['date_capacity_overrides'] as Map)['2026-10-22'],
        0,
      );
      // 删除键=恢复上层规则：序列化后该键不存在，而不是 null/0。
      final cleared = data.copyWith(
        profile: data.profile.copyWith(
          dateCapacityOverrides: {'2026-10-23': 90},
        ),
      );
      final clearedJson =
          (cleared.toJson()['profile'] as Map)['date_capacity_overrides'] as Map;
      expect(clearedJson.containsKey('2026-10-22'), isFalse);
    });
  });

  group('round trip', () {
    test('storage, backup, export and sync wire keep every new field', () async {
      var sequence = 0;
      final database = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase('ws-e-${sequence++}'),
      );
      final storage = SembastStorageRepository(database: database);
      addTearDown(database.close);
      // 临时学习已下线：清理后的文档才是合法的当前文档形态。
      final data = purgeAdHocData(richData());
      final metadata = StorageMetadata(revision: 7, pending: true, base: data);
      await storage.save('account', data, metadata);
      final loaded = await SembastStorageRepository(database: database).load(
        'account',
      );
      expect(loaded.data, data);
      expect(loaded.metadata.base, data);
      final exported = await storage.exportJson(data);
      expect(parsePlannerJson(exported!), data);
      // 服务端写入体必须原样包含新字段（没有 passthrough 丢失）。
      final wire = plannerDocumentForSync(data, null);
      expect(wire, data.toJson());
      expect(wire['ad_hoc_learnings'], isEmpty);
      final wireLogs = (wire['logs'] as List).cast<Map>();
      expect(wireLogs.any((log) => log['id'] == 'log-adhoc'), isFalse);
      expect(
        wireLogs.firstWhere((log) => log['id'] == 'log-extra')['session_id'],
        'session-1',
      );
      expect(
        wireLogs.firstWhere((log) => log['id'] == 'log-extra')['relation'],
        'extra',
      );
      final convertedWire = wireLogs.firstWhere(
        (log) => log['id'] == 'log-converted',
      );
      expect(convertedWire['relation'], 'extra');
      expect(convertedWire['ad_hoc_id'], isNull);
      expect(convertedWire['quota_minutes'], 0);
      final wireProfile = wire['profile'] as Map;
      expect(wireProfile['capacity_basis'], 'net');
      expect(wireProfile['weekly_baseline_minutes'], 360);
      expect(
        (wireProfile['date_capacity_overrides'] as Map)['2026-10-22'],
        0,
      );
      expect(PlannerData.fromJson(JsonMap.from(wire)), data);
    });

    test('explicit clears become null on the sync wire, absent stays absent', () {
      final base = richData();
      final cleared = base.copyWith(
        profile: base.profile.copyWith(
          weeklyBaselineMinutes: null,
          weeklyRangeMinMinutes: null,
          weeklyRangeMaxMinutes: null,
          weekCapacityOverrides: null,
          dateCapacityOverrides: null,
        ),
        logs: [
          for (final log in base.logs)
            if (log.id == 'log-extra')
              log.copyWith(sessionId: null, quotaMinutes: null)
            else
              log,
        ],
      );
      final wire = plannerDocumentForSync(cleared, base);
      final profile = wire['profile'] as Map;
      expect(profile['weekly_baseline_minutes'], isNull);
      expect(profile['weekly_range_min_minutes'], isNull);
      expect(profile['weekly_range_max_minutes'], isNull);
      expect(profile['week_capacity_overrides'], isNull);
      expect(profile['date_capacity_overrides'], isNull);
      final extra = (wire['logs'] as List)
          .cast<Map>()
          .firstWhere((log) => log['id'] == 'log-extra');
      expect(extra.containsKey('session_id'), isTrue);
      expect(extra['session_id'], isNull);
      expect(extra['quota_minutes'], isNull);
      // 没有历史值的字段保持缺省，不额外制造 null。
      final fresh = plannerDocumentForSync(plannerFixture(), null);
      expect(
        (fresh['profile'] as Map).containsKey('weekly_baseline_minutes'),
        isFalse,
      );
      expect(
        (fresh['logs'] as List).cast<Map>().single.containsKey('ad_hoc_id'),
        isFalse,
      );
    });

    test('explicit clear survives a save/export/import cycle', () async {
      var sequence = 0;
      final database = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase('ws-e-clear-${sequence++}'),
      );
      final storage = SembastStorageRepository(database: database);
      addTearDown(database.close);
      final data = richData().copyWith(
        profile: richData().profile.copyWith(dateCapacityOverrides: null),
      );
      await storage.save('a', data, const StorageMetadata());
      final reloaded = await storage.load('a');
      expect(reloaded.data!.profile.dateCapacityOverrides, isNull);
      expect(parsePlannerJson(data.toJsonString()).profile.dateCapacityOverrides, isNull);
    });

    test('an old export after stripping new keys is still accepted and defaults', () {
      final json = richData().toJson();
      // 模拟旧版本导出：新字段整体不存在。
      json.remove('ad_hoc_learnings');
      final profile = json['profile'] as Map<String, dynamic>;
      profile.removeWhere(
        (key, _) =>
            key == 'capacity_basis' ||
            key == 'weekly_baseline_minutes' ||
            key == 'weekly_range_min_minutes' ||
            key == 'weekly_range_max_minutes' ||
            key == 'week_capacity_overrides' ||
            key == 'date_capacity_overrides',
      );
      // 旧版本无法表达临时学习日志，历史工具会丢弃这些行。
      json['logs'] = [
        for (final row in (json['logs'] as List).cast<Map>())
          if (row['task_id'] != null)
            {
              for (final entry in row.entries)
                if (!['relation', 'session_id', 'ad_hoc_id', 'quota_minutes']
                    .contains(entry.key))
                  entry.key: entry.value,
            },
      ];
      final data = parsePlannerJson(jsonEncode(json));
      validatePlanner(data);
      expect(data.adHocLearnings, isEmpty);
      expect(data.profile.capacityBasis, CapacityBasis.grossBuffer);
      expect(data.profile.weeklyBaselineMinutes, isNull);
      expect(
        data.logs.map((log) => log.relation),
        everyElement(TimeLogRelation.legacyUnknown),
      );
    });
  });

  group('mergePlans new fields', () {
    test('no-op merge keeps the local document semantically and JSON-stable', () {
      final base = plannerFixture();
      final local = richData();
      final merged = mergePlans(base, local, base);
      expect(merged.conflicts, isEmpty);
      expect(semanticallyEqual(merged.data.toJson(), local.toJson()), isTrue);
      expect(jsonEncode(merged.data.toJson()), jsonEncode(local.toJson()));
      expect(merged.data.adHocLearnings.map((row) => row.id), [
        'adhoc-photo',
        'adhoc-math',
      ]);
      expect(merged.data.profile.capacityBasis, CapacityBasis.net);
      expect(merged.data.profile.dateCapacityOverrides, {
        '2026-10-22': 0,
        '2026-10-23': 90,
      });
      final adhocLog = merged.data.logs.firstWhere((log) => log.id == 'log-adhoc');
      expect(adhocLog.taskId, isNull);
      expect(adhocLog.adHocId, 'adhoc-photo');
      expect(adhocLog.relation, TimeLogRelation.adHoc);
      expect(adhocLog.sessionId, 'session-2');
      final extra = merged.data.logs.firstWhere((log) => log.id == 'log-extra');
      expect(extra.relation, TimeLogRelation.extra);
      expect(extra.sessionId, 'session-1');
      final converted = merged.data.logs.firstWhere(
        (log) => log.id == 'log-converted',
      );
      expect(converted.taskId, isNotNull);
      expect(converted.adHocId, 'adhoc-math');
      expect(converted.quotaMinutes, 0);
      // 合并结果仍是可通过校验、可再次三路合并的文档。
      validatePlanner(merged.data);
      expect(mergePlans(base, merged.data, base).conflicts, isEmpty);
    });

    test('ad-hoc entities merge by id without cross-entity log mixing', () {
      final base = richData();
      // 两台设备各自新增临时学习与当天记录：都保留，不互相覆盖、不误报冲突。
      final local = base.copyWith(
        adHocLearnings: [
          ...base.adHocLearnings,
          _adHoc(id: 'adhoc-local', title: '本机临时学习'),
        ],
        logs: [
          ...base.logs,
          _log(
            id: 'log-local',
            adHocId: 'adhoc-local',
            relation: TimeLogRelation.adHoc,
          ),
        ],
      );
      final remote = base.copyWith(
        adHocLearnings: [
          ...base.adHocLearnings,
          _adHoc(id: 'adhoc-remote', title: '云端临时学习'),
        ],
        logs: [
          ...base.logs,
          _log(
            id: 'log-remote',
            adHocId: 'adhoc-remote',
            relation: TimeLogRelation.adHoc,
          ),
        ],
      );
      final merged = mergePlans(base, local, remote);
      expect(merged.conflicts, isEmpty);
      expect(
        merged.data.adHocLearnings.map((row) => row.id).toSet(),
        containsAll(['adhoc-photo', 'adhoc-math', 'adhoc-local', 'adhoc-remote']),
      );
      final logIds = merged.data.logs.map((log) => log.id).toList();
      expect(logIds.toSet().length, logIds.length, reason: '不重复累计同一段记录');
      expect(
        merged.data.logs.firstWhere((log) => log.id == 'log-local').adHocId,
        'adhoc-local',
      );
      expect(
        merged.data.logs.firstWhere((log) => log.id == 'log-remote').adHocId,
        'adhoc-remote',
      );
      validatePlanner(merged.data);
    });

    test('same ad-hoc entity/day conflict keeps local and reports its scope', () {
      final base = richData();
      final local = replaceLog(
        base,
        base.logs.firstWhere((log) => log.id == 'log-adhoc').copyWith(minutes: 30),
      );
      final remote = replaceLog(
        base,
        base.logs.firstWhere((log) => log.id == 'log-adhoc').copyWith(minutes: 40),
      );
      final merged = mergePlans(base, local, remote);
      expect(merged.conflicts, contains('同一临时学习当天的累计用时'));
      expect(merged.logConflicts, [
        LogConflict(null, '2026-10-17', adHocId: 'adhoc-photo'),
      ]);
      expect(
        merged.data.logs.firstWhere((log) => log.id == 'log-adhoc').minutes,
        30,
      );
      // 不同临时学习实体/不同日期不互相牵连。
      expect(merged.data.logs.firstWhere((log) => log.id == 'log-extra').minutes, 30);
      expect(merged.data.adHocLearnings, hasLength(2));
      validatePlanner(merged.data);
      final adopted = mergePlans(base, local, remote, preferLocal: false);
      final adoptedLog = adopted.data.logs.firstWhere(
        (log) => log.id == 'log-adhoc',
      );
      expect(adoptedLog.minutes, 40);
      // 采用云端时不丢弃新字段：归属、会话与关系仍完整。
      expect(adoptedLog.taskId, isNull);
      expect(adoptedLog.adHocId, 'adhoc-photo');
      expect(adoptedLog.relation, TimeLogRelation.adHoc);
      expect(adoptedLog.sessionId, 'session-2');
      expect(adopted.data.adHocLearnings, hasLength(2));
      expect(adopted.data.profile.dateCapacityOverrides, {
        '2026-10-22': 0,
        '2026-10-23': 90,
      });
      validatePlanner(adopted.data);
    });

    test('task-day conflicts still drive timer discard scopes', () {
      final base = richData();
      final local = replaceLog(
        base,
        base.logs.firstWhere((log) => log.id == 'log-extra').copyWith(minutes: 50),
      );
      final remote = replaceLog(
        base,
        base.logs.firstWhere((log) => log.id == 'log-extra').copyWith(minutes: 60),
      );
      final merged = mergePlans(base, local, remote);
      final taskId = base.tasks.single.id;
      expect(merged.logConflicts, contains(LogConflict(taskId, '2026-10-17')));
      expect(merged.logConflicts.single.adHocId, isNull);
    });

    test('deleted ad-hoc entity and its history are removed consistently', () {
      final base = richData();
      final remote = base.copyWith(
        adHocLearnings: [
          for (final row in base.adHocLearnings)
            if (row.id != 'adhoc-photo') row,
        ],
        logs: [
          for (final log in base.logs)
            if (log.adHocId != 'adhoc-photo') log,
        ],
      );
      final merged = mergePlans(base, base, remote, preferLocal: false);
      expect(merged.conflicts, isEmpty);
      expect(
        merged.data.adHocLearnings.any((row) => row.id == 'adhoc-photo'),
        isFalse,
      );
      expect(merged.data.logs.any((log) => log.adHocId == 'adhoc-photo'), isFalse);
      validatePlanner(merged.data);
    });

    test('locally changed ad-hoc history survives a remote entity deletion', () {
      final base = richData();
      final local = replaceLog(
        base,
        base.logs.firstWhere((log) => log.id == 'log-adhoc').copyWith(minutes: 15),
      );
      final remote = base.copyWith(
        adHocLearnings: [
          for (final row in base.adHocLearnings)
            if (row.id != 'adhoc-photo') row,
        ],
        logs: [
          for (final log in base.logs)
            if (log.adHocId != 'adhoc-photo') log,
        ],
      );
      final merged = mergePlans(base, local, remote);
      expect(merged.conflicts, isNotEmpty);
      expect(
        merged.data.adHocLearnings.any((row) => row.id == 'adhoc-photo'),
        isTrue,
      );
      expect(
        merged.data.logs.firstWhere((log) => log.id == 'log-adhoc').minutes,
        15,
      );
      validatePlanner(merged.data);
    });

    test('log group merge keeps relation/session/quota when only minutes change', () {
      final base = richData();
      final local = replaceLog(
        base,
        base.logs.firstWhere((log) => log.id == 'log-extra').copyWith(minutes: 45),
      );
      final merged = mergePlans(base, local, base);
      expect(merged.conflicts, isEmpty);
      final extra = merged.data.logs.firstWhere((log) => log.id == 'log-extra');
      expect(extra.minutes, 45);
      expect(extra.relation, TimeLogRelation.extra);
      expect(extra.sessionId, 'session-1');
    });
  });

  group('account remap and isolation', () {
    test('forAccount remaps ad-hoc ids but keeps session identifiers', () {
      final data = richData();
      final migrated = forAccount(data, 'new-owner');
      validatePlanner(migrated);
      expect(migrated.profile.userId, 'new-owner');
      final originalAdHoc = data.adHocLearnings.firstWhere(
        (row) => row.id == 'adhoc-photo',
      );
      final mappedAdHoc = migrated.adHocLearnings.firstWhere(
        (row) => row.title == '摄影构图',
      );
      expect(mappedAdHoc.id, isNot(originalAdHoc.id));
      expect(mappedAdHoc.id, contains('new-owner'));
      expect(mappedAdHoc.userId, 'new-owner');
      final adhocLog = migrated.logs.firstWhere((log) => log.id.isNotEmpty && log.taskId == null);
      expect(adhocLog.adHocId, mappedAdHoc.id);
      // session_id 是会话标识，不属于账号内实体引用，原样保留。
      expect(adhocLog.sessionId, 'session-2');
      final converted = migrated.logs.firstWhere(
        (log) => log.id.contains('log-converted'),
      );
      final mappedTask = migrated.tasks.single.id;
      expect(converted.taskId, mappedTask);
      expect(converted.adHocId, migrated.adHocLearnings.last.id);
      expect(migrated.adHocLearnings.last.convertedTaskId, mappedTask);
      // 容量覆盖按日期键/值保留（键不是账号实体引用）。
      expect(migrated.profile.dateCapacityOverrides, {
        '2026-10-22': 0,
        '2026-10-23': 90,
      });
      expect(migrated.profile.weekCapacityOverrides!.keys.single, '2026-10-19');
    });

    test('two accounts receive different entity ids', () {
      final a = forAccount(richData(), 'user-a');
      final b = forAccount(richData(), 'user-b');
      expect(
        a.adHocLearnings.map((row) => row.id).toSet().intersection(
          b.adHocLearnings.map((row) => row.id).toSet(),
        ),
        isEmpty,
      );
      expect(a.logs.firstWhere((log) => log.taskId == null).adHocId, isNot(
        b.logs.firstWhere((log) => log.taskId == null).adHocId,
      ));
    });
  });

  group('optimistic edit guards', () {
    test('changing any new field changes the serialized document', () {
      final base = richData();
      final before = jsonEncode(base.toJson());
      expect(
        jsonEncode(
          base.copyWith(
            profile: base.profile.copyWith(
              dateCapacityOverrides: {'2026-10-24': 30},
            ),
          ).toJson(),
        ),
        isNot(before),
      );
      expect(
        jsonEncode(
          base.copyWith(
            adHocLearnings: [
              ...base.adHocLearnings,
              _adHoc(id: 'adhoc-new', title: '新临时学习'),
            ],
          ).toJson(),
        ),
        isNot(before),
      );
      expect(
        jsonEncode(
          replaceLog(
            base,
            base.logs.first.copyWith(relation: TimeLogRelation.extra),
          ).toJson(),
        ),
        isNot(before),
      );
      expect(
        jsonEncode(
          replaceLog(base, base.logs.first.copyWith(sessionId: 'other')).toJson(),
        ),
        isNot(before),
      );
      expect(
        jsonEncode(
          replaceLog(base, base.logs.first.copyWith(adHocId: 'adhoc-photo'))
              .toJson(),
        ),
        isNot(before),
      );
      expect(
        jsonEncode(
          replaceLog(base, base.logs.first.copyWith(quotaMinutes: 5)).toJson(),
        ),
        isNot(before),
      );
      expect(
        jsonEncode(
          base.copyWith(
            profile: base.profile.copyWith(
              weekCapacityOverrides: {
                '2026-10-19': const WeekCapacityOverride(totalMinutes: 120),
              },
            ),
          ).toJson(),
        ),
        isNot(before),
      );
    });

    test('serialization is deterministic across encode/decode cycles', () {
      final data = richData();
      final first = jsonEncode(data.toJson());
      final second = jsonEncode(PlannerData.fromJson(data.toJson()).toJson());
      expect(second, first);
      expect(jsonEncode(PlannerData.fromJson(data.toJson()).toJson()), first);
    });
  });
}
