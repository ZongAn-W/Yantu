import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/task_editing.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// A second course and task so grouping, capacity and filters have real input.
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
  final subject = Subject(
    id: 'english',
    userId: base.profile.userId,
    name: '英语',
    color: '#1f7a5a',
    priority: 2,
  );
  final block = base.blocks.single.copyWith(
    id: 'block-2',
    taskId: second.id,
    date: '2026-10-16',
    durationMinutes: 60,
  );
  return base.copyWith(
    subjects: [...base.subjects, subject],
    tasks: [...base.tasks, second],
    blocks: [...base.blocks, block],
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
      expect(
        groups.map((group) => group.first.taskId).toSet(),
        {data.tasks.first.id, 'task-2'},
      );
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
          base.tasks.first.copyWith(
            estimatedMinutes: 300,
            completedMinutes: 0,
          ),
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
      final recorded = refreshTaskProgress(
        data.copyWith(logs: base.logs),
      );
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

  group('toggle and delete', () {
    test('setTaskDayCompletion rewrites only the given blocks', () {
      final data = twoTaskFixture();
      final blocks = data.blocks
          .where((block) => block.date == '2026-10-16')
          .toList();
      final completed = setTaskDayCompletion(
        data,
        blocks,
        true,
        updatedAt: '2026-10-17T00:00:00.000Z',
      );
      expect(
        completed.blocks.every(
          (block) => block.status == BlockStatus.completed,
        ),
        isTrue,
      );
      final reopened = setTaskDayCompletion(completed, blocks, false);
      expect(
        reopened.blocks.every((block) => block.status == BlockStatus.planned),
        isTrue,
      );
    });

    test('deleteTask removes the task, its blocks and its logs', () {
      final data = plannerFixture();
      final id = data.tasks.single.id;
      final next = deleteTask(data, id);
      expect(next.tasks, isEmpty);
      expect(next.blocks, isEmpty);
      expect(next.logs, isEmpty);
      expect(next.subjects, isNotEmpty);
    });
  });

  group('calendar day', () {
    test('subtracts the daily fixed events and warns when over capacity', () {
      final data = plannerFixture();
      final day = calendarDay(data, '2026-10-16');
      // 30 planned minutes are inside the 450 minute daily budget.
      expect(day.capacityWarning, isNull);
      expect(day.capacity, 480 - 30 - 60);
      expect(day.fixedMinutes, 60);
      final overloaded = data.copyWith(
        blocks: [
          data.blocks.single.copyWith(durationMinutes: 600),
        ],
      );
      expect(calendarDay(overloaded, '2026-10-16').capacityWarning, isNotNull);
    });

    test('fixedEventsOn returns repeating events in start order', () {
      final data = plannerFixture();
      expect(fixedEventsOn(data, '2026-10-15'), isEmpty);
      expect(fixedEventsOn(data, '2026-10-16'), hasLength(1));
      expect(fixedEventsOn(data, '2027-01-01'), hasLength(1));
    });
  });

  group('scheduleTaskDay', () {
    test('splits the requested minutes into 30 minute blocks', () {
      final data = plannerFixture();
      final result = scheduleTaskDay(data, data.tasks.single.id, '2026-10-18', 90);
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
      final result = scheduleTaskDay(data, data.tasks.single.id, '2026-10-18', 45);
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
      final result = scheduleTaskDay(
        prepared,
        task.id,
        '2026-10-18',
        null,
      );
      expect(result.outcome.requested, 120);
      expect(result.outcome.remaining, 120);
      expect(
        () => scheduleTaskDay(prepared, task.id, '2026-10-18', 0),
        throwsA(isA<StateError>()),
      );
    });

    test('a task past its deadline is marked conflicted instead of scheduled', () {
      final data = plannerFixture();
      final result = scheduleTaskDay(
        data,
        data.tasks.single.id,
        '2027-05-01',
        60,
      );
      expect(result.outcome.placed, 0);
      expect(result.outcome.conflict, isTrue);
      expect(
        result.data.tasks.single.status,
        TaskStatus.conflict,
      );
      expect(result.outcome.message, contains('容量不足'));
    });
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
      expect(moveTaskDay(fixed, fixed.blocks, '2026-10-18').error, contains('不可移动'));
      final done = data.copyWith(
        blocks: [
          data.blocks.single.copyWith(status: BlockStatus.completed),
        ],
      );
      expect(moveTaskDay(done, done.blocks, '2026-10-18').error, contains('不可移动'));
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
  });

  group('task drafts', () {
    test('validation reports the same messages as the Web form', () {
      final data = plannerFixture();
      final blank = TaskDraft.blank(data, '2026-10-16');
      expect(validateTaskDraft(blank.copyWith(title: '  ')), '请填写事项名称和课程');
      expect(
        validateTaskDraft(
          blank.copyWith(title: 'x', deadline: '2026-10-01', earliestDate: '2026-10-10'),
        ),
        '截止日期不能早于开始日期',
      );
      expect(
        validateTaskDraft(blank.copyWith(title: 'x', estimatedMinutes: 60), completedMinutes: 120),
        '预计时长不能少于已完成时长',
      );
      expect(validateTaskDraft(blank.copyWith(title: 'x')), isNull);
    });

    test('a new course name creates a subject and a new task', () {
      final data = plannerFixture();
      final draft = TaskDraft.blank(data, '2026-10-16').copyWith(
        title: '  线代强化  ',
        subjectId: 'linear-algebra',
        estimatedMinutes: 600,
      );
      final next = applyTaskDraft(
        data,
        draft,
        taskId: 'new-task',
        updatedAt: '2026-10-17T00:00:00.000Z',
      );
      expect(next.subjects.map((subject) => subject.id), contains('linear-algebra'));
      final created = next.tasks.last;
      expect(created.id, 'new-task');
      expect(created.title, '线代强化');
      expect(created.estimatedMinutes, 600);
      expect(created.completedMinutes, 0);
      expect(created.createdAt, '2026-10-17T00:00:00.000Z');
      // An existing subject id is reused instead of duplicated.
      final again = applyTaskDraft(
        next,
        draft.copyWith(title: '线代真题'),
        taskId: next.tasks.first.id,
        updatedAt: '2026-10-18T00:00:00.000Z',
      );
      expect(
        again.subjects.where((subject) => subject.id == 'linear-algebra'),
        hasLength(1),
      );
      expect(again.tasks.first.subjectId, 'linear-algebra');
      expect(again.tasks.first.title, '线代真题');
      expect(again.tasks.first.createdAt, data.tasks.single.createdAt);
    });

    test('resolveSubjectId maps a typed course name to its id', () {
      final data = plannerFixture();
      expect(resolveSubjectId(data, '高数'), 'calculus');
      expect(resolveSubjectId(data, ' 政治 '), '政治');
    });
  });

  group('fixed events', () {
    test('daily mode accepts an overlapping event', () {
      final data = plannerFixture();
      final event = FixedEvent(
        id: 'event-1',
        userId: data.profile.userId,
        title: '晚课',
        date: '2026-10-16',
        startMinute: 720,
        durationMinutes: 60,
        kind: FixedEventKind.course,
        repeat: EventRepeat.none,
        createdAt: '2026-10-16T00:00:00.000Z',
        updatedAt: '2026-10-16T00:00:00.000Z',
      );
      expect(fixedEventConflict(data, event), isNull);
      expect(addFixedEvent(data, event).fixedEvents, hasLength(2));
    });

    test('timed mode refuses an event that overlaps a study block', () {
      final data = plannerFixture();
      final timed = data.copyWith(
        profile: data.profile.copyWith(storedPlanningMode: PlanningMode.timed),
        blocks: [data.blocks.single.copyWith(startMinute: 600)],
      );
      final event = FixedEvent(
        id: 'event-2',
        userId: timed.profile.userId,
        title: '晚课',
        date: '2026-10-16',
        startMinute: 615,
        durationMinutes: 60,
        kind: FixedEventKind.course,
        repeat: EventRepeat.none,
        createdAt: '2026-10-16T00:00:00.000Z',
        updatedAt: '2026-10-16T00:00:00.000Z',
      );
      expect(fixedEventConflict(timed, event), contains('学习时间块'));
      expect(() => addFixedEvent(timed, event), throwsA(isA<StateError>()));
      final clear = event.copyWith(date: '2026-10-17');
      expect(fixedEventConflict(timed, clear), isNull);
    });
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
        next.logs.where((log) => log.taskId == taskId).fold<int>(0, (sum, log) => sum + log.minutes),
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
}
