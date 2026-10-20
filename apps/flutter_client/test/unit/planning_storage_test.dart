import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:sjtu_study_planner_client/core/storage/local_database.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/storage/sembast_storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/merge_plans.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart'
    as day_ops;
import 'package:sjtu_study_planner_client/shared/models/api_models.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';
import '../support/planner_fixture.dart';

PlannerData strategyFixture() {
  final data = plannerFixture();
  return data.copyWith(
    planning: {
      'version': 1,
      'prompt_version': 'planning-1',
      'rules_version': 'rules-1',
      'detail_days': 14,
      'rolling': true,
      'route': [
        {
          'id': 'route',
          'title': 'Build a result',
          'item_ids': [data.tasks.single.id],
          'outcome': 'A runnable result',
          'check': 'Run and inspect',
        },
      ],
      'milestones': [],
      'assumptions': ['estimated'],
      'risks': [],
      'uncovered': [],
      'frozen_inputs': {'plan_revision': 4},
      'quality': {'issues': []},
    },
    tasks: [
      data.tasks.single.copyWith(
        planning: {
          'workload': {
            'components': [
              {
                'id': 'papers',
                'label': 'Past papers',
                'quantity': 1,
                'unit': 'paper',
                'minutes_per_unit': 30,
              },
            ],
            'source': 'confirmed scope',
            'confidence': 'medium',
            'calibration': 'Check after three attempts',
          },
          'activity': {
            'kind': 'recurring',
            'starts_on': '2026-10-17',
            'ends_on': '2026-11-12',
            'sessions_per_week': 3,
            'session_minutes': 30,
            'state': 'active',
          },
          'content_progress': {'completed_units': 1, 'confirmed': false},
        },
      ),
    ],
    blocks: [
      data.blocks.single.copyWith(activityInstanceId: 'task:2026-10-12:1'),
    ],
  );
}

void main() {
  test(
    'draft, storage, baseline, export and restore preserve strategy and instances',
    () async {
      final data = strategyFixture();
      final draft = ItemDraft(
        id: data.tasks.single.id,
        tagNames: const ['数学', '真题'],
        title: 'Practice',
        estimatedMinutes: 3780,
        deadline: '2026-11-12',
        planning: data.tasks.single.planning,
      );
      expect(ItemDraft.fromJson(draft.toJson()).planning, draft.planning);
      expect(parsePlannerJson(data.toJsonString()), data);
      final db = LocalDatabase(
        open: () => databaseFactoryMemory.openDatabase('planning-storage'),
      );
      final storage = SembastStorageRepository(database: db);
      try {
        await storage.save(
          'planning',
          data,
          StorageMetadata(revision: 4, base: data, pending: true),
        );
        final stored = await storage.load('planning');
        expect(stored.data, data);
        expect(stored.metadata.base, data);
        expect(parsePlannerJson((await storage.exportJson(data))!), data);
      } finally {
        await db.close();
      }
    },
  );
  test(
    'independent planning changes merge and competing strategy edits surface conflict',
    () {
      final base = strategyFixture();
      final local = base.copyWith(
        planning: {
          ...base.planning!,
          'risks': ['review needed'],
        },
      );
      final remote = base.copyWith(
        tasks: [
          base.tasks.single.copyWith(
            planning: {
              ...base.tasks.single.planning!,
              'content_progress': {'completed_units': 2, 'confirmed': false},
            },
          ),
        ],
      );
      final merged = mergePlans(base, local, remote);
      expect(merged.conflicts, isEmpty);
      expect(merged.data.planning!['risks'], ['review needed']);
      expect(
        merged
            .data
            .tasks
            .single
            .planning!['content_progress']['completed_units'],
        2,
      );
      final conflict = mergePlans(
        base,
        local,
        base.copyWith(
          planning: {
            ...base.planning!,
            'risks': ['different risk'],
          },
        ),
      );
      expect(conflict.conflicts, contains('学习路线与策略'));
      expect(
        conflict.data.blocks.single.activityInstanceId,
        base.blocks.single.activityInstanceId,
      );
    },
  );
  test(
    'explicit clears are written as null while legacy metadata remains absent',
    () {
      final base = strategyFixture();
      final cleared = base.copyWith(
        planning: null,
        tasks: [base.tasks.single.copyWith(planning: null)],
        blocks: [base.blocks.single.copyWith(activityInstanceId: null)],
      );
      final wire = plannerDocumentForSync(cleared, base);
      expect(wire.containsKey('planning'), isTrue);
      expect(wire['planning'], isNull);
      expect((wire['tasks'] as List).single['planning'], isNull);
      expect((wire['blocks'] as List).single['activity_instance_id'], isNull);
      expect(
        plannerDocumentForSync(plannerFixture(), null).containsKey('planning'),
        isFalse,
      );
    },
  );
  test('account restore remaps route and dependency references', () {
    final base = strategyFixture();
    final second = base.tasks.single.copyWith(
      id: 'dependent',
      planning: {
        'dependencies': [
          {'task_id': base.tasks.single.id, 'mode': 'confirmed'},
        ],
      },
    );
    final migrated = forAccount(
      base.copyWith(tasks: [...base.tasks, second]),
      'new-owner',
    );
    validatePlanner(migrated);
    expect((migrated.planning!['route'] as List).single['item_ids'], [
      migrated.tasks.first.id,
    ]);
    expect(
      (migrated.tasks.last.planning!['dependencies'] as List).single['task_id'],
      migrated.tasks.first.id,
    );
  });
  test('deleting a route-referenced item exports and reloads valid JSON', () {
    final base = strategyFixture();
    final next = day_ops.deleteTask(base, base.tasks.single.id);
    validatePlanner(next);
    expect(next.tasks, isEmpty);
    expect(next.planning!['route'], isEmpty, reason: '删空的阶段不留在元数据里');
    expect(next.planning!['needs_review'], isTrue);
    expect(next.planning!['quality'], isNull);
    expect(parsePlannerJson(next.toJsonString()), next, reason: '导出后重新读取仍通过校验');
    final wire = plannerDocumentForSync(next, base);
    expect(wire['planning'], isNotNull);
  });
}
