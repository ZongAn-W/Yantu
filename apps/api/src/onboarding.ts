import { type OnboardingAction, type OnboardingSession, type ScheduleAction, CalendarDateSchema, FIRST_QUESTION, newSession, validateReferences } from "./onboarding-contracts.js";
import { generateItems, nextInterview, recommendSchedule, shanghaiDate } from "./onboarding-ai.js";
import { sanitizeInterviewSession } from "./onboarding-evidence.js";
import { buildLearningContext, ResearchSchema } from "./learning-context.js";
import { type CapacityBasis } from "./contracts.js";
import { resolveRangeCapacity } from "./planning-scheduler.js";
import {
  evaluatePlanning, existingPlanMode, frozenInputs, newPlanning, normalizePlanningMetadata, planningHash, type PlanMode,
} from "./planning-service.js";
import { checkAndRepair } from "./planning-repair.js";
import type { PlannerDocument } from "./sync-contracts.js";

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

function validDate(value: string) {
  const parsed = new Date(`${value}T00:00:00Z`);
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(+parsed) && parsed.toISOString().slice(0, 10) === value;
}

/**
 * Capacity input accepted from the constraints/preview/finish actions.
 *
 * Old clients keep sending a complete `weekly_minutes` and no capacity fields at all, which
 * keeps the legacy gross semantics. New clients may send only a weekly baseline/range plus
 * obvious rests; an explicitly provided capacity payload is authoritative for the whole
 * capacity state (omitted overrides are clears, not "keep the old value").
 */
export function capacityFromAction(action: ScheduleAction, profile: OnboardingSession["profile"]) {
  const raw = action as Record<string, unknown>;
  const hasPayload = ["capacity_basis", "weekly_baseline_minutes", "weekly_range_min_minutes", "weekly_range_max_minutes",
    "week_capacity_overrides", "date_capacity_overrides"].some(key => raw[key] !== undefined);
  const basis: CapacityBasis = action.capacity_basis ?? profile.capacity_basis
    ?? (hasPayload ? "gross_buffer" : "gross_buffer");
  const rawWeekly: Record<string, number> | undefined = action.weekly_minutes
    ?? (profile.weekly_minutes && Object.keys(profile.weekly_minutes).length === 7 ? profile.weekly_minutes : undefined);
  // Old finish payloads could carry a partial week; keep them readable by zero-filling the
  // missing days (explicit 0 still means a rest day) instead of rejecting the whole draft.
  // For new net plans the profile's default all-zero week is not a user-confirmed template:
  // a weekly baseline alone must still schedule (distribution weights fall back to the day cap).
  const netWithoutTemplate = basis === "net" && action.weekly_minutes === undefined
    && rawWeekly !== undefined && Object.values(rawWeekly).every(value => value === 0);
  const weekly = rawWeekly && Object.keys(rawWeekly).length > 0 && !netWithoutTemplate
    ? (Object.keys(rawWeekly).length === 7 ? rawWeekly
      : Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map(day => [String(day), rawWeekly[String(day)] ?? 0])))
    : undefined;
  const baseline = action.weekly_baseline_minutes ?? (hasPayload ? undefined : profile.weekly_baseline_minutes ?? undefined);
  const rangeMin = action.weekly_range_min_minutes ?? (hasPayload ? undefined : profile.weekly_range_min_minutes ?? undefined);
  const rangeMax = action.weekly_range_max_minutes ?? (hasPayload ? undefined : profile.weekly_range_max_minutes ?? undefined);
  if (rangeMin !== undefined && rangeMax !== undefined && rangeMin > rangeMax)
    throw new Error("每周容量范围的最小值不能大于最大值");
  if (baseline !== undefined && rangeMax !== undefined && baseline > rangeMax)
    throw new Error("采用的每周基线不能高于你给出的容量范围上限");
  for (const monday of Object.keys(action.week_capacity_overrides ?? {})) {
    if (!validDate(monday) || new Date(`${monday}T00:00:00Z`).getUTCDay() !== 1)
      throw new Error("周容量覆盖必须以周一日期作为键");
  }
  for (const date of Object.keys(action.date_capacity_overrides ?? {}))
    if (!validDate(date)) throw new Error("日期容量覆盖必须是有效日期");
  const weekOverrides = hasPayload ? action.week_capacity_overrides ?? {} : profile.week_capacity_overrides ?? undefined;
  const dateOverrides = hasPayload ? action.date_capacity_overrides ?? {} : profile.date_capacity_overrides ?? undefined;
  const adopted: OnboardingSession["profile"] = {
    ...profile,
    capacity_basis: basis,
    ...(weekly ? { weekly_minutes: weekly } : {}),
    ...(baseline !== undefined ? { weekly_baseline_minutes: baseline } : {}),
    ...(rangeMin !== undefined ? { weekly_range_min_minutes: rangeMin } : {}),
    ...(rangeMax !== undefined ? { weekly_range_max_minutes: rangeMax } : {}),
    ...(weekOverrides !== undefined ? { week_capacity_overrides: weekOverrides } : {}),
    ...(dateOverrides !== undefined ? { date_capacity_overrides: dateOverrides } : {}),
  };
  return { basis, weekly, baseline, rangeMin, rangeMax, weekOverrides, dateOverrides, hasPayload,
    templateAbsent: netWithoutTemplate, profile: adopted };
}

