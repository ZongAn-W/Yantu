import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { PlannerDocumentSchema } from "./sync-contracts.js";

const legacyFixture = () => JSON.parse(readFileSync(new URL("../../flutter_client/test/fixtures/planner_v1.json", import.meta.url), "utf8"));

describe("tag document contract", () => {
  it("normalizes legacy courses to tags at the input boundary and writes canonical relations", () => {
    const legacy = legacyFixture();
    const canonical = PlannerDocumentSchema.parse(legacy);
    expect(canonical.tags).toHaveLength(1);
    expect(canonical.tags[0]).toMatchObject({ id: "calculus", name: "高数", user_id: legacy.profile.user_id });
    expect(canonical.tasks[0].tag_ids).toEqual(["calculus"]);
    expect(canonical.profile).not.toHaveProperty("subject_limit_minutes");
    expect(canonical).not.toHaveProperty("subjects");
    expect(canonical.tasks[0]).not.toHaveProperty("subject_id");
  });

  it("allows untagged and multi-tag tasks while checking names and ownership", () => {
    const document = PlannerDocumentSchema.parse(legacyFixture());
    const owner = document.profile.user_id;
    document.tags.push({ id: "tag-2", user_id: owner, name: "真题" });
    document.tasks[0].tag_ids = [document.tags[0].id, "tag-2"];
    const untagged = { ...document.tasks[0], id: "task-untagged", tag_ids: [] };
    document.tasks.push(untagged);
    expect(PlannerDocumentSchema.parse(document).tasks.map(task => task.tag_ids)).toEqual([["calculus", "tag-2"], []]);

    const duplicateName = structuredClone(document);
    duplicateName.tags[1].name = "  高数  ";
    expect(PlannerDocumentSchema.safeParse(duplicateName).success).toBe(false);
    const foreignTag = structuredClone(document);
    foreignTag.tags[1].user_id = "other-user";
    expect(PlannerDocumentSchema.safeParse(foreignTag).success).toBe(false);
    const missingTag = structuredClone(document);
    missingTag.tasks[0].tag_ids = ["missing"];
    expect(PlannerDocumentSchema.safeParse(missingTag).success).toBe(false);
  });
});
