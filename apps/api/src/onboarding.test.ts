import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ProfileSchema } from "./contracts.js";
import { ActionSchema, CalendarDateSchema, FIRST_QUESTION, FIRST_QUESTION_OPTIONS, QuestionOptionsSchema, RecommendationsSchema, newSession, normalizeQuestionOptions, SessionSchema, type OnboardingSession } from "./onboarding-contracts.js";
import { advanceOnboarding } from "./onboarding.js";
import { sanitizeInterviewSession } from "./onboarding-evidence.js";
import { generateItems, nextInterview } from "./onboarding-ai.js";
import { buildPlanningDocument, newPlanning } from "./planning-service.js";

const aiConfig = vi.hoisted(() => ({ aiApiKey: "", aiBaseUrl: "https://ai.invalid", aiModel: "test", aiReasoningEffort: "max",
  aiSimpleReasoningEffort: "low", aiPlanningReasoningEffort: "high" }));
vi.mock("./config.js", () => ({ config: aiConfig }));
const fetchMock = vi.fn<typeof fetch>();
const answer = (session: OnboardingSession, text: string) => advanceOnboarding(session, { type: "answer", answer: text });
async function fiveAnswers() {
  let session = newSession();
  for (const text of ["我要考研", "上海交通大学", "计算机技术", "高数刚开始，英语词汇学了一半", "英语词汇背完了，高数还没开始"]) session = await answer(session, text);
  return session;
}
const week = { "0": 120, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 120 };
const confirmConstraints = (session: OnboardingSession) => advanceOnboarding(session, { type: "set_constraints",
  start_date: "2026-10-17", end_date: "2026-11-13", weekly_minutes: week, detail_days: 14 });
async function finishPreview(session: OnboardingSession, fields: {start_date: string; end_date: string; target_date?: string; weekly_minutes: Record<string, number>}) {
  const preview = await advanceOnboarding(session, { type: "preview_schedule", ...fields, detail_days: 14 });
  return advanceOnboarding(preview, { type: "finish", ...fields, preview_token: preview.preview?.token as string });
}
/** 确保规划测试有足够的访谈上下文，不改变现有回答。 */
const withMinimumAnswers = (session: OnboardingSession) => ({
  ...session,
  stage: "interview" as const,
  answers: [
    ...session.answers,
    ...Array.from({ length: Math.max(0, 5 - session.answers.length) }, (_, i) => ({ question: `补充问题${i}`, answer: `补充回答${i}` })),
  ],
});

beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date("2026-10-17T04:00:00Z")); aiConfig.aiApiKey = ""; fetchMock.mockReset(); vi.stubGlobal("fetch", fetchMock); });
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); });

