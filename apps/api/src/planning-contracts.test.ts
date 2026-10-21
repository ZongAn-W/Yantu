import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { ItemDraftSchema, PlanDraftSchema } from "./contracts.js";
import { ItemPlanningSchema, PlanPlanningSchema } from "./planning-contracts.js";
import { PlannerDocumentSchema } from "./sync-contracts.js";
import { hasPlanningMetadata, preservePlanningMetadata } from "./sync.js";

const fixture = () => JSON.parse(readFileSync(new URL("../../flutter_client/test/fixtures/planner_v1.json", import.meta.url), "utf8"));
const strategy = () => PlanPlanningSchema.parse({ version: 1, prompt_version: "planning-1", rules_version: "rules-1",
  rolling: true, route: [], milestones: [], assumptions: ["estimated"], risks: [], uncovered: [] });
const timePlanning = () => ItemPlanningSchema.parse({ activity: { kind: "finite", starts_on: "2026-10-17",
  ends_on: "2027-12-21" }, dependencies: [] });
/** 旧数据里的内容量机制：读取必须宽容，但不再保留。 */
const legacyContentPlanning = { workload: { components: [{ id: "papers", label: "past papers", quantity: 21, unit: "paper", minutes_per_unit: 180 }],
  source: "user supplied scope", confidence: "medium", calibration: "compare actual time after 3 papers" },
  content_progress: { completed_units: 2, confirmed: true },
  feedback: { content_units: 100, content_completed: false, difficulty: "manageable", sampled_at: "2026-10-16T00:00:00.000Z" },
  activity: { kind: "finite" as const, starts_on: "2026-10-17", ends_on: "2027-12-21" }, dependencies: [] };

