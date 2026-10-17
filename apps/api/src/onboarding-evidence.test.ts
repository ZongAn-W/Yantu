import { describe, expect, it } from "vitest";
import { FIRST_QUESTION, newSession } from "./onboarding-contracts.js";
import { sanitizeInterviewSession } from "./onboarding-evidence.js";

describe("confirmed planning constraints during session recovery", () => {
  it("preserves confirmed rest days, capacity and target date over earlier interview answers", () => {
    const session = newSession();
    session.stage = "schedule";
    session.constraints_confirmed = true;
    session.answers = [{ question: FIRST_QUESTION, answer: "学习 Python" },
      { question: "每天可用学习时间？", answer: "每天3小时" }];
    session.profile.weekly_minutes = { "0": 0, "1": 300, "2": 300, "3": 300, "4": 300, "5": 300, "6": 300 };
    session.profile.target_date = "2027-12-21";
    session.profile.target_date_confirmed = true;
    session.profile.plan_start_date = "2026-10-17";
    session.profile.plan_end_date = "2026-11-13";
    const recovered = sanitizeInterviewSession(session);
    expect(recovered.profile).toEqual(session.profile);
    expect(recovered.profile).not.toBe(session.profile);
    expect(sanitizeInterviewSession(recovered).profile).toEqual(session.profile);
  });

  it("still derives unconfirmed interview values and preserves an explicitly cleared confirmed target", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "学习 Python" },
      { question: "每天可用学习时间？", answer: "每天3小时，目标日期2027-12-21" }];
    expect(sanitizeInterviewSession(session).profile.weekly_minutes["0"]).toBe(180);
    session.constraints_confirmed = true;
    session.profile.target_date = null;
    session.profile.target_date_confirmed = false;
    expect(sanitizeInterviewSession(session).profile.target_date).toBeNull();
    expect(sanitizeInterviewSession(session).profile.target_date_confirmed).toBe(false);
  });
});