describe("guided onboarding", () => {
  it("restarts at the goal without resetting persistent revisions or the current plan", async () => {
    const previous = { ...(await fiveAnswers()), stage: "complete" as const, has_plan: true, plan_revision: 8,
      current_plan: { courses: [{ id: "math", name: "高数" }] } };
    const restarted = await advanceOnboarding(previous, { type: "restart_interview" });
    expect(restarted).toMatchObject({ revision: previous.revision + 1, stage: "interview", has_plan: true, replanning: true,
      plan_revision: 8, answers: [], question: FIRST_QUESTION, current_plan: previous.current_plan });
    expect(restarted.question_options).toEqual(FIRST_QUESTION_OPTIONS);
    expect(previous.answers).toHaveLength(5);
  });

  it("continues an existing interview with its transcript, profile and current plan", async () => {
    const previous = { ...(await fiveAnswers()), stage: "complete" as const, has_plan: true, plan_revision: 8,
      current_plan: { items: [{ id: "math", completed_minutes: 120 }] } };
    const resumed = await advanceOnboarding(previous, { type: "resume_interview" });
    expect(resumed).toMatchObject({ revision: previous.revision + 1, stage: "interview", replanning: true, plan_revision: 8 });
    expect(resumed.answers).toEqual(previous.answers);
    expect(resumed.profile.target_school).toBe(previous.profile.target_school);
    expect(resumed.question).not.toBe(FIRST_QUESTION);
    expect(SessionSchema.parse({ ...newSession(), has_plan: undefined, replanning: undefined, plan_revision: undefined }))
      .toMatchObject({ has_plan: false, replanning: false, plan_revision: null });
  });

  it("starts with a freeform learning goal and stops after five answers", async () => {
    expect(newSession().question).toBe(FIRST_QUESTION);
    // 首题只返回具体业务选项；“其他”自定义回答入口由客户端统一提供。
    expect(newSession().question_options).toEqual(["考试备考", "课程学习", "技能提升", "自主学习"]);
    expect(newSession().question_options).not.toContain("其他");
    expect(FIRST_QUESTION_OPTIONS).toEqual(newSession().question_options);
    expect(newSession().profile.goal_type).toBe("other");
    expect(newSession().profile.target_date).toBeNull();
    const session = await fiveAnswers();
    // 第五题之后直接显示第六题，不再进入“信息已记录”暂停页。
    expect(session.stage).toBe("interview");
    expect(session.answers).toHaveLength(5);
    expect(session.question).not.toBe(FIRST_QUESTION);
    expect(session.question).not.toBe("");
    expect(session.profile).toMatchObject({ goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学",
      target_program: "计算机技术", target_date: null });
    expect(session.profile.goal_text).toBe("我要考研");
    expect(session.items).toEqual([]);
    // 没有明确日期时保持未知，不编造考试日期。
    expect(session.recommendations.target_date).toBe("");
    expect(session.recommendations.plan_end_date).toBe("2026-11-13");
    expect(Object.keys(session.recommendations.weekly_minutes)).toHaveLength(7);
  });

  it("offers contextual answer choices only in the matching scene", async () => {
    const first = await answer(newSession(), "考研");
    expect(first.question_options).toContain("本科大三");
    expect(first.question_multiple).toBe(false);
    const schoolName = await answer(first, "本科大三");
    expect(schoolName.profile.target_school).toBe("");
    expect(schoolName.question).toContain("院校");
    const program = await answer(schoolName, "上海交通大学计算机技术专硕");
    expect(program.profile.target_program).toBe("计算机技术");
    expect(program.question).not.toContain("院校");
  });

  it("adapts recommendations to working and full-time study and preserves explicit rest days", async () => {
    const working = await answer(newSession(), "在职考研，2027年，零基础");
    const fullTime = await answer(newSession(), "脱产全职备考，2027年考研");
    expect(working.recommendations.weekly_minutes["1"]).toBe(60);
    expect(fullTime.recommendations.weekly_minutes["1"]).toBe(300);
    expect(working.profile.weekly_minutes["1"]).toBe(0);
    const time = { ...working, question: "你每周哪些天可以学习，每天大约能投入多久？" };
    const explicit = await answer(time, "工作日1.5小时，周末休息");
    expect(explicit.recommendations.weekly_minutes).toEqual({ "0": 0, "1": 90, "2": 90, "3": 90, "4": 90, "5": 90, "6": 0 });
    expect(explicit.profile.weekly_minutes).toEqual(explicit.recommendations.weekly_minutes);
    const rest = await answer({ ...working, question: "每天可用时间是多少？" }, "每天2小时，周三休息，周末3小时");
    expect(rest.recommendations.weekly_minutes).toEqual({ "0": 180, "1": 120, "2": 120, "3": 0, "4": 120, "5": 120, "6": 180 });
  });

  it("estimates the exam day from an explicit year and schedules to the day before a real target date", async () => {
    const future = await answer(newSession(), "2028年考研");
    expect(future.recommendations.target_date).toBe("");
    expect(future.profile.target_date).toBeNull();
    // 目标日期未知但初试年份已知时按往年规律估算：2028 年 12 月倒数第二个周六是 2028-12-23。
    expect(future.recommendations.plan_end_date).toBe("2028-12-22");
    expect(future.recommendations.plan_end_date_reason).toContain("12月倒数第二个周六");
    expect(future.recommendations.plan_end_date_reason).toContain("以官方通知为准");
    const explicit = await answer({ ...future, question: "考试日期是哪一天？" }, "2028年12月25日");
    expect(explicit.profile.target_date).toBe("2028-12-25");
    expect(explicit.profile.target_date_confirmed).toBe(false);
    expect(explicit.recommendations.target_date).toBe("2028-12-25");
    expect(explicit.recommendations.target_date_estimated).toBe(true);
    // 有目标日期时排到目标日期前一天，既不等于目标日期，也不再固定为 28 天。
    expect(explicit.recommendations.plan_end_date).toBe("2028-12-24");
    expect(explicit.recommendations.plan_end_date_reason).toBe("本次排程到目标日期前一天（2028-12-24）。");
  });

  it("schedules to the day before a target date that is inside the default four weeks", async () => {
    const session = await answer(newSession(), "考研，考试日期2026年11月1日");
    expect(session.recommendations.target_date).toBe("2026-11-01");
    expect(session.recommendations.plan_end_date).toBe("2026-10-31");
    expect(session.recommendations.plan_end_date_reason).toBe("本次排程到目标日期前一天（2026-10-31）。");
  });

  it("falls back to the default 28-day cycle when the target date is not in the future", async () => {
    const session = await answer(newSession(), "考研，考试日期2026年10月1日");
    expect(session.recommendations.target_date).toBe("2026-10-01");
    expect(session.recommendations.plan_end_date).toBe("2026-11-13");
    expect(session.recommendations.plan_end_date_reason).toBe("本次规划周期默认为从今天开始的未来28个自然日，首尾均计入，可以随时调整。");
  });

  it("truncates a horizon longer than three years at the hard limit and explains it", async () => {
    const byTarget = await answer(newSession(), "考研，目标日期2032年5月1日");
    // 从 2026-10-17 起 1095 个自然日（首尾均计入）的上限是 2029-10-15。
    expect(byTarget.recommendations.plan_end_date).toBe("2029-10-15");
    expect(byTarget.recommendations.plan_end_date_reason).toContain("超过三年上限");
    expect(byTarget.recommendations.plan_end_date_reason).toContain("到期后再续排");
    const byExam = await answer(newSession(), "2033年考研");
    expect(byExam.recommendations.plan_end_date).toBe("2029-10-15");
    expect(byExam.recommendations.plan_end_date_reason).toContain("超过三年上限");
  });

  it("accepts an explicit no-deadline answer without inventing a target date", async () => {
    const session = await answer(newSession(), "长期阅读中国近现代史，没有固定结束日期");
    expect(session.profile.goal_type).toBe("self_study");
    expect(session.profile.target_date).toBeNull();
    expect(session.recommendations.target_date).toBe("");
    expect(session.recommendations.target_date_reason).toContain("暂不设置");
    expect(session.recommendations.plan_end_date).toBe("2026-11-13");
  });

  it("keeps the 28-day default when the year answer lands on a different question", async () => {
    // 与 onboarding.integration.test.ts 的确认计划用例保持同一回答序列：
    // “2027年”落在专业问题上，不构成初试年份，推荐值仍应是 28 天默认。
    let session = newSession();
    for (const text of ["考研", "上海交通大学", "计算机", "2027年", "高数一轮"]) session = await answer(session, text);
    expect(session.learning_context.timing.exam_year).toBeNull();
    expect(session.recommendations.target_date).toBe("");
    expect(session.recommendations.plan_end_date).toBe("2026-11-13");
  });

  it("generates items directly from the goal and offers tags only as optional grouping", async () => {
    const skillSession = withMinimumAnswers(await answer(newSession(), "从零学习 Python，能独立处理 CSV 并完成简单的数据分析练习"));
    const skill = await confirmConstraints(await advanceOnboarding(skillSession, { type: "continue" }));
    expect(skill.profile.goal_type).toBe("skill");
    expect(skill.stage).toBe("items");
    expect(skill.items.length).toBeGreaterThan(0);
    expect(skill.items.every(item => !item.tag_names?.some(name => /政治|数学/.test(name)))).toBe(true);
    const readingSession = withMinimumAnswers(await answer(newSession(), "每天读一点历史，没有固定截止日期"));
    const reading = await confirmConstraints(await advanceOnboarding(readingSession, { type: "continue" }));
    expect(reading.profile.goal_type).toBe("self_study");
    expect(reading.items.length).toBeGreaterThan(0);
  });

  it("reads legacy saved recommendations and maps the old date field", () => {
    const legacy = SessionSchema.parse({ ...newSession(),
      recommendations: { exam_date: "2027-06-30", exam_date_reason: "旧会话估算", exam_date_estimated: true,
        weekly_minutes: week, weekly_minutes_reason: "旧会话推荐" } });
    expect(legacy.recommendations.target_date).toBe("2027-06-30");
    expect(legacy.recommendations.target_date_reason).toBe("旧会话估算");
    expect(legacy.recommendations.plan_end_date).toBe("");
  });

  it("keeps asking after five answers and advances on an on-topic answer", async () => {
    const session = await fiveAnswers();
    expect(session.stage).toBe("interview");
    const next = await answer(session, "英语比较弱，阅读经常来不及");
    expect(next.stage).toBe("interview");
    expect(next.answers).toHaveLength(6);
    expect(next.learning_context.facts.weakness?.value).toContain("英语比较弱");
    expect(next.question).not.toBe(session.question);
    // 答非所问（在薄弱题下只说了可用时间）不能写成 weakness，只记录真实提供的可用时间。
    const offTopic = await answer(session, "工作日2小时，周末4小时");
    expect(offTopic.learning_context.facts.weakness).toBeUndefined();
    expect(offTopic.learning_context.facts.availability?.value).toContain("工作日2小时");
    expect(offTopic.profile.weekly_minutes["1"]).toBe(120);
    expect(session.answers).toHaveLength(5);
  });

  it("lets the user continue to planning constraints without a course confirmation step", async () => {
    const session = await answer(newSession(), "每天读一点历史");
    const constraints = await advanceOnboarding(session, { type: "continue" });
    expect(constraints.stage).toBe("constraints");
    expect(constraints.answers).toHaveLength(1);
  });

  it("resumes a legacy checkpoint into the current constraints stage", async () => {
    const legacy = { ...(await fiveAnswers()), stage: "checkpoint" as const };
    const restored = sanitizeInterviewSession(legacy);
    expect(restored.stage).toBe("interview");
    expect(restored.answers).toEqual(legacy.answers);
    expect(restored.question).toBe(legacy.question);
    const constraints = await advanceOnboarding(legacy, { type: "continue" });
    expect(constraints.stage).toBe("constraints");
    expect(constraints.answers).toEqual(legacy.answers);
  });

  it("stops adding questions at the limit but lets the user continue", async () => {
    let session = newSession();
    for (let index = 0; index < 50; index++) session = await answer(session, `第${index + 1}个回答`);
    expect(session.answers).toHaveLength(50);
    expect(session.stage).toBe("interview");
    expect(session.question).toBe("");
    expect(session.question_options).toEqual([]);
    await expect(answer(session, "第51个回答")).rejects.toThrow("已达到50题");
    const constraints = await advanceOnboarding(session, { type: "continue" });
    expect(constraints.stage).toBe("constraints");
    expect(constraints.answers).toHaveLength(50);
  });

  it("generates and confirms items directly after capacity confirmation", async () => {
    const constraints = await advanceOnboarding(await fiveAnswers(), { type: "continue" });
    expect(constraints.stage).toBe("constraints");
    const items = await confirmConstraints(constraints);
    expect(items.stage).toBe("items");
    expect(items.end_date).toBe("2026-11-13");
    const schedule = await advanceOnboarding(items, { type: "confirm_items", items: items.items });
    expect(schedule.stage).toBe("schedule");
    const done = await finishPreview(schedule, { start_date: "2026-11-01", end_date: "2027-12-25",
      target_date: "2027-12-25", weekly_minutes: week });
    expect(done.stage).toBe("complete");
    expect(done.profile.plan_start_date).toBe("2026-11-01");
    expect(done.profile.plan_end_date).toBe("2027-12-25");
    expect(done.profile.target_date).toBe("2027-12-25");
    expect(done.items.every(i => i.earliest_date! >= "2026-11-01" && i.deadline === "2027-12-25")).toBe(true);
    expect(done.profile.constraints_text).toContain("我要考研");
  });

  it("allows finishing without any target date", async () => {
    const readingSession = withMinimumAnswers(await answer(newSession(), "每天读一点历史，没有固定截止日期"));
    const session = await advanceOnboarding(readingSession, { type: "continue" });
    const items = await confirmConstraints(session);
    const schedule = await advanceOnboarding(items, { type: "confirm_items", items: items.items });
    const done = await finishPreview(schedule, { start_date: "2026-10-17", end_date: "2026-11-13",
      weekly_minutes: week });
    expect(done.stage).toBe("complete");
    expect(done.profile.target_date).toBeNull();
    expect(done.profile.plan_end_date).toBe("2026-11-13");
    expect(done.items.every(i => i.deadline === "2026-11-13" && i.deadline_kind === "plan_end")).toBe(true);
  });

  it("rejects stage skipping and duplicate item ids while allowing untagged items", async () => {
    await expect(advanceOnboarding(newSession(), { type: "set_constraints", start_date: "2026-10-17", end_date: "2026-11-13", weekly_minutes: week })).rejects.toThrow("当前阶段");
    const constraints = await advanceOnboarding(await fiveAnswers(), { type: "continue" });
    const items = await confirmConstraints(constraints);
    await expect(advanceOnboarding(items, { type: "confirm_items", items: [items.items[0], items.items[0]] })).rejects.toThrow("事项编号重复");
    const untagged = items.items.map(item => ({ ...item, tag_names: [] }));
    expect((await advanceOnboarding(items, { type: "confirm_items", items: untagged })).stage).toBe("schedule");
  });

  it("keeps a real deadline when the target date was initially unknown", async () => {
    const session = { ...(await fiveAnswers()), stage: "schedule" as const,
      items: [{ id: "manual", tag_names: [], title: "自定义截止", description: "", completion_criteria: "",
        estimated_minutes: 60, deadline: "2026-12-31", deadline_kind: "deadline" as const, priority: 2 }] };
    const done = await advanceOnboarding(session, { type: "finish", start_date: "2026-11-01", end_date: "2027-12-25", weekly_minutes: { "1": 120 } });
    expect(done.items[0].deadline).toBe("2026-12-31");
  });
  it("retains a past real deadline outside the new cycle without inventing a contradictory start", async () => {
    const session = { ...newSession(), stage: "schedule" as const,
      items: [{ id: "old", tag_names: [], title: "已过截止但仍保留的事项", description: "", completion_criteria: "",
        estimated_minutes: 60, earliest_date: "2026-10-01", deadline: "2026-10-10", deadline_kind: "deadline" as const, priority: 2 }] };
    const done = await advanceOnboarding(session, { type: "finish", start_date: "2026-10-17", end_date: "2026-11-13", weekly_minutes: week });
    expect(done.items[0].deadline).toBe("2026-10-10");
    expect(done.items[0].earliest_date).toBe("2026-10-01");
  });

  it("extends plan-end items into the next cycle but keeps real deadlines", async () => {
    const session = { ...(await fiveAnswers()), stage: "schedule" as const,
      items: [
        { id: "open", tag_names: [], title: "本期推进", description: "", completion_criteria: "", estimated_minutes: 60,
          deadline: "2026-11-13", deadline_kind: "plan_end" as const, priority: 2 },
        { id: "real", tag_names: [], title: "真实截止", description: "", completion_criteria: "", estimated_minutes: 60,
          deadline: "2026-11-20", deadline_kind: "deadline" as const, priority: 2 },
      ] };
    const done = await advanceOnboarding(session, { type: "finish", start_date: "2026-10-17", end_date: "2026-12-31", weekly_minutes: { "1": 120 } });
    expect(done.items.find(item => item.id === "open")?.deadline).toBe("2026-12-31");
    expect(done.items.find(item => item.id === "real")?.deadline).toBe("2026-11-20");
  });

  it("extends only plan-end items and never rewrites a real deadline", async () => {
    const profile = ProfileSchema.parse({ goal_text: "通用学习", plan_start_date: "2026-10-17", plan_end_date: "2026-11-13" });
    const item = (id: string, deadline: string, kind: "deadline" | "plan_end", extra: Record<string, unknown> = {}) =>
      ({ id, tag_names: [], title: id, description: "", completion_criteria: "", estimated_minutes: 60, deadline, deadline_kind: kind, priority: 2, ...extra });
    const session = { ...newSession(), stage: "schedule" as const, end_date: "2026-11-13", profile,
      items: [
        item("real-at-old-end", "2026-11-13", "deadline"),
        item("boundary", "2026-11-13", "plan_end"),
        item("real-far", "2027-03-01", "deadline"),
      ] };
    const longer = await advanceOnboarding(session, { type: "finish", start_date: "2026-10-17", end_date: "2026-12-31", weekly_minutes: week });
    expect(longer.items.find(row => row.id === "real-at-old-end")?.deadline).toBe("2026-11-13");
    expect(longer.items.find(row => row.id === "boundary")?.deadline).toBe("2026-12-31");
    expect(longer.items.find(row => row.id === "real-far")?.deadline).toBe("2027-03-01");
    const shorter = await advanceOnboarding(session, { type: "finish", start_date: "2026-10-17", end_date: "2026-10-31", weekly_minutes: week });
    expect(shorter.items.find(row => row.id === "real-at-old-end")?.deadline).toBe("2026-11-13");
    expect(shorter.items.find(row => row.id === "boundary")?.deadline).toBe("2026-10-31");
    expect(shorter.items.find(row => row.id === "real-far")?.deadline).toBe("2027-03-01");
  });

  it("keeps a follow-up item that starts after this cycle without scheduling it", async () => {
    const profile = ProfileSchema.parse({ goal_text: "通用学习", plan_start_date: "2026-10-17", plan_end_date: "2026-11-13" });
    const session = { ...newSession(), stage: "schedule" as const, end_date: "2026-11-13", profile,
      items: [{ id: "later", tag_names: [], title: "后续事项", description: "", completion_criteria: "", estimated_minutes: 60,
        earliest_date: "2027-02-01", deadline: "2027-03-01", deadline_kind: "deadline" as const, priority: 2 }] };
    const done = await advanceOnboarding(session, { type: "finish", start_date: "2026-10-17", end_date: "2026-11-13", weekly_minutes: week });
    expect(done.items[0].earliest_date).toBe("2027-02-01");
    expect(done.items[0].deadline).toBe("2027-03-01");
  });

  it("drops an earlier date once the user explicitly cancels the target date", async () => {
    const first = await answer(newSession(), "考研，考试日期2028-12-25");
    expect(first.profile.target_date).toBe("2028-12-25");
    const cancelled = await answer({ ...first, question: "目标日期还要调整吗？" }, "取消目标日期，暂时不设截止日期");
    expect(cancelled.profile.target_date).toBeNull();
    expect(cancelled.profile.target_date_confirmed).toBe(false);
    // 推荐值也不能把旧日期带回来。
    expect(cancelled.recommendations.target_date).toBe("");
    expect(cancelled.recommendations.target_date_estimated).toBe(true);
  });

  it("does not let the model restore a cancelled target date", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [
      { question: FIRST_QUESTION, answer: "考研，考试日期2028-12-25" },
      { question: "目标日期还要调整吗？", answer: "取消目标日期，暂时不设截止日期" },
    ];
    const profile = { ...session.profile, target_date: "2028-12-25", target_date_confirmed: true };
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
      question: "你每周能投入多久？",
      profile,
      recommendations: { target_date: "2028-12-25", plan_end_date: "2026-11-13", weekly_minutes: week },
    }) } }] }));
    const result = await nextInterview(session);
    expect(result.profile.target_date).toBeNull();
    expect(result.profile.target_date_confirmed).toBe(false);
    expect(result.recommendations.target_date).toBe("");
  });

  it("validates actual calendar dates, chronology and available study time", async () => {
    expect(CalendarDateSchema.safeParse("2027-02-30").success).toBe(false);
    expect(ActionSchema.safeParse({ type: "answer", answer: " " }).success).toBe(false);
    const session = { ...(await fiveAnswers()), stage: "schedule" as const };
    const finish = { type: "finish" as const, start_date: "2026-10-17", end_date: "2027-12-25", weekly_minutes: { "1": 120 } };
    await expect(advanceOnboarding(session, { ...finish, start_date: "2026-10-16" })).rejects.toThrow("早于今天");
    await expect(advanceOnboarding(session, { ...finish, end_date: "2026-10-16" })).rejects.toThrow("不能早于");
    await expect(advanceOnboarding(session, { ...finish, weekly_minutes: { "1": 30 } })).rejects.toThrow("机动");
    expect(ActionSchema.safeParse({ type: "finish", start_date: "2026-10-17", end_date: "2026-11-13", target_date: null, weekly_minutes: week }).success).toBe(true);
  });

  it("sends all answers to the AI and uses its next question", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers.push({ question: FIRST_QUESTION, answer: "准备雅思，目标7分" });
    const profile = { ...session.profile, current_progress: "雅思5分" };
    const recommendations = { target_date: "2027-06-30", target_date_reason: "按留学申请准备进度暂定，考试日期待确认", target_date_estimated: true,
      plan_end_date: "2027-06-30", plan_end_date_reason: "本次安排到目标日期",
      weekly_minutes: { "0": 180, "1": 90, "2": 90, "3": 90, "4": 90, "5": 90, "6": 180 }, weekly_minutes_reason: "工作日练习听读，周末集中练习写作和口语" };
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ question: "你的听说读写目前分别是什么水平？", question_options: ["听力较弱", "口语较弱", "阅读较弱", "写作较弱"], question_multiple: true, profile, recommendations }) } }] }));
    const result = await nextInterview(session);
    expect(result.question).toContain("听说读写");
    expect(result.question_options).toEqual(["听力较弱", "口语较弱", "阅读较弱", "写作较弱"]);
    expect(result.question_multiple).toBe(true);
    // AI 建议的“安排到目标日期”必须改成为目标日期前一天，避免默认四周。
    expect(result.recommendations).toEqual({ ...recommendations, plan_end_date: "2027-06-29",
      plan_end_date_reason: "本次排程到目标日期前一天（2027-06-29）。" });
    expect(result.profile.target_date).toBeNull();
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(JSON.parse(request.messages[1].content).answers).toEqual(session.answers);
    expect(request.reasoning_effort).toBe("low");
    expect(request.messages[0].content).toContain("一次只提一道问题");
    expect(request.messages[0].content).toContain("界面自动提供“其他”文字输入");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("accepts a numeric exam_year in learner_updates instead of failing the whole interview turn", async () => {
    // 线上实际失败样本：模型把 learner_updates 里 exam_year 的 value 写成数字 2027，
    // LearnerUpdateSchema 只接受字符串，导致整条 AI 输出被判“格式有误”。
    const session = await fiveAnswers();
    aiConfig.aiApiKey = "key";
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
      question: "你周一、周三的课程分别在什么时间？",      question_type: "text", question_options: null, question_multiple: false,
      profile: { ...session.profile, goal_type: "exam", goal_subtype: "考研" },
      learner_updates: [
        { field: "identity", value: "本科大三", answer_index: 0, quote: "我要考研" },
        { field: "exam_year", value: 2027, answer_index: 0, quote: "我要考研" },
      ],
      subject_updates: [],
      question_fields: ["availability"],
    }) } }] }));
    const result = await nextInterview(session);
    expect(result.question.length).toBeGreaterThan(0);
    // 校验通过就不会走安全模板兜底，也不会写 ai_schema_invalid 日志。
    expect(errorSpy).not.toHaveBeenCalled();
    errorSpy.mockRestore();
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(request.messages[0].content).toContain("value 一律用字符串");
  });

  it("degrades to the safe question when the model output still violates the schema", async () => {
    const session = await fiveAnswers();
    aiConfig.aiApiKey = "key";
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
      question: "",
      profile: { goal_type: "invalid_goal_type" },
      learner_updates: [{ field: "unknown_field", value: { nested: true }, answer_index: -1, quote: "" }],
      recommendations: null,
      question_options: null,
    }) } }] }));
    const result = await nextInterview(session);
    // 不再把 ZodError 抛给路由；用户看到的是可继续回答的安全问题，进度不丢。
    expect(result.question.length).toBeGreaterThan(0);
    expect(result.profile.goal_type).toBe("exam");
    expect(result.question_options.length).toBeLessThanOrEqual(8);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    // 宽松数组会先记录被丢弃的 learner_updates，schema 失败日志可能不是第一行。
    const lines = errorSpy.mock.calls.map(call => String(call[0]));
    expect(lines.some(line => line.includes('"ai_schema_invalid"'))).toBe(true);
    errorSpy.mockRestore();
  });

  it("keeps the model's question when the user wrote the exam level as 6级", async () => {
    const session = await answer(newSession(), "12 月份要考 6 级，这次 6 级我要刷到 580 分，还要保研");
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
      question: "你目前六级是什么水平？上次考试总分大概多少？",
      question_type: "text", question_options: [], question_multiple: false,
      profile: { ...session.profile, goal_type: "exam", goal_subtype: "四六级" },
      recommendations: null,
    }) } }] }));
    const result = await nextInterview(session);
    // 关键：用户写“6 级”、模型说“六级”，不能因为归一差异退回安全模板。
    expect(result.question).toBe("你目前六级是什么水平？上次考试总分大概多少？");
    expect(result.profile.goal_type).toBe("exam");
    expect(result.profile.goal_subtype).toBe("四六级");
  });

  it("drops invalid learner_updates entries instead of degrading the whole turn", async () => {
    const session = await answer(newSession(), "12 月份要考 6 级，这次 6 级我要刷到 580 分，还要保研");
    aiConfig.aiApiKey = "key";
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
      question: "你目前六级是什么水平？上次考试总分大概多少？",
      profile: { ...session.profile, goal_type: "exam", goal_subtype: "四六级" },
      recommendations: null,
      learner_updates: [
        // 线上实际样本：模型把资料字段名当成 learner field 输出。
        { field: "goal_text", value: "12 月份要考 6 级", answer_index: 0, quote: "12 月份要考 6 级" },
        { field: "goal_subtype", value: "四六级", answer_index: 0, quote: "6 级" },
        { field: "outcome", value: "580", answer_index: 0, quote: "这次 6 级我要刷到 580 分" },
      ],
    }) } }] }));
    const result = await nextInterview(session);
    expect(result.question).toBe("你目前六级是什么水平？上次考试总分大概多少？");
    // 合规的那条仍然生效；两条非法条目被丢弃，并留下可定位的服务端日志。
    expect(result.learning_context.facts.outcome?.value).toBe("580");
    const lines = errorSpy.mock.calls.map(call => String(call[0]));
    expect(lines.some(line => line.includes('"ai_updates_dropped"'))).toBe(true);
    expect(lines.some(line => line.includes('"ai_schema_invalid"'))).toBe(false);
    errorSpy.mockRestore();
  });

  it("lets the model re-ask an already-recorded field after the user sends an off-topic question", async () => {
    const session = await answer(newSession(), "12 月份要考 6 级，这次 6 级我要刷到 580 分");
    session.profile = { ...session.profile, goal_type: "exam", goal_subtype: "四六级" };
    session.answers.push({ question: "你最近一次六级考了多少分？", answer: "六级上次考了 530", fields: ["baseline"] });
    session.answers.push({ question: "你觉得哪部分最薄弱？", answer: "你是什么 AI", fields: ["weakness"] });
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
      question: "我是负责目标访谈的助手。回到刚才的问题：你最近一次六级考了多少分？",
      profile: { ...session.profile },
      recommendations: null,
      question_fields: ["baseline"],
    }) } }] }));
    const result = await nextInterview(session);
    // baseline 已经记录，但上一轮用户发的是提问；AI 回应提问后再追问同一题是合理的，不应退回模板。
    expect(result.question).toBe("我是负责目标访谈的助手。回到刚才的问题：你最近一次六级考了多少分？");
  });

  it("falls back to a safe question when the model returns malformed JSON", async () => {
    const session = await answer(newSession(), "12 月份要考 6 级，这次 6 级我要刷到 580 分");
    aiConfig.aiApiKey = "key";
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    fetchMock.mockResolvedValue(Response.json({ choices: [{ finish_reason: "length",
      message: { content: '{"question":"你目前六级是什么水平？","profile":' } }] }));
    const result = await nextInterview(session);
    // 不把英文 JSON 解析错误抛给路由/用户，访谈用安全模板继续。
    expect(result.question.length).toBeGreaterThan(0);
    expect(result.question).not.toContain("你目前六级");
    const lines = errorSpy.mock.calls.map(call => String(call[0]));
    expect(lines.some(line => line.includes('"ai_json_invalid"'))).toBe(true);
    errorSpy.mockRestore();
  });

  it("normalizes null dates and null option lists from model output", () => {
    expect(QuestionOptionsSchema.parse(null)).toEqual([]);
    expect(RecommendationsSchema.parse({ target_date: null, plan_end_date: null })).toMatchObject({ target_date: "", plan_end_date: "" });
  });

  it("keeps user-provided dates and time over conflicting AI suggestions", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "考研，考试日期2028-12-25，每天1小时" }];
    const profile = { ...session.profile, goal_type: "exam" as const, goal_subtype: "考研", target_date: "2029-12-20",
      weekly_minutes: { "0": 300, "1": 300, "2": 300, "3": 300, "4": 300, "5": 300, "6": 300 } };
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ question: "你的准备情况如何？", profile,
      question_options: ["零基础", "已开始"], recommendations: { target_date: "2029-12-20", plan_end_date: "2029-12-20", weekly_minutes: profile.weekly_minutes } }) } }] }));
    const result = await nextInterview(session);
    expect(result.profile.target_date).toBe("2028-12-25");
    expect(result.recommendations.target_date).toBe("2028-12-25");
    expect(result.recommendations.target_date_estimated).toBe(true);
    // 用户明确给出的目标日期同样决定规划结束日期：排到目标日期前一天，覆盖 AI 的建议。
    expect(result.recommendations.plan_end_date).toBe("2028-12-24");
    expect(result.recommendations.plan_end_date_reason).toBe("本次排程到目标日期前一天（2028-12-24）。");
    expect(Object.values(result.recommendations.weekly_minutes)).toEqual(Array(7).fill(60));
  });

  it("overrides an AI four-week plan end with the estimated exam horizon", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "2028年考研" }];
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({
      question: "你目前是大几？", question_options: ["本科大三", "已毕业，正在备考"], profile: session.profile,
      recommendations: { target_date: "", plan_end_date: "2026-11-13", plan_end_date_reason: "默认四周", weekly_minutes: week },
    }) } }] }));
    const result = await nextInterview(session);
    expect(result.recommendations.target_date).toBe("");
    // 只有初试年份时不能沿用 AI 的四周默认，要一次性排到估算初试日的前一天。
    expect(result.recommendations.plan_end_date).toBe("2028-12-22");
    expect(result.recommendations.plan_end_date_reason).toContain("12月倒数第二个周六");
    expect(result.recommendations.plan_end_date_reason).toContain("以官方通知为准");
  });

  it("deduplicates AI choices and reserves Other for the client's custom input", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "学习英语" }];
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ question: "目前基础如何？", profile: session.profile,
      question_options: ["零基础", "零基础", " 已开始 ", "其他", "其它", "Other", "其他（自填）", "其他语言课程", " other(自填) "] }) } }] }));
    const result = await nextInterview(session);
    // 只移除通用自填占位项；“其他语言课程”是有具体含义的业务选项，必须保留。
    expect(result.question_options).toEqual(["零基础", "已开始", "其他语言课程"]);
    expect(result.question_options.filter(option => /^其他$/i.test(option))).toHaveLength(0);
    expect(Object.keys(result.recommendations.weekly_minutes)).toHaveLength(7);
  });

  it("normalizes saved session options so legacy duplicates cannot add a second Other entry", () => {
    const legacy = SessionSchema.parse({ ...newSession(), question_options: [
      " 考试备考 ", "", "考试备考", "其他", "其它", "Other", "其他（自填）", "其他语言课程", "课程学习",
    ] });
    expect(legacy.question_options).toEqual(["考试备考", "其他语言课程", "课程学习"]);
    expect(legacy.question_options.filter(option => option === "其他")).toHaveLength(0);
    // 没有选项的旧题目继续表示自由文字回答。
    expect(SessionSchema.parse({ ...newSession(), question_options: [] }).question_options).toEqual([]);
    expect(QuestionOptionsSchema.parse(["其他", "  ", "Other（自填）"])).toEqual([]);
    expect(QuestionOptionsSchema.parse(["其他语言课程", "其他语言课程", " 二外 "])).toEqual(["其他语言课程", "二外"]);
  });

  it("normalizes the fallback template options without removing business options", async () => {
    // 无 AI 时的基础模板同样经过归一化，不会夹带“其他”入口。
    const first = await answer(newSession(), "考研");
    expect(first.question_options.length).toBeGreaterThan(0);
    expect(first.question_options).not.toContain("其他");
    expect(normalizeQuestionOptions(["其他语言课程", "其他", "Other"])).toEqual(["其他语言课程"]);
  });

  it("backfills recommendations for a legacy items draft without another interview question", async () => {
    const session = await fiveAnswers();
    session.stage = "items";
    session.items = [{ id: "math-1", tag_names: [], title: "基础复习", description: "", completion_criteria: "",
      estimated_minutes: 60, deadline: "2026-11-13", deadline_kind: "plan_end", priority: 2 }];
    session.recommendations = SessionSchema.parse({ ...session, recommendations: undefined }).recommendations;
    const recommendations = { target_date: "2027-12-20", target_date_reason: "依据2027年目标估算，官方日期待公布", target_date_estimated: true,
      plan_end_date: "2027-12-20", plan_end_date_reason: "本次安排到目标日期",
      weekly_minutes: { "0": 180, "1": 90, "2": 90, "3": 90, "4": 90, "5": 90, "6": 180 }, weekly_minutes_reason: "先建立每日复习节奏" };
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ recommendations }) } }] }));
    const schedule = await advanceOnboarding(session, { type: "confirm_items", items: session.items });
    expect(schedule.stage).toBe("schedule");
    expect(schedule.recommendations.plan_end_date).toBe("2027-12-19");
    expect(schedule.recommendations.plan_end_date_reason).toBe("本次排程到目标日期前一天（2027-12-19）。");
    // 日程阶段的初始结束日期随推荐值一次性排到目标日期前一天。
    expect(schedule.end_date).toBe("2027-12-19");
    expect(schedule.answers).toEqual(session.answers);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(request.messages[0].content).toContain("不要继续提问");
    expect(request.reasoning_effort).toBe("low");
  });

  it("provides AI item generation the plan cycle rather than an unrelated default", async () => {
    const session = await fiveAnswers();
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ items: [{ id: "math-1", tag_names: ["高数"], title: "基础复习", estimated_minutes: 60, deadline: "2026-11-13", deadline_kind: "plan_end" }], summary: "", assumptions: [], warnings: [] }) } }] }));
    await generateItems(session);
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(JSON.parse(request.messages[1].content).plan_end_date).toBe("2026-11-13");
    expect(JSON.parse(request.messages[1].content).target_date).toBe("");
    expect(request.reasoning_effort).toBe("high");
  });

  it("includes current manual edits in conversational item revisions and accepts tag names", async () => {
    const session: OnboardingSession = { ...await fiveAnswers(), stage: "items", items: [{ id: "manual", tag_names: ["手动标签"],
      title: "手动事项", description: "自定义范围", completion_criteria: "", estimated_minutes: 60,
      deadline: "2026-11-13", deadline_kind: "plan_end", priority: 1 }] };
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ items: [{ ...session.items[0], title: "修改后", tag_names: ["新标签"] }], summary: "修改后", assumptions: [], warnings: [] }) } }] }));
    await generateItems(session, "保留手动事项");
    expect(JSON.parse(JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).messages[1].content).items[0].tag_names).toEqual(["手动标签"]);
    expect(JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).reasoning_effort).toBe("high");
  });

  it("preserves progress on AI errors and clearly reports unavailable chat editing", async () => {
    const session = await fiveAnswers();
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(new Response(null, { status: 503 }));
    const constraints = await advanceOnboarding(session, { type: "continue" });
    await expect(confirmConstraints(constraints)).rejects.toThrow("503");
    expect(session.stage).toBe("interview");
  });

  it("retains the constraints draft after an AI timeout and allows the same submission to be retried", async () => {
    const session: OnboardingSession = { ...newSession(), stage: "constraints" };
    const before = structuredClone(session);
    aiConfig.aiApiKey = "key";
    fetchMock.mockRejectedValueOnce(new DOMException("The operation was aborted due to timeout", "TimeoutError"));

    await expect(confirmConstraints(session)).rejects.toThrow("已有进度已保留，请重试");
    expect(session).toEqual(before);

    fetchMock.mockResolvedValueOnce(Response.json({ choices: [{ message: { content: JSON.stringify({
      items: [{ id: "math-1", tag_names: ["高数"], title: "极限练习", estimated_minutes: 60,
        deadline: "2026-11-13", deadline_kind: "plan_end" }], summary: "", assumptions: [], warnings: [],
    }) } }] }));
    const retried = await confirmConstraints(session);
    expect(retried).toMatchObject({ stage: "items", revision: before.revision + 1, constraints_confirmed: true });
    expect(retried.items).toHaveLength(1);
    expect(session).toEqual(before);
  });
});

