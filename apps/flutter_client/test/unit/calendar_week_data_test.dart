import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_day_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_week_data.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const _monday = '2026-10-19';
const _tuesday = '2026-10-20';
const _wednesday = '2026-10-21';
const _thursday = '2026-10-22';
const _friday = '2026-10-23';
const _saturday = '2026-10-24';
const _sunday = '2026-10-25';

ScheduleBlock _block(
  PlannerData data, {
  required String id,
  required String taskId,
  required String date,
  int minutes = 60,
  int startMinute = 0,
}) => ScheduleBlock(
  id: id,
  userId: data.profile.userId,
  taskId: taskId,
  date: date,
  startMinute: startMinute,
  durationMinutes: minutes,
  actualMinutes: 0,
  isFixed: false,
  status: BlockStatus.planned,
  createdAt: '${date}T00:00:00+08:00',
  updatedAt: '${date}T00:00:00+08:00',
);

TimeLog _log(
  PlannerData data, {
  required String id,
  required int minutes,
  required String date,
  String? taskId,
  String? adHocId,
  String? blockId,
  String? sessionId,
  TimeLogRelation relation = TimeLogRelation.legacyUnknown,
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
  startedAt: '${date}T00:00:00+08:00',
  endedAt: '${date}T01:00:00+08:00',
  source: LogSource.timer,
);

AdHocLearning _temporary(
  PlannerData data, {
  String id = 'photo',
  String title = '摄影构图',
  String? convertedTaskId,
}) => AdHocLearning(
  id: id,
  userId: data.profile.userId,
  title: title,
  createdAt: '${data.profile.userId}-created',
  updatedAt: '${data.profile.userId}-updated',
  archived: convertedTaskId != null,
  convertedTaskId: convertedTaskId,
);

int _effortMinutes(CalendarDayItem item, CalendarEffortKind kind) => item
    .efforts
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

/// Every week total must reconcile with the existing daily domain statistics,
/// the shared layers and the course legend. This is the contract both week
/// charts and the detail panel consume. Historical ad-hoc records are the only
/// rows deliberately missing from the displayed actual minutes.
void _expectWeekReconciles(PlannerData data, CalendarWeekData week) {
  expect(week.days, hasLength(7));
  var planned = 0;
  var actual = 0;
  var maximum = 0;
  for (final weekDay in week.days) {
    final execution = dayExecutionSummary(data, weekDay.date);
    final displayedActual = _displayedActual(data, weekDay.date);
    expect(weekDay.plannedMinutes, execution.planned);
    expect(weekDay.actualMinutes, displayedActual);
    expect(displayedActual, execution.actual - execution.adHoc);
    expect(
      weekDay.day.items.fold<int>(0, (sum, item) => sum + item.plannedMinutes),
      execution.planned,
    );
    expect(
      weekDay.day.items.fold<int>(0, (sum, item) => sum + item.actualMinutes),
      displayedActual,
    );
    for (final item in weekDay.day.items) {
      expect(
        item.efforts.fold<int>(0, (sum, effort) => sum + effort.minutes),
        item.actualMinutes,
      );
      expect(item.scheduledMinutes, lessThanOrEqualTo(item.plannedMinutes));
    }
    // The stacked mountain layers must sum to the same actual minutes per day.
    var layerTotal = 0;
    for (final layer in week.layers) {
      layerTotal += layer.minutesOn(weekDay.index);
    }
    expect(layerTotal, displayedActual);
    // Per-day classification totals are identical in items and layers.
    final itemKinds = <CalendarEffortKind, int>{};
    for (final item in weekDay.day.items) {
      for (final effort in item.efforts) {
        itemKinds[effort.kind] = (itemKinds[effort.kind] ?? 0) + effort.minutes;
      }
    }
    for (final kind in CalendarEffortKind.values) {
      final fromLayers = week.layers
          .where((layer) => layer.kind == kind)
          .fold<int>(0, (sum, layer) => sum + layer.minutesOn(weekDay.index));
      expect(fromLayers, itemKinds[kind] ?? 0, reason: '${weekDay.date} $kind');
    }
    // Both charts render the same canonical item order.
    expect(
      week.itemsFor(weekDay.date).map((item) => item.id),
      buildCalendarDayData(data, weekDay.date).items.map((item) => item.id),
    );
    planned += execution.planned;
    actual += displayedActual;
    maximum = math.max(
      maximum,
      math.max(weekDay.plannedMinutes, weekDay.actualMinutes),
    );
  }
  expect(week.plannedMinutes, planned);
  expect(week.actualMinutes, actual);
  expect(week.scaleMinutes, math.max(1, maximum));
  // Course legend totals and layer totals are the same facts.
  expect(
    week.courses.fold<int>(0, (sum, course) => sum + course.plannedMinutes),
    planned,
  );
  expect(
    week.courses.fold<int>(0, (sum, course) => sum + course.actualMinutes),
    actual,
  );
  expect(
    week.layers.fold<int>(0, (sum, layer) => sum + layer.totalMinutes),
    actual,
  );
  for (final entry in week.minutesByKind.entries) {
    expect(
      week.layers
          .where((layer) => layer.kind == entry.key)
          .fold<int>(0, (sum, layer) => sum + layer.totalMinutes),
      entry.value,
    );
  }
  // A course's actual minutes equal its layer totals, so area stacking and the
  // mirror's item segments cannot disagree about ownership.
  for (final course in week.courses) {
    expect(
      week.layers
          .where((layer) => layer.subjectId == course.subjectId)
          .fold<int>(0, (sum, layer) => sum + layer.totalMinutes),
      course.actualMinutes,
    );
  }
}

void main() {
  group('Shanghai Monday–Sunday week window', () {
    test(
      'anchors any date of the week to its Monday and keeps seven dates',
      () {
        expect(calendarWeekStart(_monday), _monday);
        expect(calendarWeekStart(_thursday), _monday);
        expect(calendarWeekStart(_sunday), _monday);
        expect(calendarWeekEnd(_thursday), _sunday);
        expect(calendarWeekDates(_wednesday), [
          _monday,
          _tuesday,
          _wednesday,
          _thursday,
          _friday,
          _saturday,
          _sunday,
        ]);
      },
    );

    test('crosses month and year boundaries without dropping a day', () {
      expect(calendarWeekDates('2026-10-29'), [
        '2026-10-26',
        '2026-10-27',
        '2026-10-28',
        '2026-10-29',
        '2026-10-30',
        '2026-10-31',
        '2026-11-01',
      ]);
      expect(calendarWeekStart('2027-01-01'), '2026-12-28');
      expect(calendarWeekDates('2027-01-01'), [
        '2026-12-28',
        '2026-12-29',
        '2026-12-30',
        '2026-12-31',
        '2027-01-01',
        '2027-01-02',
        '2027-01-03',
      ]);
      expect(weekRangeLabel('2026-10-19'), '10月19日–25日');
      expect(weekRangeLabel('2026-10-26'), '10月26日 – 11月1日');
      expect(weekRangeLabel('2026-12-28'), '2026年12月28日 – 2027年1月3日');
      expect(weekSemanticRange('2026-12-28'), '12月28日 周一至1月3日 周日');
    });

    test('uses the Asia/Shanghai date at the UTC week boundary', () {
      // 2026-10-18T15:59Z is Sunday 23:59 in Shanghai.
      expect(shanghaiToday(DateTime.utc(2026, 10, 18, 15, 59)), '2026-10-18');
      expect(calendarWeekStart('2026-10-18'), '2026-10-12');
      // 2026-10-18T16:00Z is Monday 00:00 in Shanghai: a new week, new month later.
      expect(shanghaiToday(DateTime.utc(2026, 10, 18, 16)), _monday);
      expect(calendarWeekStart(_monday), _monday);
      expect(
        calendarWeekDates(shanghaiToday(DateTime.utc(2026, 10, 18, 16))).last,
        _sunday,
      );
    });

    test('empty week keeps a finite shared scale and no layers', () {
      final base = plannerFixture();
      final week = buildCalendarWeekData(
        base.copyWith(blocks: [], logs: []),
        _thursday,
      );
      expect(week.isEmpty, isTrue);
      expect(week.scaleMinutes, 1);
      expect(week.layers, isEmpty);
      expect(week.courses, isEmpty);
      expect(week.plannedMinutes, 0);
      expect(week.actualMinutes, 0);
      expect(week.days, hasLength(7));
    });
  });

  group('shared week facts', () {
    test('totals, owners, classifications and layers reconcile for all days', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final plannedOnly = task.copyWith(id: 'planned-only', title: '英语阅读');
      final unscheduled = task.copyWith(id: 'unscheduled', title: '额外复习');
      final over = task.copyWith(id: 'over-plan', title: '超计划事项');
      final data = base.copyWith(
        tasks: [task, plannedOnly, unscheduled, over],
        adHocLearnings: [_temporary(base)],
        blocks: [
          _block(base, id: 'b1', taskId: task.id, date: _monday, minutes: 60),
          _block(base, id: 'b2', taskId: task.id, date: _tuesday, minutes: 90),
          _block(
            base,
            id: 'b3',
            taskId: plannedOnly.id,
            date: _wednesday,
            minutes: 45,
          ),
          _block(base, id: 'b4', taskId: over.id, date: _sunday, minutes: 30),
        ],
        logs: [
          _log(
            base,
            id: 'l1',
            taskId: task.id,
            date: _monday,
            minutes: 40,
            relation: TimeLogRelation.scheduled,
          ),
          _log(
            base,
            id: 'l2',
            taskId: task.id,
            date: _tuesday,
            minutes: 20,
            relation: TimeLogRelation.scheduled,
          ),
          _log(
            base,
            id: 'l3',
            taskId: task.id,
            date: _tuesday,
            minutes: 30,
            relation: TimeLogRelation.extra,
          ),
          _log(
            base,
            id: 'l4',
            taskId: unscheduled.id,
            date: _thursday,
            minutes: 25,
            relation: TimeLogRelation.extra,
          ),
          _log(
            base,
            id: 'l5',
            adHocId: 'photo',
            date: _friday,
            minutes: 15,
            relation: TimeLogRelation.adHoc,
          ),
          _log(
            base,
            id: 'l6',
            taskId: over.id,
            date: _sunday,
            minutes: 30,
            relation: TimeLogRelation.scheduled,
          ),
          _log(
            base,
            id: 'l7',
            taskId: over.id,
            date: _sunday,
            minutes: 60,
            relation: TimeLogRelation.extra,
          ),
          _log(
            base,
            id: 'l8',
            taskId: over.id,
            date: _sunday,
            minutes: 20,
            relation: TimeLogRelation.scheduled,
          ),
        ],
      );
      final week = buildCalendarWeekData(data, _thursday);
      expect(week.weekStart, _monday);
      expect(week.weekEnd, _sunday);
      _expectWeekReconciles(data, week);

      expect(
        [for (final day in week.days) day.plannedMinutes],
        [60, 90, 45, 0, 0, 0, 30],
      );
      expect(
        [for (final day in week.days) day.actualMinutes],
        [40, 50, 0, 25, 0, 0, 110],
      );
      expect(week.plannedMinutes, 225);
      expect(week.actualMinutes, 225);
      expect(week.scaleMinutes, 110);

      final tuesday = week.itemsFor(_tuesday).single;
      expect(tuesday.plannedMinutes, 90);
      expect(tuesday.actualMinutes, 50);
      expect(tuesday.scheduledMinutes, 20);
      expect(_effortMinutes(tuesday, CalendarEffortKind.scheduled), 20);
      expect(_effortMinutes(tuesday, CalendarEffortKind.extra), 30);

      final unscheduledItem = week.itemsFor(_thursday).single;
      expect(unscheduledItem.id, 'task:${unscheduled.id}');
      expect(unscheduledItem.plannedMinutes, 0);
      expect(
        _effortMinutes(unscheduledItem, CalendarEffortKind.unscheduled),
        25,
      );

      // Friday carried only a historical temporary-learning row: it is an empty
      // day and no such effort kind or layer may exist for it.
      expect(week.itemsFor(_friday), isEmpty);
      expect(week.days[4].actualMinutes, 0);
      expect(week.days[4].day.items, isEmpty);

      // Over-plan minutes are kept in full and the overflow stays unclassified.
      final overItem = week.itemsFor(_sunday).single;
      expect(overItem.plannedMinutes, 30);
      expect(overItem.actualMinutes, 110);
      expect(overItem.scheduledMinutes, 30);
      expect(_effortMinutes(overItem, CalendarEffortKind.scheduled), 30);
      expect(_effortMinutes(overItem, CalendarEffortKind.extra), 60);
      expect(_effortMinutes(overItem, CalendarEffortKind.legacyUnknown), 20);
      expect(week.minutesByKind[CalendarEffortKind.scheduled], 90);
      expect(week.minutesByKind[CalendarEffortKind.extra], 90);
      expect(week.minutesByKind[CalendarEffortKind.unscheduled], 25);
      expect(week.minutesByKind[CalendarEffortKind.legacyUnknown], 20);
      expect(
        week.minutesByKind.values.fold<int>(0, (sum, value) => sum + value),
        week.actualMinutes,
      );
    });

    test(
      'plan-only, actual-only, blank and zero-capacity days keep their slot',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final data = base.copyWith(
          tasks: [
            task,
            task.copyWith(id: 'actual-only', title: '仅实学事项'),
          ],
          // Zero capacity: real learning must still be displayed as a fact.
          profile: base.profile.copyWith(
            weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 0},
          ),
          blocks: [
            _block(base, id: 'only-plan', taskId: task.id, date: _monday),
          ],
          logs: [
            _log(
              base,
              id: 'only-actual',
              taskId: 'actual-only',
              date: _wednesday,
              minutes: 45,
              relation: TimeLogRelation.extra,
            ),
          ],
        );
        final week = buildCalendarWeekData(data, _monday);
        _expectWeekReconciles(data, week);
        expect(week.days[0].plannedMinutes, 60);
        expect(week.days[0].actualMinutes, 0);
        expect(week.days[1].plannedMinutes, 0);
        expect(week.days[1].actualMinutes, 0);
        expect(week.days[2].plannedMinutes, 0);
        expect(week.days[2].actualMinutes, 45);
        expect(week.days[3].day.items, isEmpty);
        expect(week.days[6].day.items, isEmpty);
        expect(week.plannedMinutes, 60);
        expect(week.actualMinutes, 45);
        expect(week.scaleMinutes, 60);
        // An existing item without a block that day is classified as unscheduled.
        expect(
          _effortMinutes(
            week.itemsFor(_wednesday).single,
            CalendarEffortKind.unscheduled,
          ),
          45,
        );
      },
    );

    test('extra study stays extra while the original quota is unfilled', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final data = base.copyWith(
        blocks: [
          _block(base, id: 'b1', taskId: task.id, date: _monday, minutes: 90),
        ],
        logs: [
          _log(
            base,
            id: 'scheduled',
            taskId: task.id,
            date: _monday,
            minutes: 20,
            relation: TimeLogRelation.scheduled,
          ),
          _log(
            base,
            id: 'extra',
            taskId: task.id,
            date: _monday,
            minutes: 30,
            relation: TimeLogRelation.extra,
          ),
        ],
      );
      final week = buildCalendarWeekData(data, _monday);
      _expectWeekReconciles(data, week);
      final item = week.itemsFor(_monday).single;
      expect(item.plannedMinutes, 90);
      expect(item.scheduledMinutes, 20);
      expect(item.actualMinutes, 50);
      expect(_effortMinutes(item, CalendarEffortKind.scheduled), 20);
      expect(_effortMinutes(item, CalendarEffortKind.extra), 30);
    });

    test(
      'unscheduled existing items stay visible while temporary learning is ignored',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final other = task.copyWith(
          id: 'existing-unscheduled',
          title: '当天未排程的已有事项',
        );
        final data = base.copyWith(
          tasks: [task, other],
          adHocLearnings: [_temporary(base)],
          blocks: [
            _block(base, id: 'b1', taskId: task.id, date: _monday, minutes: 60),
          ],
          logs: [
            _log(
              base,
              id: 'scheduled',
              taskId: task.id,
              date: _monday,
              minutes: 30,
              relation: TimeLogRelation.scheduled,
            ),
            _log(
              base,
              id: 'unscheduled',
              taskId: other.id,
              date: _tuesday,
              minutes: 20,
              relation: TimeLogRelation.extra,
            ),
            _log(
              base,
              id: 'temporary',
              adHocId: 'photo',
              date: _wednesday,
              minutes: 15,
              relation: TimeLogRelation.adHoc,
            ),
          ],
        );
        final week = buildCalendarWeekData(data, _monday);
        _expectWeekReconciles(data, week);
        final unscheduled = week.itemsFor(_tuesday).single;
        expect(unscheduled.id, 'task:${other.id}');
        expect(unscheduled.plannedMinutes, 0);
        expect(_effortMinutes(unscheduled, CalendarEffortKind.unscheduled), 20);
        // The Wednesday temporary-learning row is retired: that day is empty
        // and contributes nothing to the week actual minutes.
        expect(week.itemsFor(_wednesday), isEmpty);
        expect(week.days[2].actualMinutes, 0);
        expect(week.actualMinutes, 50);
        expect(week.minutesByKind[CalendarEffortKind.unscheduled], 20);
        expect(
          week.minutesByKind.values.fold<int>(0, (sum, value) => sum + value),
          50,
        );
      },
    );

    test('converted temporary records are ignored by the week snapshot', () {
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
            adHocId: 'photo',
            date: _monday,
            minutes: 25,
            relation: TimeLogRelation.adHoc,
          ),
          _log(
            base,
            id: 'pointer-only',
            adHocId: 'photo',
            date: _tuesday,
            minutes: 10,
            relation: TimeLogRelation.adHoc,
          ),
        ],
      );
      final week = buildCalendarWeekData(data, _monday);
      _expectWeekReconciles(data, week);
      expect(week.actualMinutes, 0);
      expect(week.isEmpty, isTrue);
      expect(week.itemsFor(_monday), isEmpty);
      expect(week.itemsFor(_tuesday), isEmpty);
      expect(week.layers, isEmpty);
      expect(week.minutesByKind, isEmpty);
    });

    test(
      'legal session segments and cross-day splits are not deduplicated',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final data = base.copyWith(
          logs: [
            _log(
              base,
              id: 'scheduled-part',
              taskId: task.id,
              date: _monday,
              minutes: 20,
              relation: TimeLogRelation.scheduled,
              sessionId: 'session',
            ),
            _log(
              base,
              id: 'extra-part',
              taskId: task.id,
              date: _monday,
              minutes: 10,
              relation: TimeLogRelation.extra,
              sessionId: 'session',
            ),
            _log(
              base,
              id: 'next-day',
              taskId: task.id,
              date: _tuesday,
              minutes: 8,
              relation: TimeLogRelation.extra,
              sessionId: 'session',
            ),
            _log(
              base,
              id: 'next-day-second-segment',
              taskId: task.id,
              date: _tuesday,
              minutes: 7,
              relation: TimeLogRelation.extra,
              sessionId: 'session',
            ),
          ],
        );
        final week = buildCalendarWeekData(data, _monday);
        _expectWeekReconciles(data, week);
        expect(week.days[0].actualMinutes, 30);
        expect(week.days[1].actualMinutes, 15);
        expect(week.actualMinutes, 45);
        final monday = week.itemsFor(_monday).single;
        // The domain cannot credit original-plan achievement without a plan on
        // that day, but every segment minute is still counted exactly once.
        expect(_effortMinutes(monday, CalendarEffortKind.legacyUnknown), 20);
        expect(_effortMinutes(monday, CalendarEffortKind.unscheduled), 10);
        expect(
          monday.efforts.fold<int>(0, (sum, effort) => sum + effort.minutes),
          30,
        );
      },
    );

    test(
      'many items, long names, one-minute efforts and over-plan stay intact',
      () {
        final base = plannerFixture();
        final task = base.tasks.single;
        final tasks = [
          for (var index = 0; index < 28; index++)
            task.copyWith(
              id: 'item-$index',
              title: '大量事项 $index：用于检查换行与完整名称的较长标题',
            ),
        ];
        final blocks = [
          for (var index = 0; index < 28; index++)
            _block(
              base,
              id: 'b-$index',
              taskId: 'item-$index',
              date: _monday,
              minutes: index + 1,
              startMinute: index,
            ),
        ];
        final logs = [
          for (var index = 0; index < 28; index++)
            _log(
              base,
              id: 'l-$index',
              taskId: 'item-$index',
              date: _monday,
              minutes: 1,
              relation: TimeLogRelation.extra,
            ),
        ];
        final data = base.copyWith(tasks: tasks, blocks: blocks, logs: logs);
        final week = buildCalendarWeekData(data, _monday);
        _expectWeekReconciles(data, week);
        expect(week.itemsFor(_monday), hasLength(28));
        expect(week.itemsFor(_monday).first.title, contains('大量事项'));
        final oneMinute = week.itemsFor(_monday).first;
        expect(_effortMinutes(oneMinute, CalendarEffortKind.extra), 1);
        expect(week.layers, hasLength(1));
        expect(week.layers.single.totalMinutes, 28);
        expect(week.scaleMinutes, 406);

        // Over-plan: actual exceeds the plan and is never truncated.
        final overData = base.copyWith(
          blocks: [
            _block(
              base,
              id: 'over',
              taskId: task.id,
              date: _monday,
              minutes: 30,
            ),
          ],
          logs: [
            _log(
              base,
              id: 'over-scheduled',
              taskId: task.id,
              date: _monday,
              minutes: 30,
              relation: TimeLogRelation.scheduled,
            ),
            _log(
              base,
              id: 'over-extra',
              taskId: task.id,
              date: _monday,
              minutes: 90,
              relation: TimeLogRelation.extra,
            ),
          ],
        );
        final over = buildCalendarWeekData(overData, _monday);
        _expectWeekReconciles(overData, over);
        expect(over.days[0].plannedMinutes, 30);
        expect(over.days[0].actualMinutes, 120);
        expect(over.scaleMinutes, 120);
        expect(
          over.layers.fold<int>(0, (sum, layer) => sum + layer.totalMinutes),
          120,
        );
      },
    );

    test('course and layer order is stable for reversed input data', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final english = task.copyWith(
        id: 'english-task',
        subjectId: 'english',
        title: '英语阅读',
      );
      final data = base.copyWith(
        subjects: [
          base.subjects.single,
          base.subjects.single.copyWith(
            id: 'english',
            name: '英语',
            color: '#1f7a5a',
          ),
        ],
        tasks: [task, english],
        blocks: [
          _block(base, id: 'b1', taskId: task.id, date: _monday, minutes: 60),
          _block(
            base,
            id: 'b2',
            taskId: english.id,
            date: _monday,
            minutes: 30,
            startMinute: 60,
          ),
        ],
        logs: [
          _log(
            base,
            id: 'l1',
            taskId: task.id,
            date: _monday,
            minutes: 20,
            relation: TimeLogRelation.scheduled,
          ),
          _log(
            base,
            id: 'l2',
            taskId: english.id,
            date: _tuesday,
            minutes: 10,
            relation: TimeLogRelation.extra,
          ),
        ],
      );
      final first = buildCalendarWeekData(data, _monday);
      final reversed = buildCalendarWeekData(
        data.copyWith(
          tasks: data.tasks.reversed.toList(),
          blocks: data.blocks.reversed.toList(),
          logs: data.logs.reversed.toList(),
        ),
        _monday,
      );
      expect(
        first.courses.map((course) => course.subjectId),
        reversed.courses.map((course) => course.subjectId),
      );
      expect(
        first.layers.map((layer) => '${layer.subjectId}/${layer.kind.name}'),
        reversed.layers.map((layer) => '${layer.subjectId}/${layer.kind.name}'),
      );
      expect(
        first.itemsFor(_monday).map((item) => item.id),
        reversed.itemsFor(_monday).map((item) => item.id),
      );
      expect(first.layers, isNotEmpty);
      expect(() => first.layers.clear(), throwsUnsupportedError);
      expect(() => first.days.clear(), throwsUnsupportedError);
    });
  });

  group('week view and mode enums', () {
    test('week views default to mirror and reject unknown stored values', () {
      expect(CalendarWeekView.fromStored(null), CalendarWeekView.mirror);
      expect(
        CalendarWeekView.fromStored('mountain'),
        CalendarWeekView.mountain,
      );
      expect(
        CalendarWeekView.fromStored('old-day-view'),
        CalendarWeekView.mirror,
      );
      expect(CalendarWeekView.mirror.label, '上下镜像');
      expect(CalendarWeekView.mountain.label, '学习山脉');
    });

    test('day chart defaults stay unchanged', () {
      expect(CalendarView.fromStored(null), CalendarView.rivers);
      expect(CalendarView.fromStored('growth'), CalendarView.growth);
      expect(CalendarView.values, hasLength(2));
    });
  });
}
