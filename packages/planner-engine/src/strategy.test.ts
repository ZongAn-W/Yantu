import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { scheduleStrategy, type StrategyInput, type StrategyTask } from "./index";

const fixture = JSON.parse(readFileSync("packages/planner-engine/fixtures/strategy-cases.json", "utf8"));
export function strategyInput(row: any): StrategyInput {
  return {
    profile: { user_id: "fixture-user", planning_mode: "daily", daily_limit_minutes: 120, buffer_minutes: 30,
      granularity_minutes: 30, study_start_minute: 480, study_end_minute: 1320,
      plan_start_date: row.plan_start_date ?? row.from, plan_end_date: row.plan_end_date ?? row.to,
      weekly_minutes: row.weekly_minutes ?? { "0": 0, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 0 },
      ...(row.profile ?? {}) },
    tasks: row.tasks.map((task: Partial<StrategyTask>) => ({ user_id: "fixture-user",
      title: task.id, estimated_minutes: 30, completed_minutes: 0, priority: 2, deadline: row.to,
      is_fixed: false, archived: false, ...task })),
    blocks: row.blocks ?? [], logs: row.logs ?? [], fixed_events: (row.fixed_events ?? []).map((event: any) => ({
      date: row.from, repeat: "none", kind: "course", ...event })),
  };
}

describe("shared strategy business fixtures", () => {
  for (const row of fixture.cases) it(row.name, () => {
    const input = strategyInput(row), before = structuredClone(input);
    let id = 0;
    const runtime = { now: () => new Date(fixture.clock), newId: () => `strategy-${++id}` };
    const result = scheduleStrategy(input, row.from, row.to, runtime);
    expect(input).toEqual(before);
    for (const original of input.blocks) expect(result.blocks.find(block => block.id === original.id)).toEqual(original);
    if (row.expected_new_starts) expect(result.blocks.filter(block => !input.blocks.some(old => old.id === block.id))
      .map(block => block.start_minute).sort((a, b) => a - b)).toEqual(row.expected_new_starts);
    expect({ scheduled: result.scheduled_minutes, unscheduled: result.unscheduled_minutes,
      instances: result.blocks.filter(block => block.activity_instance_id).length,
      last_date: result.blocks.map(block => block.date).sort().at(-1) ?? null,
      issues: result.issues.map(issue => issue.code).sort() }).toEqual(row.expected);
    const again = scheduleStrategy({ ...input, blocks: result.blocks }, row.from, row.to, runtime);
    expect(again.added).toBe(0);
    expect(again.blocks).toEqual(result.blocks);
    for (const block of result.blocks) {
      expect(block.date >= row.from && block.date <= row.to).toBe(true);
      expect(input.profile.weekly_minutes![String(new Date(`${block.date}T00:00:00Z`).getUTCDay())]).toBeGreaterThan(0);
    }
    if (row.name.includes("planned prerequisites")) {
      expect(result.blocks.find(block => block.task_id === "chapter")!.date).toBe("2026-10-12");
      expect(result.blocks.find(block => block.task_id === "assessment")!.date).toBe("2026-10-13");
    }
  });
});
