import { describe, expect, it } from "vitest";
import { applyPlanAdjustment, PlanAdjustmentError, type AdjustmentRuntime } from "./plan-adjust.js";
import { PlanAdjustmentSchema, type PlanAdjustment } from "./plan-adjust-ai.js";
import { PlannerDocumentSchema, type PlannerDocument } from "./sync-contracts.js";

const TODAY = "2026-10-18";
const OWNER = "1d4fba85-b73c-48c9-8039-fafdd77c607c";
const STAMP = "2026-10-16T12:40:00.528Z";
const FROZEN_NOW = "2026-10-18T04:00:00.000Z";

/** 每次 newId 返回合法的 UUID v4 形状，便于断言“新记录使用 UUID”。 */
function deterministicRuntime(): AdjustmentRuntime {
  let sequence = 0;
  return {
    now: () => new Date(FROZEN_NOW),
    newId: () => `00000000-0000-4000-8000-${String(++sequence).padStart(12, "0")}`,
  };
}

const block = (id: string, task_id: string, date: string, overrides: Record<string, unknown> = {}) => ({
  id,
  user_id: OWNER,
  task_id,
  date,
  start_minute: 0,
  duration_minutes: 60,
  actual_minutes: 0,
  is_fixed: false,
  status: "planned" as const,
  created_at: STAMP,
  updated_at: STAMP,
  ...overrides,
});

/**
 * 覆盖设计文档 §7 全部纯函数场景的小型计划：
 * 未归档事项合计 21000 分钟（其中归档 300 不计），今天 2026-10-18。
 */