export function prepareSchedule(session: OnboardingSession, action: ScheduleAction) {
  const today = shanghaiDate();
  if (action.start_date < today) throw new Error("计划开始日期不能早于今天");
  if (action.end_date < action.start_date) throw new Error("规划结束日期不能早于开始日期");
  const span = daySpan(action.start_date, action.end_date);
  if (span > 1095) throw new Error("单次规划周期不能超过三年，请先安排一段有限周期");
  if (Number(action.end_date.slice(0, 4)) > Number(today.slice(0, 4)) + 10) throw new Error("请将规划结束日期设置在未来十年内");
  const capacity = capacityFromAction(action, session.profile);
  if (capacity.basis === "net") {
    // Net input is the study budget itself: explicit rest days and a 20-minute day are valid.
    const probe = { ...capacity.profile, ...(capacity.templateAbsent ? { weekly_minutes: {} } : {}),
      daily_limit_minutes: 480, buffer_minutes: 30, granularity_minutes: 30 };
    const total = resolveRangeCapacity(probe, action.start_date, action.end_date)
      .reduce((sum, day) => sum + day.minutes, 0);
    if (total <= 0) throw new Error("请至少设置一天可学习的净时间，或提供大致周容量范围");
  } else {
    if (!capacity.weekly) throw new Error("请填写完整一周时间");
    if (!Object.values(capacity.weekly).some(value => value > 30)) throw new Error("请至少设置一天超过30分钟的可用时间，预留30分钟机动");
  }
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
    const earliest = kind === "deadline" && deadline < action.start_date ? item.earliest_date
      : item.earliest_date && item.earliest_date > action.start_date ? item.earliest_date : action.start_date;
    if (earliest && earliest > deadline) throw new Error(`事项「${item.title}」的开始日期晚于截止日期，请返回修改事项日期`);
    CalendarDateSchema.parse(deadline);
    return { ...item, earliest_date: earliest, deadline, deadline_kind: kind };
  });
  const goal = session.answers.filter(answer => answer.question === FIRST_QUESTION).at(-1)?.answer;
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
      weekly_minutes: capacity.weekly ?? (capacity.templateAbsent ? {} : session.profile.weekly_minutes),
      constraints_text: constraints.slice(0, 4000),
      capacity_basis: capacity.hasPayload || session.profile.capacity_basis !== undefined ? capacity.basis : session.profile.capacity_basis,
      ...(capacity.hasPayload ? {
        weekly_baseline_minutes: capacity.baseline,
        weekly_range_min_minutes: capacity.rangeMin,
        weekly_range_max_minutes: capacity.rangeMax,
        week_capacity_overrides: capacity.weekOverrides ?? {},
        date_capacity_overrides: capacity.dateOverrides ?? {},
      } : {}),
    },
  };
}

/** Mode requested by the action/session; a brand-new plan defaults to full coverage. */
export function resolvePlanMode(session: OnboardingSession, action: ScheduleAction): PlanMode {
  return (action as { mode?: PlanMode }).mode ?? existingPlanMode(session) ?? "full";
}

