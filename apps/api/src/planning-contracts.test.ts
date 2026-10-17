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
    const item = ItemDraftSchema.parse({ id: "item", course_id: "course", title: "papers", estimated_minutes: 3780,
      deadline: "2027-12-21", planning });
    const draft = PlanDraftSchema.parse({ courses: [{ id: "course", name: "course" }], items: [item], analysis_summary: "scope", planning: strategy() });
    expect(draft.items[0].planning?.workload?.components[0]).toMatchObject({ quantity: 21, minutes_per_unit: 180 });
    expect(draft.planning?.detail_days).toBe(14);
    const data = fixture();
    data.planning = strategy();
    data.tasks[0].planning = planning;
    data.tasks[0].estimated_minutes = 3780;
    data.blocks[0].activity_instance_id = "item:2026-10-12:1";
    expect(PlannerDocumentSchema.parse(data).tasks[0].planning).toEqual(planning);
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
});
