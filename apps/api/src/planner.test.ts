import { describe, expect, it } from "vitest";
import { dateAdd, isReliableWeek, normalizeWeek, replanDocument } from "./planner.js";
import { PlanDraftSchema, ProfileSchema } from "./contracts.js";
import { newSession } from "./onboarding-contracts.js";
import { PlannerDocumentSchema, type PlannerDocument } from "./sync-contracts.js";

function replanFixture() {
  const stamp = "2026-10-01T00:00:00Z";
  const task = (id: string, fixed = false): PlannerDocument["tasks"][number] => ({ id, user_id: "owner", subject_id: "math", title: id,
    estimated_minutes: 240, completed_minutes: 0, priority: 2, deadline: "2026-10-21", is_fixed: fixed, status: "not_started", created_at: stamp, updated_at: stamp });
  const block = (id: string, task_id: string, date: string, extra = {}): PlannerDocument["blocks"][number] => ({ id, user_id: "owner", task_id,
    date, start_minute: 480, duration_minutes: 60, actual_minutes: 0, is_fixed: false, status: "planned", created_at: stamp, updated_at: stamp, ...extra });
  const document: PlannerDocument = { version: 1, profile: { user_id: "owner", planning_mode: "daily", goal_text: "考研复习", goal_type: "exam",
    target_school: "", target_program: "", target_date: null, plan_start_date: "2026-10-18", plan_end_date: "2026-10-21",
    daily_limit_minutes: 240, granularity_minutes: 30, buffer_minutes: 30, subject_limit_minutes: 240, study_start_minute: 480, study_end_minute: 1320, foundation: "" },
    subjects: [{ id: "math", user_id: "owner", name: "高数", color: "#275e91", priority: 2 }], tasks: [task("reuse"), task("old"), task("fixed", true)],
    blocks: [block("past", "old", "2026-10-16"), block("future-old", "old", "2026-10-18"), block("actual", "reuse", "2026-10-18", { actual_minutes: 30 }),
      block("completed", "old", "2026-10-19", { status: "completed", actual_minutes: 60 }), block("fixed-block", "fixed", "2026-10-18", { is_fixed: true })],
    logs: [{ id: "log", user_id: "owner", task_id: "reuse", block_id: "actual", date: "2026-10-18", minutes: 30, started_at: stamp, ended_at: stamp, source: "manual" }],
    fixed_events: [{ id: "event", user_id: "owner", title: "上课", date: "2026-10-18", start_minute: 600, duration_minutes: 30, kind: "course", repeat: "daily", created_at: stamp, updated_at: stamp }], replan_runs: [], phases: [] };
  const session = { ...newSession(), has_plan: true, replanning: true, start_date: "2026-10-18", end_date: "2026-10-21",
    profile: ProfileSchema.parse({ goal_text: "考研复习", goal_type: "exam", plan_start_date: "2026-10-18", plan_end_date: "2026-10-21",
      weekly_minutes: Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map(day => [String(day), 240])) }),
    courses: [{ id: "math", name: "高数", description: "", priority: 2 }],
    items: ["reuse", "fixed"].map(id => ({ id, course_id: "math", title: id, description: "", completion_criteria: "", estimated_minutes: 240, deadline: "2026-10-21", deadline_kind: "plan_end" as const, priority: 2 })) };
  return { document, session };
}

