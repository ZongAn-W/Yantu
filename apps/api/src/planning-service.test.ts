import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession, type OnboardingSession } from "./onboarding-contracts.js";
import { ProfileSchema } from "./contracts.js";
import { advanceOnboarding } from "./onboarding.js";
import { buildPlanningDocument, checkLearningStrategy, checkScheduledPlan, evaluatePlanning, existingPlanMode, frozenInputs, newPlanning, normalizePlanningMetadata, planningHash } from "./planning-service.js";
import { checkAndRepair } from "./planning-repair.js";

const settings = vi.hoisted(() => ({ aiApiKey: "" }));
vi.mock("./config.js", () => ({ config: settings }));
const week = { "0": 0, "1": 180, "2": 120, "3": 0, "4": 90, "5": 120, "6": 240 };
function fixture(): OnboardingSession {
  return { ...newSession(), stage: "schedule", constraints_confirmed: true, start_date: "2026-10-17", end_date: "2026-11-13",
    profile: ProfileSchema.parse({ goal_type: "skill", goal_text: "用Python处理CSV", weekly_minutes: week,
      plan_start_date: "2026-10-17", plan_end_date: "2026-11-13" }),
    items: [{ id: "project", tag_names: ["Python"], title: "CSV数据清理成果", description: "清理样例数据", completion_criteria: "脚本运行通过",
      estimated_minutes: 120, earliest_date: "2026-10-17", deadline: "2026-11-13", deadline_kind: "plan_end", priority: 2,
      planning: { activity: { kind: "finite" }, dependencies: [] } }],
    planning: { ...newPlanning(), route: [{ id: "deliver", title: "数据清理成果", item_ids: ["project"], outcome: "可运行脚本", check: "通过样例" }] } };
}

function existingFixture() {
  const source = fixture(), current = buildPlanningDocument(source).document;
  const task = current.tasks[0];
  const session = structuredClone(source);
  session.items = [{ ...source.items[0], id: task.id, tag_names: task.tag_ids.map(id => current.tags.find(tag => tag.id === id)!.name),
    description: task.description ?? "", completion_criteria: "" }];
  session.planning!.route[0].item_ids = [task.id];
  session.current_plan = { tags: current.tags, items: current.tasks };
  return { session, current };
}
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date("2026-10-17T04:00:00Z")); settings.aiApiKey = ""; });
afterEach(() => vi.useRealTimers());

