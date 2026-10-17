import '../../../shared/models/planner_models.dart';
import 'planner_format.dart';
import 'scheduler/planner_scheduler.dart' as scheduler;

/// The official exam sessions of the 2027 sitting.
///
/// The Web client seeds a full preset plan; the Flutter client deliberately starts
/// empty because the account wizard creates courses and items, but the official
/// exams are not part of that wizard and must never be overwritten.
const officialExamSessions = [
  ('2027-12-25', 510, '正式初试 · 政治'),
  ('2027-12-25', 840, '正式初试 · 英语一'),
  ('2027-12-26', 510, '正式初试 · 数学一'),
  ('2027-12-26', 840, '正式初试 · 408'),
];

/// A brand new local plan for one account: no courses and no items yet.
///
/// It keeps the profile fields and the immutable official exams so every page has a
/// valid plan to edit before the server has one.
PlannerData initialPlannerData({
  required String userId,
  String? today,
  String? examDate,
  String? examEndDate,
  String? timestamp,
  String Function()? nextId,
}) {
  final stamp = timestamp ?? nowIso();
  final id = nextId ?? scheduler.newUuid;
  return PlannerData(
    version: 1,
    profile: Profile(
      userId: userId,
      storedPlanningMode: PlanningMode.daily,
      targetSchool: '',
      targetProgram: '',
      examDate: examDate ?? '${(today ?? shanghaiToday()).substring(0, 4)}-12-25',
      examEndDate:
          examEndDate ?? '${(today ?? shanghaiToday()).substring(0, 4)}-12-26',
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
    fixedEvents: [
      FixedEvent(
        id: id(),
        userId: userId,
        title: '午休与午餐',
        date: today ?? shanghaiToday(),
        startMinute: 720,
        durationMinutes: 60,
        kind: FixedEventKind.rest,
        repeat: EventRepeat.daily,
        createdAt: stamp,
        updatedAt: stamp,
      ),
      for (final (date, startMinute, title) in officialExamSessions)
        FixedEvent(
          id: id(),
          userId: userId,
          title: title,
          date: date,
          startMinute: startMinute,
          durationMinutes: 180,
          kind: FixedEventKind.officialExam,
          repeat: EventRepeat.none,
          createdAt: stamp,
          updatedAt: stamp,
        ),
    ],
    replanRuns: const [],
    phases: const [],
  );
}
