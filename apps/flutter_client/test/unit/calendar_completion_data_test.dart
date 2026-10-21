import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_completion_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_day_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_month_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_week_data.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

CalendarDayItem _item({
  required String id,
  required String title,
  int actualMinutes = 0,
  int plannedMinutes = 0,
  List<String> tagNames = const [],
  String? tagColor,
}) => CalendarDayItem(
  id: id,
  title: title,
  tagNames: List.unmodifiable(tagNames),
  tagColor: tagColor,
  plannedMinutes: plannedMinutes,
  actualMinutes: actualMinutes,
  scheduledMinutes: 0,
  efforts: const [],
);

CalendarDayData _day(String date, List<CalendarDayItem> items) {
  final actual = items.fold<int>(0, (sum, item) => sum + item.actualMinutes);
  final planned = items.fold<int>(0, (sum, item) => sum + item.plannedMinutes);
  return CalendarDayData(
    date: date,
    items: List.unmodifiable(items),
    plannedMinutes: planned,
    actualMinutes: actual,
    scaleMinutes: 1,
    riverScaleMinutes: 1,
  );
}

TimeLog _log(
  PlannerData data, {
  required String id,
  required String date,
  int minutes = 0,
  String? taskId,
  String? adHocId,
  TimeLogRelation relation = TimeLogRelation.legacyUnknown,
}) => TimeLog(
  id: id,
  userId: data.profile.userId,
  taskId: taskId,
  adHocId: adHocId,
  blockId: null,
  date: date,
  minutes: minutes,
  startedAt: '${date}T00:00:00.000Z',
  endedAt: '${date}T01:00:00.000Z',
  source: LogSource.timer,
  relation: relation,
);