function fixture(): PlannerDocument {
  const weekly = { "0": 180, "1": 300, "2": 300, "3": 300, "4": 300, "5": 300, "6": 300 };
  return PlannerDocumentSchema.parse({
    version: 1,
    profile: {
      user_id: OWNER,
      planning_mode: "daily",
      goal_text: "准备上海交通大学计算机专业考研",
      goal_type: "exam",
      goal_subtype: "考研",
      target_date: "2027-12-25",
      target_date_confirmed: false,
      plan_start_date: "2026-10-01",
      plan_end_date: "2026-11-14",
      target_school: "上海交通大学",
      target_program: "计算机技术",
      foundation: "计算机专业大四，数学基础一般",
      daily_limit_minutes: 480,
      granularity_minutes: 30,
      buffer_minutes: 30,
      subject_limit_minutes: 240,
      study_start_minute: 480,
      study_end_minute: 1320,
      weekly_minutes: weekly,
      capacity_basis: "net",
      weekly_baseline_minutes: 1860,
      weekly_range_min_minutes: 1200,
      weekly_range_max_minutes: 2400,
    },
    subjects: [
      { id: "s-math", user_id: OWNER, name: "数学", color: "#4565c7", priority: 3 },
      { id: "s-en", user_id: OWNER, name: "英语", color: "#e8684a", priority: 2 },
      { id: "s-pol", user_id: OWNER, name: "政治", color: "#6dc8ec", priority: 2 },
    ],
    tasks: [
      {
        id: "t-math", user_id: OWNER, subject_id: "s-math", title: "高数基础一轮",
        description: "高数教材与习题", estimated_minutes: 12000, completed_minutes: 600,
        priority: 3, deadline: "2027-10-01", deadline_kind: "deadline", earliest_date: "2026-10-01",
        is_fixed: false, status: "in_progress", created_at: STAMP, updated_at: STAMP,
        planning: {
          workload: {
            components: [{ id: "ch", label: "章节", quantity: 100, unit: "章", minutes_per_unit: 120 }],
            source: "教材章节", confidence: "medium", calibration: "完成 3 章后校准",
          },
          activity: { kind: "finite", starts_on: "2026-10-01", ends_on: "2026-11-14" },
          dependencies: [],
        },
      },
      {
        id: "t-en", user_id: OWNER, subject_id: "s-en", title: "英语真题",
        estimated_minutes: 6000, completed_minutes: 0, priority: 2,
        deadline: "2027-12-20", deadline_kind: "deadline",
        is_fixed: false, status: "not_started", created_at: STAMP, updated_at: STAMP,
        planning: { activity: { kind: "finite", starts_on: "2026-10-01", ends_on: "2026-11-14" }, dependencies: [] },
      },
      {
        id: "t-plan", user_id: OWNER, subject_id: "s-pol", title: "政治强化",
        estimated_minutes: 1800, completed_minutes: 0, priority: 2,
        deadline: "2026-11-14", deadline_kind: "plan_end", earliest_date: "2026-10-18",
        is_fixed: false, status: "not_started", created_at: STAMP, updated_at: STAMP,
        planning: { activity: { kind: "finite", starts_on: "2026-10-18", ends_on: "2026-11-14" }, dependencies: [] },
      },
      {
        id: "t-fixed", user_id: OWNER, subject_id: "s-math", title: "固定课程作业",
        estimated_minutes: 600, completed_minutes: 120, priority: 2,
        deadline: "2026-11-01", deadline_kind: "deadline",
        is_fixed: true, status: "in_progress", created_at: STAMP, updated_at: STAMP,
      },
      {
        id: "t-done", user_id: OWNER, subject_id: "s-math", title: "线性代数已完成",
        estimated_minutes: 600, completed_minutes: 600, priority: 2,
        deadline: "2026-10-10", deadline_kind: "deadline",
        is_fixed: false, status: "completed", created_at: STAMP, updated_at: STAMP,
      },
      {
        id: "t-arch", user_id: OWNER, subject_id: "s-en", title: "旧计划事项",
        estimated_minutes: 300, completed_minutes: 0, priority: 1,
        deadline: "2026-12-01", deadline_kind: "deadline",
        is_fixed: false, status: "archived", created_at: STAMP, updated_at: STAMP,
      },
    ],
    blocks: [
      block("b-history", "t-math", "2026-10-10"),
      block("b-fixed", "t-fixed", "2026-10-20", { is_fixed: true }),
      block("b-completed", "t-math", "2026-10-19", { status: "completed", actual_minutes: 60 }),
      block("b-actual", "t-en", "2026-10-21", { actual_minutes: 30 }),
      block("b-logged", "t-math", "2026-10-22"),
      block("b-logged-day", "t-en", "2026-10-23"),
      block("b-arch", "t-arch", "2026-10-24", { duration_minutes: 30 }),
      block("b-adjust-a", "t-math", "2026-10-25"),
      block("b-adjust-b", "t-plan", "2026-10-26"),
      block("b-adjust-c", "t-en", "2026-10-27"),
    ],
    logs: [
      {
        id: "log-block", user_id: OWNER, task_id: "t-math", block_id: "b-logged",
        date: "2026-10-22", minutes: 60, started_at: STAMP, ended_at: STAMP,
        source: "timer", relation: "scheduled",
      },
      {
        id: "log-day", user_id: OWNER, task_id: "t-en", block_id: null,
        date: "2026-10-23", minutes: 30, started_at: STAMP, ended_at: STAMP, source: "manual",
      },
    ],
    fixed_events: [],
    replan_runs: [],
    phases: [],
    planning: {
      version: 1,
      prompt_version: "learning-route-2-full",
      rules_version: "workload-rhythm-2",
      mode: "full",
      detail_days: 45,
      rolling: false,
      route: [{ id: "route-math", title: "数学基础", item_ids: ["t-math"], outcome: "完成基础一轮", check: "完成章节练习" }],
      milestones: [{ title: "预报名", source_kind: "user", date_precision: "day", date_value: "2026-10-10" }],
      assumptions: ["按每周 31 小时安排"],
      risks: ["时间紧张"],
      uncovered: ["政治强化尚未安排"],
      detailed_until: "2026-11-14",
      forecast: null,
      needs_review: false,
      capacity: null,
    },
  });
}

const baseAdjustment = {
  assessment: "当前计划总时长约 350 小时，明显低于交大计算机考研所需区间，本次延长周期并补充训练量。",
  verdict: "too_light" as const,
  required_minutes: { min: 90_000, max: 150_000 },
  cycle: { end_date: "2027-09-30", reason: "延长到目标日期前，覆盖完整备考周期" },
  intensity: null,
  task_updates: [],
  new_subjects: [],
  new_tasks: [],
  warnings: [],
};

