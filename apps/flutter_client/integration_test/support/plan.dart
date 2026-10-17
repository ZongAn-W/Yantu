import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

/// The document shape `/api/planner/sync` stores, with two courses, two tasks and
/// one planned block each for today, plus a repeating rest event.
///
/// It is shared by the integration tests and the debug probe so both assert against
/// exactly the same numbers.
PlannerData seededPlan() {
  const now = '2026-10-16T12:40:00.528Z';
  const userId = 'integration-user';
  final today = shanghaiToday();
  return PlannerData(
    version: 1,
    profile: const Profile(
      userId: userId,
      storedPlanningMode: PlanningMode.daily,
      targetSchool: '上海交通大学',
      targetProgram: '计算机技术',
      examDate: '2027-12-25',
      examEndDate: '2027-12-26',
      dailyLimitMinutes: 480,
      granularityMinutes: 30,
      bufferMinutes: 30,
      subjectLimitMinutes: 240,
      studyStartMinute: 480,
      studyEndMinute: 1320,
      foundation: '集成验收数据',
    ),
    subjects: const [
      Subject(
        id: 'calculus',
        userId: userId,
        name: '高数',
        color: '#4565c7',
        priority: 3,
      ),
      Subject(
        id: 'english',
        userId: userId,
        name: '英语',
        color: '#1f7a5a',
        priority: 2,
      ),
    ],
    tasks: const [
      Task(
        id: 'task-math',
        userId: userId,
        subjectId: 'calculus',
        title: '基础一轮',
        description: '范围：极限、导数与积分基础题。',
        estimatedMinutes: 600,
        completedMinutes: 0,
        priority: 3,
        deadline: '2027-04-30',
        earliestDate: '2026-10-01',
        isFixed: false,
        status: TaskStatus.notStarted,
        createdAt: now,
        updatedAt: now,
      ),
      Task(
        id: 'task-english',
        userId: userId,
        subjectId: 'english',
        title: '真题精读',
        description: '2015 年至 2019 年阅读真题精读。',
        estimatedMinutes: 300,
        completedMinutes: 0,
        priority: 2,
        deadline: '2027-06-30',
        earliestDate: '2026-10-01',
        isFixed: false,
        status: TaskStatus.notStarted,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    blocks: [
      ScheduleBlock(
        id: 'block-math',
        userId: userId,
        taskId: 'task-math',
        date: today,
        startMinute: 0,
        durationMinutes: 90,
        actualMinutes: 0,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: now,
        updatedAt: now,
      ),
      ScheduleBlock(
        id: 'block-english',
        userId: userId,
        taskId: 'task-english',
        date: today,
        startMinute: 0,
        durationMinutes: 60,
        actualMinutes: 0,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    logs: const [],
    fixedEvents: [
      FixedEvent(
        id: 'event-lunch',
        userId: userId,
        title: '午休与午餐',
        date: today,
        startMinute: 720,
        durationMinutes: 60,
        kind: FixedEventKind.rest,
        repeat: EventRepeat.daily,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    replanRuns: const [],
    phases: const [],
  );
}
