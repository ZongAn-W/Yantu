import { describe, expect, it } from "vitest";
import { mergeTaskDayLogs, recordTaskDayMinutes } from "./study-records";
import type { PlannerData, Task } from "./types";

function fixture(): PlannerData {
  const stamp = "2026-10-14T00:00:00Z";
  const tasks: Task[] = ["基础一轮", "专题强化"].map((title, index) => ({
    id: `item-${index}`, user_id: "demo", tag_ids: [], title,
    description: "范围与完成标准", estimated_minutes: 120, completed_minutes: 0,
    priority: 3, deadline: "2026-12-31", earliest_date: "2026-10-01",
    is_fixed: false, archived: false, created_at: stamp, updated_at: stamp,
  }));
  return {
    version: 1,
    profile: { user_id: "demo", target_school: "上海交通大学", target_program: "408",
      exam_date: "2027-12-25", exam_end_date: "2027-12-26", daily_limit_minutes: 480,
      buffer_minutes: 30, granularity_minutes: 30,
      study_start_minute: 0, study_end_minute: 1440, foundation: "", planning_mode: "daily" },
    tags: [],
    tasks, logs: [], fixed_events: [], replan_runs: [], phases: [],
    blocks: tasks.map((task) => ({ id: `block-${task.id}`, user_id: "demo", task_id: task.id,
      date: "2026-10-14", start_minute: 0, duration_minutes: 60, actual_minutes: 0,
      status: "planned", is_fixed: false, created_at: stamp, updated_at: stamp })),
  };
}

const total = (data: PlannerData, taskId: string) =>
  data.logs.filter((log) => log.task_id === taskId).reduce((sum, log) => sum + log.minutes, 0);

describe("course item study records", () => {
  it("corrects archived history without reactivating the task", () => {
    const original = fixture();
    original.tasks[0].archived = true;
    const recorded = recordTaskDayMinutes(original, "item-0", "2026-10-14", 150);
    const corrected = recordTaskDayMinutes(recorded, "item-0", "2026-10-14", 0);
    expect(recorded.tasks[0].archived).toBe(true);
    expect(recorded.tasks[0].completed_minutes).toBe(120);
    expect(corrected.tasks[0].archived).toBe(true);
    expect(corrected.tasks[0].completed_minutes).toBe(0);
  });

  it("keeps two items in one course independent", () => {
    let data = recordTaskDayMinutes(fixture(), "item-0", "2026-10-14", 90);
    data = recordTaskDayMinutes(data, "item-1", "2026-10-14", 45);
    data = recordTaskDayMinutes(data, "item-0", "2026-10-14", 20);
    expect(total(data, "item-0")).toBe(20);
    expect(total(data, "item-1")).toBe(45);
    expect(data.tasks[0].completed_minutes).toBe(20);
    expect(data.tasks[1].completed_minutes).toBe(45);
  });

  it("merges concurrent edits by item and date", () => {
    const base = fixture();
    const local = recordTaskDayMinutes(base, "item-0", "2026-10-14", 20);
    const remote = recordTaskDayMinutes(base, "item-1", "2026-10-14", 35);
    const merged = mergeTaskDayLogs(base.logs, local.logs, remote.logs);
    expect(merged.reduce((sum, log) => sum + log.minutes, 0)).toBe(55);
    expect(new Set(merged.map((log) => log.task_id))).toEqual(new Set(["item-0", "item-1"]));
  });

  it("retains actual minutes above the planned time", () => {
    const data = recordTaskDayMinutes(fixture(), "item-0", "2026-10-14", 150);
    expect(total(data, "item-0")).toBe(150);
    expect(data.tasks[0].completed_minutes).toBe(120);
  });

  it("rejects invalid item records without mutation", () => {
    const data = fixture();
    expect(() => recordTaskDayMinutes(data, "missing", "2026-10-14", 30)).toThrow();
    expect(() => recordTaskDayMinutes(data, "item-0", "2026-10-14", 0.5)).toThrow();
    expect(data.logs).toHaveLength(0);
  });
});
