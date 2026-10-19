import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { resolveDayCapacity, resolveWeekCapacity, scheduleStrategy, type CapacityProfile, type StrategyInput } from "./planning-scheduler.js";

/**
 * The API owns the production copy of the strategy scheduler. It is checked against the
 * same cross-entry contract fixture as the TypeScript reference engine and the Flutter
 * mirror, so API scheduling cannot drift from the manual placement rules on its own.
 */
const fixture = JSON.parse(
  readFileSync(
    "packages/planner-engine/fixtures/scheduler-contract-cases.json",
    "utf8",
  ),
);
const clock: string = fixture.clock;

/**
 * Shared cross-end capacity contract (CONTEXT §2.2). The Dart resolver in
 * `lib/features/planner/domain/capacity.dart` must return the exact same values.
 */
const capacityFixture = JSON.parse(
  readFileSync("packages/planner-engine/fixtures/capacity-cases.json", "utf8"),
);
describe("shared day/week capacity contract", () => {
  it("fixture is the shared contract version and covers the frozen cases", () => {
    expect(capacityFixture.version).toBe(1);
    expect(capacityFixture.week_order_monday_first).toEqual([1, 2, 3, 4, 5, 6, 0]);
    expect(capacityFixture.cases.length).toBeGreaterThanOrEqual(20);
    expect(capacityFixture.cases.map((row: { name: string }) => row.name)).toEqual(expect.arrayContaining([
      "legacy-template-gross", "net-template", "date-overrides-net", "week-total-weighted-remainder",
      "baseline-distribution", "baseline-with-date-override", "baseline-rest-unallocated",
      "week-total-explicit-and-date-same-day", "week-total-rest-unallocated",
      "week-total-exceeded-by-date-override", "cross-year-week",
    ]));
  });
  for (const row of capacityFixture.cases) {
    it(`resolves ${row.name} exactly like the shared fixture`, () => {
      const profile = { ...capacityFixture.defaults, ...row.profile } as CapacityProfile;
      for (const expected of row.days) {
        expect(resolveDayCapacity(profile, expected.date)).toEqual({
          date: expected.date,
          monday: expected.monday,
          minutes: expected.minutes,
          raw_minutes: expected.raw_minutes,
          source: expected.source,
          estimated: expected.estimated,
          week_budget_minutes: expected.week_budget_minutes,
        });
      }
      for (const expected of row.weeks) {
        const week = resolveWeekCapacity(profile, expected.monday);
        expect({
          monday: week.monday,
          budget_minutes: week.budget_override_minutes,
          resolved_minutes: week.resolved_minutes,
          conflicts: week.conflicts,
        }).toEqual(expected);
      }
    });
  }
});

function buildInput(row: Record<string, any>): StrategyInput {
  return {
    profile: { ...fixture.base_profile, ...(row.profile ?? {}) },
    tasks: (row.tasks ?? []).map((task: Record<string, any>) => ({
      user_id: "fixture-user",
      subject_id: "course",
      title: task.id,
      estimated_minutes: 30,
      completed_minutes: 0,
      priority: 2,
      deadline: row.to,
      is_fixed: false,
      status: "not_started",
      ...task,
    })),
    blocks: (row.blocks ?? []).map((block: Record<string, any>) => ({
      user_id: "fixture-user",
      start_minute: 0,
      duration_minutes: 30,
      actual_minutes: 0,
      is_fixed: false,
      status: "planned",
      created_at: clock,
      updated_at: clock,
      ...block,
    })),
    logs: (row.logs ?? []).map((log: Record<string, any>) => ({
      user_id: "fixture-user",
      block_id: null,
      started_at: clock,
      ended_at: clock,
      source: "manual",
      ...log,
    })),
    fixed_events: (row.fixed_events ?? []).map((event: Record<string, any>) => ({
      user_id: "fixture-user",
      title: event.id,
      date: row.from,
      kind: "course",
      repeat: "none",
      ...event,
    })),
  } as StrategyInput;
}

