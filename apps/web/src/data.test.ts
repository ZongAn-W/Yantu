import { describe, expect, it } from "vitest";
import { createInitialData, normalizePlannerData } from "./data";
import { refreshTaskProgress } from "./utils";
import { recordTaskDayMinutes } from "@planner/engine";

describe("stage item plans", () => {
  it("uses one item per learning stage with scope and finite dates", () => {
    const data = createInitialData("2026-10-14");
    const calculus = data.tasks.filter((item) => item.subject_id === "calculus");
    expect(calculus.map((item) => item.title)).toEqual(["基础一轮", "专题强化", "真题训练", "考前回顾"]);
    expect(calculus.filter((item) => item.title === "基础一轮")).toHaveLength(1);
    expect(calculus[0]).toMatchObject({ earliest_date: "2026-10-01", deadline: "2027-04-30" });
    expect(data.tasks.every((item) => item.description?.includes("范围：") && item.description?.includes("完成标准："))).toBe(true);
    expect(data.tasks.every((item) => item.earliest_date && item.earliest_date <= item.deadline)).toBe(true);
    expect(data.subjects.some((course) => course.name.includes("综合复习"))).toBe(false);
    expect(new Set(data.tasks.map((item) => `${item.subject_id}:${item.title}`)).size).toBe(data.tasks.length);
  });

  it("keeps vocabulary review and whole-paper work as separate time budgets", () => {
    const data = createInitialData("2026-10-14");
    expect(data.tasks.filter((item) => item.subject_id === "vocabulary").map((item) => item.title)).toEqual(["首轮记忆", "滚动复习"]);
    expect(data.tasks.filter((item) => item.subject_id === "mock-408").map((item) => item.title)).toEqual(["限时模拟", "试卷复盘"]);
    const scheduled = new Set(data.blocks.map((block) => block.task_id));
    expect(data.tasks.filter((item) => scheduled.has(item.id)).every((item) => item.earliest_date! <= "2026-10-28")).toBe(true);
    expect(data.blocks.filter((block) => block.date === "2026-10-14").reduce((sum, block) => sum + block.duration_minutes, 0)).toBe(360);
  });

  it("does not turn a time budget into content completion", () => {
    const data = createInitialData("2026-10-14");
    const task = data.tasks[0];
    task.estimated_minutes = 30;
    const recorded = refreshTaskProgress(recordTaskDayMinutes(data, task.id, "2026-10-14", 60));
    expect(recorded.tasks[0]).toMatchObject({ completed_minutes: 30, status: "in_progress" });
    expect(recorded.logs.reduce((sum, log) => sum + log.minutes, 0)).toBe(60);
  });

  it("round-trips item descriptions while rejecting the old category format", () => {
    const data = createInitialData("2026-10-14");
    expect(normalizePlannerData(JSON.parse(JSON.stringify(data)))).toEqual(data);
    const old = JSON.parse(JSON.stringify(data));
    old.tasks[0].category_id = "math-calculus";
    expect(normalizePlannerData(old)).toBeNull();
  });
});
