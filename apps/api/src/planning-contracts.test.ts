import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { ItemDraftSchema, PlanDraftSchema } from "./contracts.js";
import { ItemPlanningSchema, PlanPlanningSchema } from "./planning-contracts.js";
import { PlannerDocumentSchema } from "./sync-contracts.js";
import { hasPlanningMetadata, preservePlanningMetadata } from "./sync.js";

const fixture = () => JSON.parse(readFileSync(new URL("../../flutter_client/test/fixtures/planner_v1.json", import.meta.url), "utf8"));
const strategy = () => PlanPlanningSchema.parse({ version: 1, prompt_version: "planning-1", rules_version: "rules-1",
  rolling: true, route: [], milestones: [], assumptions: ["estimated"], risks: [], uncovered: [] });
const workload = { components: [{ id: "papers", label: "past papers", quantity: 21, unit: "paper", minutes_per_unit: 180 }],
  source: "user supplied scope", confidence: "medium" as const, calibration: "compare actual time after 3 papers" };

describe("planning metadata contracts and writer compatibility", () => {
  it("leaves legacy records without inferred metadata", () => {
    const data = PlannerDocumentSchema.parse(fixture());
    expect(data.planning).toBeUndefined();
    expect(data.tasks.every(task => task.planning === undefined)).toBe(true);
    expect(hasPlanningMetadata(data)).toBe(false);
  });
  it("preserves structured workload and strategy through draft and sync parsing", () => {
    const planning = ItemPlanningSchema.parse({ workload, activity: { kind: "finite", starts_on: "2026-10-17",
      ends_on: "2027-12-21" } });
    const item = ItemDraftSchema.parse({ id: "item", tag_names: ["高数"], title: "papers", estimated_minutes: 3780,
      deadline: "2027-12-21", planning });
    const draft = PlanDraftSchema.parse({ items: [item], analysis_summary: "scope", planning: strategy() });
    expect(draft.items[0].planning?.workload?.components[0]).toMatchObject({ quantity: 21, minutes_per_unit: 180 });
    expect(draft.planning?.detail_days).toBe(14);
    const data = fixture();
    data.planning = strategy();
    data.tasks[0].planning = planning;
    data.tasks[0].estimated_minutes = 3780;
    data.blocks[0].activity_instance_id = "item:2026-10-12:1";
    expect(PlannerDocumentSchema.parse(data).tasks[0].planning).toEqual(planning);
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
    current.tasks[0].planning = { workload };
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
  it("refuses a new client's scalar budget edit that contradicts confirmed scope", () => {
    const data = fixture();
    data.planning = strategy();
    data.tasks[0].planning = { workload };
    data.tasks[0].estimated_minutes = 2400;
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(false);
    data.tasks[0].estimated_minutes = 3780;
    expect(PlannerDocumentSchema.safeParse(data).success).toBe(true);
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