void main() {
  group('buildCalendarCompletionData', () {
    test('aggregates actual minutes per owner across days', () {
      final data = buildCalendarCompletionData([
        _day('2026-10-12', [
          _item(id: 'task:a', title: '高数', actualMinutes: 30),
          _item(id: 'task:b', title: '英语', actualMinutes: 20),
        ]),
        _day('2026-10-13', [
          _item(id: 'task:a', title: '高数', actualMinutes: 15),
          _item(id: 'task:c', title: '408', actualMinutes: 5),
        ]),
      ]);

      expect(data.isEmpty, isFalse);
      expect(data.itemCount, 3);
      expect(data.slices.map((slice) => slice.id), [
        'task:a',
        'task:b',
        'task:c',
      ]);
      final byId = {for (final slice in data.slices) slice.id: slice};
      expect(byId['task:a']!.minutes, 45);
      expect(byId['task:a']!.title, '高数');
      expect(byId['task:b']!.minutes, 20);
      expect(byId['task:c']!.minutes, 5);
      expect(data.totalMinutes, 70);
      expect(
        data.slices.fold<int>(0, (sum, slice) => sum + slice.minutes),
        data.totalMinutes,
      );
      expect(data.slices, isA<List<CalendarCompletionSlice>>());
    });

    test('empty input and planned-only owners produce an empty period', () {
      final empty = buildCalendarCompletionData(const <CalendarDayData>[]);
      expect(empty.isEmpty, isTrue);
      expect(empty.slices, isEmpty);
      expect(empty.totalMinutes, 0);
      expect(empty.itemCount, 0);

      final plannedOnly = buildCalendarCompletionData([
        _day('2026-10-12', [
          _item(
            id: 'task:a',
            title: '高数',
            plannedMinutes: 60,
            actualMinutes: 0,
          ),
        ]),
      ]);
      expect(plannedOnly.isEmpty, isTrue);
      expect(plannedOnly.slices, isEmpty);
      expect(plannedOnly.totalMinutes, 0);
      expect(plannedOnly.itemCount, 0);
    });

    test('merges task-less history and deleted owners into named buckets', () {
      final data = buildCalendarCompletionData([
        _day('2026-10-12', [
          _item(id: 'log:one', title: '历史学习记录', actualMinutes: 12),
          _item(id: 'log:two', title: '历史学习记录', actualMinutes: 8),
          _item(id: 'task:gone', title: '已删除事项', actualMinutes: 25),
        ]),
        _day('2026-10-13', [
          _item(id: 'log:three', title: '历史学习记录', actualMinutes: 5),
          _item(id: 'task:gone', title: '已删除事项', actualMinutes: 10),
        ]),
      ]);

      expect(data.slices, hasLength(2));
      final legacy = data.slices.singleWhere((slice) => slice.id == 'legacy');
      expect(legacy.minutes, 25);
      expect(legacy.title, '历史学习记录');
      expect(legacy.tagNames, isEmpty);
      expect(legacy.tagColor, isNull);
      final deleted = data.slices.singleWhere((slice) => slice.id == 'deleted');
      expect(deleted.minutes, 35);
      expect(deleted.title, '已删除事项');
      expect(deleted.tagNames, isEmpty);
      expect(deleted.tagColor, isNull);
      expect(data.totalMinutes, 60);
      expect(data.itemCount, 2);
    });

    test('sorts by minutes, then title and id, and keeps slice metadata', () {
      final data = buildCalendarCompletionData([
        _day('2026-10-12', [
          _item(id: 'task:small', title: 'A-小', actualMinutes: 5),
          _item(id: 'task:big', title: 'B-大', actualMinutes: 90),
          _item(
            id: 'task:tie-b',
            title: '同名',
            actualMinutes: 30,
            tagNames: ['线代'],
            tagColor: '#3366ff',
          ),
          _item(id: 'task:tie-a', title: '同名', actualMinutes: 30),
          _item(id: 'task:tie-0', title: '提前', actualMinutes: 30),
        ]),
      ]);

      // 90 first, the three 30-minute slices by title ('同名' before '提前'),
      // then by id for equal titles, then the 5-minute slice.
      expect(data.slices.map((slice) => slice.id).toList(), [
        'task:big',
        'task:tie-a',
        'task:tie-b',
        'task:tie-0',
        'task:small',
      ]);
      expect(data.totalMinutes, 185);
      final tieB = data.slices.singleWhere((slice) => slice.id == 'task:tie-b');
      expect(tieB.tagNames, ['线代']);
      expect(tieB.tagColor, '#3366ff');
      expect(tieB.minutes, 30);
    });

    test('derives tagColor from the first coloured tag of the owner', () {
      final base = plannerFixture();
      final task = base.tasks.single.copyWith(tagIds: ['plain', 'accent']);
      final data = base.copyWith(
        tasks: [task],
        tags: [
          Tag(id: 'plain', userId: base.profile.userId, name: '未着色'),
          Tag(
            id: 'accent',
            userId: base.profile.userId,
            name: '高数',
            color: '#3366ff',
          ),
        ],
        blocks: [],
        logs: [
          _log(
            base,
            id: 'colour',
            date: '2026-10-12',
            taskId: task.id,
            minutes: 40,
            relation: TimeLogRelation.extra,
          ),
        ],
      );
      final day = buildCalendarDayData(data, '2026-10-12');
      expect(day.items.single.tagNames, ['未着色', '高数']);
      expect(day.items.single.tagColor, '#3366ff');

      final completion = buildCalendarCompletionData([day]);
      final slice = completion.slices.single;
      expect(slice.id, 'task:${task.id}');
      expect(slice.tagColor, '#3366ff');
      expect(slice.tagNames, ['未着色', '高数']);
      expect(slice.minutes, 40);
    });

    test('seven-day and whole-month snapshots count every minute once', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final other = task.copyWith(id: 'other', title: '线代复盘');
      final weekDates = calendarWeekDates('2026-10-16');
      final data = base.copyWith(
        tasks: [task, other],
        blocks: [],
        logs: [
          for (var index = 0; index < weekDates.length; index++)
            _log(
              base,
              id: 'week-$index',
              date: weekDates[index],
              taskId: task.id,
              minutes: 10 + index,
              relation: TimeLogRelation.extra,
            ),
          _log(
            base,
            id: 'other-log',
            date: weekDates[3],
            taskId: other.id,
            minutes: 25,
            relation: TimeLogRelation.extra,
          ),
        ],
      );
      final week = buildCalendarWeekData(data, '2026-10-16');
      final weekly = buildCalendarCompletionData([
        for (final day in week.days) day.day,
      ]);
      expect(weekly.totalMinutes, week.actualMinutes);
      expect(weekly.totalMinutes, 116);
      expect(weekly.slices, hasLength(2));
      // Seven daily rows of the same owner collapse into one 91-minute slice.
      expect(weekly.slices.first.id, 'task:${task.id}');
      expect(weekly.slices.first.minutes, 91);
      expect(weekly.slices.last.id, 'task:${other.id}');
      expect(weekly.slices.last.minutes, 25);

      final month = buildCalendarMonthData(
        data,
        '2026-10-16',
        today: '2026-10-16',
      );
      final monthly = buildCalendarCompletionData([
        for (final day in month.days) day.day,
      ]);
      expect(monthly.totalMinutes, month.actualMinutes);
      expect(monthly.totalMinutes, 116);
      expect(monthly.slices, hasLength(2));
      expect(monthly.slices.first.minutes, 91);
    });

    test('does not create a slice for a task that only has recorded zero', () {
      final data = buildCalendarCompletionData([
        _day('2026-10-12', [
          _item(
            id: 'task:planned',
            title: '只计划',
            plannedMinutes: 120,
            actualMinutes: 0,
          ),
          _item(id: 'task:actual', title: '已学', actualMinutes: 1),
        ]),
      ]);
      expect(data.slices, hasLength(1));
      expect(data.slices.single.id, 'task:actual');
      expect(data.slices.single.minutes, 1);
    });

    test('historical temporary-learning rows never reach the pie', () {
      final base = plannerFixture();
      final task = base.tasks.single;
      final data = base.copyWith(
        blocks: const [],
        adHocLearnings: [
          AdHocLearning(
            id: 'reading',
            userId: base.profile.userId,
            title: '临时学习：阅读',
            createdAt: '2026-10-12T00:00:00.000Z',
            updatedAt: '2026-10-12T00:00:00.000Z',
          ),
        ],
        logs: [
          _log(
            base,
            id: 'real',
            date: '2026-10-12',
            taskId: task.id,
            minutes: 20,
            relation: TimeLogRelation.extra,
          ),
          _log(
            base,
            id: 'temporary',
            date: '2026-10-12',
            minutes: 30,
            adHocId: 'reading',
            relation: TimeLogRelation.adHoc,
          ),
        ],
      );
      final day = buildCalendarDayData(data, '2026-10-12');
      // The retired temporary row contributes neither an owner nor a minute.
      expect(day.actualMinutes, 20);
      final completion = buildCalendarCompletionData([day]);
      expect(completion.totalMinutes, 20);
      expect(completion.slices.single.id, 'task:${task.id}');
      expect(completion.slices.single.minutes, 20);
    });
  });
}