export async function advanceOnboarding(current: OnboardingSession, action: OnboardingAction, currentDocument?: PlannerDocument | null): Promise<OnboardingSession> {
  // 旧草稿里可能残留 AI 无依据推断的考试信息；先按本轮回答修正再继续，revision 由原有协议推进。
  const session = sanitizeInterviewSession(structuredClone(current));
  if (session.constraints_confirmed) session.profile = structuredClone(current.profile);
  if (["refresh_plan", "set_exam_year", "answer", "resume_interview", "back"].includes(action.type)) session.preview = null;
  const requireStage = (...stages: OnboardingSession["stage"][]) => {
    if (!stages.includes(session.stage)) throw new Error("当前阶段不支持此操作，请刷新后重试");
  };
  if (action.type === "restart_interview") {
    return { ...newSession(), revision: session.revision + 1, has_plan: session.has_plan,
      replanning: session.has_plan, plan_revision: session.plan_revision, current_plan: session.current_plan };
  } else if (action.type === "resume_interview") {
    if (session.answers.length >= 50) throw new Error("已达到50题，请继续确认规划条件，或重新访谈");
    Object.assign(session, await nextInterview(session), { stage: "interview", replanning: session.has_plan });
  } else if (action.type === "refresh_plan") {
    if (!session.replanning) throw new Error("当前没有需要更新的重新规划草案");
  } else if (action.type === "retry_research") {
    requireStage("interview", "checkpoint", "constraints", "items", "schedule");
  } else if (action.type === "set_exam_year") {
    requireStage("interview", "checkpoint", "constraints", "items", "schedule");
    const currentYear = Number(shanghaiDate().slice(0, 4));
    if (session.profile.goal_subtype !== "考研") throw new Error("只有考研目标需要设置初试年份");
    if (action.year < currentYear || action.year > currentYear + 10) throw new Error("请选择未来十年内的初试年份");
    session.exam_year_override = action.year;
    session.learning_context = buildLearningContext(session);
    session.research = ResearchSchema.parse({});
  } else if (action.type === "answer") {
    requireStage("interview");
    if (session.answers.length >= 50) throw new Error("已达到50题，请继续确认规划条件，或重新访谈");
    session.answers.push({ question: session.question, answer: action.answer, ...(session.question_fields.length ? { fields: session.question_fields } : {}) });
    if (session.answers.length >= 50) {
      // 到达题数上限后不再追加问题，用户可继续确认规划条件。
      session.question = "";
      session.question_options = [];
      session.question_multiple = false;
      session.question_type = "text";
    } else {
      const result = await nextInterview(session);
      session.question = result.question;
      session.question_type = result.question_type;
      session.question_options = result.question_options;
      session.question_multiple = result.question_multiple;
      session.question_fields = result.question_fields ?? [];
      session.learning_context = result.learning_context;
      session.research = result.research;
      session.profile = result.profile;
      session.recommendations = result.recommendations;
    }
  } else if (action.type === "continue") {
    // Continue leaves the interview and opens schedule constraints.
    requireStage("interview", "checkpoint");
    session.recommendations = await ensureRecommendations(session);
    if (!session.end_date) session.end_date = session.recommendations.plan_end_date || cycleEnd(session.profile);
    session.stage = "constraints";
  } else if (action.type === "set_constraints") {
    requireStage("constraints");
    Object.assign(session, prepareSchedule(session, action), { constraints_confirmed: true });
    // The mode comes from the action/session (never from the model): a brand-new plan is full,
    // an inherited rolling plan keeps rolling unless the caller explicitly upgrades it.
    const mode = resolvePlanMode(session, action);
    session.planning = normalizePlanningMetadata(newPlanning(), { start_date: session.start_date, end_date: session.end_date,
      requested_mode: mode, requested_detail_days: action.detail_days });
    Object.assign(session, await generateItems(session), { stage: "items", preview: null });
    session.planning = normalizePlanningMetadata(session.planning ?? newPlanning(), { start_date: session.start_date,
      end_date: session.end_date, requested_mode: mode, requested_detail_days: action.detail_days });
    const checked = evaluatePlanning(session, currentDocument);
    session.planning = checked.planning;
  } else if (action.type === "save_items" || action.type === "revise_items" || action.type === "confirm_items") {
    requireStage("items");
    validateReferences(action.items);
    for (const item of action.items) {
      if (item.earliest_date && item.earliest_date > item.deadline) throw new Error(`事项「${item.title}」的开始日期晚于截止日期`);
    }
    session.items = action.items;
    session.preview = null;
    if (action.type === "revise_items") Object.assign(session, await generateItems(session, action.instruction));
    if (action.type === "confirm_items") {
      session.recommendations = await ensureRecommendations(session);
      session.stage = "schedule";
      if (!session.end_date) session.end_date = session.recommendations.plan_end_date || cycleEnd(session.profile);
    }
  } else if (action.type === "preview_schedule") {
    requireStage("schedule");
    Object.assign(session, prepareSchedule(session, action));
    const mode = resolvePlanMode(session, action);
    session.planning = normalizePlanningMetadata(session.planning ?? newPlanning(), { start_date: session.start_date,
      end_date: session.end_date, requested_mode: mode, requested_detail_days: action.detail_days });
    Object.assign(session, await checkAndRepair(session, currentDocument));
  } else if (action.type === "back") {
    requireStage("constraints", "items", "schedule");
    if (action.target === "interview") session.stage = "interview";
    else if (action.target === "constraints") { session.stage = "constraints"; session.preview = null; }
    else {
      requireStage("schedule");
      session.stage = "items";
    }
  } else if (action.type === "finish") {
    requireStage("schedule");
    const prepared = prepareSchedule(session, action);
    if (session.planning || session.constraints_confirmed) {
      if (!action.preview_token || action.preview_token !== session.preview?.token
        || planningHash(frozenInputs(prepared)) !== session.preview?.fingerprint)
        throw new Error("条件或草案已变化，请重新检查并预览每日安排");
      const checked = evaluatePlanning(prepared, currentDocument);
      if (checked.preview.status !== "ready") throw new Error("仍有必须解决的规划冲突，请返回预览修改");
    }
    return { ...prepared, revision: session.revision + 1, stage: "complete" };
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