describe("planning metadata contracts and writer compatibility", () => {
  it("leaves legacy records without inferred metadata", () => {
    const data = PlannerDocumentSchema.parse(fixture());
    expect(data.planning).toBeUndefined();
    expect(data.tasks.every(task => task.planning === undefined)).toBe(true);
    expect(hasPlanningMetadata(data)).toBe(false);
  });
  it("keeps time-based strategy and silently drops legacy content-volume fields", () => {
    const planning = ItemPlanningSchema.parse(legacyContentPlanning);
    expect(planning.activity).toEqual({ kind: "finite", starts_on: "2026-10-17", ends_on: "2027-12-21" });
    expect(planning.dependencies).toEqual([]);
    expect(JSON.stringify(planning)).not.toContain("workload");
    expect(JSON.stringify(planning)).not.toContain("content_progress");
    const item = ItemDraftSchema.parse({ id: "item", tag_names: ["高数"], title: "papers", estimated_minutes: 3780,
      deadline: "2027-12-21", planning });
    const draft = PlanDraftSchema.parse({ items: [item], analysis_summary: "scope", planning: strategy() });
    expect(draft.items[0].planning?.activity?.kind).toBe("finite");
    expect(draft.planning?.detail_days).toBe(14);
    const data = fixture();
    data.planning = strategy();
    // 旧文档里带内容量字段：解析宽容，写回结构不含它们。
    data.tasks[0].planning = legacyContentPlanning;
    data.tasks[0].estimated_minutes = 3780;
    data.tasks[0].completed_at = "2026-10-20T08:00:00.000Z";
    data.blocks[0].activity_instance_id = "item:2026-10-12:1";
    const parsed = PlannerDocumentSchema.parse(data);
    expect(parsed.tasks[0].planning).toEqual(timePlanning());
    expect(parsed.tasks[0].completed_at).toBe("2026-10-20T08:00:00.000Z");
    expect(JSON.stringify(parsed.tasks[0])).not.toContain("workload");
  });
  it("maps old course draft references to optional tag names at the input boundary", () => {
    const draft = PlanDraftSchema.parse({ courses: [{ id: "old-id", name: "读书" }], items: [{ id: "item", course_id: "old-id",
      title: "Read", estimated_minutes: 60, deadline: "2027-12-21" }], analysis_summary: "legacy", assumptions: [], warnings: [] });
    expect(draft).not.toHaveProperty("courses");
    expect(draft.items[0].tag_names).toEqual(["读书"]);
    expect(draft.items[0]).not.toHaveProperty("course_id");
  });
  it("rejects dangling route references, missing dependencies and cycles", () => {
    const data = fixture();
    data.planning = { ...strategy(), route: [{ id: "phase", title: "phase", item_ids: ["missing"], outcome: "outcome", check: "check" }] };
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(false);
    delete data.planning;
    data.tasks[0].planning = { dependencies: [{ task_id: "missing", mode: "confirmed" }] };
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(false);
    const second = { ...data.tasks[0], id: "second", planning: { dependencies: [{ task_id: data.tasks[0].id, mode: "planned" }] } };
    data.tasks[0].planning = { dependencies: [{ task_id: second.id, mode: "planned" }] };
    data.tasks.push(second);
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(false);
  });
  it("preserves omitted metadata while honoring an explicit clear", () => {
    const current = PlannerDocumentSchema.parse(fixture());
    current.planning = strategy();
    current.tasks[0].planning = timePlanning();
    current.blocks[0].activity_instance_id = "stable-instance";
    const stripped = PlannerDocumentSchema.parse(fixture());
    const saved = preservePlanningMetadata(stripped, current);
    expect(saved.planning).toEqual(current.planning);
    expect(saved.tasks[0].planning).toEqual(current.tasks[0].planning);
    expect(saved.blocks[0].activity_instance_id).toBe("stable-instance");
    expect(hasPlanningMetadata(saved)).toBe(true);
    stripped.planning = null;
    stripped.tasks[0].planning = null;
    stripped.blocks[0].activity_instance_id = null;
    const cleared = preservePlanningMetadata(stripped, current);
    expect(cleared.planning).toBeNull();
    expect(cleared.tasks[0].planning).toBeNull();
    expect(cleared.blocks[0].activity_instance_id).toBeNull();
  });
  it("accepts time-budget edits without any workload consistency requirement", () => {
    const data = fixture();
    data.planning = strategy();
    data.tasks[0].planning = timePlanning();
    // 纯时间口径：改预算不再需要同步任何结构化工作量。
    data.tasks[0].estimated_minutes = 2400;
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(true);
    data.tasks[0].completed_at = "2026-10-20T08:00:00.000Z";
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(true);
    // completed_at 必须是合法的 ISO 时间戳；空字符串按“未完成”处理。
    data.tasks[0].completed_at = "not-a-timestamp";
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(false);
    data.tasks[0].completed_at = "";
    const parsed = PlannerDocumentSchema.parse(data);
    expect(parsed.tasks[0].completed_at).toBeNull();
  });
  it("supports the archived dual form while status stays a legacy projection", () => {
    // 新客户端：只发 archived + completed_at，status 可省略。
    const data = fixture();
    data.tasks[0].archived = true;
    delete data.tasks[0].status;
    data.tasks[0].completed_at = "2026-10-20T08:00:00.000Z";
    const parsed = PlannerDocumentSchema.parse(data);
    expect(parsed.tasks[0].archived).toBe(true);
    expect(parsed.tasks[0].status).toBeUndefined();
    expect(parsed.tasks[0].completed_at).toBe("2026-10-20T08:00:00.000Z");

    // 新客户端显式 false=取消归档；旧 status 仍可同时存在（服务端归一化时以 archived 为准）。
    data.tasks[0].archived = false;
    data.tasks[0].status = "archived";
    expect(PlannerDocumentSchema.parse(data).tasks[0].archived).toBe(false);

    // 旧客户端/旧文档：只发 status（含历史 delayed/conflict），archived 缺失可解析。
    const legacy = fixture();
    delete legacy.tasks[0].archived;
    for (const status of ["archived", "delayed", "conflict", "completed", "not_started"] as const) {
      legacy.tasks[0].status = status;
      expect(PlannerDocumentSchema.safeParse(legacy).success, status).toBe(true);
    }

    // archived 只接受布尔值。
    const invalid = fixture();
    invalid.tasks[0].archived = "true";
    expect(PlannerDocumentSchema.safeParse(invalid).success).toBe(false);
  });
  it("keeps server relation checks consistent with the client deletion rules", () => {
    // The client removes a deletable item, cleans `planning.route[].item_ids`,
    // drops stages left empty and invalidates quality. The cleaned document must
    // pass the server schema, while the unsafe variants the client refuses must
    // keep failing here too.
    const clone = (value: unknown) => JSON.parse(JSON.stringify(value));
    const data = fixture();
    const deletedId = data.tasks[0].id;
    data.tasks.push({ ...data.tasks[0], id: "second", title: "second" });
    data.planning = {
      ...strategy(),
      route: [{ id: "phase", title: "phase", item_ids: [deletedId, "second"], outcome: "outcome", check: "check" }],
      quality: { status: "pass" },
      needs_review: false,
    };
    const cleaned = clone(data);
    cleaned.tasks = cleaned.tasks.filter((task: { id: string }) => task.id !== deletedId);
    cleaned.blocks = [];
    cleaned.logs = [];
    cleaned.planning.route[0].item_ids = ["second"];
    cleaned.planning.needs_review = true;
    cleaned.planning.quality = null;
    expect(PlannerDocumentSchema.safeParse(cleaned).success).toBe(true);

    // Removing a prerequisite from the plan while another item still depends on
    // it would silently unlock the dependent item; the client refuses to save it.
    const danglingDependency = clone(cleaned);
    danglingDependency.tasks[0].planning = { dependencies: [{ task_id: deletedId, mode: "planned" }] };
    expect(PlannerDocumentSchema.safeParse(danglingDependency).success).toBe(false);

    // A stale route reference to the deleted item is rejected like before.
    const staleRoute = clone(cleaned);
    staleRoute.planning.route[0].item_ids = ["second", deletedId];
    expect(PlannerDocumentSchema.safeParse(staleRoute).success).toBe(false);

    // The client never emits an empty stage, and an emptied/removed route stays valid.
    const emptiedStage = clone(cleaned);
    emptiedStage.planning.route = [{ ...cleaned.planning.route[0], item_ids: [] }];
    expect(PlannerDocumentSchema.safeParse(emptiedStage).success).toBe(true);
    const noRoute = clone(cleaned);
    noRoute.planning.route = [];
    expect(PlannerDocumentSchema.safeParse(noRoute).success).toBe(true);
  });
});
