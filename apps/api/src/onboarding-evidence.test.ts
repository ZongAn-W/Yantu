import { describe, expect, it } from "vitest";
import { FIRST_QUESTION, newSession } from "./onboarding-contracts.js";
import { analyzeInterview, findUngroundedMentions, sanitizeInterviewSession } from "./onboarding-evidence.js";

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

describe("exam goal recognition from the user's own wording", () => {
  it("recognizes 6级/6 级 as a 四六级 exam goal and keeps the model's follow-up question", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "12 月份要考 6 级，这次 6 级我要刷到 580 分，还要保研" }];
    const evidence = analyzeInterview(session);
    expect(evidence.goalType).toBe("exam");
    expect(evidence.subtype).toBe("四六级");
    // 用户自己说过“6 级/580 分”，模型追问“六级”“580 分”不能被判成无依据而退回模板。
    expect(findUngroundedMentions(["你目前六级是什么水平？上次模考 580 分了吗？"], session, evidence)).toEqual([]);
  });

  it("promotes the goal type when the exam name appears in an answer that is not the goal question", () => {
    const session = newSession();
    session.answers = [
      { question: FIRST_QUESTION, answer: "我想提升英语，顺便准备一个考试" },
      { question: "各科学到哪一步了？", answer: "我要考英语六级" },
    ];
    const evidence = analyzeInterview(session);
    // “英语六级”是在非目标题里说的；旧逻辑会因 goal_type=other 把 subtype 清空，导致后续整轮降级。
    expect(evidence.goalType).toBe("exam");
    expect(evidence.subtype).toBe("四六级");
  });

  it("does not treat a cohort year like 2024级 as an exam level", () => {
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "我是 2024 级本科生，想提升英语写作" }];
    const evidence = analyzeInterview(session);
    expect(evidence.subtype).toBe("");
    expect(evidence.goalType).toBe("skill");
  });

  it("accepts a score difference derived from two scores the user gave, but still flags invented scores", () => {
    const session = newSession();
    session.answers = [
      { question: FIRST_QUESTION, answer: "12 月份要考 6 级，这次我要刷到 580 分" },
      { question: "你上次考了多少分？", answer: "六级上次考了 530" },
    ];
    const evidence = analyzeInterview(session);
    expect(findUngroundedMentions(["六级上次 530 分，距离 580 分还差 50 分。"], session, evidence)).toEqual([]);
    expect(findUngroundedMentions(["你上次考了 600 分吧？"], session, evidence)).toEqual(["分数「600」"]);
  });
});
