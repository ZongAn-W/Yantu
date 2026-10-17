import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  EXAM_CLARIFICATION_OPTIONS, EXAM_CLARIFICATION_QUESTION, EXAM_DETAIL_QUESTION,
  analyzeInterview, buildSafeInterview, deriveInterviewProfile, sanitizeInterviewSession,
} from "./onboarding-evidence.js";
import { FIRST_QUESTION, newSession, type OnboardingSession } from "./onboarding-contracts.js";
import { advanceOnboarding } from "./onboarding.js";
import { generateCourses, nextInterview } from "./onboarding-ai.js";

const aiConfig = vi.hoisted(() => ({ aiApiKey: "", aiBaseUrl: "https://ai.invalid", aiModel: "test", aiReasoningEffort: "max" }));
vi.mock("./config.js", () => ({ config: aiConfig }));
const fetchMock = vi.fn<typeof fetch>();
const week = { "0": 120, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 120 };
const answer = (session: OnboardingSession, text: string) => advanceOnboarding(session, { type: "answer", answer: text });

function aiResponse(body: Record<string, unknown>) {
  fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify(body) } }] }));
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-10-17T04:00:00Z"));
  aiConfig.aiApiKey = "";
  fetchMock.mockReset();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("exam information confirmation", () => {
  it("keeps unverified generated exam subjects explicit without blocking an editable draft", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.profile = { ...session.profile, goal_type: "exam", goal_subtype: "考研" };
    session.answers = [{ question: FIRST_QUESTION, answer: "考研" }];
    aiResponse({ courses: [{ id: "english", name: "英语一", description: "阅读练习", priority: 2 }], summary: "课程草案", assumptions: [], warnings: [] });
    const result = await generateCourses(session);
    expect(result.courses[0].name).toBe("英语一");
    expect(result.assumptions.join(" ")).toContain("英语一");
    expect(result.warnings.join(" ")).toContain("核实依据");
  });
  it("clarifies the exam type when only 考试备考 is answered", async () => {
    const session = await answer(newSession(), "考试备考");
    expect(session.profile).toMatchObject({ goal_type: "exam", goal_subtype: "" });
    expect(session.question).toBe(EXAM_CLARIFICATION_QUESTION);
    expect(session.question_options).toEqual(EXAM_CLARIFICATION_OPTIONS);
    expect(session.question_options).not.toContain("其他");
    expect(session.question).not.toMatch(/考研|雅思|数学一|408|英语一|总分\s*\d/);
  });

  it("does not carry an old 考研 plan into a restarted interview", async () => {
    const oldPlan = {
      profile: { goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学", target_program: "计算机技术" },
      courses: [{ id: "math", name: "高数" }], items: [], fixed_events: [], recent_blocks: [],
    };
    const completed: OnboardingSession = { ...(await answer(newSession(), "考研")), stage: "complete", has_plan: true, plan_revision: 7, current_plan: oldPlan };
    const restarted = await advanceOnboarding(completed, { type: "restart_interview" });
    expect(restarted).toMatchObject({ stage: "interview", answers: [], has_plan: true, replanning: true, current_plan: oldPlan });
    const answered = await answer(restarted, "考试备考");
    expect(answered.profile).toMatchObject({ goal_type: "exam", goal_subtype: "", target_school: "", target_program: "" });
    expect(answered.question).toBe(EXAM_CLARIFICATION_QUESTION);
    // 旧计划仍然保留，作为进度和历史背景，但没有成为本轮目标。
    expect(answered.current_plan).toEqual(oldPlan);
  });

  it("keeps old-plan 考研 out of a restarted AI interview", async () => {
    const oldPlan = {
      profile: { goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学", target_program: "计算机技术" },
      courses: [{ id: "math", name: "高数" }], items: [],
    };
    const completed: OnboardingSession = { ...(await answer(newSession(), "考研")), stage: "complete", has_plan: true, plan_revision: 7, current_plan: oldPlan };
    const restarted = await advanceOnboarding(completed, { type: "restart_interview" });
    aiConfig.aiApiKey = "key";
    aiResponse({
      question: "继续考研吗？数学一怎么复习？",
      question_options: ["数学一"],
      question_multiple: false,
      profile: { ...newSession().profile, goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学" },
    });
    const answered = await answer(restarted, "考试备考");
    expect(answered.profile).toMatchObject({ goal_type: "exam", goal_subtype: "", target_school: "" });
    expect(answered.question).toBe(EXAM_CLARIFICATION_QUESTION);
    expect(answered.current_plan).toEqual(oldPlan);
  });

  it.each([
    ["雅思", "雅思"],
    ["考公", "考公"],
    ["教资", "教师资格"],
    ["公务员/事业单位", "考公"],
    ["CATTI 二笔", "CATTI 二笔"],
  ])("continues with the user-reported exam %s", async (text, expected) => {
    const clarified = await answer(newSession(), "考试备考");
    const confirmed = await answer(clarified, text);
    expect(confirmed.profile.goal_type).toBe("exam");
    expect(confirmed.profile.goal_subtype).toBe(expected);
    expect(confirmed.question).toContain(expected);
    expect(confirmed.question).not.toMatch(/数学一|408|英语一|总分\s*\d/);
  });

  it("normalizes graduate-exam synonyms without another naming question", async () => {
    const clarified = await answer(newSession(), "考试备考");
    const category = await answer(clarified, "研究生招生");
    expect(category.profile.goal_subtype).toBe("考研");
    expect(category.question).toContain("大几");
    expect(category.question).not.toMatch(/具体考试|哪一类.*招生考试|数学一|408/);
  });

  it("does not assume subjects or fixed scores once 考研 is confirmed", async () => {
    let session = await answer(newSession(), "考研");
    expect(session.profile.goal_subtype).toBe("考研");
    expect(session.question).not.toMatch(/数学一|数学二|数学三|408|英语一|英语二|政治|总分\s*\d|四科/);
    session = await answer(session, "上海交通大学");
    session = await answer(session, "计算机技术");
    expect(session.question).toContain("学硕还是专硕");
    expect(session.question).not.toMatch(/数学一|408|英语一|政治|总分\s*\d/);
  });

  it("lets the latest explicit goal override earlier ones and handles negation", async () => {
    const direct = await answer(newSession(), "不是考研，我准备雅思");
    expect(direct.profile).toMatchObject({ goal_type: "exam", goal_subtype: "雅思" });
    expect(direct.question).toContain("雅思");
    expect(direct.question).not.toContain("考研");

    const first = await answer(newSession(), "考研");
    const changed = await answer(first, "不考研了，我准备雅思");
    expect(changed.profile.goal_subtype).toBe("雅思");
    expect(changed.question).toContain("雅思");
    expect(changed.question).not.toContain("考研");
  });

  it("does not change the exam goal when later answers are background details", async () => {
    let session = await answer(newSession(), "考研");
    session = await answer(session, "上海交通大学");
    session = await answer(session, "计算机技术");
    // 基础题里的“零基础”等描述不能把考试目标改判成技能提升。
    session = await answer(session, "零基础，尚未开始");
    expect(session.profile.goal_type).toBe("exam");
    expect(session.profile.goal_subtype).toBe("考研");
  });

  it("asks whether to reuse the old goal when resuming without new answers", async () => {
    const session: OnboardingSession = { ...newSession(), has_plan: true };
    session.current_plan = { profile: { goal_type: "exam", goal_subtype: "考研" }, courses: [], items: [] };
    const asked = await nextInterview(session);
    expect(asked.question).not.toBe(FIRST_QUESTION);
    expect(asked.question).toContain("沿用");
    // 用户尚未确认，旧计划目标不会成为本轮目标。
    expect(asked.profile.goal_subtype).toBe("");

    const carried: OnboardingSession = { ...session, answers: [{ question: asked.question, answer: "沿用原来的目标" }] };
    const confirmed = await nextInterview(carried);
    expect(confirmed.profile).toMatchObject({ goal_type: "exam", goal_subtype: "考研" });
  });

  it("corrects a polluted pending question while keeping valid answers and revision", async () => {
    const polluted: OnboardingSession = {
      ...newSession(),
      revision: 9,
      answers: [{ question: FIRST_QUESTION, answer: "考试备考" }],
      question: "你考研总分目标是多少？数学一、408、英语一、政治怎么安排？",
      question_options: ["数学一", "408", "英语一", "政治"],
      profile: {
        ...newSession().profile, goal_type: "exam", goal_subtype: "考研",
        target_school: "上海交通大学", target_program: "计算机技术", target_date: "2027-12-25",
        constraints_text: "按考研数学一和408安排",
      },
      current_plan: { profile: { goal_type: "exam", goal_subtype: "考研" }, courses: [], items: [] },
    };
    const fixed = sanitizeInterviewSession(polluted);
    expect(fixed.revision).toBe(9);
    expect(fixed.answers).toEqual(polluted.answers);
    expect(fixed.profile).toMatchObject({ goal_type: "exam", goal_subtype: "", target_school: "", target_program: "", target_date: null, constraints_text: "" });
    expect(fixed.question).toBe(EXAM_CLARIFICATION_QUESTION);
    expect(fixed.question_options).toEqual(EXAM_CLARIFICATION_OPTIONS);
    expect(fixed.question).not.toMatch(/数学一|408|英语一|政治|总分/);

    const answered = await advanceOnboarding(fixed, { type: "answer", answer: "雅思" });
    expect(answered.revision).toBe(10);
    expect(answered.answers).toEqual([...polluted.answers, { question: EXAM_CLARIFICATION_QUESTION, answer: "雅思" }]);
    expect(answered.profile.goal_subtype).toBe("雅思");
    expect(answered.question).toContain("雅思");
  });

  it("keeps the safe fallback question independent from old plan details", () => {
    const session: OnboardingSession = {
      ...newSession(),
      answers: [{ question: FIRST_QUESTION, answer: "考试备考" }],
      current_plan: { profile: { goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学" }, courses: [], items: [] },
    };
    const evidence = analyzeInterview(session);
    const prompt = buildSafeInterview(session, evidence);
    const profile = deriveInterviewProfile(session, evidence);
    expect(prompt.question).toBe(EXAM_CLARIFICATION_QUESTION);
    expect(prompt.question).not.toMatch(/上海交通大学|考研/);
    expect(profile.goal_subtype).toBe("");
  });

  it("falls back when the AI returns an exam that the current answer does not support", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "考试备考" }];
    aiResponse({
      question: "考研总分500，数学一、408、英语一、政治怎么安排？",
      question_options: ["数学一", "408", "英语一", "政治"],
      question_multiple: false,
      profile: {
        ...session.profile, goal_type: "exam", goal_subtype: "考研",
        target_school: "上海交通大学", target_program: "计算机技术", target_date: "2027-12-25",
      },
      recommendations: {
        target_date: "2027-12-25", target_date_reason: "按考研日期安排", target_date_estimated: true,
        plan_end_date: "2026-11-13", plan_end_date_reason: "", weekly_minutes: week, weekly_minutes_reason: "",
      },
    });
    const result = await nextInterview(session);
    expect(result.profile).toMatchObject({ goal_type: "exam", goal_subtype: "", target_school: "", target_program: "", target_date: null });
    expect(result.question).toBe(EXAM_CLARIFICATION_QUESTION);
    expect(result.question_options).toEqual(EXAM_CLARIFICATION_OPTIONS);
    // AI 给出的日期只能作为建议，不能标成用户已确认。
    expect(result.recommendations.target_date_estimated).toBe(true);
  });

  it("rejects AI subject assumptions after 考研 is confirmed without subjects", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "考研" }];
    aiResponse({
      question: "你数学一考多少分？408和英语一怎么复习？",
      question_options: ["数学一", "408", "英语一"],
      question_multiple: false,
      profile: { ...session.profile, goal_type: "exam", goal_subtype: "考研" },
    });
    const result = await nextInterview(session);
    expect(result.profile.goal_subtype).toBe("考研");
    expect(result.question).not.toMatch(/数学一|408|英语一/);
    expect(result.question).toContain("大几");
  });

  it("allows subject questions the user actually mentioned", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "考研，数学一和408" }];
    aiResponse({
      question: "你的数学一和408复习到什么程度？",
      question_options: ["数学一", "408"],
      question_multiple: false,
      profile: { ...session.profile, goal_type: "exam", goal_subtype: "考研" },
    });
    const result = await nextInterview(session);
    expect(result.question).toContain("数学一");
    expect(result.question).toContain("408");
  });

  it("treats explicitly negated subjects as unsupported", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "考研，不考数学一" }];
    aiResponse({
      question: "你的数学一复习到什么程度？",
      question_options: ["数学一"],
      question_multiple: false,
      profile: { ...session.profile, goal_type: "exam", goal_subtype: "考研" },
    });
    const result = await nextInterview(session);
    expect(result.question).not.toContain("数学一");
  });

  it("does not let the AI turn old plan details into current goals", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "考研" }];
    session.current_plan = {
      profile: { goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学", target_program: "计算机技术" },
      courses: [], items: [],
    };
    aiResponse({
      question: "你准备继续报考上海交通大学计算机技术吗？",
      question_options: [],
      question_multiple: false,
      profile: {
        ...session.profile, goal_type: "exam", goal_subtype: "考研",
        target_school: "上海交通大学", target_program: "计算机技术",
      },
    });
    const result = await nextInterview(session);
    expect(result.profile.goal_subtype).toBe("考研");
    expect(result.profile.target_school).toBe("");
    expect(result.profile.target_program).toBe("");
    expect(result.question).not.toMatch(/上海交通大学|计算机技术/);
  });

  it("corrects a negated subtype proposed by the AI", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "不是考研，我准备雅思" }];
    aiResponse({
      question: "你考研的目标分数是多少？",
      question_options: [],
      question_multiple: false,
      profile: { ...session.profile, goal_type: "exam", goal_subtype: "考研" },
    });
    const result = await nextInterview(session);
    expect(result.profile.goal_subtype).toBe("雅思");
    expect(result.question).toContain("雅思");
    expect(result.question).not.toContain("考研");
  });
});