describe("interview replanning", () => {
  it("deducts overlapping fixed events once when allocating the revised daily budget", () => {
    const { document, session } = replanFixture();
    document.tasks = [document.tasks[0]];
    document.blocks = [];
    document.logs = [];
    document.fixed_events = [document.fixed_events[0], { ...document.fixed_events[0], id: "overlap", start_minute: 660 }]
      .map(event => ({ ...event, duration_minutes: 120 }));
    session.items = [session.items[0]];
    session.profile.weekly_minutes = Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map(day => [String(day), 360]));
    const result = replanDocument(document, session);
    const firstDay = result.document.blocks.filter(block => block.date === session.start_date);
    expect(firstDay.reduce((sum, block) => sum + block.duration_minutes, 0)).toBe(150);
  });
  it("archives replaced tasks while retaining history, actual logs, fixed data and reused identities", () => {
    const { document, session } = replanFixture();
    const before = structuredClone(document);
    const result = replanDocument(document, session);
    expect(PlannerDocumentSchema.safeParse(result.document).success).toBe(true);
    expect(result.document.tasks.find(task => task.id === "old")?.status).toBe("archived");
    expect(result.document.tasks.find(task => task.id === "reuse")?.completed_minutes).toBe(30);
    for (const id of ["past", "actual", "completed", "fixed-block"]) expect(result.document.blocks.find(block => block.id === id)).toEqual(document.blocks.find(block => block.id === id));
    expect(result.document.blocks.some(block => block.id === "future-old")).toBe(false);
    expect(result.document.logs).toEqual(document.logs);
    expect(result.document.fixed_events).toEqual(document.fixed_events);
    const firstDay = result.document.blocks.filter(block => block.date === "2026-10-18");
    expect(firstDay.reduce((sum, block) => sum + block.duration_minutes, 0)).toBeLessThanOrEqual(180);
    expect(document).toEqual(before);
  });

  it("rejects deleting or changing protected fixed tasks and budgets below completed work", () => {
    const { document, session } = replanFixture();
    expect(() => replanDocument(document, { ...session, items: [session.items[0]] })).toThrow("固定事项");
    expect(() => replanDocument(document, { ...session, items: session.items.map(item => item.id === "fixed" ? { ...item, estimated_minutes: 300 } : item) })).toThrow("固定事项");
    expect(() => replanDocument(document, { ...session, items: session.items.map(item => item.id === "reuse" ? { ...item, estimated_minutes: 20 } : item) })).toThrow("已完成");
  });

  it("writes the newly confirmed week into the replanned document without flattening rest days", () => {
    const { document, session } = replanFixture();
    const week = { "0": 0, "1": 90, "2": 90, "3": 0, "4": 90, "5": 90, "6": 180 };
    session.profile = ProfileSchema.parse({ ...session.profile, weekly_minutes: week });
    const result = replanDocument(document, session);
    expect(result.document.profile.weekly_minutes).toEqual(week);
    expect(PlannerDocumentSchema.safeParse(result.document).success).toBe(true);
    // 周三、周日为 0，不能新生成安排（固定块和已完成块属于受保护记录）。
    const generated = result.document.blocks.filter(block =>
      block.date >= session.start_date && !block.is_fixed && block.status !== "completed"
      && !document.blocks.some(previous => previous.id === block.id));
    expect(generated.length).toBeGreaterThan(0);
    for (const block of generated) {
      expect(week[String(new Date(`${block.date}T00:00:00Z`).getUTCDay()) as keyof typeof week]).toBeGreaterThan(0);
    }
  });

  it("carries the confirmed learning constraints into the replanned document", () => {
    const { document, session } = replanFixture();
    const constraints = "每周三晚上有课，22:00 后不安排";
    session.profile = ProfileSchema.parse({ ...session.profile, constraints_text: constraints });
    const result = replanDocument(document, session);
    // 重新规划后的文档必须携带访谈确认的学习限制；否则关系表投影会用旧值覆盖刚保存的资料。
    expect((result.document.profile as Record<string, unknown>).constraints).toBe(
      constraints,
    );
    expect(
      (PlannerDocumentSchema.parse(result.document).profile as Record<string, unknown>)
        .constraints,
    ).toBe(constraints);
  });

  it("carries the confirmed flexible capacity assumptions into the replanned document", () => {
    const { document, session } = replanFixture();
    session.profile.capacity_basis = "net";
    session.profile.weekly_baseline_minutes = 540;
    session.profile.weekly_range_min_minutes = 300;
    session.profile.weekly_range_max_minutes = 600;
    session.profile.week_capacity_overrides = {
      "2026-10-19": { total_minutes: 180, days: { "6": 60 } },
    };
    session.profile.date_capacity_overrides = { "2026-11-02": 0 };
    const result = replanDocument(document, session);
    expect(result.document.profile).toMatchObject({
      capacity_basis: "net",
      weekly_baseline_minutes: 540,
      weekly_range_min_minutes: 300,
      weekly_range_max_minutes: 600,
      week_capacity_overrides: { "2026-10-19": { total_minutes: 180, days: { "6": 60 } } },
      date_capacity_overrides: { "2026-11-02": 0 },
    });
    // 显式 0 是有效容量（休息日），不能被当成“未设置”丢掉。
    expect(
      (result.document.profile.date_capacity_overrides as Record<string, number>)["2026-11-02"],
    ).toBe(0);
    expect(PlannerDocumentSchema.safeParse(result.document).success).toBe(true);

    // 旧会话/部分会话缺少容量字段时保留文档已有值，不静默清除。
    const second = replanFixture();
    (second.document.profile as Record<string, unknown>).weekly_range_max_minutes = 720;
    (second.document.profile as Record<string, unknown>).capacity_basis = "gross_buffer";
    const kept = replanDocument(second.document, second.session);
    expect(kept.document.profile).toMatchObject({
      capacity_basis: "gross_buffer",
      weekly_range_max_minutes: 720,
    });
  });

  it("only accepts a complete, valid week as the reliable source", () => {
    const week = { "0": 0, "1": 90, "2": 90, "3": 0, "4": 90, "5": 90, "6": 180 };
    expect(isReliableWeek(week)).toBe(true);
    expect(normalizeWeek(week)).toEqual(week);
    expect(isReliableWeek({ ...week, "6": undefined })).toBe(false);
    expect(isReliableWeek({ "0": 0, "1": 90 })).toBe(false);
    expect(isReliableWeek({ ...week, "3": -30 })).toBe(false);
    expect(isReliableWeek({ ...week, "3": "0" })).toBe(false);
    expect(isReliableWeek(null)).toBe(false);
    // 不可靠输入归一化为可预测的 0，不把休息日替换成默认值。
    expect(normalizeWeek({ "1": 90 })).toEqual({ "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 });
  });

  it("retains time slots and creates timed blocks around protected events", () => {
    const { document, session } = replanFixture();
    document.profile.planning_mode = "timed";
    const result = replanDocument(document, session);
    const old = new Set(document.blocks.map(block => block.id));
    for (const block of result.document.blocks.filter(block => !old.has(block.id))) {
      expect(block.start_minute).toBeGreaterThanOrEqual(480);
      expect(block.start_minute + block.duration_minutes).toBeLessThanOrEqual(1320);
      expect(block.start_minute >= 630 || block.start_minute + block.duration_minutes <= 600).toBe(true);
    }
  });
});

describe("API planning contracts", () => {
  it("does calendar arithmetic without local timezone drift", () => {
    expect(dateAdd("2027-12-25", 1)).toBe("2027-12-26");
    expect(dateAdd("2028-01-01", -1)).toBe("2027-12-31");
  });

  it("accepts a goal without any target date and rejects malformed dates", () => {
    const profile = ProfileSchema.parse({ goal_text: "每天读一点历史", plan_end_date: "2026-11-13" });
    expect(profile.target_date).toBeNull();
    expect(profile.goal_type).toBe("other");
    expect(profile.weekly_minutes["1"]).toBe(0);
    expect(ProfileSchema.parse({ target_date: "" }).target_date).toBeNull();
    expect(ProfileSchema.parse({ target_date: null }).target_date).toBeNull();
    expect(ProfileSchema.parse({ plan_end_date: "2026-11-13" }).plan_end_date).toBe("2026-11-13");
    expect(() => ProfileSchema.parse({ target_date: "not-a-date" })).toThrow();
    expect(() => ProfileSchema.parse({ plan_end_date: "2027-02-30" })).toThrow();
  });

  it("keeps structural validation separate from course reference validation", () => {
    expect(() => PlanDraftSchema.parse({
      courses: [{ id: "math", name: "数学", description: "", priority: 3 }],
      items: [{ id: "item", course_id: "english", title: "一轮复习", description: "", completion_criteria: "", estimated_minutes: 60, deadline: "2027-12-25", priority: 2 }],
      analysis_summary: "",
      assumptions: [],
      warnings: [],
    })).not.toThrow();
  });
});
