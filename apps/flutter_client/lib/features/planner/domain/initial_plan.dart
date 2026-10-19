import '../../../shared/models/planner_models.dart';
import 'planner_format.dart';

/// A brand new local plan for one account: no courses, no items and no exam events.
///
/// It only provides an editable default planning cycle so every page has a valid
/// model before the server has one; no school, exam date or official exam is
/// invented here.
PlannerData initialPlannerData({
  required String userId,
  String? today,
  String? planStartDate,
  String? planEndDate,
  String? timestamp,
  String Function()? nextId,
}) {
  final start = planStartDate ?? today ?? shanghaiToday();
  return PlannerData(
    version: 1,
    profile: Profile(
      userId: userId,
      storedPlanningMode: PlanningMode.daily,
      goalType: GoalType.other,
      planStartDate: start,
      planEndDate: planEndDate ?? addDate(start, 27),
      dailyLimitMinutes: 480,
      granularityMinutes: 30,
      bufferMinutes: 30,
      subjectLimitMinutes: 240,
      studyStartMinute: 480,
      studyEndMinute: 1320,
      foundation: '',
    ),
    subjects: const [],
    tasks: const [],
    blocks: const [],
    logs: const [],
    fixedEvents: const [],
    replanRuns: const [],
    phases: const [],
  );
}
