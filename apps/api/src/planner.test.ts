import { describe, expect, it } from "vitest";
import { dateAdd } from "./planner.js";
import { PlanDraftSchema, ProfileSchema } from "./contracts.js";

describe("API planning contracts", () => {
  it("does calendar arithmetic without local timezone drift", () => {
    expect(dateAdd("2027-12-25", 1)).toBe("2027-12-26");
    expect(dateAdd("2028-01-01", -1)).toBe("2027-12-31");
  });

  it("requires a valid exam profile and normalizes weekly defaults", () => {
    const profile = ProfileSchema.parse({ exam_type: "考研", exam_date: "2027-12-25" });
    expect(profile.weekly_minutes["1"]).toBe(0);
    expect(() => ProfileSchema.parse({ exam_type: "考研", exam_date: "not-a-date" })).toThrow();
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
