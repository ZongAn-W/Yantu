import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart'
    as scheduler;
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/task_editing.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// A second tag and task so tag-aware behavior has real input.
PlannerData twoTaskFixture() {
  final base = plannerFixture();
  final second = base.tasks.single.copyWith(
    id: 'task-2',
    title: '真题训练',
    estimatedMinutes: 300,
    completedMinutes: 0,
    deadline: '2027-06-30',
    earliestDate: '2026-10-01',
  );
  final tag = Tag(
    id: 'english',
    userId: base.profile.userId,
    name: '英语',
    color: '#1f7a5a',
  );
  final block = base.blocks.single.copyWith(
    id: 'block-2',
    taskId: second.id,
    date: '2026-10-16',
    durationMinutes: 60,
  );
  return base.copyWith(
    tags: [...base.tags, tag],
    tasks: [...base.tasks, second],
    blocks: [...base.blocks, block],
  );
}

/// Two items linked through learning-route metadata, both with real records.
PlannerData planningRouteFixture() {
  final base = plannerFixture();
  final first = base.tasks.single;
  final second = first.copyWith(
    id: 'task-dependent',
    title: '真题训练',
    estimatedMinutes: 600,
    deadline: '2027-06-30',
    earliestDate: '2026-10-01',
  );
  final firstLog = base.logs.single;
  return base.copyWith(
    tasks: [first, second],
    blocks: [
      base.blocks.single,
      base.blocks.single.copyWith(id: 'block-2', taskId: second.id),
    ],
    logs: [
      firstLog,
      firstLog.copyWith(
        id: 'log-second',
        taskId: second.id,
        blockId: 'block-2',
        minutes: 20,
      ),
    ],
    planning: <String, dynamic>{
      'version': 1,
      'prompt_version': 'planning-1',
      'rules_version': 'rules-1',
      'detail_days': 14,
      'rolling': true,
      'route': [
        {
          'id': 'stage-foundation',
          'title': '基础阶段',
          'item_ids': [first.id, second.id],
          'outcome': '完成基础',
          'check': '自测',
        },
        {
          'id': 'stage-solo',
          'title': '单事项阶段',
          'item_ids': [first.id],
          'outcome': '完成单事项',
          'check': '检查',
        },
      ],
      'milestones': <dynamic>[],
      'assumptions': <dynamic>[],
      'risks': <dynamic>[],
      'uncovered': <dynamic>[],
      'quality': <String, dynamic>{'status': 'pass', 'issues': <dynamic>[]},
      'needs_review': false,
    },
  );
}

