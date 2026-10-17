import { type OnboardingAction, type OnboardingSession, CalendarDateSchema, FIRST_QUESTION, newSession, validateReferences } from "./onboarding-contracts.js";
import { generateCourses, generateItems, nextInterview, recommendSchedule, shanghaiDate } from "./onboarding-ai.js";

/** 日期相差的自然日数。 */
export function daySpan(from: string, to: string) {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000);
}

/** 本次规划周期的结束日期；没有设置时按目标日期，再退回未来 28 天。 */
export function cycleEnd(profile: OnboardingSession["profile"], today = shanghaiDate()) {
  if (profile.plan_end_date) return profile.plan_end_date;
  if (profile.target_date) return profile.target_date;
  const end = new Date(`${today}T00:00:00Z`);
  end.setUTCDate(end.getUTCDate() + 27);
  return end.toISOString().slice(0, 10);
}

export function prepareSchedule(session: OnboardingSession, action: Extract<OnboardingAction, { type: "finish" }>) {
  const today = shanghaiDate();
  if (action.start_date < today) throw new Error("计划开始日期不能早于今天");
  if (action.end_date < action.start_date) throw new Error("规划结束日期不能早于开始日期");
  const span = daySpan(action.start_date, action.end_date);
  if (span > 1095) throw new Error("单次规划周期不能超过三年，请先安排一段有限周期");
  if (Number(action.end_date.slice(0, 4)) > Number(today.slice(0, 4)) + 10) throw new Error("请将规划结束日期设置在未来十年内");
  if (!Object.values(action.weekly_minutes).some(value => value > 30)) throw new Error("请至少设置一天超过30分钟的可用时间，预留30分钟机动");
  const targetDate = action.target_date && action.target_date.length ? CalendarDateSchema.parse(action.target_date) : null;
  const fixedItems = new Set(Array.isArray(session.current_plan?.items)
    ? session.current_plan.items.filter((item): item is Record<string, unknown> => Boolean(item && typeof item === "object"))
      .filter(item => item.is_fixed).map(item => item.id) : []);
  const items = session.items.map(item => {
    if (fixedItems.has(item.id)) return item;
    // 没有类型标记的历史事项按真实截止日期处理：
    // 不能只因为日期恰好等于旧周期结束日，就推断它没有真实截止日期。
    const kind = item.deadline_kind ?? "deadline";
    // 只有本期安排边界随新周期延展；真实截止日期保持原值。
    const deadline = kind === "plan_end"
      ? (item.earliest_date && item.earliest_date > action.end_date ? item.earliest_date : action.end_date)
      : item.deadline;
    // 开始日期晚于本期结束日的事项保留为后续事项，不强行拉进本期。
    const earliest = item.earliest_date && item.earliest_date > action.start_date ? item.earliest_date : action.start_date;
    if (earliest > deadline) throw new Error(`事项「${item.title}」的开始日期晚于截止日期，请返回修改事项日期`);
    CalendarDateSchema.parse(deadline);
    return { ...item, earliest_date: earliest, deadline, deadline_kind: kind };
  });
  const goal = session.answers.find(answer => answer.question === FIRST_QUESTION)?.answer;
  const goalText = session.profile.goal_text || goal || "";
  const constraints = goalText && !session.profile.constraints_text.includes(goalText)
    ? `学习目标：${goalText}\n${session.profile.constraints_text}`
    : session.profile.constraints_text;
  return {
    ...session,
    start_date: action.start_date,
    end_date: action.end_date,
    items,
    profile: {
      ...session.profile,
      goal_text: goalText.slice(0, 2000),
      target_date: targetDate,
      plan_start_date: action.start_date,
      plan_end_date: action.end_date,
      weekly_minutes: action.weekly_minutes,
      constraints_text: constraints.slice(0, 4000),
    },
  };
}

