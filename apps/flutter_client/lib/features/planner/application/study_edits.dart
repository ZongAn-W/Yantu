import '../../../shared/models/planner_models.dart';
import '../domain/scheduler/planner_scheduler.dart';

/// Compatibility entry point for existing callers; all rules live in domain.
PlannerData recordDayMinutes(
  PlannerData data,
  String taskId,
  String date,
  int minutes,
) => recordTaskDayMinutes(data, taskId, date, minutes);
