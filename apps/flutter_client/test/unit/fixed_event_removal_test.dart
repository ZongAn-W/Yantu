import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/initial_plan.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/planner_scheduler.dart'
    as scheduler;
import 'package:sjtu_study_planner_client/features/planner/domain/scheduler/strategy_scheduler.dart'
    as strategy;
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/task_editing.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

const _date = '2026-10-18';

PlannerData _legacyPlan(PlanningMode mode) {
  final source = plannerFixture();
  return source.copyWith(
    profile: source.profile.copyWith(
      storedPlanningMode: mode,
      capacityBasis: CapacityBasis.net,
      dailyLimitMinutes: 120,
      studyStartMinute: 480,
      studyEndMinute: 600,
    ),
    tasks: [source.tasks.single.copyWith(estimatedMinutes: 120)],
    blocks: const [],
    logs: const [],
    fixedEvents: [
      FixedEvent(
        id: 'legacy-event',
        userId: source.profile.userId,
        title: '旧版固定事件',
        date: _date,
        startMinute: 0,
        durationMinutes: 1440,
        kind: FixedEventKind.course,
        repeat: EventRepeat.daily,
        createdAt: '2026-10-16T00:00:00.000Z',
        updatedAt: '2026-10-16T00:00:00.000Z',
      ),
    ],
  );
}

void main() {
  test('new plans contain no automatic rest or fixed event', () {
    final data = initialPlannerData(userId: 'account', today: _date);
    expect(data.fixedEvents, isEmpty);
  });

  test(
    'legacy event fields survive JSON import and export but reserve no time',
    () {
      final original = _legacyPlan(PlanningMode.timed);
      final restored = PlannerData.fromJson(
        jsonDecode(original.toJsonString()) as JsonMap,
      );
      expect(restored.fixedEvents, original.fixedEvents);
      expect(calendarDay(restored, _date).capacity, 120);
      expect(calendarDay(restored, _date).fixedMinutes, 0);
      expect(fixedEventsOn(restored, _date), isEmpty);
      expect(
        scheduler.eventOccursOn(restored.fixedEvents.single, _date),
        isFalse,
      );
      expect(
        scheduler.fixedEventOccupiedIntervals(restored.fixedEvents, _date),
        isEmpty,
      );
      expect(
        scheduler.fixedEventMinutesForDate(restored.fixedEvents, _date),
        0,
      );
    },
  );

  for (final mode in PlanningMode.values) {
    test(
      'legacy events do not reduce capacity or block manual placement in $mode',
      () {
        final data = _legacyPlan(mode);
        final result = scheduleTaskDay(data, data.tasks.single.id, _date, 120);
        expect(result.outcome.placed, 120);
        expect(result.outcome.conflict, isFalse);
        expect(result.data.fixedEvents, data.fixedEvents);
        expect(dayCapacityBreakdown(result.data, _date).available, 0);
        if (mode == PlanningMode.timed) {
          expect(result.data.blocks.first.startMinute, 480);
        }
      },
    );

    test(
      'legacy events do not reserve slots in automatic scheduling in $mode',
      () {
        final data = _legacyPlan(mode);
        final result = strategy.scheduleStrategy(data, _date, _date);
        expect(result.scheduledMinutes, 120);
        expect(result.unscheduledMinutes, 0);
        expect(
          result.blocks.fold<int>(
            0,
            (sum, block) => sum + block.durationMinutes,
          ),
          120,
        );
        if (mode == PlanningMode.timed) {
          expect(result.blocks.first.startMinute, 480);
        }
      },
    );
  }
}