export async function advanceOnboarding(current: OnboardingSession, action: OnboardingAction): Promise<OnboardingSession> {
  const session = structuredClone(current);
  const requireStage = (...stages: OnboardingSession["stage"][]) => {
    if (!stages.includes(session.stage)) throw new Error("当前阶段不支持此操作，请刷新后重试");
  };
  if (action.type === "restart_interview") {
    return { ...newSession(), revision: session.revision + 1, has_plan: session.has_plan,
      replanning: session.has_plan, plan_revision: session.plan_revision, current_plan: session.current_plan };
  } else if (action.type === "resume_interview") {
    if (session.answers.length >= 50) throw new Error("已达到50题，请根据当前回答生成课程，或重新访谈");
    Object.assign(session, await nextInterview(session), { stage: "interview", replanning: session.has_plan });
  } else if (action.type === "refresh_plan") {
    if (!session.replanning) throw new Error("当前没有需要更新的重新规划草案");
  } else if (action.type === "answer") {
    requireStage("interview");
    if (session.answers.length >= 50) throw new Error("已达到50题，请根据当前回答生成课程");
    session.answers.push({ question: session.question, answer: action.answer });
    const result = await nextInterview(session);
    session.question = result.question;
    session.question_options = result.question_options;
    session.question_multiple = result.question_multiple;
    session.profile = result.profile;
    session.recommendations = result.recommendations;
    if (session.answers.length >= 5) session.stage = "checkpoint";
  } else if (action.type === "continue") {
    requireStage("checkpoint");
    if (session.answers.length >= 50) throw new Error("已达到50题，请根据当前回答生成课程");
    session.stage = "interview";
  } else if (action.type === "generate_courses") {
    requireStage("checkpoint");
    Object.assign(session, await generateCourses(session), { stage: "courses", items: [] });
  } else if (action.type === "save_courses" || action.type === "revise_courses" || action.type === "confirm_courses") {
    requireStage("courses");
    validateReferences(action.courses, []);
    session.courses = action.courses;
    session.items = [];
    if (action.type === "revise_courses") Object.assign(session, await generateCourses(session, action.instruction));
    if (action.type === "confirm_courses") {
      session.recommendations = await ensureRecommendations(session);
      if (!session.end_date) session.end_date = session.recommendations.plan_end_date || cycleEnd(session.profile);
      Object.assign(session, await generateItems(session), { stage: "items" });
    }
  } else if (action.type === "save_items" || action.type === "revise_items" || action.type === "confirm_items") {
    requireStage("items");
    validateReferences(session.courses, action.items);
    for (const item of action.items) {
      if (item.earliest_date && item.earliest_date > item.deadline) throw new Error(`事项「${item.title}」的开始日期晚于截止日期`);
    }
    session.items = action.items;
    if (action.type === "revise_items") Object.assign(session, await generateItems(session, action.instruction));
    if (action.type === "confirm_items") {
      if (session.courses.some(course => !session.items.some(item => item.course_id === course.id))) throw new Error("每门课程至少需要一个学习事项");
      session.recommendations = await ensureRecommendations(session);
      session.stage = "schedule";
      if (!session.end_date) session.end_date = session.recommendations.plan_end_date || cycleEnd(session.profile);
    }
  } else if (action.type === "back") {
    requireStage("courses", "items", "schedule");
    if (action.target === "interview") session.stage = "checkpoint";
    else if (action.target === "courses") session.stage = "courses";
    else {
      requireStage("schedule");
      session.stage = "items";
    }
  } else if (action.type === "finish") {
    requireStage("schedule");
    return { ...prepareSchedule(session, action), revision: session.revision + 1, stage: "complete" };
  }
  return { ...session, revision: session.revision + 1 };
}

/** 只补齐缺失的推荐值，保留用户已经确认的日期与时间。 */
async function ensureRecommendations(session: OnboardingSession) {
  const missingPlan = !session.recommendations.plan_end_date;
  const missingWeek = Object.keys(session.recommendations.weekly_minutes).length !== 7;
  if (!missingPlan && !missingWeek) return session.recommendations;
  const next = await recommendSchedule(session);
  return {
    ...next,
    target_date: session.recommendations.target_date || next.target_date,
    target_date_reason: session.recommendations.target_date ? session.recommendations.target_date_reason : next.target_date_reason,
    target_date_estimated: session.recommendations.target_date ? session.recommendations.target_date_estimated : next.target_date_estimated,
    plan_end_date: session.recommendations.plan_end_date || next.plan_end_date,
    plan_end_date_reason: session.recommendations.plan_end_date ? session.recommendations.plan_end_date_reason : next.plan_end_date_reason,
    weekly_minutes: missingWeek ? next.weekly_minutes : session.recommendations.weekly_minutes,
    weekly_minutes_reason: missingWeek ? next.weekly_minutes_reason : session.recommendations.weekly_minutes_reason,
  };
}
