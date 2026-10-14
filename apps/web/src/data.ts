import type {
  FixedEvent,
  Phase,
  PlannerData,
  ScheduleBlock,
  Task,
  TaskStatus,
} from "@planner/engine";
import { seedCourses } from "@planner/engine";
import { itemSeeds } from "./item-seeds";

export const LOCAL_STORAGE_KEY = "sjtu-study-planner:items-v2";
export const statusNames: Record<TaskStatus, string> = {
  not_started: "未开始",
  in_progress: "进行中",
  completed: "完成",
  delayed: "延期",
  conflict: "冲突",
};
export const priorityNames = { 1: "中", 2: "中高", 3: "高" } as const;

/** All dates are calendar dates in Shanghai, independent of the device timezone. */
export function localDate(value = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(value);
  return ["year", "month", "day"]
    .map((type) => parts.find((part) => part.type === type)?.value)
    .join("-");
}

export function addDate(date: string, days: number): string {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

export function uid(): string {
  return crypto.randomUUID();
}

export function fmtMinutes(minutes: number): string {
  const value = Math.max(0, Math.round(minutes));
  if (value < 60) return `${value} 分钟`;
  return `${Math.floor(value / 60)} 小时${value % 60 ? ` ${value % 60} 分钟` : ""}`;
}

export const phases: Phase[] = [
  {
    id: "foundation",
    title: "基础诊断与打底",
    start: "2026-10-01",
    end: "2026-12-31",
    description:
      "数学诊断、高数与线代；英语词汇、长难句与真题阅读；408 数据结构和操作系统。政治暂不系统开始。",
  },
  {
    id: "first-round",
    title: "第一轮系统学习",
    start: "2027-01-01",
    end: "2027-04-30",
    description: "数学一第一轮，408 四门课程完整覆盖，英语阅读和词汇持续。",
  },
  {
    id: "past-papers",
    title: "真题导入与六级",
    start: "2027-05-01",
    end: "2027-06-30",
    description: "数学真题题型、408 真题导入、英语一真题，以及六级复习。",
  },
  {
    id: "reinforcement",
    title: "二轮强化与政治起步",
    start: "2027-07-01",
    end: "2027-08-31",
    description:
      "数学和 408 二轮强化，政治开始，C/C++ 数据结构与机试，每周模拟。",
  },
  {
    id: "mock-exams",
    title: "套卷与失分分析",
    start: "2027-09-01",
    end: "2027-10-31",
    description:
      "四科套卷，政治选择题和主观题，每周统计失分；核对正式报考方向和初试日期。",
  },
  {
    id: "final-sprint",
    title: "冲刺与考试作息",
    start: "2027-11-01",
    end: "2027-12-24",
    description:
      "数学错题与套卷，英语作文、阅读与翻译，政治背诵与模拟，408 高频考点和错题，保持考试作息。",
  },
];

/** A complete daily workload plan. Study blocks have no clock placement. */
export function createInitialData(today = localDate()): PlannerData {
  const user_id = uid();
  const now = new Date().toISOString();
  const subjects = seedCourses.map((course) => ({ ...course, user_id }));
  const tasks: Task[] = itemSeeds.map(({ hours, ...item }) => ({
    ...item, id: uid(), user_id,
    estimated_minutes: hours * 60, completed_minutes: 0,
    priority: subjects.find((course) => course.id === item.subject_id)!.priority,
    is_fixed: false, status: "not_started" as const,
    created_at: now, updated_at: now,
  }));
  const fixed_events: FixedEvent[] = [
    {
      id: uid(),
      user_id,
      title: "午休与午餐",
      date: today,
      start_minute: 720,
      duration_minutes: 60,
      kind: "rest",
      repeat: "daily",
      created_at: now,
      updated_at: now,
    },
    ...(
      [
        ["2027-12-25", 510, "正式初试 · 政治"],
        ["2027-12-25", 840, "正式初试 · 英语一"],
        ["2027-12-26", 510, "正式初试 · 数学一"],
        ["2027-12-26", 840, "正式初试 · 408"],
      ] as const
    ).map(([date, start_minute, title]) => ({
      id: uid(),
      user_id,
      title,
      date,
      start_minute,
      duration_minutes: 180,
      kind: "official_exam" as const,
      repeat: "none" as const,
      created_at: now,
      updated_at: now,
    })),
  ];
  const blocks: ScheduleBlock[] = [];
  const allocated = new Map<string, number>();
  for (let day = 0; day <= 14; day += 1) {
    const date = addDate(today, day);
    const dailyItemBlocks = new Map<string, number>();
    const available = tasks.filter(
      (task) =>
        (!task.earliest_date || task.earliest_date <= date) &&
        task.deadline >= date,
    );
    const dailyCourses = date >= "2027-07-01"
      ? ["calculus", "linear-algebra", "vocabulary", "reading", "data-structures", "operating-systems", "marxism", "history"]
      : ["calculus", "linear-algebra", "vocabulary", "grammar", "reading", "data-structures", "operating-systems"];
    const subjectsForDay = dailyCourses.concat(dailyCourses.slice(0, 12 - dailyCourses.length));
    subjectsForDay.forEach((subject) => {
      const task = available
        .filter(
          (item) =>
            item.subject_id === subject &&
            (allocated.get(item.id) ?? 0) < item.estimated_minutes,
        )
        .sort(
          (left, right) =>
            (dailyItemBlocks.get(left.id) ?? 0) -
              (dailyItemBlocks.get(right.id) ?? 0) ||
            left.deadline.localeCompare(right.deadline) ||
            right.priority - left.priority,
        )[0];
      if (!task) return;
      blocks.push({
        id: uid(),
        user_id,
        task_id: task.id,
        date,
        start_minute: 0,
        duration_minutes: 30,
        actual_minutes: 0,
        is_fixed: false,
        status: "planned",
        created_at: now,
        updated_at: now,
      });
      allocated.set(task.id, (allocated.get(task.id) ?? 0) + 30);
      dailyItemBlocks.set(task.id, (dailyItemBlocks.get(task.id) ?? 0) + 1);
    });
  }
  return {
    version: 1,
    profile: {
      user_id,
      planning_mode: "daily",
      target_school: "上海交通大学",
      target_program: "计算机相关专业 · 408 统考（待正式报考确认）",
      exam_date: "2027-12-25",
      exam_end_date: "2027-12-26",
      daily_limit_minutes: 480,
      granularity_minutes: 30,
      buffer_minutes: 30,
      subject_limit_minutes: 240,
      // Retained only for backwards compatibility with timed plans.
      study_start_minute: 480,
      study_end_minute: 1320,
      foundation:
        "上海理工大学计算机专业大三；绩点 3.4；年级排名 30 几；六级 350；408 相关课程约 4.0。仅规划统考，不考虑推免。",
    },
    subjects,
    tasks,
    blocks,
    logs: [],
    fixed_events,
    replan_runs: [],
    phases: phases.map((phase) => ({ ...phase })),
  };
}

/** Current daily item plans only; old hierarchies are not converted. */
export function normalizePlannerData(value: unknown): PlannerData | null {
  return isPlannerData(value) ? value : null;
}

/** Validate backups before they can replace a complete local or cloud plan. */
export function isPlannerData(value: unknown): value is PlannerData {
  if (!value || typeof value !== "object") return false;
  const data = value as Partial<PlannerData>;
  if (data.version !== 1 || !data.profile || !data.profile.user_id || data.profile.planning_mode !== "daily")
    return false;
  const collectionsValid = [
    "subjects",
    "tasks",
    "blocks",
    "logs",
    "fixed_events",
    "replan_runs",
    "phases",
  ].every((key) =>
    Array.isArray((data as unknown as Record<string, unknown>)[key]),
  );
  if (!collectionsValid) return false;
  const objectRows = (rows: unknown[]) => rows.every((row) => row && typeof row === "object" && !Array.isArray(row));
  if (
    !objectRows(data.subjects!) || !objectRows(data.tasks!) ||
    !objectRows(data.blocks!) || !objectRows(data.logs!) ||
    !objectRows(data.fixed_events!) || !objectRows(data.replan_runs!) ||
    !objectRows(data.phases!)
  ) return false;
  if (
    data.subjects!.some((course) => typeof course.id !== "string" || !course.id.trim() || typeof course.name !== "string") ||
    data.tasks!.some((task) =>
      "category_id" in task ||
      typeof task.id !== "string" || !data.subjects!.some((course) => course.id === task.subject_id) ||
      !Number.isFinite(task.estimated_minutes) || task.estimated_minutes <= 0 ||
      !Number.isFinite(task.completed_minutes) || task.completed_minutes < 0 ||
      typeof task.deadline !== "string" || typeof task.title !== "string" ||
      (task.description !== undefined && typeof task.description !== "string"),
    ) ||
    data.blocks!.some((block) =>
      typeof block.id !== "string" || typeof block.task_id !== "string" ||
      typeof block.date !== "string" || !Number.isFinite(block.duration_minutes) ||
      block.duration_minutes <= 0 || !Number.isFinite(block.start_minute),
    ) ||
    data.logs!.some((log) =>
      "category_id" in log ||
      typeof log.id !== "string" || typeof log.task_id !== "string" ||
      typeof log.date !== "string" || !Number.isFinite(log.minutes) || log.minutes < 0,
    )
  ) return false;
  return true;
}