function makeAdjustment(overrides: Record<string, unknown> = {}): PlanAdjustment {
  return PlanAdjustmentSchema.parse({ ...baseAdjustment, ...overrides });
}

function findTask(document: PlannerDocument, id: string) {
  const task = document.tasks.find((row) => row.id === id);
  if (!task) throw new Error(`missing task ${id}`);
  return task;
}

function findBlock(document: PlannerDocument, id: string) {
  return document.blocks.find((row) => row.id === id);
}

describe("applyPlanAdjustment: cycle", () => {
  it("extends the cycle, follows plan_end deadlines, and never touches real deadlines", () => {
    const source = fixture();
    const { document, preview } = applyPlanAdjustment(source, makeAdjustment(), TODAY, deterministicRuntime());

    expect(document.profile.plan_end_date).toBe("2027-09-30");
    expect(document.profile.plan_start_date).toBe("2026-10-01");
    expect(findTask(document, "t-plan").deadline).toBe("2027-09-30");
    expect(findTask(document, "t-plan").planning?.activity?.ends_on).toBe("2027-09-30");
    // 真实截止日期（deadline_kind=deadline）绝不跟随周期，但结束于旧周期边界的活动窗口随周期延展。
    expect(findTask(document, "t-math").deadline).toBe("2027-10-01");
    expect(findTask(document, "t-en").deadline).toBe("2027-12-20");
    expect(findTask(document, "t-math").planning?.activity?.ends_on).toBe("2027-09-30");
    expect(findTask(document, "t-en").planning?.activity?.ends_on).toBe("2027-09-30");
    expect(source.profile.plan_end_date).toBe("2026-11-14");

    expect(preview.cycle).toEqual({
      start_date: "2026-10-01",
      previous_end_date: "2026-11-14",
      end_date: "2027-09-30",
      previous_days: 45,
      days: 365,
      remaining_days: 348,
    });
    expect(preview.notes).toContain("规划周期结束日期由 2026-11-14 调整为 2027-09-30");
    expect(preview.notes).toContain("真实截止日期、固定事项、已完成记录与历史安排均未改动");
    expect(preview.warnings).toContain("调整后总时长仍低于目标所需下限");
  });

  it("rewrites full-cycle planning metadata but keeps route, milestones and uncovered", () => {
    const source = fixture();
    const { document } = applyPlanAdjustment(source, makeAdjustment(), TODAY, deterministicRuntime());
    const planning = document.planning!;
    expect(planning.mode).toBe("full");
    expect(planning.rolling).toBe(false);
    expect(planning.detail_days).toBe(365);
    expect(planning.detailed_until).toBe("2027-09-30");
    expect(planning.forecast).toBeNull();
    expect(planning.needs_review).toBe(false);
    expect(planning.quality).toBeNull();
    expect(planning.route).toEqual(source.planning!.route);
    expect(planning.milestones).toEqual(source.planning!.milestones);
    expect(planning.uncovered).toEqual(["政治强化尚未安排"]);
    expect(planning.assumptions).toContain("按每周 31 小时安排");
    expect(planning.assumptions.some((value) => value.startsWith("周期调整："))).toBe(true);
    expect(planning.risks).toContain("时间紧张");
    expect(planning.capacity).toMatchObject({ basis: "net", adopted_weekly_minutes: 1860, week_override_count: 0 });
  });

  it("clamps the end date to the target date and to the 1095-day cycle cap, with warnings", () => {
    const beyondTarget = applyPlanAdjustment(
      fixture(),
      makeAdjustment({ cycle: { end_date: "2028-06-01", reason: "过长" } }),
      TODAY,
      deterministicRuntime(),
    );
    expect(beyondTarget.preview.cycle.end_date).toBe("2027-12-25");
    expect(beyondTarget.preview.warnings.some((value) => value.includes("目标日期"))).toBe(true);

    const noTarget = fixture();
    noTarget.profile.target_date = null;
    const capped = applyPlanAdjustment(
      noTarget,
      makeAdjustment({ cycle: { end_date: "2032-01-01", reason: "过长" } }),
      TODAY,
      deterministicRuntime(),
    );
    // 开始日期 2026-10-01 起最多 1095 天（end ≤ start+1094）：2029-09-29。
    expect(capped.preview.cycle.end_date).toBe("2029-09-29");
    expect(capped.preview.cycle.days).toBe(1095);
    expect(capped.document.planning?.detail_days).toBe(1095);
    expect(capped.preview.warnings.some((value) => value.includes("1095"))).toBe(true);
  });

  it("keeps the original plan_end deadline when the new cycle ends before earliest_date", () => {
    const data = fixture();
    // earliest_date 必须不晚于原截止日期（文档契约），所以把新周期缩短到 earliest 之前来触发保护。
    findTask(data, "t-plan").earliest_date = "2026-11-01";
    const { document, preview } = applyPlanAdjustment(
      data,
      makeAdjustment({ cycle: { end_date: "2026-10-25", reason: "缩短" } }),
      TODAY,
      deterministicRuntime(),
    );
    expect(findTask(document, "t-plan").deadline).toBe("2026-11-14");
    expect(findTask(document, "t-plan").planning?.activity?.ends_on).toBe("2026-11-14");
    expect(preview.warnings.some((value) => value.includes("最早开始日期晚于新周期结束日期"))).toBe(true);
  });
});

