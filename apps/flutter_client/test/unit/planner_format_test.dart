import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';

void main() {
  group('duration', () {
    test('matches the Web formatter for whole, partial and rounded hours', () {
      expect(duration(0), '0分钟');
      expect(duration(45), '45分钟');
      expect(duration(59), '59分钟');
      expect(duration(60), '1小时');
      expect(duration(90), '1小时30分');
      expect(duration(125), '2小时5分');
      // 119 minutes is 1 hour 59 minutes in the Web client.
      expect(duration(119), '1小时59分');
      // Rounding happens on the whole value, so a fractional total can never
      // leave an impossible "60分" remainder behind.
      expect(duration(89.6), '1小时30分');
      expect(duration(119.5), '2小时');
      expect(duration(59.5), '1小时');
    });
  });

  group('dates', () {
    test('dateOnly and addDate stay on date-only strings', () {
      expect(addDate('2026-10-16', 0), '2026-10-16');
      expect(addDate('2026-10-16', 1), '2026-10-17');
      expect(addDate('2026-10-31', 1), '2026-11-01');
      expect(addDate('2026-12-31', 1), '2027-01-01');
      expect(addDate('2026-03-01', -1), '2026-02-28');
      expect(addDate('2028-03-01', -1), '2028-02-29');
    });

    test('daysBetween counts calendar days and rejects malformed input', () {
      expect(daysBetween('2026-10-16', '2026-10-16'), 0);
      expect(daysBetween('2026-10-16', '2026-10-17'), 1);
      expect(daysBetween('2026-10-16', '2027-12-25'), 435);
      expect(daysBetween('bad', '2026-10-17'), 0);
      expect(addDate('bad', 3), 'bad');
    });

    test('labels use Monday-first weekday names and Chinese month/day', () {
      expect(weekdayLabel('2026-10-16'), '周五');
      expect(weekdayLabel('2026-10-18'), '周日');
      expect(fullDateLabel('2026-10-16'), '10月16日 周五');
      expect(monthDayLabel('2026-10-16'), '10月16日');
      expect(monthStart('2026-10-16'), '2026-10-01');
      expect(daysInMonth('2026-10'), 31);
      expect(daysInMonth('2026-02'), 28);
      expect(daysInMonth('2028-02'), 29);
      expect(daysInMonth('2026-11'), 30);
      expect(mondayIndex('2026-10-12'), 0);
      expect(mondayIndex('2026-10-18'), 6);
    });

    test('shanghaiToday follows Asia/Shanghai, not the device clock', () {
      // 2026-10-16T23:30Z is already 2026-10-17 in Asia/Shanghai.
      expect(
        shanghaiToday(DateTime.utc(2026, 10, 16, 23, 30)),
        '2026-10-17',
      );
      expect(shanghaiToday(DateTime.utc(2026, 10, 16, 15, 59)), '2026-10-16');
      expect(shanghaiToday(DateTime.utc(2026, 10, 16, 16, 0)), '2026-10-17');
    });
  });

  group('clock helpers', () {
    test('clockTime and parseClockTime round-trip a minute of day', () {
      expect(clockTime(0), '00:00');
      expect(clockTime(510), '08:30');
      expect(clockTime(1320), '22:00');
      expect(parseClockTime('12:00'), 720);
      expect(parseClockTime('8:05'), 485);
      expect(parseClockTime('24:00'), isNull);
      expect(parseClockTime('12:60'), isNull);
      expect(parseClockTime('noon'), isNull);
    });
  });
}
