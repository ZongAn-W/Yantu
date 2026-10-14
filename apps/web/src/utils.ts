import type { PlannerData, SubjectId, ScheduleBlock, Task } from "@planner/engine";
export function groupDailyBlocks(blocks: ScheduleBlock[], tasks: Task[]): ScheduleBlock[][] {
  const groups = new Map<string, ScheduleBlock[]>();
  for (const block of blocks) {
    const task = tasks.find((item) => item.id === block.task_id);
    if (!task) continue;
    const key = `${task.id}:${block.date}`;
    const group = groups.get(key) ?? [];
    group.push(block);
    groups.set(key, group);
  }
  return [...groups.values()]
    .map((group) => group.sort((a, b) => a.start_minute - b.start_minute));
}
export function today() {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Shanghai" }).format(
    new Date(),
  );
}
export function addDate(date: string, n: number) {
  const d = new Date(date + "T12:00:00+08:00");
  d.setUTCDate(d.getUTCDate() + n);
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Shanghai" }).format(
    d,
  );
}
export const uid = () => crypto.randomUUID();
export const now = () => new Date().toISOString();
export const duration = (m: number) =>
  m >= 60
    ? `${Math.floor(m / 60)}小时${m % 60 ? `${Math.round(m % 60)}分` : ""}`
    : `${Math.round(m)}分钟`;
export const minuteTime = (s: string) => {
  const [h, m] = s.split(":").map(Number);
  return h * 60 + m;
};
export const fixedEventTime = (minutes: number) =>
  `${String(Math.floor(minutes / 60)).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
export const statusLabels = {
  not_started: "未开始",
  in_progress: "进行中",
  completed: "完成",
  delayed: "延期",
  conflict: "冲突",
};
export const priorityLabels = { 1: "普通", 2: "中高", 3: "高" };
export function dayStats(data: PlannerData, date: string) {
  const blocks = data.blocks.filter((b) => b.date === date);
  const planned = blocks.reduce((s, b) => s + b.duration_minutes, 0);
  const actual = data.logs
    .filter((l) => l.date === date)
    .reduce((s, l) => s + l.minutes, 0);
  return {
    planned,
    actual,
    remaining: Math.max(0, planned - actual),
    excess: Math.max(0, actual - planned),
    rate: planned ? Math.round((actual / planned) * 100) : 0,
  };
}
export function refreshTaskProgress(
  data: PlannerData,
  correctedTaskIds: string[] = [],
): PlannerData {
  return {
    ...data,
    tasks: data.tasks.map((t) => {
      const actual = data.logs
        .filter((l) => l.task_id === t.id)
        .reduce((s, l) => s + l.minutes, 0);
      const completed = Math.min(t.estimated_minutes, actual);
      return {
        ...t,
        completed_minutes: completed,
        status:
          t.status === "completed" && !correctedTaskIds.includes(t.id)
            ? "completed"
            : completed > 0
              ? "in_progress"
              : t.status === "completed"
                ? "not_started"
                : t.status,
        updated_at: now(),
      };
    }),
  };
}