describe("API planning scheduler contract", () => {
  for (const row of fixture.cases) {
    const expected = row.expected_auto;
    if (!expected) continue;
    it(row.name, () => {
      const input = buildInput(row);
      const before = JSON.stringify(input);
      let id = 0;
      const result = scheduleStrategy(input, row.from, row.to, {
        now: () => new Date(clock),
        newId: () => `contract-${++id}`,
      });
      expect(JSON.stringify(input)).toBe(before);
      expect({
        scheduled: result.scheduled_minutes,
        unscheduled: result.unscheduled_minutes,
        issues: result.issues.map((issue) => issue.code).sort(),
      }).toEqual({
        scheduled: expected.scheduled,
        unscheduled: expected.unscheduled,
        issues: expected.issues,
      });
      expect(
        result.blocks
          .filter(
            (block) => !input.blocks.some((original) => original.id === block.id),
          )
          .map((block) => ({
            task_id: block.task_id,
            date: block.date,
            start_minute: block.start_minute,
            duration_minutes: block.duration_minutes,
          })),
      ).toEqual(expected.new_blocks);
    });
  }
});

describe("retired fixed events", () => {
  it.each(["daily", "timed"])("ignores every legacy event type and repeat rule in %s plans", planning_mode => {
    const input = buildInput({
      from: "2026-10-19", to: "2026-10-20",
      profile: { planning_mode, plan_start_date: "2026-10-19", plan_end_date: "2026-10-20",
        daily_limit_minutes: 150, study_start_minute: 480, study_end_minute: 720,
        weekly_minutes: { "0": 0, "1": 150, "2": 150, "3": 0, "4": 0, "5": 0, "6": 0 } },
      tasks: [{ id: "work", estimated_minutes: 240 }],
      fixed_events: [
        { id: "lunch", date: "2026-10-01", start_minute: 0, duration_minutes: 1440, kind: "rest", repeat: "daily" },
        { id: "course", date: "2026-10-12", start_minute: 0, duration_minutes: 1440, kind: "course", repeat: "weekly" },
        { id: "exam", date: "2026-10-20", start_minute: 0, duration_minutes: 1440, kind: "official_exam", repeat: "none" },
      ],
    });
    const run = (value: StrategyInput) => {
      let id = 0;
      return scheduleStrategy(value, "2026-10-19", "2026-10-20", {
        now: () => new Date(clock), newId: () => `retired-event-${++id}`,
      });
    };
    expect(run(input)).toEqual(run({ ...input, fixed_events: [] }));
    expect(run(input).scheduled_minutes).toBe(240);
  });
});

