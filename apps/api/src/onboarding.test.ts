import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ProfileSchema } from "./contracts.js";
import { ActionSchema, CalendarDateSchema, FIRST_QUESTION, FIRST_QUESTION_OPTIONS, newSession, SessionSchema, type OnboardingSession } from "./onboarding-contracts.js";
import { advanceOnboarding } from "./onboarding.js";
import { generateCourses, generateItems, nextInterview } from "./onboarding-ai.js";

const aiConfig = vi.hoisted(() => ({ aiApiKey: "", aiBaseUrl: "https://ai.invalid", aiModel: "test", aiReasoningEffort: "max" }));
vi.mock("./config.js", () => ({ config: aiConfig }));
const fetchMock = vi.fn<typeof fetch>();
const answer = (session: OnboardingSession, text: string) => advanceOnboarding(session, { type: "answer", answer: text });
async function fiveAnswers() {
  let session = newSession();
  for (const text of ["我要考研", "上海交通大学", "计算机技术", "高数刚开始，英语词汇学了一半", "英语词汇背完了，高数还没开始"]) session = await answer(session, text);
  return session;
}
const week = { "0": 120, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 120 };

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
    expect(newSession().question_options).toEqual(FIRST_QUESTION_OPTIONS);
    expect(newSession().profile.goal_type).toBe("other");
    expect(newSession().profile.target_date).toBeNull();
    const session = await fiveAnswers();
    expect(session.stage).toBe("checkpoint");
    expect(session.answers).toHaveLength(5);
    expect(session.profile).toMatchObject({ goal_type: "exam", goal_subtype: "考研", target_school: "上海交通大学",
      target_program: "计算机技术", target_date: null });
    expect(session.profile.goal_text).toBe("我要考研");
    expect(session.courses).toEqual([]);
    expect(session.items).toEqual([]);
    // 没有明确日期时保持未知，不编造考试日期。
    expect(session.recommendations.target_date).toBe("");
    expect(session.recommendations.plan_end_date).toBe("2026-11-13");
    expect(Object.keys(session.recommendations.weekly_minutes)).toHaveLength(7);
  });

  it("offers contextual answer choices only in the matching scene", async () => {
    const first = await answer(newSession(), "考研");
    expect(first.question_options).toContain("已确定目标院校");
    expect(first.question_multiple).toBe(false);
    const schoolName = await answer(first, "已确定目标院校");
    expect(schoolName.profile.target_school).toBe("");
    expect(schoolName.question).toContain("专业");
    const program = await answer(schoolName, "计算机技术");
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

  it("keeps an unknown target date unknown and uses explicit dates when given", async () => {
    const future = await answer(newSession(), "2028年考研");
    expect(future.recommendations.target_date).toBe("");
    expect(future.profile.target_date).toBeNull();
    expect(future.recommendations.plan_end_date).toBe("2026-11-13");
    const explicit = await answer({ ...future, question: "考试日期是哪一天？" }, "2028年12月25日");
    expect(explicit.profile.target_date).toBe("2028-12-25");
    expect(explicit.profile.target_date_confirmed).toBe(false);
    expect(explicit.recommendations.target_date).toBe("2028-12-25");
    expect(explicit.recommendations.target_date_estimated).toBe(true);
  });

  it("accepts an explicit no-deadline answer without inventing a target date", async () => {
    const session = await answer(newSession(), "长期阅读中国近现代史，没有固定结束日期");
    expect(session.profile.goal_type).toBe("self_study");
    expect(session.profile.target_date).toBeNull();
    expect(session.recommendations.target_date).toBe("");
    expect(session.recommendations.target_date_reason).toContain("暂不设置");
    expect(session.recommendations.plan_end_date).toBe("2026-11-13");
  });

  it("builds fallback courses from the real goal instead of exam subjects", async () => {
    const skillSession = { ...(await answer(newSession(), "从零学习 Python，能独立处理 CSV 并完成简单的数据分析练习")), stage: "checkpoint" as const };
    const skill = await advanceOnboarding(skillSession, { type: "generate_courses" });
    expect(skill.profile.goal_type).toBe("skill");
    expect(skill.courses.map(course => course.name)).toEqual(["数据分析基础", "数据分析练习", "数据分析实践"]);
    expect(skill.courses.some(course => /政治|数学/.test(course.name))).toBe(false);
    const readingSession = { ...(await answer(newSession(), "每天读一点历史，没有固定截止日期")), stage: "checkpoint" as const };
    const reading = await advanceOnboarding(readingSession, { type: "generate_courses" });
    expect(reading.profile.goal_type).toBe("self_study");
    expect(reading.courses.map(course => course.name)).toEqual(["历史阅读与记录", "历史专题整理"]);
  });

  it("reads legacy saved recommendations and maps the old date field", () => {
    const legacy = SessionSchema.parse({ ...newSession(),
      recommendations: { exam_date: "2027-06-30", exam_date_reason: "旧会话估算", exam_date_estimated: true,
        weekly_minutes: week, weekly_minutes_reason: "旧会话推荐" } });
    expect(legacy.recommendations.target_date).toBe("2027-06-30");
    expect(legacy.recommendations.target_date_reason).toBe("旧会话估算");
    expect(legacy.recommendations.plan_end_date).toBe("");
  });

  it("asks one follow-up and returns to the choice after each additional answer", async () => {
    const session = await fiveAnswers();
    const continued = await advanceOnboarding(session, { type: "continue" });
    expect(continued.stage).toBe("interview");
    const next = await answer(continued, "工作日2小时，周末4小时");
    expect(next.stage).toBe("checkpoint");
    expect(next.answers).toHaveLength(6);
    expect(next.profile.weekly_minutes["1"]).toBe(120);
    expect(session.answers).toHaveLength(5);
  });

  it("keeps courses and items behind separate confirmations and finishes a finite cycle", async () => {
    const courses = await advanceOnboarding(await fiveAnswers(), { type: "generate_courses" });
    expect(courses.stage).toBe("courses");
    expect(courses.items).toEqual([]);
    const custom = [{ id: "custom", name: "计算机组成原理", description: "408", priority: 3 }];
    const items = await advanceOnboarding(courses, { type: "confirm_courses", courses: custom });
    expect(items.stage).toBe("items");
    expect(items.courses).toEqual(custom);
    expect(items.items.every(i => i.course_id === "custom")).toBe(true);
    expect(items.end_date).toBe("2026-11-13");
    const schedule = await advanceOnboarding(items, { type: "confirm_items", items: items.items });
    expect(schedule.stage).toBe("schedule");
    const done = await advanceOnboarding(schedule, { type: "finish", start_date: "2026-11-01", end_date: "2027-12-25",
      target_date: "2027-12-25", weekly_minutes: { "0": 120 } });
    expect(done.stage).toBe("complete");
    expect(done.profile.plan_start_date).toBe("2026-11-01");
    expect(done.profile.plan_end_date).toBe("2027-12-25");
    expect(done.profile.target_date).toBe("2027-12-25");
    expect(done.items.every(i => i.earliest_date! >= "2026-11-01" && i.deadline === "2027-12-25")).toBe(true);
    expect(done.profile.constraints_text).toContain("我要考研");
  });

  it("allows finishing without any target date", async () => {
    const readingSession = { ...(await answer(newSession(), "每天读一点历史，没有固定截止日期")), stage: "checkpoint" as const };
    const session = await advanceOnboarding(readingSession, { type: "generate_courses" });
    const items = await advanceOnboarding(session, { type: "confirm_courses", courses: session.courses });
    const schedule = await advanceOnboarding(items, { type: "confirm_items", items: items.items });
    const done = await advanceOnboarding(schedule, { type: "finish", start_date: "2026-10-17", end_date: "2026-11-13",
      weekly_minutes: week });
    expect(done.stage).toBe("complete");
    expect(done.profile.target_date).toBeNull();
    expect(done.profile.plan_end_date).toBe("2026-11-13");
    expect(done.items.every(i => i.deadline === "2026-11-13" && i.deadline_kind === "plan_end")).toBe(true);
  });

  it("rejects stage skipping, orphan items and duplicate course ids", async () => {
    await expect(advanceOnboarding(newSession(), { type: "generate_courses" })).rejects.toThrow("当前阶段");
    const session = await advanceOnboarding(await fiveAnswers(), { type: "generate_courses" });
    await expect(advanceOnboarding(session, { type: "confirm_courses", courses: [session.courses[0], session.courses[0]] })).rejects.toThrow("重复");
    const items = await advanceOnboarding(session, { type: "confirm_courses", courses: session.courses });
    await expect(advanceOnboarding(items, { type: "confirm_items", items: [{ ...items.items[0], course_id: "missing" }] })).rejects.toThrow("已确认的课程");
    await expect(advanceOnboarding(items, { type: "confirm_items", items: [items.items[0]] })).rejects.toThrow("每门课程");
  });

  it("keeps a real deadline when the target date was initially unknown", async () => {
    const session = { ...(await fiveAnswers()), stage: "schedule" as const,
      items: [{ id: "manual", course_id: "math", title: "自定义截止", description: "", completion_criteria: "",
        estimated_minutes: 60, deadline: "2026-12-31", deadline_kind: "deadline" as const, priority: 2 }] };
    const done = await advanceOnboarding(session, { type: "finish", start_date: "2026-11-01", end_date: "2027-12-25", weekly_minutes: { "1": 120 } });
    expect(done.items[0].deadline).toBe("2026-12-31");
  });

  it("extends plan-end items into the next cycle but keeps real deadlines", async () => {
    const session = { ...(await fiveAnswers()), stage: "schedule" as const,
      items: [
        { id: "open", course_id: "math", title: "本期推进", description: "", completion_criteria: "", estimated_minutes: 60,
          deadline: "2026-11-13", deadline_kind: "plan_end" as const, priority: 2 },
        { id: "real", course_id: "math", title: "真实截止", description: "", completion_criteria: "", estimated_minutes: 60,
          deadline: "2026-11-20", deadline_kind: "deadline" as const, priority: 2 },
      ] };
    const done = await advanceOnboarding(session, { type: "finish", start_date: "2026-10-17", end_date: "2026-12-31", weekly_minutes: { "1": 120 } });
    expect(done.items.find(item => item.id === "open")?.deadline).toBe("2026-12-31");
    expect(done.items.find(item => item.id === "real")?.deadline).toBe("2026-11-20");
  });

  it("extends only plan-end items and never rewrites a real deadline", async () => {
    const profile = ProfileSchema.parse({ goal_text: "通用学习", plan_start_date: "2026-10-17", plan_end_date: "2026-11-13" });
    const item = (id: string, deadline: string, kind: "deadline" | "plan_end", extra: Record<string, unknown> = {}) =>
      ({ id, course_id: "c", title: id, description: "", completion_criteria: "", estimated_minutes: 60, deadline, deadline_kind: kind, priority: 2, ...extra });
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
      items: [{ id: "later", course_id: "c", title: "后续事项", description: "", completion_criteria: "", estimated_minutes: 60,
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
    expect(result.recommendations).toEqual(recommendations);
    expect(result.profile.target_date).toBeNull();
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(JSON.parse(request.messages[1].content).answers).toEqual(session.answers);
    expect(request.messages[0].content).toContain("一次只提一道问题");
    expect(request.messages[0].content).toContain("界面自动提供“其他”文字输入");
    expect(fetchMock).toHaveBeenCalledTimes(1);
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
    expect(Object.values(result.recommendations.weekly_minutes)).toEqual(Array(7).fill(60));
  });

  it("deduplicates AI choices and reserves Other for the client's custom input", async () => {
    aiConfig.aiApiKey = "key";
    const session = newSession();
    session.answers = [{ question: FIRST_QUESTION, answer: "学习英语" }];
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ question: "目前基础如何？", profile: session.profile,
      question_options: ["零基础", "零基础", " 已开始 ", "其他", "其他（自填）", "Other"] }) } }] }));
    const result = await nextInterview(session);
    expect(result.question_options).toEqual(["零基础", "已开始"]);
    expect(Object.keys(result.recommendations.weekly_minutes)).toHaveLength(7);
  });

  it("backfills recommendations for a legacy items draft without another interview question", async () => {
    const session = await fiveAnswers();
    session.stage = "items";
    session.courses = [{ id: "math", name: "高数", description: "", priority: 2 }];
    session.items = [{ id: "math-1", course_id: "math", title: "基础复习", description: "", completion_criteria: "",
      estimated_minutes: 60, deadline: "2026-11-13", deadline_kind: "plan_end", priority: 2 }];
    session.recommendations = SessionSchema.parse({ ...session, recommendations: undefined }).recommendations;
    const recommendations = { target_date: "2027-12-20", target_date_reason: "依据2027年目标估算，官方日期待公布", target_date_estimated: true,
      plan_end_date: "2027-12-20", plan_end_date_reason: "本次安排到目标日期",
      weekly_minutes: { "0": 180, "1": 90, "2": 90, "3": 90, "4": 90, "5": 90, "6": 180 }, weekly_minutes_reason: "先建立每日复习节奏" };
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ recommendations }) } }] }));
    const schedule = await advanceOnboarding(session, { type: "confirm_items", items: session.items });
    expect(schedule.stage).toBe("schedule");
    expect(schedule.recommendations.plan_end_date).toBe("2027-12-20");
    expect(schedule.answers).toEqual(session.answers);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(request.messages[0].content).toContain("不要继续提问");
  });

  it("provides AI item generation the plan cycle rather than an unrelated default", async () => {
    const session = await fiveAnswers();
    session.courses = [{ id: "math", name: "高数", description: "", priority: 2 }];
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ items: [{ id: "math-1", course_id: "math", title: "基础复习", estimated_minutes: 60, deadline: "2026-11-13", deadline_kind: "plan_end" }], summary: "", assumptions: [], warnings: [] }) } }] }));
    await generateItems(session);
    const request = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    expect(JSON.parse(request.messages[1].content).plan_end_date).toBe("2026-11-13");
    expect(JSON.parse(request.messages[1].content).target_date).toBe("");
  });

  it("includes current manual edits in conversational revisions and rejects new course references", async () => {
    const session = await advanceOnboarding(await fiveAnswers(), { type: "generate_courses" });
    session.courses = [{ id: "manual", name: "手动课程", description: "自定义范围", priority: 1 }];
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ courses: session.courses, summary: "修改后", assumptions: [], warnings: [] }) } }] }));
    await generateCourses(session, "保留手动课程");
    expect(JSON.parse(JSON.parse(String(fetchMock.mock.calls[0][1]?.body)).messages[1].content).courses).toEqual(session.courses);
    fetchMock.mockResolvedValue(Response.json({ choices: [{ message: { content: JSON.stringify({ items: [{ id: "bad", course_id: "invented", title: "错误引用", estimated_minutes: 60, deadline: "2027-12-25" }], summary: "", assumptions: [], warnings: [] }) } }] }));
    await expect(generateItems(session)).rejects.toThrow("已确认的课程");
  });

  it("preserves progress on AI errors and clearly reports unavailable chat editing", async () => {
    const session = await fiveAnswers();
    aiConfig.aiApiKey = "key";
    fetchMock.mockResolvedValue(new Response(null, { status: 503 }));
    await expect(advanceOnboarding(session, { type: "generate_courses" })).rejects.toThrow("503");
    expect(session.stage).toBe("checkpoint");
    aiConfig.aiApiKey = "";
    await expect(generateCourses(session, "增加一门课")).rejects.toThrow("尚未配置 AI");
  });
});
