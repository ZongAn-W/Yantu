import { describe, expect, it } from "vitest";
import { newSession, type OnboardingSession } from "./onboarding-contracts.js";
import { compactPlanContext } from "./onboarding-plan-context.js";

type Row = Record<string, any>;
const task = (id: string, subject_id: string, changes: Row = {}) => ({ id, subject_id, title: id, description: "Original learning scope",
  estimated_minutes: 240, completed_minutes: 0, earliest_date: "2026-10-18", deadline: "2026-12-01", deadline_kind: "deadline",
  priority: 2, is_fixed: false, status: "not_started", user_id: "owner", created_at: "2026-10-01T00:00:00Z", ...changes });
const course = (id: string, name = id) => ({ id, name, priority: 2, color: "#000000", user_id: "owner" });
const draft = (id: string, course_id: string, changes: Row = {}): OnboardingSession["items"][number] => ({ id, course_id, title: id,
  description: "", completion_criteria: "", estimated_minutes: 240, deadline: "2026-12-01", deadline_kind: "deadline", priority: 2, ...changes });
const resultItems = (result: ReturnType<typeof compactPlanContext>) => result?.items as Row[];

describe("compactPlanContext", () => {
  it("keeps a missing plan absent", () => {
    expect(compactPlanContext(newSession(), "items")).toBeNull();
  });

  it("keeps fixed tasks and dependency closure across unrelated, completed and archived courses", () => {
    const session = newSession();
    session.courses = [{ id: "new-math-id", name: "Mathematics", description: "", priority: 2 }];
    session.items = [draft("draft", "new-math-id", { planning: { dependencies: [{ task_id: "draft-predecessor", mode: "confirmed" }] } })];
    session.current_plan = {
      courses: [course("math", "Mathematics"), course("history"), course("prerequisites")],
      items: [task("active", "math", { planning: { dependencies: [{ task_id: "completed", mode: "confirmed" }] } }),
        task("completed", "prerequisites", { status: "completed", completed_minutes: 240,
          planning: { dependencies: [{ task_id: "archived-predecessor", mode: "planned" }] } }),
        task("archived-predecessor", "prerequisites", { status: "archived", planning: { dependencies: [{ task_id: "active", mode: "planned" }] } }),
        task("draft-predecessor", "prerequisites", { status: "completed" }),
        task("fixed", "history", { is_fixed: true, status: "archived" }),
        task("fixed-by-block", "history", { status: "completed" }),
        task("unrelated", "history"), task("unrelated-completed", "history", { status: "completed" }),
        task("unrequested-archive", "math", { status: "archived" })],
      recent_blocks: [{ id: "fixed-block", task_id: "fixed-by-block", is_fixed: true, date: "2026-10-20", duration_minutes: 30 }],
    };
    const result = compactPlanContext(session, "items");
    expect(resultItems(result).map(item => item.id)).toEqual(["active", "completed", "archived-predecessor", "draft-predecessor", "fixed", "fixed-by-block"]);
    expect(resultItems(result).find(item => item.id === "fixed-by-block")?.is_fixed).toBe(true);
    expect((result?.courses as Row[]).map(course => course.id)).toEqual(["math", "history", "prerequisites"]);
    expect(resultItems(result)[0].course_id).toBe("math");
    expect(result?.archived_items).toEqual([{ id: "unrequested-archive", title: "unrequested-archive", status: "archived", course_id: "math" }]);
  });

  it("retains reused course IDs and explicit draft item IDs even when the current course name changes", () => {
    const session = newSession();
    session.courses = [{ id: "math", name: "Renamed", description: "", priority: 2 }];
    session.items = [draft("retained", "math")];
    session.current_plan = { courses: [course("math", "Original"), course("old")],
      items: [task("same-course", "math"), task("retained", "old", { status: "archived" }), task("skip", "old")] };
    expect(resultItems(compactPlanContext(session, "items")).map(item => item.id)).toEqual(["same-course", "retained"]);
  });

  it("preserves true deadlines, all structured workload evidence and execution facts without clipping", () => {
    const session = newSession();
    const planning = {
      workload: { components: [{ id: "exercise", label: "Chapters and exercises", quantity: 4, unit: "chapter", minutes_per_unit: 60,
        selected: true, range_min: 30, range_max: 90 }], source: "answer:0 and verified material", confidence: "low", calibration: "Measure three complete chapters",
        evidence_refs: ["answer:0", "https://example.test/course"] },
      activity: { kind: "recurring", starts_on: "2026-10-18", ends_on: "2026-12-01", sessions_per_week: 3, session_minutes: 240, state: "paused" },
      dependencies: [{ task_id: "unavailable-predecessor", mode: "confirmed" }],
      content_progress: { completed_units: 2, confirmed: false, feedback: "Still cannot solve chapter 2" },
      feedback: { content_units: 2, content_completed: false, difficulty: "hard", sampled_at: "2026-10-18T00:00:00Z" },
    };
    const signals = [{ item_id: "active", content_units: 2, content_completed: false, difficulty: "hard", valid_samples: 2,
      actual_minutes: 170, observed_minutes_per_unit: null, estimated: true }];
    const event = { id: "exam", title: "Official exam", date: "2026-12-01", start_minute: 540, duration_minutes: 180, kind: "official_exam", repeat: "none" };
    session.current_plan = { courses: [course("math")], items: [task("active", "math", { planning, completed_minutes: 170, deadline_kind: undefined })],
      feedback_signals: signals, fixed_events: [event] };
    const result = compactPlanContext(session, "items");
    expect(resultItems(result)[0]).toMatchObject({ deadline: "2026-12-01", completed_minutes: 170, planning });
    expect(resultItems(result)[0]).not.toHaveProperty("deadline_kind");
    expect(result?.feedback_signals).toEqual(signals);
    expect(result).not.toHaveProperty("fixed_events");
  });

  it("omits only duplicated draft descriptions and retains unique scope and constraints", () => {
    const session = newSession();
    session.items = [draft("same", "math", { description: "Read chapters 1-2" }),
      draft("combined", "math", { description: "Read chapter 3", completion_criteria: "Pass the quiz" }),
      draft("different", "math", { description: "Edited description" })];
    session.current_plan = { courses: [course("math")], items: [task("same", "math", { description: "Read chapters 1-2" }),
      task("combined", "math", { description: "Read chapter 3\n\u5b8c\u6210\u6807\u51c6\uff1aPass the quiz" }),
      task("different", "math", { description: "Only use the printed edition; do not use videos" })] };
    const result = resultItems(compactPlanContext(session, "items"));
    expect(result[0]).not.toHaveProperty("description");
    expect(result[1]).not.toHaveProperty("description");
    expect(result[2].description).toBe("Only use the printed edition; do not use videos");
  });

  it("keeps descriptions when the request does not include their draft copies", () => {
    const session = newSession();
    session.courses = [{ id: "math", name: "Mathematics", description: "Printed assignments", priority: 2 }];
    session.items = [draft("fixed", "math", { description: "Submit printed copy in person" })];
    session.current_plan = { courses: [{ ...course("math", "Mathematics"), description: "Printed assignments" }],
      items: [task("fixed", "math", { description: "Submit printed copy in person", is_fixed: true })] };
    for (const scope of ["interview", "recommendations", "courses"] as const) {
      const result = compactPlanContext(session, scope);
      expect(resultItems(result)[0].description).toBe("Submit printed copy in person");
      if (scope !== "courses") expect((result?.courses as Row[])[0].description).toBe("Printed assignments");
    }
    expect(resultItems(compactPlanContext(session, "items"))[0]).not.toHaveProperty("description");
  });

  it("keeps workload details for item generation and fixed tasks while simple calls retain only relevant execution structure", () => {
    const session = newSession();
    const planning = { workload: { components: [{ id: "read", label: "Reading", quantity: 4, unit: "chapter", minutes_per_unit: 60 }],
      source: "User material", confidence: "low", calibration: "Measure actual speed" }, activity: { kind: "finite", starts_on: "2026-10-18", ends_on: "2026-12-01" },
      content_progress: { completed_units: 1, confirmed: true }, dependencies: [{ task_id: "fixed", mode: "confirmed" }] };
    session.current_plan = { courses: [{ ...course("math"), description: "Only the printed textbook is available" }],
      items: [task("active", "math", { planning }), task("fixed", "math", { planning, is_fixed: true })] };
    expect(resultItems(compactPlanContext(session, "items"))[0].planning).toEqual(planning);
    for (const scope of ["interview", "courses", "recommendations"] as const) {
      const result = compactPlanContext(session, scope);
      const items = resultItems(result);
      expect(items[0].planning).toEqual({ activity: planning.activity, content_progress: planning.content_progress, dependencies: planning.dependencies });
      expect(items[1].planning).toEqual(planning);
      expect((result?.courses as Row[])[0].description).toBe("Only the printed textbook is available");
    }
  });

  it("exposes old goals only as interview background and keeps scheduling constraints and factual milestones", () => {
    const session = newSession();
    session.current_plan = { profile: { user_id: "owner", goal_text: "Former goal", goal_subtype: "Old exam", target_school: "Old school",
      foundation: "Completed first chapter", weekly_minutes: { "1": 0 }, buffer_minutes: 45, subject_limit_minutes: 180 },
      planning: { route: [{ title: "Old route" }], forecast: { minutes: 20000 }, frozen_inputs: { huge: "previous inputs" },
        milestones: [{ title: "Real exam", source_kind: "user", date_value: "2026-12-01", source_ref: "answer:0" },
          { title: "Verified announcement", source_kind: "verified", date_precision: "month", date_value: "2026-12", source_ref: "https://example.test/notice" },
          { title: "Old suggestion", source_kind: "suggested", date_value: "2026-12-15" }] } };
    const interview = compactPlanContext(session, "interview");
    expect(interview).not.toHaveProperty("profile");
    expect(interview?.historical_profile).toEqual({ goal_text: "Former goal", goal_subtype: "Old exam", target_school: "Old school", foundation: "Completed first chapter" });
    for (const scope of ["courses", "items", "recommendations"] as const) {
      const result = compactPlanContext(session, scope);
      expect(result).not.toHaveProperty("historical_profile");
      expect(result).not.toHaveProperty("planning");
      expect(result?.scheduling_constraints).toEqual({ weekly_minutes: { "1": 0 }, buffer_minutes: 45, subject_limit_minutes: 180 });
      expect(result?.milestones).toEqual((session.current_plan.planning as Row).milestones.slice(0, 2));
    }
  });

  it("retains fixed block protections and aggregates recent actual time without generated advice or ownership metadata", () => {
    const session = newSession();
    session.current_plan = { courses: [course("math")], items: [task("active", "math")], recent_blocks: [
      { id: "fixed", task_id: "active", is_fixed: true, date: "2026-10-18", start_minute: 600, duration_minutes: 30, actual_minutes: 10,
        status: "planned", completion_status: "partial", feedback: "Locked appointment", activity_instance_id: "instance-1", advice_text: "Old advice", user_id: "owner" },
      { id: "one", task_id: "active", date: "2026-10-17", actual_minutes: 40, feedback: "Difficult exercise", completion_status: "partial", advice_text: "Long generic generated advice" },
      { id: "two", task_id: "active", date: "2026-10-18", actual_minutes: 20 },
    ] };
    const result = compactPlanContext(session, "items");
    expect(result?.recent_blocks).toEqual([{ id: "fixed", task_id: "active", is_fixed: true, date: "2026-10-18", start_minute: 600, duration_minutes: 30,
      actual_minutes: 10, status: "planned", completion_status: "partial", feedback: "Locked appointment", activity_instance_id: "instance-1" }]);
    expect(result?.recent_execution).toEqual([{ item_id: "active", actual_minutes: 60, blocks: 2, latest_date: "2026-10-18",
      feedback: [{ id: "one", date: "2026-10-17", completion_status: "partial", feedback: "Difficult exercise" }] }]);
  });

  it("substantially reduces repeated snapshots while leaving stored full plan and returned facts independent", () => {
    const session = newSession();
    const items = Array.from({ length: 16 }, (_, i) => task(`item-${i}`, "math", {
      planning: { workload: { components: [{ id: "read", label: "Reading", quantity: 4, unit: "chapter", minutes_per_unit: 60 }], source: "User material", confidence: "low", calibration: "Measure actual speed" } },
    }));
    session.current_plan = { courses: [course("math")], items, planning: { route: [{ item_ids: items.map(item => item.id), outcome: "Previous intended outcome" }],
      frozen_inputs: { current_plan: { courses: [course("math")], items }, items, research: { full_original_text: "Historical material. ".repeat(500) } },
      forecast: { daily: Array.from({ length: 100 }, () => ({ date: "2026-10-18", minutes: 240, item_ids: items.map(item => item.id) })) } } };
    const previous = structuredClone(session);
    const result = compactPlanContext(session, "items");
    expect(JSON.stringify(result).length).toBeLessThan(JSON.stringify(session.current_plan).length * 0.4);
    expect(session).toEqual(previous);
    (resultItems(result)[0].planning as Row).workload.components[0].quantity = 999;
    expect(session).toEqual(previous);
  });
});
