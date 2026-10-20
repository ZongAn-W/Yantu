import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_month_data.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

void main() {
  PlannerData monthPlan({String today = '2026-10-20'}) {
    final fixture = plannerFixture();
    final base = fixture.blocks.single;
    final userId = fixture.profile.userId;
    ScheduleBlock block(String id, String date, int minutes) =>
        base.copyWith(id: id, date: date, durationMinutes: minutes);
    TimeLog log(
      String id,
      String date,
      int minutes,
      TimeLogRelation relation, {
      String? adHocId,
    }) => TimeLog(
      id: id,
      userId: userId,
      taskId: relation == TimeLogRelation.adHoc ? null : base.taskId,
      blockId: null,
      date: date,
      minutes: minutes,
      startedAt: '${date}T04:00:00.000Z',
      endedAt: '${date}T05:00:00.000Z',
      source: LogSource.timer,
      relation: relation,
      adHocId: adHocId,
    );
    return fixture.copyWith(
      profile: fixture.profile.copyWith(
        dateCapacityOverrides: {'2026-10-06': 0},
      ),
      blocks: [
        block('b1', '2026-10-01', 60),
        block('b2', '2026-10-02', 90),
        block('b3', '2026-10-03', 60),
        block('b-today', today, 30),
        block('b-future', '2026-10-21', 45),
      ],
      logs: [
        log('l1', '2026-10-01', 60, TimeLogRelation.scheduled),
        log('l2', '2026-10-02', 30, TimeLogRelation.scheduled),
        log('l4', '2026-10-04', 25, TimeLogRelation.extra),
        // Retired temporary learning stays in the document but never reaches
        // the month facts.
        log(
          'l-adhoc',
          '2026-10-04',
          15,
          TimeLogRelation.adHoc,
          adHocId: 'photo',
        ),
      ],
    );
  }

  test('month snapshot aggregates plan, actual, capacity and status', () {
    final month = buildCalendarMonthData(
      monthPlan(),
      '2026-10-15',
      today: '2026-10-20',
    );
    expect(month.month, '2026-10');
    expect(month.days, hasLength(31));
    expect(month.heatLead, 3); // 2026-10-01 is a Thursday.
    expect(month.plannedMinutes, 60 + 90 + 60 + 30 + 45);
    expect(month.actualMinutes, 60 + 30 + 25);
    expect(month.isEmpty, isFalse);

    final first = month.dayFor('2026-10-01')!;
    expect(first.status, CalendarDayStatus.completed);
    expect(first.scheduledMinutes, 60);
    expect(first.heatLevel, 1);
    expect(first.isToday, isFalse);

    final second = month.dayFor('2026-10-02')!;
    expect(second.status, CalendarDayStatus.partial);
    expect(second.scheduledMinutes, 30);

    final third = month.dayFor('2026-10-03')!;
    expect(third.status, CalendarDayStatus.interrupted);
    expect(third.scheduledMinutes, 0);

    final fourth = month.dayFor('2026-10-04')!;
    expect(fourth.status, CalendarDayStatus.extraOnly);
    expect(fourth.actualMinutes, 25, reason: 'ad-hoc minutes must be ignored');
    expect(fourth.scheduledMinutes, 0);

    expect(month.dayFor('2026-10-05')!.status, CalendarDayStatus.free);
    expect(month.dayFor('2026-10-06')!.status, CalendarDayStatus.rest);
    expect(month.dayFor('2026-10-06')!.capacityMinutes, 0);
    expect(month.dayFor('2026-10-20')!.status, CalendarDayStatus.pending);
    expect(month.dayFor('2026-10-21')!.status, CalendarDayStatus.upcoming);
    expect(month.dayFor('2026-10-21')!.isFuture, isTrue);
    expect(month.dayFor('2026-10-21')!.plannedMinutes, 45);

    // Two interrupted days: 10-03 had a plan but nothing was achieved, and
    // today's plan is not achieved yet (same rule as the former heat map).
    expect(month.interruptedDays, 2);
    expect(month.studiedDays, 3);
    expect(
      month.capacityMinutes,
      month.days.fold<int>(0, (sum, day) => sum + day.capacityMinutes),
    );
    expect(
      month.days.where((day) => day.date != '2026-10-06').every(
        (day) => day.capacityMinutes > 0,
      ),
      isTrue,
    );
  });

  test('empty month reports zero totals without inventing statuses', () {
    final fixture = plannerFixture();
    final empty = buildCalendarMonthData(
      fixture.copyWith(blocks: const [], logs: const []),
      '2026-10-01',
      today: '2026-10-20',
    );
    expect(empty.isEmpty, isTrue);
    expect(empty.plannedMinutes, 0);
    expect(empty.actualMinutes, 0);
    expect(empty.interruptedDays, 0);
    expect(empty.studiedDays, 0);
    expect(empty.days.every((day) => day.status == CalendarDayStatus.free), isTrue);
  });

  test('month label and month arithmetic survive month boundaries', () {
    expect(monthLabel('2026-10'), '2026年10月');
    expect(monthLabel('2026-01'), '2026年1月');
    expect(addMonth('2026-01-31', 1), '2026-02-28');
    expect(addMonth('2026-03-31', -1), '2026-02-28');
    expect(addMonth('2026-12-15', 1), '2027-01-15');
    expect(addMonth('2026-10-20', 0), '2026-10-20');
    expect(addDate('2026-10-31', 1), '2026-11-01');
  });
}
