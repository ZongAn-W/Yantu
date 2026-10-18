import { describe, expect, it } from "vitest";
import { estimatedExamDate } from "./exam-dates.js";

describe("estimatedExamDate", () => {
  it("estimates the second-to-last Saturday of December for recent years", () => {
    // 近年实际初试日：2023-12-23、2024-12-21、2025-12-20、2026-12-19 均为 12 月倒数第二个周六。
    expect(estimatedExamDate(2023)).toBe("2023-12-23");
    expect(estimatedExamDate(2024)).toBe("2024-12-21");
    expect(estimatedExamDate(2025)).toBe("2025-12-20");
    expect(estimatedExamDate(2026)).toBe("2026-12-19");
    expect(estimatedExamDate(2027)).toBe("2027-12-18");
  });

  it("stays on a Saturday inside December across leap years", () => {
    for (const year of [2023, 2027, 2028, 2033]) {
      const date = estimatedExamDate(year);
      const value = new Date(`${date}T00:00:00Z`);
      expect(date.slice(0, 7)).toBe(`${year}-12`);
      expect(Number.isNaN(value.getTime())).toBe(false);
      expect(value.getUTCDay()).toBe(6);
      // “倒数第二个”：下一个周六仍在 12 月，再下一个已经跨年。
      const next = new Date(value);
      next.setUTCDate(next.getUTCDate() + 7);
      expect(next.getUTCMonth()).toBe(11);
      const nextNext = new Date(value);
      nextNext.setUTCDate(nextNext.getUTCDate() + 14);
      expect(nextNext.getUTCFullYear()).toBe(year + 1);
    }
  });

  it("rejects a non-integer year", () => {
    expect(() => estimatedExamDate(2027.5)).toThrow("整数");
  });
});