describe("learning budget and strategy quality", () => {
  it.each(["daily", "timed"] as const)("ignores legacy fixed events during %s replanning and independent validation", planning_mode => {
    const { session, current } = existingFixture();
    current.profile.planning_mode = planning_mode;
    const baseline = buildPlanningDocument(session, current);
    current.fixed_events = [{ id: "legacy-lunch", user_id: current.profile.user_id, title: "午休与午餐",
      date: session.start_date, start_minute: 0, duration_minutes: 1440, kind: "rest", repeat: "daily",
      created_at: "2026-10-01T00:00:00Z", updated_at: "2026-10-01T00:00:00Z" }];
    const actual = buildPlanningDocument(session, current);
    const allocations = (value: typeof actual) => value.document.blocks.map(({ id, ...block }) => block);
    expect(allocations(actual)).toEqual(allocations(baseline));
    expect(actual.document.fixed_events).toEqual(current.fixed_events);
    expect(checkScheduledPlan(actual.document, session.start_date, session.end_date)).toEqual(
      checkScheduledPlan(baseline.document, session.start_date, session.end_date),
    );
  });

  it("independently rejects new allocations outside the cycle or above capacity", () => {
    const trial = buildPlanningDocument(fixture()).document;
    const block = trial.blocks[0];
    trial.blocks = [{ ...block, duration_minutes: 600, date: "2026-10-18" }];
    expect(checkScheduledPlan(trial, "2026-10-17", "2026-10-17").map(issue => issue.code))
      .toEqual(expect.arrayContaining(["SCHEDULE_BOUNDARY", "REST_DAY", "DAILY_CAPACITY"]));
  });

  it("no longer blocks or warns on time-only estimates without structured workload", () => {
    const session = fixture();
    // 纯时间口径：没有 planning 元数据、也没有内容量字段时不再出现工作量/内容进度类问题。
    session.items[0].planning = undefined;
    const removedCodes = ["LEGACY_ESTIMATE", "WORKLOAD_UNKNOWN", "WORKLOAD_MISMATCH", "EXECUTION_FACT_CHANGED", "WORKLOAD_RANGE"];
    expect(checkLearningStrategy(session).filter(issue => removedCodes.includes(issue.code))).toEqual([]);
    session.items[0].planning = { activity: { kind: "finite" }, dependencies: [] };
    expect(checkLearningStrategy(session).filter(issue => issue.severity === "error")).toEqual([]);
  });

  it("keeps an unknown target date and generates the full 28-day cycle by default", () => {
    const session = fixture(), result = evaluatePlanning(session);
    expect(session.profile.target_date).toBeNull();
    // New plans default to full-period coverage: never truncated at 14 days.
    expect(result.preview.mode).toBe("full");
    expect(result.preview.detailed_until).toBe(session.end_date);
    expect(result.preview.detailed_until).toBe("2026-11-13");
    expect(result.planning.mode).toBe("full");
    expect(result.planning.rolling).toBe(false);
    expect(result.planning.detail_days).toBe(28);
    expect(result.planning.forecast).toBeNull();
    expect(result.preview.days.every(day => day.date >= session.start_date && day.date <= session.end_date)).toBe(true);
    expect(result.preview.issues.some(issue => issue.severity === "error")).toBe(false);
    expect(result.preview.scheduled_minutes).toBe(120);
    expect(result.planning.route[0].outcome).toBe("可运行脚本");
  });

  it("does not interpret legitimate spare time as failure", () => {
    const session = fixture();
    session.profile.goal_type = "self_study";
    const result = evaluatePlanning(session);
    expect(result.preview.status).toBe("ready");
    expect(result.preview.issues).toEqual([]);
    expect(result.preview.days.length).toBe(1);
  });

  it("catches dependency cycles, missing parents and route references independently", () => {
    const session = fixture();
    session.items[0].planning!.dependencies = [{ task_id: "project", mode: "confirmed" }, { task_id: "missing", mode: "planned" }];
    session.planning!.route[0].item_ids.push("missing");
    expect(checkLearningStrategy(session).map(issue => issue.code)).toEqual(expect.arrayContaining(["DEPENDENCY_CYCLE", "DEPENDENCY_MISSING", "ROUTE_REFERENCE"]));
    expect(evaluatePlanning(session).preview.status).toBe("blocked");
  });

  it("recurring practice persists through the full long activity window, without duplicate cycle budgets", () => {
    const session = fixture();
    session.end_date = "2027-12-21";
    session.profile.plan_end_date = session.end_date;
    session.items[0].deadline = session.end_date;
    session.items[0].estimated_minutes = 30;
    session.items[0].planning!.activity = { kind: "recurring", starts_on: session.start_date, ends_on: session.end_date, sessions_per_week: 2, session_minutes: 30 };
    session.planning!.rolling = false;
    const trial = buildPlanningDocument(session);
    expect(trial.document.blocks.some(block => block.date.startsWith("2027-12"))).toBe(true);
    expect(trial.document.blocks.some(block => block.date.startsWith("2027-03"))).toBe(true);
    expect(trial.document.tasks[0].estimated_minutes).toBe(trial.document.blocks.reduce((sum, block) => sum + block.duration_minutes, 0));
    const ids = trial.document.blocks.map(block => block.activity_instance_id);
    expect(new Set(ids).size).toBe(ids.length);
    expect(trial.document.blocks.every(block => (week as Record<string, number>)[String(new Date(`${block.date}T00:00:00Z`).getUTCDay())] > 30)).toBe(true);
  });

  it("reports a small-capacity recurrence deficit without changing session scope", () => {
    const session = fixture();
    session.profile.weekly_minutes = { "0": 0, "1": 60, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 };
    session.items[0].planning!.activity = { kind: "recurring", starts_on: session.start_date, ends_on: session.end_date, sessions_per_week: 3, session_minutes: 120 };
    const result = evaluatePlanning(session);
    expect(result.preview.status).toBe("ready");
    expect(result.preview.unscheduled_minutes).toBeGreaterThan(0);
    expect(result.preview.issues.some(issue => issue.code === "RECURRENCE_SHORTFALL")).toBe(true);
    expect(session.items[0].planning!.activity.session_minutes).toBe(120);
    expect(session.profile.weekly_minutes["1"]).toBe(60);
  });

  it("requires a fresh preview after constraint changes, and does not mutate the original", async () => {
    const session = fixture();
    const fields = { start_date: session.start_date, end_date: session.end_date, weekly_minutes: week };
    const preview = await advanceOnboarding(session, { type: "preview_schedule", ...fields, detail_days: 14 });
    const finish = { type: "finish" as const, ...fields, preview_token: preview.preview!.token as string };
    expect((await advanceOnboarding(preview, finish)).stage).toBe("complete");
    await expect(advanceOnboarding(preview, { ...finish, weekly_minutes: { ...week, "6": 0 } })).rejects.toThrow("重新检查");
    expect(session.preview).toBeNull();
    expect(preview.preview!.status).toBe("ready");
  });

  it("finishes at most two model repairs and keeps hard failures", async () => {
    const session = fixture();
    // 缺失前置事项是硬错误；修复不补全时重试两次后保留最后一次结果。
    session.items[0].planning!.dependencies = [{ task_id: "prereq", mode: "planned" }];
    settings.aiApiKey = "test";
    const revise = vi.fn(async () => ({ items: session.items, planning: session.planning!, summary: "", assumptions: [], warnings: [] }));
    const result = await checkAndRepair(session, null, revise);
    expect(revise).toHaveBeenCalledTimes(2);
    expect(result.preview!.status).toBe("blocked");
    expect(result.preview!.repairs).toBe(2);
    expect(result.items).toEqual(session.items);
  });

  it("accepts the first repaired candidate and stops, but preserves drafts on network errors", async () => {
    const session = fixture();
    session.items[0].planning!.dependencies = [{ task_id: "prereq", mode: "planned" }];
    settings.aiApiKey = "test";
    // 修复补全缺失的前置事项：这是不改变已确认预算与活动策略的合法修复。
    const prereq = { ...session.items[0], id: "prereq", title: "先修章节", estimated_minutes: 30,
      planning: { activity: { kind: "finite" as const }, dependencies: [] } };
    const revise = vi.fn(async () => ({ items: [...session.items, prereq], planning: session.planning!, summary: "", assumptions: [], warnings: [] }));
    expect((await checkAndRepair(session, null, revise)).preview!.status).toBe("ready");
    expect(revise).toHaveBeenCalledTimes(1);
    const failed = await checkAndRepair(session, null, async () => { throw new Error("AI 请求超时"); });
    expect(failed.items).toEqual(session.items);
    expect(failed.preview!.issues).toEqual(expect.arrayContaining([expect.objectContaining({ code: "REPAIR_FAILED" })]));
  });

  it.each(["frequency", "pause"])("keeps scope unchanged when a repair proposes changing %s", async change => {
    const session = fixture();
    session.items[0].planning!.activity = {
      kind: "recurring", starts_on: session.start_date, ends_on: session.end_date,
      sessions_per_week: 3, session_minutes: 120, state: "active",
    };
    session.profile.weekly_minutes = { "0": 0, "1": 60, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 };
    settings.aiApiKey = "test";
    const revise = vi.fn(async () => {
      const items = structuredClone(session.items), item = items[0];
      if (change === "frequency") item.planning!.activity!.sessions_per_week = 1;
      if (change === "pause") item.planning!.activity!.state = "paused";
      return { items, planning: session.planning!, summary: "", assumptions: [], warnings: [] };
    });
    const result = await checkAndRepair(session, null, revise);
    expect(result.items).toEqual(session.items);
    expect(result.planning!.risks).toEqual(expect.arrayContaining([expect.stringContaining("范围取舍尚未应用")]));
    expect(result.preview!.issues).toEqual(expect.arrayContaining([expect.objectContaining({ code: "SCOPE_CHANGE_PROPOSAL" })]));
    expect(result.preview!.fingerprint).toBe(planningHash(frozenInputs(result)));
    expect(revise).toHaveBeenCalledTimes(1);
  });

  it("refuses a repair that silently reduces a confirmed time budget", async () => {
    const session = fixture();
    session.items[0].planning!.activity = {
      kind: "recurring", starts_on: session.start_date, ends_on: session.end_date,
      sessions_per_week: 3, session_minutes: 120, state: "active",
    };
    session.profile.weekly_minutes = { "0": 0, "1": 60, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 };
    settings.aiApiKey = "test";
    const revise = vi.fn(async () => ({ items: session.items.map(item => ({ ...item, estimated_minutes: 60 })),
      planning: session.planning!, summary: "", assumptions: [], warnings: [] }));
    const result = await checkAndRepair(session, null, revise);
    expect(result.items).toEqual(session.items);
    expect(result.planning!.risks).toEqual(expect.arrayContaining([expect.stringContaining("范围取舍尚未应用")]));
    expect(result.preview!.issues).toEqual(expect.arrayContaining([expect.objectContaining({ code: "SCOPE_CHANGE_PROPOSAL" })]));
  });

  it("does not relabel a real deadline as the planning boundary during a repair", async () => {
    const session = fixture();
    // 真实截止日期过近导致未排完，触发一次修复尝试。
    session.items[0].deadline_kind = "deadline";
    session.items[0].estimated_minutes = 300;
    session.items[0].deadline = session.start_date;
    settings.aiApiKey = "test";
    const result = await checkAndRepair(session, null, async () => ({
      items: session.items.map(item => ({ ...item, deadline_kind: "plan_end" as const, deadline: session.end_date })),
      planning: session.planning!, summary: "", assumptions: [], warnings: [],
    }));
    expect(result.items[0].deadline_kind).toBe("deadline");
    expect(result.preview!.issues).toEqual(expect.arrayContaining([expect.objectContaining({ code: "REPAIR_FAILED", message: expect.stringContaining("真实截止日期") })]));
  });

  it.each(["task", "block"])("protects planning metadata and budgets when the %s is fixed", fixed => {
    const { session, current } = existingFixture();
    if (fixed === "task") current.tasks[0].is_fixed = true;
    else current.blocks[0].is_fixed = true;
    const original = structuredClone(current);
    const unchanged = buildPlanningDocument(session, current);
    expect(unchanged.document.tasks[0].estimated_minutes).toBe(current.tasks[0].estimated_minutes);
    session.items[0].planning = { activity: { kind: "recurring", starts_on: session.start_date,
        ends_on: session.end_date, sessions_per_week: 1, session_minutes: 30 } };
    const result = evaluatePlanning(session, current);
    expect(result.preview.status).toBe("blocked");
    expect(result.preview.issues).toEqual(expect.arrayContaining([expect.objectContaining({ message: expect.stringContaining("固定事项") })]));
    expect(() => buildPlanningDocument(session, current)).toThrow("活动策略不能修改");
    expect(current).toEqual(original);
  });

  it("protects real deadlines even when legacy items lack planning metadata", () => {
    const { session, current } = existingFixture();
    current.tasks[0].deadline_kind = "deadline";
    session.items[0].deadline_kind = "deadline";
    session.items[0].deadline = "2026-12-31";
    session.items[0].planning = undefined;
    expect(checkLearningStrategy(session)).toEqual(expect.arrayContaining([expect.objectContaining({ code: "HARD_DEADLINE_CHANGED" })]));
    expect(evaluatePlanning(session, current).preview.status).toBe("blocked");
    expect(() => buildPlanningDocument(session, current)).toThrow("真实截止日期");
  });

  it("checks the actual reused identity when generated draft ids change", () => {
    const { session, current } = existingFixture();
    current.tasks[0].deadline_kind = "deadline";
    session.items[0] = { ...session.items[0], id: "replacement-draft-id",
      deadline_kind: "deadline", deadline: "2026-12-31" };
    session.planning!.route[0].item_ids = [session.items[0].id];
    const result = evaluatePlanning(session, current);
    expect(result.preview.status).toBe("blocked");
    expect(result.preview.issues).toEqual(expect.arrayContaining([expect.objectContaining({ message: expect.stringContaining("复用了已有记录") })]));
    expect(() => buildPlanningDocument(session, current)).toThrow("真实截止日期");
  });
});

