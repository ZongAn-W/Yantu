import type { PlannerData, TimeLog } from "./types";
import { defaultPlannerRuntime, type PlannerRuntime } from "./runtime";

/** An item/day is an editable total; simultaneous corrections must not add together. */
export function mergeTaskDayLogs(base: TimeLog[], local: TimeLog[], remote: TimeLog[]): TimeLog[] {
  const key = (log: TimeLog) => `${log.date}:${log.task_id}`;
  let merged = [...remote];
  for (const groupKey of new Set([...base, ...local].map(key))) {
    const before = base.filter((log) => key(log) === groupKey);
    const after = local.filter((log) => key(log) === groupKey);
    const signature = (logs: TimeLog[]) => JSON.stringify([...logs].sort((a, b) => a.id.localeCompare(b.id)));
    if (signature(before) === signature(after)) continue;
    merged = [...merged.filter((log) => key(log) !== groupKey), ...after];
  }
  return merged;
}

/** Each item's daily time is independent of other items in the same course. */
export function recordTaskDayMinutes(data: PlannerData, taskId: string, date: string, minutes: number, runtime: PlannerRuntime = defaultPlannerRuntime): PlannerData {
  if (!Number.isInteger(minutes) || minutes < 0 || minutes > 1440) throw new Error("实际用时需要是 0–1440 之间的整数分钟");
  const task = data.tasks.find((item) => item.id === taskId);
  if (!task) throw new Error("请先创建并选择事项");
  const stamp = runtime.now().toISOString();
  const blocks = data.blocks.filter((block) => block.task_id === taskId && block.date === date);
  const logs = data.logs.filter((log) => log.task_id !== taskId || log.date !== date);
  let remaining = minutes;
  for (const block of blocks) {
    const amount = Math.min(remaining, block.duration_minutes);
    if (amount > 0) logs.push({ id: runtime.newId(), user_id: task.user_id, task_id: taskId, block_id: block.id, date, minutes: amount, started_at: stamp, ended_at: stamp, source: "manual" });
    remaining -= amount;
  }
  if (remaining > 0) logs.push({ id: runtime.newId(), user_id: task.user_id, task_id: taskId, block_id: blocks.at(-1)?.id ?? null, date, minutes: remaining, started_at: stamp, ended_at: stamp, source: "manual" });
  const total = logs.filter((log) => log.task_id === taskId).reduce((sum, log) => sum + log.minutes, 0);
  return { ...data, logs, tasks: data.tasks.map((item) => item.id === taskId ? { ...item, completed_minutes: Math.min(item.estimated_minutes, total), updated_at: stamp } : item),
    blocks: data.blocks.map((block) => block.task_id === taskId && block.date === date ? { ...block, actual_minutes: logs.filter((log) => log.block_id === block.id).reduce((sum, log) => sum + log.minutes, 0), updated_at: stamp } : block) };
}
