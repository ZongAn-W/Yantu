import { describe, expect, it } from "vitest";
import { newSession } from "./onboarding-contracts.js";
import { compactPlanContext } from "./onboarding-plan-context.js";

type Row = Record<string, unknown>;
const tag = (id: string, name = id): Row => ({ id, name });
const task = (id: string, tag_ids: string[], changes: Row = {}): Row => ({
  id, title: id, tag_ids, status: "not_started", estimated_minutes: 60, completed_minutes: 0,
  priority: 2, deadline: "2026-12-01", ...changes,
});

describe("compact tag-aware planning context", () => {
  it("includes multi-tag tasks once and returns only referenced labels", () => {
    const session = newSession();
    session.current_plan = { tags: [tag("math", "数学"), tag("weakness", "薄弱项"), tag("unused")],
      items: [task("one", ["math", "weakness"]), task("two", [])] };
    const result = compactPlanContext(session, "items")!;
    expect(result.tags).toEqual([tag("math", "数学"), tag("weakness", "薄弱项")]);
    expect((result.items as Row[]).map(row => row.tag_ids)).toEqual([["math", "weakness"], []]);
    expect(result).not.toHaveProperty("courses");
  });

  it("keeps fixed tasks and dependency closure, while retaining archived task context separately", () => {
    const session = newSession();
    session.current_plan = { tags: [tag("reading", "阅读")],
      items: [task("fixed", ["reading"], { is_fixed: true, planning: { dependencies: [{ task_id: "done" }] } }),
        task("done", [], { status: "completed" }), task("archived", ["reading"], { status: "archived" })],
      recent_blocks: [{ id: "block", task_id: "fixed", is_fixed: true, date: "2026-10-20" }] };
    const result = compactPlanContext(session, "items")!;
    expect((result.items as Row[]).map(row => row.id)).toEqual(["fixed", "done"]);
    expect(result.archived_items).toEqual([{ id: "archived", title: "archived", status: "archived", tag_ids: ["reading"] }]);
    expect(result.recent_blocks).toHaveLength(1);
  });

  it("converts legacy course references into tag names for model context", () => {
    const session = newSession();
    const legacy = task("legacy", []);
    delete legacy.tag_ids;
    legacy.subject_id = "old-math";
    session.current_plan = { courses: [{ id: "old-math", name: "数学" }], items: [legacy] };
    const result = compactPlanContext(session, "items")!;
    expect(result.tags).toEqual([{ id: "old-math", name: "数学" }]);
    expect((result.items as Row[])[0].tag_ids).toEqual(["old-math"]);
  });
});