const addDays = (date: string, days: number) => new Date(Date.parse(`${date}T00:00:00Z`) + days * 86_400_000).toISOString().slice(0, 10);
const fullWeek = { "0": 120, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 120 };

function fullFixture(days: number, profileExtra: Record<string, unknown> = {}) {
  const start = "2026-10-17", end = addDays(start, days - 1);
  return { ...newSession(), stage: "schedule" as const, constraints_confirmed: true, start_date: start, end_date: end,
    profile: ProfileSchema.parse({ goal_type: "skill", goal_text: "全周期学习", weekly_minutes: fullWeek,
      plan_start_date: start, plan_end_date: end, ...profileExtra }),
    items: [{ id: "long", tag_names: [], title: "长期内容", description: "", completion_criteria: "",
      estimated_minutes: Math.min(100000, days * 120), earliest_date: start, deadline: end,
      deadline_kind: "plan_end" as const, priority: 2 }],
    planning: newPlanning() };
}

describe("full-period planning (default mode)", () => {
  it.each([28, 90, 431])("covers a %i-day cycle end to end without a 14/90-day truncation", days => {
    const session = fullFixture(days);
    const result = evaluatePlanning(session);
    expect(result.preview.mode).toBe("full");
    expect(result.planning.mode).toBe("full");
    expect(result.planning.rolling).toBe(false);
    expect(result.planning.detail_days).toBe(days);
    expect(result.planning.detail_days!).toBeLessThanOrEqual(1095);
    expect(result.preview.detailed_until).toBe(session.end_date);
    expect(result.planning.detailed_until).toBe(session.end_date);
    // Full mode has no "rest of cycle still to be detailed" interval: forecast is null, never inverted.
    expect(result.planning.forecast).toBeNull();
    expect(result.preview.forecast_minutes).toBe(0);
    // The final part of the cycle really has scheduled blocks, not just the first 14 days.
    const lastDay = result.preview.days.at(-1)!;
    expect(lastDay.date).toBe(session.end_date);
    expect(lastDay.minutes).toBeGreaterThan(0);
    expect(result.preview.days.length).toBe(days);
    const trial = buildPlanningDocument(session);
    expect(trial.until).toBe(session.end_date);
    expect(trial.document.planning!.mode).toBe("full");
    expect(trial.document.planning!.forecast).toBeNull();
    expect(trial.document.planning!.capacity).toBeTruthy();
  });

  it("does not silently upgrade an inherited rolling plan and keeps its detail window", () => {
    const session = fullFixture(90);
    session.planning = { ...newPlanning(), mode: "rolling", rolling: true, detail_days: 14 };
    const result = evaluatePlanning(session);
    expect(result.preview.mode).toBe("rolling");
    expect(result.planning.mode).toBe("rolling");
    expect(result.planning.rolling).toBe(true);
    expect(result.planning.detail_days).toBe(14);
    expect(result.preview.detailed_until).toBe(addDays(session.start_date, 13));
    expect(result.planning.forecast).toMatchObject({ from: addDays(session.start_date, 14), to: session.end_date, confirmed: false });
    expect((result.planning.forecast as { from: string }).from <= (result.planning.forecast as { to: string }).to).toBe(true);
  });

  it("reads the inherited mode from the current plan document for a re-interview", () => {
    const session = fullFixture(28);
    session.planning = null as never;
    session.current_plan = { planning: { version: 1, rolling: true, detail_days: 14 } };
    expect(existingPlanMode(session)).toBe("rolling");
    expect(normalizePlanningMetadata(newPlanning(), { start_date: session.start_date, end_date: session.end_date }).mode).toBe("full");
    expect(normalizePlanningMetadata({ ...newPlanning(), mode: "rolling", rolling: true }, { start_date: session.start_date,
      end_date: session.end_date, requested_detail_days: 30 }).detail_days).toBe(30);
  });

  it("exposes confirmed capacity assumptions and baseline/range reachability in the preview and planning metadata", () => {
    const session = fullFixture(28, { capacity_basis: "net", weekly_baseline_minutes: 210,
      weekly_range_min_minutes: 180, weekly_range_max_minutes: 420,
      weekly_minutes: { "0": 60, "1": 60, "2": 60, "3": 60, "4": 60, "5": 60, "6": 60 } });
    session.items[0].estimated_minutes = 840;
    const result = evaluatePlanning(session);
    expect(result.preview.capacity.basis).toBe("net");
    expect(result.preview.capacity.adopted_weekly_minutes).toBe(210);
    expect(result.preview.capacity.source).toBe("baseline");
    // The 28-day cycle intersects five natural Monday..Sunday weeks.
    expect(result.preview.capacity.weeks).toHaveLength(5);
    expect(result.preview.capacity.weeks.every(week => week.budget_minutes === 210 && week.estimated)).toBe(true);
    expect(result.preview.capacity.weeks.reduce((sum, week) => sum + week.resolved_minutes, 0)).toBe(1050);
    expect(result.preview.capacity.weekly_range_minutes).toEqual({ min: 180, max: 420 });
    expect(result.preview.capacity.assumptions.join("\n")).toContain("基线");
    expect(result.planning.capacity).toMatchObject({ basis: "net", adopted_weekly_minutes: 210, source: "baseline",
      weeks_estimated: 5, partial_week_rule: "full_week_distribution_cycle_clipped" });
  });

  it("surfaces week/date capacity conflicts as structured warnings instead of silently picking a side", () => {
    const session = fullFixture(28, { capacity_basis: "net",
      week_capacity_overrides: { "2026-10-19": { total_minutes: 100 } },
      date_capacity_overrides: { "2026-10-19": 150 } });
    const result = evaluatePlanning(session);
    expect(result.preview.status).toBe("ready");
    const conflict = result.preview.issues.find(issue => issue.code === "WEEK_CAPACITY_CONFLICT");
    expect(conflict).toMatchObject({ severity: "warning", date: "2026-10-19", expected: 100, actual: 150 });
    expect(result.preview.capacity.weeks.find(week => week.monday === "2026-10-19")?.conflicts)
      .toEqual([{ code: "WEEK_TOTAL_EXCEEDED", total: 100, resolved: 150 }]);
    expect(result.planning.capacity).toMatchObject({ conflicts: [expect.objectContaining({ code: "WEEK_TOTAL_EXCEEDED", monday: "2026-10-19" })] });
  });

  it("reports structured capacity-change impact for protected records and real deadlines", () => {
    const { session, current } = existingFixture();
    // A record before the new cycle is protected history and must stay exactly as-is.
    current.blocks[0].date = "2026-10-10";
    current.tasks[0].deadline = "2026-10-20";
    current.tasks[0].deadline_kind = "deadline";
    session.end_date = "2026-12-31";
    session.profile.plan_end_date = session.end_date;
    session.items[0].deadline = "2026-10-20";
    session.items[0].deadline_kind = "deadline";
    session.profile.weekly_minutes = { "0": 0, "1": 60, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 };
    const result = evaluatePlanning(session, current);
    expect(result.preview.status).toBe("ready");
    expect(result.preview.capacity_impact.kept_blocks).toBeGreaterThanOrEqual(1);
    expect(result.preview.capacity_impact.kept_minutes).toBeGreaterThan(0);
    expect(result.preview.capacity_impact.released_blocks).toBeGreaterThanOrEqual(0);
    expect(result.preview.capacity_impact.added_blocks).toBeGreaterThan(0);
    expect(result.preview.capacity_impact.unscheduled_minutes).toBeGreaterThan(0);
    expect(result.preview.capacity_impact.deadline_at_risk).toEqual([
      expect.objectContaining({ item_id: session.items[0].id, deadline: "2026-10-20", unscheduled_minutes: 60 }),
    ]);
  });
});