describe("applyPlanAdjustment: intensity", () => {
  it("replaces the seven-day template and clears baseline/range", () => {
    const weekly = { "0": 0, "1": 240, "2": 300, "3": 240, "4": 300, "5": 300, "6": 360 };
    const { document, preview } = applyPlanAdjustment(
      fixture(),
      makeAdjustment({
        intensity: { weekly_minutes: weekly, reason: "近期实际每周约 11 小时，目标需要提高投入" },
      }),
      TODAY,
      deterministicRuntime(),
    );
    expect(document.profile.weekly_minutes).toEqual(weekly);
    expect(document.profile.weekly_baseline_minutes).toBeNull();
    expect(document.profile.weekly_range_min_minutes).toBeNull();
    expect(document.profile.weekly_range_max_minutes).toBeNull();
    expect(document.profile.daily_limit_minutes).toBe(360);
    expect(preview.intensity).toEqual({
      previous_weekly_minutes: 1860,
      weekly_minutes: 1740,
      reason: "近期实际每周约 11 小时，目标需要提高投入",
    });
    expect(preview.notes.some((value) => value.includes("每周 1740 分钟"))).toBe(true);
  });

  it("leaves capacity untouched when intensity is null", () => {
    const source = fixture();
    const { document, preview } = applyPlanAdjustment(source, makeAdjustment({ intensity: null }), TODAY, deterministicRuntime());
    expect(document.profile.weekly_minutes).toEqual(source.profile.weekly_minutes);
    expect(document.profile.weekly_baseline_minutes).toBe(1860);
    expect(preview.intensity.previous_weekly_minutes).toBe(1860);
    expect(preview.intensity.weekly_minutes).toBe(1860);
    expect(preview.intensity.reason).toBe("本次未调整每周学习强度");
  });
});

