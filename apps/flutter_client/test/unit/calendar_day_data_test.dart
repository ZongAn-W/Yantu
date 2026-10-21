import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_day_data.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const _date = '2026-10-16';

TimeLog _log(
  PlannerData data, {
  required String id,
  required int minutes,
  String? taskId,
  String? adHocId,
  TimeLogRelation relation = TimeLogRelation.legacyUnknown,
  String? blockId,
  String? sessionId,
  String date = _date,
}) => TimeLog(
  id: id,
  userId: data.profile.userId,
  taskId: taskId,
  adHocId: adHocId,
  blockId: blockId,
  date: date,
  minutes: minutes,
  relation: relation,
  sessionId: sessionId,
  startedAt: '${date}T00:00:00.000Z',
  endedAt: '${date}T01:00:00.000Z',
  source: LogSource.timer,
);

AdHocLearning _temporary(
  PlannerData data, {
  String id = 'photography',
  String? convertedTaskId,
}) => AdHocLearning(
  id: id,
  userId: data.profile.userId,
  title: '摄影构图',
  createdAt: '${_date}T00:00:00.000Z',
  updatedAt: '${_date}T00:00:00.000Z',
  archived: convertedTaskId != null,
  convertedTaskId: convertedTaskId,
);

int _minutes(CalendarDayItem item, CalendarEffortKind kind) => item.efforts
    .where((effort) => effort.kind == kind)
    .fold(0, (sum, effort) => sum + effort.minutes);

/// Actual minutes the read-only calendar is allowed to display.
///
/// Temporary (ad-hoc) learning is retired in the client: historical rows for it
/// still exist in [PlannerData] and count in [dayExecutionSummary], but the
/// presentation layer ignores them.
int _displayedActual(PlannerData data, String date) => data.logs
    .where(
      (log) =>
          log.date == date &&
          log.relation != TimeLogRelation.adHoc &&
          log.adHocId == null,
    )
    .fold(0, (sum, log) => sum + log.minutes);

void _expectSharedTotals(PlannerData data, CalendarDayData day) {
  final execution = dayExecutionSummary(data, day.date);
  final displayedActual = _displayedActual(data, day.date);
  expect(day.plannedMinutes, execution.planned);
  expect(day.actualMinutes, displayedActual);
  // The only rows intentionally hidden are the historical ad-hoc records.
  expect(displayedActual, execution.actual - execution.adHoc);
  expect(
    day.items.fold<int>(0, (sum, item) => sum + item.plannedMinutes),
    execution.planned,
  );
  expect(
    day.items.fold<int>(0, (sum, item) => sum + item.actualMinutes),
    displayedActual,
  );
  expect(
    day.items.fold<int>(0, (sum, item) => sum + item.scheduledMinutes),
    execution.scheduled,
  );
  for (final item in day.items) {
    expect(
      item.efforts.fold<int>(0, (sum, effort) => sum + effort.minutes),
      item.actualMinutes,
    );
    expect(item.scheduledMinutes, lessThanOrEqualTo(item.plannedMinutes));
  }
}