describe("full-period onboarding (one model response, flexible capacity)", () => {
  const week120 = { "0": 120, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 120 };
  const cycle = { start_date: "2026-10-17", end_date: "2026-11-13" };
  const scheduleSession = (planning: OnboardingSession["planning"] = null): OnboardingSession => ({
    ...newSession(), stage: "schedule",
    start_date: cycle.start_date, end_date: cycle.end_date,
    profile: ProfileSchema.parse({ goal_text: "线性代数复习", plan_start_date: cycle.start_date, plan_end_date: cycle.end_date }),
    recommendations: { ...newSession().recommendations, plan_end_date: cycle.end_date, weekly_minutes: week120 },
    items: [{ id: "math-1", tag_names: ["线性代数"], title: "矩阵章节", description: "", completion_criteria: "",
      estimated_minutes: 120, earliest_date: cycle.start_date, deadline: cycle.end_date,
      deadline_kind: "plan_end", priority: 2,
      planning: { workload: { components: [{ id: "unit", label: "章", quantity: 2, unit: "章", minutes_per_unit: 60 }],
        source: "估算", confidence: "low", calibration: "记录本次速度" }, activity: { kind: "finite" }, dependencies: [] } }],
    planning,
  });

  it("generates the whole cycle with exactly one model response and ignores the model's rolling flag", async () => {
    const session: OnboardingSession = { ...newSession(), stage: "constraints",
      recommendations: { ...newSession().recommendations, weekly_minutes: week120, plan_end_date: cycle.end_date } };
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValueOnce(Response.json({ choices: [{ message: { content: JSON.stringify({
      items: [{ id: "math-1", tag_names: ["线性代数"], title: "矩阵章节", description: "矩阵运算", completion_criteria: "完成练习",
        estimated_minutes: 120, earliest_date: cycle.start_date, deadline: cycle.end_date, deadline_kind: "plan_end", priority: 2,
        planning: { workload: { components: [{ id: "unit", label: "章", quantity: 2, unit: "章", minutes_per_unit: 60 }],
          source: "估算", confidence: "low", calibration: "记录速度" }, activity: { kind: "finite" }, dependencies: [] } }],
      planning: { version: 1, prompt_version: "model", rules_version: "model", rolling: true, detail_days: 14,
        route: [{ id: "route", title: "完整周期路线", item_ids: ["math-1"], outcome: "完成矩阵", check: "练习通过" }],
        milestones: [], assumptions: ["模型给出的全周期假设"], risks: [], uncovered: [] },
      summary: "", assumptions: [], warnings: [] }) } }] }));

    const items = await advanceOnboarding(session, { type: "set_constraints", ...cycle, weekly_minutes: week120 });
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(items.stage).toBe("items");
    // Full mode is decided server-side from the action, not from the model's rolling flag.
    expect(items.planning).toMatchObject({ mode: "full", rolling: false, detail_days: 28,
      detailed_until: cycle.end_date, forecast: null });
    expect(items.planning!.assumptions).toContain("模型给出的全周期假设");
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    // Per-session planning notes live in the user payload so the system prefix stays cacheable.
    const input = JSON.parse(request.messages[1].content);
    expect(input.planning_instructions.horizon).toContain("全周期一次性生成");
    expect(request.messages[0].content).not.toContain("全周期一次性生成");
    expect(input).toMatchObject({ plan_mode: "full", plan_horizon_days: 28 });
    expect(input.capacity.basis).toBe("gross_buffer");

    const schedule = await advanceOnboarding(items, { type: "confirm_items", items: items.items });
    expect(schedule.stage).toBe("schedule");
    const preview = await advanceOnboarding(schedule, { type: "preview_schedule", ...cycle, weekly_minutes: week120 });
    // No repair was needed, so the normal path stayed at one planning model call.
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(preview.preview!.status).toBe("ready");
    expect(preview.preview!.mode).toBe("full");
    expect(preview.preview!.detailed_until).toBe(cycle.end_date);
    expect(preview.preview!.forecast_minutes).toBe(0);
    const done = await advanceOnboarding(preview, { type: "finish", ...cycle, weekly_minutes: week120,
      preview_token: preview.preview!.token as string });
    expect(done.stage).toBe("complete");
    expect(done.planning).toMatchObject({ mode: "full", rolling: false, detailed_until: cycle.end_date, forecast: null });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("keeps generating the full cycle when materials and speed are unknown (fallback estimates stay visible)", async () => {
    const session: OnboardingSession = { ...newSession(), stage: "constraints",
      recommendations: { ...newSession().recommendations, weekly_minutes: week120, plan_end_date: cycle.end_date } };
    const items = await advanceOnboarding(session, { type: "set_constraints", ...cycle, weekly_minutes: week120 });
    expect(items.stage).toBe("items");
    expect(items.planning!.mode).toBe("full");
    expect(items.planning!.detail_days).toBe(28);
    expect(items.items.length).toBeGreaterThan(0);
    expect(items.items.every(item => item.planning?.workload?.confidence === "low")).toBe(true);
    expect(items.items.every(item => Boolean(item.planning?.workload?.calibration))).toBe(true);
    const schedule = await advanceOnboarding(items, { type: "confirm_items", items: items.items });
    const preview = await advanceOnboarding(schedule, { type: "preview_schedule", ...cycle, weekly_minutes: week120 });
    expect(preview.preview!.mode).toBe("full");
    expect(preview.preview!.detailed_until).toBe(cycle.end_date);
    expect((preview.preview as { capacity: { weeks: Array<{ monday: string }> } }).capacity.weeks.at(-1)!.monday).toBe("2026-11-09");
    const done = await advanceOnboarding(preview, { type: "finish", ...cycle, weekly_minutes: week120,
      preview_token: preview.preview!.token as string });
    expect(done.stage).toBe("complete");
    expect(done.planning).toMatchObject({ mode: "full", detailed_until: cycle.end_date, forecast: null });
  });

  it("accepts a net plan with only a weekly baseline/range and no detail_days, while old payloads still work", async () => {
    expect(ActionSchema.safeParse({ type: "finish", ...cycle, weekly_minutes: week120 }).success).toBe(true);
    const netAction = { type: "finish" as const, ...cycle, capacity_basis: "net" as const,
      weekly_baseline_minutes: 210, weekly_range_min_minutes: 150, weekly_range_max_minutes: 300,
      week_capacity_overrides: { "2026-10-19": { total_minutes: 120 } },
      date_capacity_overrides: { "2026-10-18": 0 } };
    expect(ActionSchema.safeParse(netAction).success).toBe(true);
    const prepared = await advanceOnboarding(scheduleSession(), netAction);
    expect(prepared.stage).toBe("complete");
    expect(prepared.profile.capacity_basis).toBe("net");
    expect(prepared.profile.weekly_baseline_minutes).toBe(210);
    expect(prepared.profile.weekly_range_min_minutes).toBe(150);
    expect(prepared.profile.week_capacity_overrides).toEqual({ "2026-10-19": { total_minutes: 120 } });
    expect(prepared.profile.date_capacity_overrides).toEqual({ "2026-10-18": 0 });
    const built = buildPlanningDocument(prepared);
    expect(built.document.profile.capacity_basis).toBe("net");
    expect(built.document.profile.weekly_baseline_minutes).toBe(210);
    // The user confirmed no daily template, so the program distributes the weekly baseline instead
    // of persisting an all-zero template as if the user had confirmed every day.
    expect(built.document.profile.weekly_minutes).toBeUndefined();
    expect(built.document.blocks.length).toBeGreaterThan(0);
    expect(built.document.planning!.mode).toBe("full");
  });

  it("rejects invalid week/date override keys and inverted capacity ranges", async () => {
    const base = { type: "finish" as const, ...cycle, capacity_basis: "net" as const, weekly_baseline_minutes: 210 };
    await expect(advanceOnboarding(scheduleSession(), { ...base,
      week_capacity_overrides: { "2026-10-20": { total_minutes: 60 } } })).rejects.toThrow("周一");
    await expect(advanceOnboarding(scheduleSession(), { ...base,
      date_capacity_overrides: { "2026-02-30": 30 } })).rejects.toThrow("有效日期");
    await expect(advanceOnboarding(scheduleSession(), { ...base,
      weekly_range_min_minutes: 300, weekly_range_max_minutes: 100 })).rejects.toThrow("最小值不能大于最大值");
    await expect(advanceOnboarding(scheduleSession(), { ...base,
      weekly_range_max_minutes: 100 })).rejects.toThrow("不能高于");
  });

  it("keeps an inherited rolling plan rolling unless the caller explicitly upgrades it", async () => {
    const rolling: OnboardingSession["planning"] = { ...newPlanning(), mode: "rolling", rolling: true, detail_days: 14 };
    const preview = await advanceOnboarding(scheduleSession(rolling), { type: "preview_schedule", ...cycle, weekly_minutes: week120 });
    expect(preview.planning).toMatchObject({ mode: "rolling", rolling: true, detail_days: 14,
      detailed_until: "2026-10-30" });
    expect(preview.preview!.mode).toBe("rolling");
    expect(preview.planning!.forecast).toMatchObject({ from: "2026-10-31", to: cycle.end_date });
    const done = await advanceOnboarding(preview, { type: "finish", ...cycle, weekly_minutes: week120,
      preview_token: preview.preview!.token as string });
    expect(done.planning).toMatchObject({ mode: "rolling", rolling: true, detail_days: 14 });
    // An explicit upgrade request switches the same draft to full-cycle coverage.
    const upgraded = await advanceOnboarding(scheduleSession(rolling), { type: "preview_schedule", ...cycle,
      weekly_minutes: week120, mode: "full" });
    expect(upgraded.planning).toMatchObject({ mode: "full", rolling: false, detail_days: 28,
      detailed_until: cycle.end_date, forecast: null });
  });
});