describe("applyPlanAdjustment: task budgets", () => {
  it("raises budgets and ignores fixed, completed, archived and unknown tasks", () => {
    const { document, preview } = applyPlanAdjustment(
      fixture(),
      makeAdjustment({
        task_updates: [
          { task_id: "t-math", estimated_minutes: 18000, reason: "数学需要更多时间" },
          { task_id: "t-en", estimated_minutes: 9000, reason: "英语真题量增加" },
          { task_id: "t-fixed", estimated_minutes: 900, reason: "固定事项" },
          { task_id: "t-done", estimated_minutes: 900, reason: "已完成" },
          { task_id: "t-arch", estimated_minutes: 900, reason: "已归档" },
          { task_id: "missing", estimated_minutes: 900, reason: "不存在" },
        ],
      }),
      TODAY,
      deterministicRuntime(),
    );
    expect(findTask(document, "t-math").estimated_minutes).toBe(18000);
    expect(findTask(document, "t-en").estimated_minutes).toBe(9000);
    expect(findTask(document, "t-fixed").estimated_minutes).toBe(600);
    expect(findTask(document, "t-done").estimated_minutes).toBe(600);
    expect(findTask(document, "t-arch").estimated_minutes).toBe(300);
    expect(findTask(document, "t-math").updated_at).toBe(FROZEN_NOW);
    // 结构化工作量与预算保持一致：数量按比例缩放，单价/单位/标签不变。
    const workload = findTask(document, "t-math").planning!.workload!;
    const computed = workload.components
      .filter((component) => component.selected !== false)
      .reduce((sum, component) => sum + component.quantity * component.minutes_per_unit, 0);
    expect(Math.ceil(computed)).toBe(18000);
    expect(workload.components[0]).toMatchObject({ label: "章节", unit: "章", minutes_per_unit: 120 });
    expect(preview.workload.updated_tasks).toEqual([
      { task_id: "t-math", title: "高数基础一轮", subject: "数学", previous_minutes: 12000, minutes: 18000, reason: "数学需要更多时间" },
      { task_id: "t-en", title: "英语真题", subject: "英语", previous_minutes: 6000, minutes: 9000, reason: "英语真题量增加" },
    ]);
    expect(preview.hours.current_minutes).toBe(21000);
    expect(preview.hours.next_minutes).toBe(30000);
    expect(preview.hours.remaining_minutes).toBe(21000 + 9000 - 1320);
    for (const keyword of ["固定事项", "已完成", "已归档", "未知事项"])
      expect(preview.warnings.some((value) => value.includes(keyword))).toBe(true);
  });

  it("clamps a budget below the completed minutes and explains why", () => {
    const { document, preview } = applyPlanAdjustment(
      fixture(),
      makeAdjustment({ task_updates: [{ task_id: "t-math", estimated_minutes: 300, reason: "下调" }] }),
      TODAY,
      deterministicRuntime(),
    );
    expect(findTask(document, "t-math").estimated_minutes).toBe(600);
    const workload = findTask(document, "t-math").planning!.workload!;
    const computed = workload.components
      .filter((component) => component.selected !== false)
      .reduce((sum, component) => sum + component.quantity * component.minutes_per_unit, 0);
    expect(Math.ceil(computed)).toBe(600);
    expect(findTask(document, "t-math").planning!.workload!.components[0].minutes_per_unit).toBe(120);
    expect(preview.workload.updated_tasks[0]).toMatchObject({ previous_minutes: 12000, minutes: 600 });
    expect(preview.warnings.some((value) => value.includes("低于已完成分钟"))).toBe(true);
  });
});