void main() {
  group('dayStats', () {
    test('sums planned blocks and logged minutes for one day', () {
      final data = plannerFixture();
      final stats = dayStats(data, '2026-10-16');
      expect(stats.planned, 30);
      expect(stats.actual, 35);
      expect(stats.remaining, 0);
      expect(stats.excess, 5);
      expect(stats.rate, 117);
      final empty = dayStats(data, '2026-10-17');
      expect(empty.planned, 0);
      expect(empty.actual, 0);
      expect(empty.rate, 0);
    });
  });

  group('groupDailyBlocks', () {
    test('groups per task and day and drops blocks without a task', () {
      final data = twoTaskFixture();
      final groups = groupDailyBlocks(
        data.blocks.where((block) => block.date == '2026-10-16'),
        data.tasks,
      );
      expect(groups, hasLength(2));
      expect(groups.map((group) => group.first.taskId).toSet(), {
        data.tasks.first.id,
        'task-2',
      });
      final orphan = data.blocks.first.copyWith(taskId: 'missing');
      expect(groupDailyBlocks([orphan], data.tasks), isEmpty);
    });

    test('orders each group by start minute', () {
      final data = plannerFixture();
      final block = data.blocks.single;
      final groups = groupDailyBlocks([
        block.copyWith(id: 'late', startMinute: 600),
        block.copyWith(id: 'early', startMinute: 0),
      ], data.tasks);
      expect(groups.single.map((item) => item.id), ['early', 'late']);
    });
  });

  group('task totals', () {
    test('day and total minutes read the study log', () {
      final data = plannerFixture();
      final taskId = data.tasks.single.id;
      expect(taskDayMinutes(data, taskId, '2026-10-16'), 35);
      expect(taskDayMinutes(data, taskId, '2026-10-17'), 0);
      expect(taskTotalMinutes(data, taskId), 35);
      expect(taskDayPlannedMinutes(data, taskId, '2026-10-16'), 30);
    });

    test('unscheduledTaskMinutes subtracts logged and already planned minutes', () {
      final base = plannerFixture();
      // Budget 300, nothing logged, 30 minutes already planned on 2026-10-16.
      final data = base.copyWith(
        tasks: [
          base.tasks.first.copyWith(estimatedMinutes: 300, completedMinutes: 0),
        ],
        logs: const [],
      );
      expect(
        unscheduledTaskMinutes(data, data.tasks.first, from: '2026-10-01'),
        270,
        reason: '300 分钟预算扣除已安排的 30 分钟',
      );
      // Past the planned day the block no longer counts towards the remainder.
      expect(
        unscheduledTaskMinutes(data, data.tasks.first, from: '2026-11-01'),
        300,
      );
      // Recorded time reduces the remainder once the task totals are refreshed,
      // which is what recording minutes does in the app; the fixture log has 35.
      final recorded = refreshTaskProgress(data.copyWith(logs: base.logs));
      expect(
        unscheduledTaskMinutes(
          recorded,
          recorded.tasks.first,
          from: '2026-10-01',
        ),
        235,
        reason: '300 - 35 已记录 - 30 已安排',
      );
    });
  });

  group('refreshTaskProgress', () {
    test('derives completed minutes from logs and keeps explicit completion', () {
      final data = plannerFixture();
      final task = data.tasks.single.copyWith(estimatedMinutes: 30);
      final refreshed = refreshTaskProgress(
        data.copyWith(tasks: [task]),
        updatedAt: '2026-10-17T00:00:00.000Z',
      );
      // The log records 35 minutes against a 30 minute budget, so it is capped.
      expect(refreshed.tasks.single.completedMinutes, 30);
      expect(refreshed.tasks.single.status, TaskStatus.inProgress);
      expect(refreshed.tasks.single.updatedAt, '2026-10-17T00:00:00.000Z');
    });

    test('a completed task stays completed unless it is corrected', () {
      final data = plannerFixture();
      final task = data.tasks.single.copyWith(
        status: TaskStatus.completed,
        completedMinutes: 15600,
      );
      final kept = refreshTaskProgress(data.copyWith(tasks: [task]));
      expect(kept.tasks.single.status, TaskStatus.completed);
      final corrected = refreshTaskProgress(
        data.copyWith(tasks: [task]),
        correctedTaskIds: [task.id],
      );
      expect(corrected.tasks.single.status, TaskStatus.inProgress);
    });
  });

  group('delete', () {
    test('deleteTask removes the task, its blocks and its logs', () {
      final data = plannerFixture();
      final id = data.tasks.single.id;
      final next = deleteTask(data, id);
      expect(next.tasks, isEmpty);
      expect(next.blocks, isEmpty);
      expect(next.logs, isEmpty);
      expect(next.tags, isNotEmpty);
    });
  });

  group('deleteTask with learning metadata', () {
    test('cleans route references and removes stages left empty', () {
      final data = planningRouteFixture();
      final deleted = data.tasks.first;
      final next = deleteTask(data, deleted.id);

      // Before the fix this throws '学习路线引用无效' from validatePlanner.
      validatePlanner(next);
      expect(next.tasks.map((task) => task.id), [data.tasks.last.id]);
      expect(next.blocks.map((block) => block.id), ['block-2']);
      expect(next.logs.map((log) => log.id), ['log-second']);
      expect(next.tags, data.tags);
      expect(next.fixedEvents, data.fixedEvents);
      expect(next.replanRuns, data.replanRuns, reason: '历史重排记录不被改写');
      final route = (next.planning!['route'] as List).cast<Map>();
      expect(route, hasLength(1), reason: '被删空的路线阶段移除，不制造空阶段元数据');
      expect(route.single['id'], 'stage-foundation');
      expect(route.single['item_ids'], [data.tasks.last.id]);
      expect(next.planning!['needs_review'], isTrue);
      expect(next.planning!['quality'], isNull);
      expect(
        parsePlannerJson(next.toJsonString()),
        next,
        reason: 'JSON 导出并重新读取仍然有效',
      );
    });

    test('refuses to delete an item other items depend on', () {
      final data = planningRouteFixture();
      final first = data.tasks.first;
      final second = data.tasks.last.copyWith(
        planning: <String, dynamic>{
          'dependencies': [
            {'task_id': first.id, 'mode': 'planned'},
          ],
        },
      );
      final withDependency = data.copyWith(tasks: [first, second]);
      expect(
        () => deleteTask(withDependency, first.id),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(contains('前置'), contains(second.title)),
          ),
        ),
        reason: '静默删除前置依赖会让后续事项意外解锁',
      );
    });

    test('keeps untracked items and unrelated history intact', () {
      final data = planningRouteFixture();
      final deleted = data.tasks.first;
      final next = deleteTask(data, deleted.id);
      expect(next.logs.where((log) => log.taskId == deleted.id), isEmpty);
      expect(
        next.logs.where((log) => log.taskId == data.tasks.last.id),
        hasLength(1),
      );
      expect(next.blocks.where((block) => block.taskId == deleted.id), isEmpty);
      expect((next.planning!['route'] as List), isNotEmpty);
    });

    test('legacy items without planning metadata delete as before', () {
      final data = plannerFixture();
      final next = deleteTask(data, data.tasks.single.id);
      expect(next.tasks, isEmpty);
      expect(next.blocks, isEmpty);
      expect(next.logs, isEmpty);
      expect(next.planning, isNull);
      validatePlanner(next);
      expect(parsePlannerJson(next.toJsonString()), next);
    });

    test('refuses a task that no longer exists instead of writing a no-op', () {
      final data = planningRouteFixture();
      expect(
        () => deleteTask(data, 'missing-task'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('不存在'),
          ),
        ),
      );
    });
  });

  group('calendar day', () {
    test('uses the study budget and warns when over capacity', () {
      final data = plannerFixture();
      final day = calendarDay(data, '2026-10-16');
      // 30 planned minutes are inside the 450 minute daily budget.
      expect(day.capacityWarning, isNull);
      expect(day.capacity, 480 - 30);
      expect(day.fixedMinutes, 0);
      final overloaded = data.copyWith(
        blocks: [data.blocks.single.copyWith(durationMinutes: 600)],
      );
      expect(calendarDay(overloaded, '2026-10-16').capacityWarning, isNotNull);
    });

    test('legacy fixed events are absent from the calendar', () {
      final data = plannerFixture();
      expect(fixedEventsOn(data, '2026-10-15'), isEmpty);
      expect(fixedEventsOn(data, '2026-10-16'), isEmpty);
      expect(fixedEventsOn(data, '2027-01-01'), isEmpty);
    });
  });

  group('scheduleTaskDay', () {
    test('splits the requested minutes into 30 minute blocks', () {
      final data = plannerFixture();
      final result = scheduleTaskDay(
        data,
        data.tasks.single.id,
        '2026-10-18',
        90,
      );
      final added = result.data.blocks
          .where((block) => block.date == '2026-10-18')
          .toList();
      expect(added, hasLength(3));
      expect(added.every((block) => block.durationMinutes == 30), isTrue);
      expect(result.outcome.placed, 90);
      expect(result.outcome.conflict, isFalse);
      expect(result.outcome.message, contains('2026-10-18'));
    });

    test('a remainder below the granularity is still scheduled', () {
      final data = plannerFixture();
      final result = scheduleTaskDay(
        data,
        data.tasks.single.id,
        '2026-10-18',
        45,
      );
      final added = result.data.blocks
          .where((block) => block.date == '2026-10-18')
          .toList();
      expect(added.map((block) => block.durationMinutes), [30, 15]);
      expect(result.outcome.placed, 45);
    });

    test('an empty request reports the remaining budget and refuses zero', () {
      final data = plannerFixture();
      final task = data.tasks.single.copyWith(
        estimatedMinutes: 120,
        completedMinutes: 0,
      );
      final prepared = data.copyWith(tasks: [task], blocks: [], logs: []);
      final result = scheduleTaskDay(prepared, task.id, '2026-10-18', null);
      expect(result.outcome.requested, 120);
      expect(result.outcome.remaining, 120);
      expect(
        () => scheduleTaskDay(prepared, task.id, '2026-10-18', 0),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a task past its deadline is marked conflicted instead of scheduled',
      () {
        final data = plannerFixture();
        final result = scheduleTaskDay(
          data,
          data.tasks.single.id,
          '2027-05-01',
          60,
        );
        expect(result.outcome.placed, 0);
        expect(result.outcome.conflict, isTrue);
        expect(result.data.tasks.single.status, TaskStatus.conflict);
        expect(result.outcome.message, contains('容量不足'));
      },
    );
  });

  group('moveTaskDay', () {
    test('refuses a day that already has recorded time', () {
      final data = plannerFixture();
      final result = moveTaskDay(data, data.blocks, '2026-10-18');
      expect(result.ok, isFalse);
      expect(result.error, contains('已记录用时'));
    });

    test('refuses fixed and completed blocks', () {
      final data = plannerFixture().copyWith(logs: []);
      final fixed = data.copyWith(
        blocks: [data.blocks.single.copyWith(isFixed: true)],
      );
      expect(
        moveTaskDay(fixed, fixed.blocks, '2026-10-18').error,
        contains('不可移动'),
      );
      final done = data.copyWith(
        blocks: [data.blocks.single.copyWith(status: BlockStatus.completed)],
      );
      expect(
        moveTaskDay(done, done.blocks, '2026-10-18').error,
        contains('不可移动'),
      );
    });

    test('moves a movable day and stamps the update time', () {
      final data = plannerFixture().copyWith(logs: []);
      final result = moveTaskDay(
        data,
        data.blocks,
        '2026-10-18',
        updatedAt: '2026-10-17T00:00:00.000Z',
      );
      expect(result.ok, isTrue);
      expect(result.blocks.single.date, '2026-10-18');
      expect(result.blocks.single.updatedAt, '2026-10-17T00:00:00.000Z');
    });

    test('refuses a date outside the task window', () {
      final data = plannerFixture().copyWith(logs: []);
      final result = moveTaskDay(data, data.blocks, '2027-05-01');
      expect(result.ok, isFalse);
      expect(result.error, isNotNull);
    });

    test('uses the current record instead of the passed snapshot', () {
      final data = plannerFixture().copyWith(logs: []);
      final stale = data.blocks.single;
      final current = data.copyWith(
        blocks: [stale.copyWith(durationMinutes: 60)],
      );
      final result = moveTaskDay(current, [stale], '2026-10-18');
      expect(result.ok, isTrue);
      expect(
        result.blocks.single.durationMinutes,
        60,
        reason: '按稳定 id 取当前记录，不使用对话框打开时的旧对象',
      );
    });

    test('refuses a snapshot whose record was deleted from the plan', () {
      final stale = plannerFixture().blocks.single;
      final data = plannerFixture().copyWith(logs: [], blocks: []);
      final result = moveTaskDay(data, [stale], '2026-10-18');
      expect(result.ok, isFalse);
      expect(result.error, contains('不存在'));
    });

    test('refuses a snapshot whose record moved to another day', () {
      final fixture = plannerFixture().copyWith(logs: []);
      final stale = fixture.blocks.single;
      final moved = fixture.copyWith(
        blocks: [stale.copyWith(date: '2026-10-17')],
      );
      final result = moveTaskDay(moved, [stale], '2026-10-18');
      expect(result.ok, isFalse);
      expect(result.error, contains('已变化'));
    });
  });

  group('task drafts', () {
    test('validation reports the same messages as the Web form', () {
      final data = plannerFixture();
      final blank = TaskDraft.blank(data, '2026-10-16');
      expect(validateTaskDraft(blank.copyWith(title: '  ')), '请填写事项名称');
      expect(
        validateTaskDraft(
          blank.copyWith(
            title: 'x',
            deadline: '2026-10-01',
            earliestDate: '2026-10-10',
          ),
        ),
        '截止日期不能早于开始日期',
      );
      expect(
        validateTaskDraft(
          blank.copyWith(title: 'x', estimatedMinutes: 60),
          completedMinutes: 120,
        ),
        '预计时长不能少于已完成时长',
      );
      expect(validateTaskDraft(blank.copyWith(title: 'x')), isNull);
    });

    test(
      'a task can be created with no tags and tag changes do not duplicate definitions',
      () {
        final data = plannerFixture();
        final draft = TaskDraft.blank(
          data,
          '2026-10-16',
        ).copyWith(title: '  线代强化  ', estimatedMinutes: 600);
        final next = applyTaskDraft(
          data,
          draft,
          taskId: 'new-task',
          updatedAt: '2026-10-17T00:00:00.000Z',
        );
        final created = next.tasks.last;
        expect(created.id, 'new-task');
        expect(created.title, '线代强化');
        expect(created.estimatedMinutes, 600);
        expect(created.completedMinutes, 0);
        expect(created.createdAt, '2026-10-17T00:00:00.000Z');
        // Updating task text leaves its optional tags unchanged.
        final again = applyTaskDraft(
          next,
          draft.copyWith(title: '线代真题'),
          taskId: next.tasks.first.id,
          updatedAt: '2026-10-18T00:00:00.000Z',
        );
        expect(again.tasks.first.tagIds, isEmpty);
        expect(again.tasks.first.title, '线代真题');
        expect(again.tasks.first.createdAt, data.tasks.single.createdAt);
      },
    );
  });

  group('completeTask', () {
    test('records minutes, drops future blocks and completes the task', () {
      final data = twoTaskFixture();
      final taskId = data.tasks.first.id;
      final next = completeTask(
        data,
        taskId,
        date: '2026-10-16',
        actualMinutes: 60,
      );
      final task = next.tasks.firstWhere((item) => item.id == taskId);
      expect(task.status, TaskStatus.completed);
      expect(task.completedMinutes, 60);
      expect(
        next.logs
            .where((log) => log.taskId == taskId)
            .fold<int>(0, (sum, log) => sum + log.minutes),
        60,
      );
      // The other task and its block are untouched.
      expect(next.blocks.any((block) => block.taskId == 'task-2'), isTrue);
    });

    test('a later planned block of the same task is removed', () {
      final data = plannerFixture();
      final future = data.blocks.single.copyWith(
        id: 'future',
        date: '2027-01-01',
      );
      final next = completeTask(
        data.copyWith(blocks: [...data.blocks, future], logs: []),
        data.tasks.single.id,
        date: '2026-10-16',
        actualMinutes: 0,
      );
      expect(next.blocks.any((block) => block.id == 'future'), isFalse);
      expect(next.tasks.single.status, TaskStatus.completed);
    });
  });

  group('learning relations and capacity dedup', () {
    const date = '2026-10-16';

    TimeLog scheduledLog(
      PlannerData data,
      String taskId,
      int minutes, {
      String id = 'scheduled-log',
      String? blockId,
    }) => TimeLog(
      id: id,
      userId: data.profile.userId,
      taskId: taskId,
      blockId: blockId,
      date: date,
      minutes: minutes,
      startedAt: '${date}T00:00:00.000Z',
      endedAt: '${date}T01:00:00.000Z',
      source: LogSource.timer,
      relation: TimeLogRelation.scheduled,
    );

    TimeLog extraLog(
      PlannerData data,
      String taskId,
      int minutes, {
      String id = 'extra-log',
    }) => TimeLog(
      id: id,
      userId: data.profile.userId,
      taskId: taskId,
      blockId: null,
      date: date,
      minutes: minutes,
      startedAt: '${date}T02:00:00.000Z',
      endedAt: '${date}T03:00:00.000Z',
      source: LogSource.timer,
      relation: TimeLogRelation.extra,
    );

    TimeLog adHocLog(
      PlannerData data,
      String adHocId,
      int minutes, {
      String id = 'ad-hoc-log',
      String? taskId,
    }) => TimeLog(
      id: id,
      userId: data.profile.userId,
      taskId: taskId,
      blockId: null,
      date: date,
      minutes: minutes,
      startedAt: '${date}T04:00:00.000Z',
      endedAt: '${date}T05:00:00.000Z',
      source: LogSource.timer,
      relation: TimeLogRelation.adHoc,
      adHocId: adHocId,
    );

    AdHocLearning adHocEntity(
      PlannerData data, {
      String id = 'photo',
      String title = '摄影构图',
      bool archived = false,
      String? convertedTaskId,
    }) => AdHocLearning(
      id: id,
      userId: data.profile.userId,
      title: title,
      createdAt: '2026-10-01T00:00:00.000Z',
      updatedAt: '2026-10-01T00:00:00.000Z',
      archived: archived,
      convertedTaskId: convertedTaskId,
    );

    test('capacity breakdown never bills an executed minute twice', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final data = base.copyWith(
        profile: base.profile.copyWith(
          weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 150},
          bufferMinutes: 30,
        ),
        fixedEvents: const [],
        blocks: [base.blocks.single.copyWith(durationMinutes: 60)],
        logs: [scheduledLog(base, task.id, 30), adHocLog(base, 'photo', 20)],
        adHocLearnings: [adHocEntity(base)],
      );
      final breakdown = dayCapacityBreakdown(data, date);
      expect(breakdown.capacity, 120);
      expect(breakdown.actual, 50);
      expect(breakdown.reserved, 30);
      expect(breakdown.available, 40);
      expect(breakdown.over, 0);
      expect(120 - 60 - 30 - 20, 10, reason: '旧的逐项扣减算法必须被容量分解测试排除');
    });

    test('extra study beyond capacity is kept and reported as over', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final data = base.copyWith(
        fixedEvents: const [],
        blocks: const [],
        logs: [extraLog(base, task.id, 500)],
      );
      final breakdown = dayCapacityBreakdown(data, date);
      expect(breakdown.planned, 0);
      expect(breakdown.actual, 500);
      expect(breakdown.reserved, 0);
      expect(breakdown.available, 0);
      expect(breakdown.over, 500 - 450);
    });

    test('extra study never offsets a missing scheduled item', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final second = task.copyWith(id: 'task-2', title: '真题训练');
      final data = base.copyWith(
        tasks: [task, second],
        blocks: [
          base.blocks.single.copyWith(durationMinutes: 60),
          base.blocks.single.copyWith(
            id: 'block-2',
            taskId: second.id,
            durationMinutes: 60,
          ),
        ],
        // Only the first task receives extra study; neither was scheduled.
        logs: [extraLog(base, task.id, 120)],
      );
      expect(scheduledMinutesForTaskDay(data, task.id, date), 0);
      expect(scheduledMinutesForTaskDay(data, second.id, date), 0);
      final stats = dayStats(data, date);
      expect(stats.actual, 120);
      expect(stats.scheduled, 0);
      expect(stats.remaining, 120);
      expect(stats.extra, 120);
    });

    test(
      'scheduled achievement is capped per task and never by total actual',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final second = task.copyWith(id: 'task-2', title: '真题训练');
        final data = base.copyWith(
          tasks: [task, second],
          blocks: [
            base.blocks.single.copyWith(durationMinutes: 60),
            base.blocks.single.copyWith(
              id: 'block-2',
              taskId: second.id,
              durationMinutes: 60,
            ),
          ],
          logs: [
            scheduledLog(base, task.id, 90),
            extraLog(base, second.id, 60),
          ],
        );
        expect(scheduledMinutesForTaskDay(data, task.id, date), 60);
        expect(scheduledMinutesForTaskDay(data, second.id, date), 0);
        final stats = dayStats(data, date);
        expect(stats.scheduled, 60);
        expect(stats.actual, 150);
        expect(stats.extra, 60);
      },
    );

    test('legacy logs are inferred only from reliable evidence', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final legacy = base.logs.single; // 35 minutes, block_id null, 30 planned
      // Task/day has blocks: limited inference up to the planned quota.
      final inferred = dayExecutionSummary(base, date);
      expect(inferred.scheduled, 30);
      expect(inferred.legacyUnknown, 5);
      expect(taskDayMinutes(base, task.id, date), 35);
      // A reliable block binding counts as scheduled (still capped by the plan).
      final linked = base.copyWith(
        logs: [legacy.copyWith(blockId: base.blocks.single.id)],
      );
      expect(dayExecutionSummary(linked, date).scheduled, 30);
      expect(dayExecutionSummary(linked, date).legacyUnknown, 5);
      // No blocks at all: unknown actual, never original-plan achievement.
      final unplanned = base.copyWith(blocks: const []);
      expect(dayExecutionSummary(unplanned, date).scheduled, 0);
      expect(dayExecutionSummary(unplanned, date).legacyUnknown, 35);
      // Extra logs of another task do not absorb the leftover quota.
      final withExtra = base.copyWith(
        logs: [
          legacy,
          extraLog(base, task.id, 90, id: 'extra-log'),
        ],
      );
      expect(dayExecutionSummary(withExtra, date).scheduled, 30);
      expect(dayExecutionSummary(withExtra, date).legacyUnknown, 5);
      expect(dayExecutionSummary(withExtra, date).extra, 90);
    });

    test(
      'temporary learning needs only a name and is reused by exact title',
      () {
        final base = plannerFixture();
        final created = upsertAdHocLearning(
          base,
          title: '  摄影构图  ',
          id: 'photo',
          updatedAt: '2026-10-17T00:00:00.000Z',
        );
        expect(created.created, isTrue);
        expect(created.learning.title, '摄影构图');
        expect(created.data.tasks, base.tasks, reason: '不为临时学习伪造正式事项');
        expect(created.data.blocks, base.blocks);
        expect(created.data.adHocLearnings, hasLength(1));
        final reused = upsertAdHocLearning(
          created.data,
          title: '摄影构图',
          id: 'another',
          updatedAt: '2026-10-18T00:00:00.000Z',
        );
        expect(reused.created, isFalse);
        expect(reused.learning.id, 'photo');
        expect(reused.data.adHocLearnings, hasLength(1));
        // Different names are different entities — never merged by similarity.
        final other = upsertAdHocLearning(
          reused.data,
          title: '摄影构图入门',
          id: 'photo-2',
          updatedAt: '2026-10-18T00:00:00.000Z',
        );
        expect(other.created, isTrue);
        expect(other.data.adHocLearnings, hasLength(2));
        expect(
          () => upsertAdHocLearning(
            base,
            title: '   ',
            id: 'x',
            updatedAt: '2026-10-18T00:00:00.000Z',
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'converting temporary learning keeps log ids, minutes and history',
      () {
        final base = plannerFixture();
        final data = base.copyWith(
          logs: [adHocLog(base, 'photo', 25)],
          adHocLearnings: [adHocEntity(base)],
        );
        final draft = TaskDraft.blank(
          data,
          date,
        ).copyWith(title: '摄影构图', estimatedMinutes: 120);
        final first = convertAdHocToTask(
          data,
          'photo',
          draft,
          taskId: 'converted-task',
          updatedAt: '2026-10-18T00:00:00.000Z',
        );
        final log = first.data.logs.single;
        expect(log.taskId, 'converted-task');
        expect(log.adHocId, 'photo');
        expect(log.relation, TimeLogRelation.adHoc);
        expect(log.minutes, 25);
        expect(
          first.data.logs.fold<int>(0, (sum, log) => sum + log.minutes),
          25,
        );
        expect(
          first.data.tasks.any((task) => task.id == 'converted-task'),
          isTrue,
        );
        final entity = first.data.adHocLearnings.single;
        expect(entity.archived, isTrue);
        expect(entity.convertedTaskId, 'converted-task');
        // Repeated confirmation is a no-op, not a second copy.
        final again = convertAdHocToTask(
          first.data,
          'photo',
          draft,
          taskId: 'converted-task',
        );
        expect(again.data.logs, first.data.logs);
        expect(again.data.adHocLearnings, first.data.adHocLearnings);
        expect(
          again.data.logs.fold<int>(0, (sum, log) => sum + log.minutes),
          25,
        );
      },
    );

    test('linking temporary learning to an existing item is idempotent', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final data = base.copyWith(
        logs: [adHocLog(base, 'photo', 20)],
        adHocLearnings: [adHocEntity(base)],
      );
      final linked = linkAdHocToTask(
        data,
        'photo',
        task.id,
        updatedAt: '2026-10-18T00:00:00.000Z',
      );
      expect(linked.taskId, task.id);
      expect(linked.data.logs.single.taskId, task.id);
      expect(linked.data.logs.single.relation, TimeLogRelation.adHoc);
      expect(linked.data.adHocLearnings.single.archived, isTrue);
      expect(linked.data.adHocLearnings.single.convertedTaskId, task.id);
      final again = linkAdHocToTask(linked.data, 'photo', task.id);
      expect(again.data.logs, linked.data.logs);
      expect(again.data.adHocLearnings, linked.data.adHocLearnings);
      expect(
        () => linkAdHocToTask(data, 'photo', 'missing-task'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'deleting a converted task keeps the archived history explainable',
      () {
        final base = plannerFixture();
        final data = base.copyWith(
          logs: [adHocLog(base, 'photo', 20)],
          adHocLearnings: [adHocEntity(base)],
        );
        final converted = convertAdHocToTask(
          data,
          'photo',
          TaskDraft.blank(
            data,
            date,
          ).copyWith(title: '摄影构图', estimatedMinutes: 120),
          taskId: 'converted-task',
        ).data;
        final deleted = deleteTask(converted, 'converted-task');
        expect(deleted.tasks.map((task) => task.id), [base.tasks.single.id]);
        expect(deleted.logs, isEmpty);
        expect(deleted.adHocLearnings.single.archived, isTrue);
        expect(deleted.adHocLearnings.single.convertedTaskId, isNull);
        validatePlanner(deleted);
      },
    );

    test('manual day review rebuilds only scheduled aggregates', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final extra = extraLog(base, task.id, 15);
      final adHoc = adHocLog(base, 'photo', 20);
      final manual = base.logs.single.copyWith(
        id: 'manual-total',
        taskId: task.id,
        blockId: null,
        minutes: 35,
        source: LogSource.manual,
      );
      final data = base.copyWith(
        logs: [manual, extra, adHoc],
        adHocLearnings: [adHocEntity(base)],
      );
      final next = scheduler.recordTaskDayMinutes(data, task.id, date, 40);
      // The temporary-learning record is untouched (task-less, different owner).
      expect(next.logs.where((log) => log.adHocId == 'photo'), hasLength(1));
      expect(
        next.logs.where((log) => log.adHocId == 'photo').single.minutes,
        20,
      );
      // The extra-study record is a real fact and must not be deleted or
      // double-counted by the manual day total.
      expect(
        next.logs.where((log) => log.relation == TimeLogRelation.extra),
        hasLength(1),
      );
      expect(taskDayMinutes(next, task.id, date), 40 + 15);
      expect(
        next.logs
            .where((log) => log.taskId == task.id)
            .fold<int>(
              0,
              (sum, log) =>
                  sum +
                  (log.relation == TimeLogRelation.extra ? 0 : log.minutes),
            ),
        40,
        reason: '手工当天合计只重建原定/手工语义，不叠加到加学记录上',
      );
      // Repeating the same manual total is idempotent.
      final again = scheduler.recordTaskDayMinutes(next, task.id, date, 40);
      expect(taskDayMinutes(again, task.id, date), 55);
      expect(
        again.logs.where((log) => log.relation == TimeLogRelation.extra),
        hasLength(1),
      );
    });
  });
}