describe("flexible capacity scheduling (net / overrides / priority mixing)", () => {
  const profile = (extra: Record<string, unknown> = {}) => ({
    user_id: "user", planning_mode: "daily" as const, daily_limit_minutes: 480, buffer_minutes: 30,
    granularity_minutes: 30, subject_limit_minutes: 240, study_start_minute: 480, study_end_minute: 1320,
    plan_start_date: "2026-10-19", plan_end_date: "2026-10-25",
    weekly_minutes: { "0": 0, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 0 },
    ...extra,
  });
  const task = (id: string, extra: Record<string, unknown> = {}) => ({
    id, user_id: "user", subject_id: "course", title: id, estimated_minutes: 30, completed_minutes: 0,
    priority: 2, deadline: "2026-10-25", is_fixed: false, status: "not_started", ...extra,
  });
  const run = (input: StrategyInput) => {
    let id = 0;
    return scheduleStrategy(input, "2026-10-19", "2026-10-25", { now: () => new Date(clock), newId: () => `block-${++id}` });
  };
  const newBlocks = (result: ReturnType<typeof run>, input: StrategyInput) =>
    result.blocks.filter(block => !input.blocks.some(original => original.id === block.id));

  it("keeps the legacy gross 30-minute buffer and 480 ceiling exactly as before", () => {
    const input = { profile: profile({ weekly_minutes: { "0": 0, "1": 20, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 } }),
      tasks: [task("reading", { estimated_minutes: 60 })], blocks: [], logs: [], fixed_events: [] } as StrategyInput;
    const result = run(input);
    // Gross: max(0, min(480,20) - 30) = 0 capacity, so nothing is scheduled.
    expect(result.scheduled_minutes).toBe(0);
    expect(result.unscheduled_minutes).toBe(60);
    expect(newBlocks(result, input)).toEqual([]);
  });

  it("schedules a suitable short block on a 20-minute net day (10-minute minimum)", () => {
    const input = { profile: profile({ capacity_basis: "net",
      weekly_minutes: { "0": 0, "1": 20, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 } }),
      tasks: [task("reading", { estimated_minutes: 60 })], blocks: [], logs: [], fixed_events: [] } as StrategyInput;
    const result = run(input);
    expect(result.scheduled_minutes).toBe(20);
    expect(newBlocks(result, input).map(block => [block.date, block.duration_minutes])).toEqual([["2026-10-19", 20]]);
  });

  it("respects an explicit zero date override as a rest day and a clear override as capacity", () => {
    const input = { profile: profile({ capacity_basis: "net",
      date_capacity_overrides: { "2026-10-19": 0, "2026-10-20": 150 } }),
      tasks: [task("reading", { estimated_minutes: 600 })], blocks: [], logs: [], fixed_events: [] } as StrategyInput;
    const result = run(input);
    const byDate = new Map<string, number>();
    for (const block of newBlocks(result, input)) byDate.set(block.date, (byDate.get(block.date) ?? 0) + block.duration_minutes);
    expect(byDate.has("2026-10-19")).toBe(false);
    expect(byDate.get("2026-10-20")).toBe(150);
  });

  it("never exceeds a confirmed weekly total when it is distributed over the template days", () => {
    const input = { profile: profile({ capacity_basis: "net",
      week_capacity_overrides: { "2026-10-19": { total_minutes: 100 } } }),
      tasks: [task("reading", { estimated_minutes: 900 })], blocks: [], logs: [], fixed_events: [] } as StrategyInput;
    const result = run(input);
    const mondayWeek = newBlocks(result, input).filter(block => block.date >= "2026-10-19" && block.date <= "2026-10-25");
    expect(mondayWeek.reduce((sum, block) => sum + block.duration_minutes, 0)).toBe(100);
  });

  it("lets urgent finite work win a contested day over low-priority recurring practice", () => {
    const input = { profile: profile({ capacity_basis: "net",
      weekly_minutes: { "0": 0, "1": 30, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 } }),
      tasks: [
        task("exam", { estimated_minutes: 30, priority: 3, deadline: "2026-10-19" }),
        task("practice", { estimated_minutes: 60, priority: 1,
          planning: { activity: { kind: "recurring", starts_on: "2026-10-19", ends_on: "2026-10-25", sessions_per_week: 1, session_minutes: 30 } } }),
      ], blocks: [], logs: [], fixed_events: [] } as StrategyInput;
    const result = run(input);
    expect(newBlocks(result, input).map(block => block.task_id)).toEqual(["exam"]);
    expect(result.unscheduled_minutes).toBe(30);
    expect(result.issues.map(issue => issue.code)).toContain("RECURRENCE_SHORTFALL");
  });

  it("treats an unconfirmed date value as capacity but still reports the week conflict", () => {
    const week = resolveWeekCapacity(profile({ capacity_basis: "net",
      week_capacity_overrides: { "2026-10-19": { total_minutes: 100 } },
      date_capacity_overrides: { "2026-10-19": 150 } }), "2026-10-19");
    expect(week.budget_override_minutes).toBe(100);
    expect(week.days["2026-10-19"]).toBe(150);
    expect(week.conflicts).toEqual([{ code: "WEEK_TOTAL_EXCEEDED", total: 100, resolved: 150 }]);
  });
});