describe("applyPlanAdjustment: new subjects and tasks", () => {
  it("creates subjects/tasks with UUID ids, deadlines and preview rows", () => {
    const { document, preview } = applyPlanAdjustment(
      fixture(),
      makeAdjustment({
        new_subjects: [
          { key: "s408", name: "408", priority: 3 },
          { key: "spol2", name: "政治强化", priority: 2 },
        ],
        new_tasks: [
          {
            key: "t408", subject: "s408", title: "408 真题 15 套", description: "完成并复盘",
            estimated_minutes: 9000, deadline_kind: "plan_end", priority: 3, reason: "补齐 408 训练量",
          },
          {
            key: "ten", subject: "s-en", title: "英语作文模板", estimated_minutes: 1200,
            deadline_kind: "deadline", deadline: "2027-06-30", priority: 2, reason: "补齐写作训练",
          },
        ],
      }),
      TODAY,
      deterministicRuntime(),
    );
    const createdSubjects = document.subjects.filter((subject) => subject.id.startsWith("00000000"));
    expect(createdSubjects.map((subject) => subject.name)).toEqual(["408", "政治强化"]);
    expect(createdSubjects.map((subject) => subject.color)).toEqual(["#4565c7", "#e8684a"]);
    expect(createdSubjects.every((subject) => /^[0-9a-f-]{36}$/.test(subject.id))).toBe(true);

    const created = document.tasks.filter((task) => task.id.startsWith("00000000"));
    expect(created).toHaveLength(2);
    const papers = created.find((task) => task.title === "408 真题 15 套")!;
    expect(papers).toMatchObject({
      subject_id: createdSubjects[0].id,
      estimated_minutes: 9000,
      completed_minutes: 0,
      is_fixed: false,
      status: "not_started",
      deadline_kind: "plan_end",
      deadline: "2027-09-30",
      created_at: FROZEN_NOW,
      updated_at: FROZEN_NOW,
    });
    expect(papers.planning).toBeUndefined();
    const essay = created.find((task) => task.title === "英语作文模板")!;
    expect(essay).toMatchObject({ subject_id: "s-en", deadline_kind: "deadline", deadline: "2027-06-30" });

    expect(preview.workload.new_tasks).toEqual([
      {
        title: "408 真题 15 套", subject: "408", minutes: 9000,
        deadline_kind: "plan_end", deadline: "2027-09-30", reason: "补齐 408 训练量",
      },
      {
        title: "英语作文模板", subject: "英语", minutes: 1200,
        deadline_kind: "deadline", deadline: "2027-06-30", reason: "补齐写作训练",
      },
    ]);
    expect(preview.workload.subjects.map(({ name, previous_minutes, minutes }) => ({ name, previous_minutes, minutes }))).toEqual([
      { name: "英语", previous_minutes: 6000, minutes: 7200 },
      { name: "408", previous_minutes: 0, minutes: 9000 },
    ]);
    // 数学、政治没有工作量变化，不进入 subjects；只新增课程但没有事项的新课程也不出现。
    expect(preview.workload.subjects.find((row) => row.name === "数学")).toBeUndefined();
    expect(preview.workload.subjects.find((row) => row.name === "政治强化")).toBeUndefined();
    expect(preview.hours.next_minutes).toBe(21000 + 9000 + 1200);
    expect(preview.notes.some((value) => value.includes("新增 2 个事项"))).toBe(true);
  });
});