void main() {
  group('shared read-only calendar day facts', () {
    test(
      'merges daily blocks, keeps plan/actual owners and ignores historical temporary rows',
      () {
        final base = plannerFixture();
        final first = base.tasks.single;
        final plannedOnly = first.copyWith(id: 'planned-only', title: '英语阅读');
        final unscheduled = first.copyWith(id: 'unscheduled', title: '额外复习');
        final data = base.copyWith(
          tasks: [first, plannedOnly, unscheduled],
          adHocLearnings: [_temporary(base)],
          blocks: [
            base.blocks.single.copyWith(durationMinutes: 30),
            base.blocks.single.copyWith(
              id: 'second',
              durationMinutes: 45,
              startMinute: 60,
            ),
            base.blocks.single.copyWith(
              id: 'planned-only-block',
              taskId: plannedOnly.id,
              durationMinutes: 60,
              startMinute: 90,
            ),
          ],
          logs: [
            _log(
              base,
              id: 'original',
              taskId: first.id,
              minutes: 40,
              relation: TimeLogRelation.scheduled,
            ),
            _log(
              base,
              id: 'unscheduled',
              taskId: unscheduled.id,
              minutes: 20,
              relation: TimeLogRelation.extra,
            ),
            _log(
              base,
              id: 'temporary',
              adHocId: 'photography',
              minutes: 15,
              relation: TimeLogRelation.adHoc,
            ),
          ],
        );
        final day = buildCalendarDayData(data, _date);
        expect(day.items, hasLength(3));
        expect(day.items.first.plannedMinutes, 75);
        expect(day.items[1].actualMinutes, 0);
        final extra = day.items.singleWhere(
          (item) => item.id == 'task:unscheduled',
        );
        expect(extra.plannedMinutes, 0);
        expect(_minutes(extra, CalendarEffortKind.unscheduled), 20);
        // The historical temporary-learning row is ignored: it creates no
        // owner and contributes no actual minute to the day.
        expect(day.items.any((item) => item.id.startsWith('adhoc:')), isFalse);
        expect(day.actualMinutes, 60);
        expect(day.scaleMinutes, 75);
        expect(day.riverScaleMinutes, 135);
        _expectSharedTotals(data, day);
      },
    );

    test(
      'extra learning stays extra while original quota is still unfilled',
      () {
        final base = plannerFixture();
        final first = base.tasks.single;
        final second = first.copyWith(id: 'unexecuted');
        final data = base.copyWith(
          tasks: [first, second],
          blocks: [
            base.blocks.single.copyWith(durationMinutes: 60),
            base.blocks.single.copyWith(
              id: 'other-block',
              taskId: second.id,
              durationMinutes: 60,
            ),
          ],
          logs: [
            _log(
              base,
              id: 'extra-first',
              taskId: first.id,
              minutes: 90,
              relation: TimeLogRelation.extra,
            ),
            _log(
              base,
              id: 'original',
              taskId: first.id,
              minutes: 20,
              relation: TimeLogRelation.scheduled,
            ),
          ],
        );
        final day = buildCalendarDayData(data, _date);
        final learned = day.items.singleWhere(
          (item) => item.id == 'task:${first.id}',
        );
        expect(learned.actualMinutes, 110);
        expect(learned.scheduledMinutes, 20);
        expect(_minutes(learned, CalendarEffortKind.extra), 90);
        expect(
          day.items
              .singleWhere((item) => item.id == 'task:unexecuted')
              .scheduledMinutes,
          0,
        );
        expect(day.scaleMinutes, 110);
        _expectSharedTotals(data, day);
      },
    );

    test(
      'converted temporary records are ignored like other ad-hoc history',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final data = base.copyWith(
          adHocLearnings: [_temporary(base, convertedTaskId: task.id)],
          logs: [
            // Both a converted row (task id + ad-hoc reference) and an old row
            // carrying only the conversion pointer are historical ad-hoc data.
            _log(
              base,
              id: 'converted',
              taskId: task.id,
              adHocId: 'photography',
              minutes: 25,
              relation: TimeLogRelation.adHoc,
            ),
            _log(
              base,
              id: 'pointer-only',
              adHocId: 'photography',
              minutes: 10,
              relation: TimeLogRelation.adHoc,
            ),
          ],
        );
        final day = buildCalendarDayData(data, _date);
        // Only the fixture's planned block remains; no ad-hoc minute is shown.
        expect(day.items, hasLength(1));
        expect(day.items.single.title, task.title);
        expect(day.items.single.plannedMinutes, 30);
        expect(day.items.single.actualMinutes, 0);
        expect(day.items.single.scheduledMinutes, 0);
        expect(day.items.single.efforts, isEmpty);
        expect(day.actualMinutes, 0);
        _expectSharedTotals(data, day);
      },
    );

    test('historical ad-hoc-only days render as empty read-only days', () {
      final base = plannerFixture();
      final data = base.copyWith(
        adHocLearnings: [_temporary(base)],
        blocks: [],
        logs: [
          _log(
            base,
            id: 'history',
            adHocId: 'photography',
            minutes: 25,
            relation: TimeLogRelation.adHoc,
          ),
        ],
      );
      final day = buildCalendarDayData(data, _date);
      expect(day.items, isEmpty);
      expect(day.plannedMinutes, 0);
      expect(day.actualMinutes, 0);
      expect(day.scaleMinutes, 1);
      expect(day.riverScaleMinutes, 1);
      _expectSharedTotals(data, day);
    });

    test(
      'relation segments sharing a session id are distinct learning facts',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final data = base.copyWith(
          logs: [
            _log(
              base,
              id: 'scheduled-part',
              taskId: task.id,
              minutes: 20,
              relation: TimeLogRelation.scheduled,
              sessionId: 'session',
            ),
            _log(
              base,
              id: 'extra-part',
              taskId: task.id,
              minutes: 10,
              relation: TimeLogRelation.extra,
              sessionId: 'session',
            ),
            _log(
              base,
              id: 'next-day',
              taskId: task.id,
              minutes: 8,
              relation: TimeLogRelation.extra,
              sessionId: 'session',
              date: '2026-10-17',
            ),
          ],
        );
        final day = buildCalendarDayData(data, _date);
        expect(day.actualMinutes, 30);
        expect(day.items.single.scheduledMinutes, 20);
        expect(_minutes(day.items.single, CalendarEffortKind.extra), 10);
        expect(buildCalendarDayData(data, '2026-10-17').actualMinutes, 8);
        _expectSharedTotals(data, day);
      },
    );

    test(
      'legacy inference and scheduled overflow match existing daily statistics',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final data = base.copyWith(
          logs: [
            _log(
              base,
              id: 'explicit',
              taskId: task.id,
              minutes: 20,
              relation: TimeLogRelation.scheduled,
            ),
            _log(base, id: 'inferred', taskId: task.id, minutes: 25),
            _log(base, id: 'unowned-old', minutes: 7),
            _log(
              base,
              id: 'lost-owner',
              taskId: 'deleted-task',
              minutes: 8,
              relation: TimeLogRelation.scheduled,
            ),
          ],
        );
        final day = buildCalendarDayData(data, _date);
        final item = day.items.singleWhere(
          (item) => item.id == 'task:${task.id}',
        );
        expect(item.scheduledMinutes, 30);
        expect(_minutes(item, CalendarEffortKind.legacyUnknown), 15);
        expect(
          day.items
              .singleWhere((item) => item.id == 'task:deleted-task')
              .actualMinutes,
          8,
        );
        _expectSharedTotals(data, day);

        final overflowData = base.copyWith(
          logs: [
            _log(
              base,
              id: 'overflow',
              taskId: task.id,
              minutes: 90,
              relation: TimeLogRelation.scheduled,
            ),
          ],
        );
        final overflow = buildCalendarDayData(overflowData, _date);
        expect(overflow.items.single.scheduledMinutes, 30);
        expect(
          _minutes(overflow.items.single, CalendarEffortKind.legacyUnknown),
          60,
        );
        expect(overflow.actualMinutes, 90);
        _expectSharedTotals(overflowData, overflow);
      },
    );

    test(
      'completed and archived lifecycle never creates actual study minutes',
      () {
        final base = plannerFixture();
        final fixtures = [
          base.tasks.single.copyWith(
            completedAt: '2026-10-16T00:00:00.000Z',
            completedMinutes: 999,
          ),
          base.tasks.single.copyWith(archived: true, completedMinutes: 999),
        ];
        for (final task in fixtures) {
          final data = base.copyWith(
            tasks: [task],
            blocks: [
              base.blocks.single.copyWith(
                status: BlockStatus.completed,
                completionStatus: CompletionStatus.completed,
                actualMinutes: 999,
              ),
            ],
            logs: [],
          );
          final day = buildCalendarDayData(data, _date);
          expect(day.items.single.plannedMinutes, 30);
          expect(day.items.single.actualMinutes, 0);
          expect(day.items.single.scheduledMinutes, 0);
          _expectSharedTotals(data, day);
        }
      },
    );

    test(
      'zero capacity, empty, actual-only and planned-only days retain finite scales',
      () {
        final base = plannerFixture();
        final zeroCapacity = base.copyWith(
          profile: base.profile.copyWith(
            weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 0},
          ),
        );
        expect(buildCalendarDayData(zeroCapacity, _date).actualMinutes, 35);
        final empty = buildCalendarDayData(
          base.copyWith(blocks: [], logs: []),
          _date,
        );
        expect(empty.items, isEmpty);
        expect(empty.scaleMinutes, 1);
        expect(empty.riverScaleMinutes, 1);
        final actualOnly = buildCalendarDayData(
          base.copyWith(blocks: []),
          _date,
        );
        expect(actualOnly.actualMinutes, 35);
        expect(actualOnly.plannedMinutes, 0);
        expect(actualOnly.scaleMinutes, 35);
        final plannedOnly = buildCalendarDayData(
          base.copyWith(logs: []),
          _date,
        );
        expect(plannedOnly.items.single.actualMinutes, 0);
        expect(plannedOnly.scaleMinutes, 30);
      },
    );

    test(
      'sort and task tags are stable across input orders and many objects',
      () {
        final base = plannerFixture();
        final tasks = [
          for (var i = 0; i < 32; i++)
            base.tasks.single.copyWith(
              id: 'task-${i.toString().padLeft(2, '0')}',
            ),
        ];
        final blocks = [
          for (var i = 0; i < 16; i++)
            base.blocks.single.copyWith(
              id: 'block-$i',
              taskId: tasks[i].id,
              startMinute: 100 - i,
            ),
        ];
        final logs = [
          for (var i = 16; i < 32; i++)
            _log(
              base,
              id: 'log-$i',
              taskId: tasks[i].id,
              minutes: i,
              relation: TimeLogRelation.extra,
            ),
        ];
        final data = base.copyWith(tasks: tasks, blocks: blocks, logs: logs);
        final first = buildCalendarDayData(data, _date);
        final reversed = buildCalendarDayData(
          data.copyWith(
            tasks: tasks.reversed.toList(),
            blocks: blocks.reversed.toList(),
            logs: logs.reversed.toList(),
          ),
          _date,
        );
        expect(
          first.items.map((item) => item.id),
          reversed.items.map((item) => item.id),
        );
        expect(first.items, hasLength(32));
        expect(first.items.first.id, 'task:task-15');
        expect(first.items[16].id, 'task:task-16');
        expect(
          first.items.every((item) => item.tagNames.contains('高数')),
          isTrue,
        );
        expect(() => first.items.clear(), throwsUnsupportedError);
        _expectSharedTotals(data, first);
      },
    );
  });
}