describe("applyPlanAdjustment: protected blocks and rescheduling", () => {
  it("keeps protected records and releases/replans future adjustable blocks", () => {
    const source = fixture();
    const { document, preview } = applyPlanAdjustment(source, makeAdjustment(), TODAY, deterministicRuntime());
    const protectedIds = [
      "b-history", "b-fixed", "b-completed", "b-actual", "b-logged", "b-logged-day", "b-arch",
    ];
    for (const id of protectedIds) {
      const beforeBlock = findBlock(source, id)!;
      const afterBlock = findBlock(document, id);
      expect(afterBlock, id).toBeDefined();
      expect(afterBlock!.date).toBe(beforeBlock.date);
      expect(afterBlock!.task_id).toBe(beforeBlock.task_id);
    }
    for (const id of ["b-adjust-a", "b-adjust-b", "b-adjust-c"])
      expect(findBlock(document, id)).toBeUndefined();

    expect(preview.schedule).toMatchObject({
      protected_blocks: 7,
      released_blocks: 3,
      released_minutes: 180,
      unscheduled_minutes: 0,
    });
    expect(preview.schedule.added_blocks).toBeGreaterThan(0);
    expect(preview.schedule.added_minutes).toBeGreaterThan(0);
    expect(preview.deadline_risks).toEqual([]);
  });

  it("reports the real unscheduled remainder instead of dropping it", () => {
    const data = fixture();
    data.profile.weekly_minutes = { "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 };
    data.profile.weekly_baseline_minutes = null;
    data.profile.weekly_range_min_minutes = null;
    data.profile.weekly_range_max_minutes = null;
    const { document, preview } = applyPlanAdjustment(data, makeAdjustment(), TODAY, deterministicRuntime());
    const released = ["b-adjust-a", "b-adjust-b", "b-adjust-c"];
    for (const id of released) expect(findBlock(document, id)).toBeUndefined();
    expect(preview.schedule.added_blocks).toBe(0);
    expect(preview.schedule.unscheduled_minutes).toBeGreaterThan(0);
    expect(preview.warnings.some((value) => value.includes("未能安排"))).toBe(true);
    // 未安排不等于丢弃：事项与剩余工作总量都保留。
    expect(document.tasks).toHaveLength(data.tasks.length);
    expect(preview.hours.remaining_minutes).toBe(19680);
  });

  it("lists deadline risks with the remaining gap before each real deadline", () => {
    const data = fixture();
    data.profile.weekly_minutes = { "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 };
    data.profile.weekly_baseline_minutes = null;
    data.profile.weekly_range_min_minutes = null;
    data.profile.weekly_range_max_minutes = null;
    const { preview } = applyPlanAdjustment(
      data,
      makeAdjustment({ cycle: { end_date: "2027-12-25", reason: "覆盖全部真实截止日期" } }),
      TODAY,
      deterministicRuntime(),
    );
    expect(preview.deadline_risks).toEqual([
      { task_id: "t-math", title: "高数基础一轮", deadline: "2027-10-01", unscheduled_minutes: 11280 },
      { task_id: "t-en", title: "英语真题", deadline: "2027-12-20", unscheduled_minutes: 5850 },
      { task_id: "t-fixed", title: "固定课程作业", deadline: "2026-11-01", unscheduled_minutes: 420 },
    ]);
  });
});

describe("applyPlanAdjustment: preview contract", () => {
  it("returns every §3 preview field with server-computed integers", () => {
    const { preview } = applyPlanAdjustment(fixture(), makeAdjustment(), TODAY, deterministicRuntime());
    expect(preview.assessment).toContain("350 小时");
    expect(preview.verdict).toBe("too_light");
    expect(preview.hours).toEqual({
      current_minutes: 21000,
      next_minutes: 21000,
      remaining_minutes: 19680,
      required_min_minutes: 90000,
      required_max_minutes: 150000,
    });
    expect(preview.workload).toEqual({ updated_tasks: [], new_tasks: [], subjects: [] });
    expect(preview.intensity).toEqual({
      previous_weekly_minutes: 1860,
      weekly_minutes: 1860,
      reason: "本次未调整每周学习强度",
    });
    for (const value of Object.values(preview.schedule))
      expect(Number.isInteger(value)).toBe(true);
    expect(Number.isInteger(preview.cycle.days)).toBe(true);
    expect(Array.isArray(preview.warnings)).toBe(true);
    expect(Array.isArray(preview.notes)).toBe(true);
  });
});

describe("applyPlanAdjustment: invalid plans are rejected atomically", () => {
  it.each([
    [
      "end date before today",
      makeAdjustment({ cycle: { end_date: "2026-10-17", reason: "过去" } }),
    ],
    [
      "required minutes range inverted",
      makeAdjustment({ required_minutes: { min: 1000, max: 500 } }),
    ],
  ])("rejects %s", (_name, ai) => {
    const source = fixture();
    const original = structuredClone(source);
    expect(() => applyPlanAdjustment(source, ai, TODAY, deterministicRuntime())).toThrow(PlanAdjustmentError);
    expect(source).toEqual(original);
  });

  it("rejects a new task that references an unknown subject", () => {
    const ai = makeAdjustment({
      new_tasks: [
        {
          key: "x", subject: "missing-subject", title: "无效事项", estimated_minutes: 300,
          deadline_kind: "plan_end", priority: 2, reason: "测试",
        },
      ],
    });
    expect(() => applyPlanAdjustment(fixture(), ai, TODAY, deterministicRuntime()))
      .toThrow(/不存在的课程/);
  });

  it("rejects a real-deadline new task without a deadline", () => {
    const ai = makeAdjustment({
      new_tasks: [
        {
          key: "x", subject: "s-en", title: "无效事项", estimated_minutes: 300,
          deadline_kind: "deadline", priority: 2, reason: "测试",
        },
      ],
    });
    expect(() => applyPlanAdjustment(fixture(), ai, TODAY, deterministicRuntime()))
      .toThrow(/缺少有效的真实截止日期/);
  });

  it("rejects duplicate new subject keys", () => {
    const ai = makeAdjustment({
      new_subjects: [
        { key: "dup", name: "A", priority: 2 },
        { key: "dup", name: "B", priority: 2 },
      ],
    });
    expect(() => applyPlanAdjustment(fixture(), ai, TODAY, deterministicRuntime()))
      .toThrow(/新增课程标识重复/);
  });
});
