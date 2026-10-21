import { createHash } from "node:crypto";
import type { OnboardingSession } from "./onboarding-contracts.js";
import type { PlanPlanning } from "./planning-contracts.js";
import type { PlannerDocument } from "./sync-contracts.js";
import { dateAdd, isReliableWeek, normalizeWeek, replanDocument } from "./planner.js";
import {
  mondayOf, recurringDemand, resolveDayCapacity, resolveWeeksInRange, scheduleStrategy, taskArchived, weekdayOf,
  type CapacityBasis,
} from "./planning-scheduler.js";

export const PLANNING_PROMPT_VERSION = "learning-route-2-full";
/** 纯时间口径：进度=实际学习分钟/预计总时长，内容量与内容反馈不再参与规划规则。 */
export const PLANNING_RULES_VERSION = "time-progress-1";
/** Hard ceiling of the finite planning cycle; full mode never truncates below it. */
export const PLAN_CYCLE_MAX_DAYS = 1095;
export type PlanMode = "rolling" | "full";
export type QualityIssue = {
  code: string; severity: "error" | "warning" | "info"; item_id?: string; date?: string;
  expected?: unknown; actual?: unknown; message: string; evidence: string; repair: string;
};
export type PlanCapacityWeek = {
  monday: string; budget_minutes: number | null; resolved_minutes: number; estimated: boolean;
  conflicts: Array<{ code: string; total: number; resolved: number }>;
};
export type PlanCapacitySummary = {
  basis: CapacityBasis;
  /** Adopted weekly value that actually schedules (confirmed baseline wins over the range). */
  adopted_weekly_minutes: number | null;
  source: "baseline" | "range_min" | "template" | "legacy_default";
  weekly_baseline_minutes: number | null;
  weekly_range_minutes: { min: number; max: number } | null;
  weeks: PlanCapacityWeek[];
  estimated_weeks: number;
  week_override_count: number;
  date_override_count: number;
  /** Partial weeks are distributed over the full Monday..Sunday week; only the cycle clip is scheduled. */
  partial_week_rule: "full_week_distribution_cycle_clipped";
  assumptions: string[];
};
export type CapacityImpact = {
  kept_blocks: number; kept_minutes: number;
  released_blocks: number; released_minutes: number;
  added_blocks: number; added_minutes: number;
  unscheduled_minutes: number;
  deadline_at_risk: Array<{ item_id: string; title: string; deadline: string; unscheduled_minutes: number }>;
};
export type PlanningPreview = {
  token: string; detailed_until: string; scheduled_minutes: number; unscheduled_minutes: number;
  protected_blocks: number; days: Array<{ date: string; minutes: number; items: Array<{ item_id: string; title: string; minutes: number }> }>;
  issues: QualityIssue[]; repairs: number; status: "ready" | "blocked"; fingerprint: string;
  forecast_minutes: number;
  mode: PlanMode;
  capacity: PlanCapacitySummary;
  capacity_impact: CapacityImpact;
};

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value)
    // Derived scheduling metadata never changes the frozen-input fingerprint: the profile,
    // mode and horizon it derives from are already part of the hash.
    .filter(([key]) => !["updated_at", "created_at", "quality", "frozen_inputs", "capacity"].includes(key))
    .sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => [key, canonical(item)]));
  return value;
}
export const planningHash = (value: unknown) => createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");

export function newPlanning(): PlanPlanning {
  // New plans generate the whole finite cycle; old rolling metadata keeps its own mode.
  return { version: 1, prompt_version: PLANNING_PROMPT_VERSION, rules_version: PLANNING_RULES_VERSION,
    mode: "full", detail_days: 14, rolling: false, route: [], milestones: [], assumptions: [], risks: [], uncovered: [] };
}

/** Inclusive calendar day count; full mode must cover start..end without the old 14/90 truncation. */
export function inclusiveDaySpan(start: string, end: string): number {
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000) + 1;
}

export function effectivePlanMode(metadata: Pick<PlanPlanning, "mode" | "rolling"> | null | undefined): PlanMode {
  if (!metadata) return "full";
  if (metadata.mode === "rolling" || metadata.mode === "full") return metadata.mode;
  return metadata.rolling ? "rolling" : "full";
}

/** Mode of the plan this session already owns; null for a brand-new plan. */
export function existingPlanMode(session: Pick<OnboardingSession, "planning" | "current_plan">): PlanMode | null {
  if (session.planning) return effectivePlanMode(session.planning);
  const metadata = (session.current_plan as { planning?: { mode?: unknown; rolling?: unknown } } | null)?.planning;
  if (!metadata || typeof metadata !== "object") return null;
  if (metadata.mode === "rolling" || metadata.mode === "full") return metadata.mode;
  if (typeof metadata.rolling === "boolean") return metadata.rolling ? "rolling" : "full";
  return null;
}

/**
 * Normalize the mode/horizon fields from the session/action, never from the model.
 * Full mode: detail_days = inclusive cycle span (≤1095), detailed_until = end, forecast = null.
 * Rolling mode keeps the legacy detail window and never leaves an inverted forecast interval.
 */
export function normalizePlanningMetadata(metadata: PlanPlanning, options: {
  start_date: string; end_date: string; requested_mode?: PlanMode; requested_detail_days?: number;
}): PlanPlanning {
  const result = structuredClone(metadata);
  const mode = options.requested_mode ?? effectivePlanMode(result);
  result.mode = mode;
  result.rolling = mode === "rolling";
  const span = Math.max(1, inclusiveDaySpan(options.start_date, options.end_date));
  if (mode === "full") {
    result.detail_days = Math.min(PLAN_CYCLE_MAX_DAYS, span);
    result.detailed_until = options.end_date;
    result.forecast = null;
    return result;
  }
  const requested = Math.floor(options.requested_detail_days ?? result.detail_days ?? 14);
  result.detail_days = Math.max(1, Math.min(PLAN_CYCLE_MAX_DAYS, Number.isFinite(requested) ? requested : 14));
  const until = [options.end_date, dateAdd(options.start_date, result.detail_days - 1)].sort()[0];
  result.detailed_until = until;
  if (until >= options.end_date) result.forecast = null;
  return result;
}

/** Capacity assumptions shown in the preview and persisted once the plan is confirmed. */
export function summarizePlanCapacity(profile: OnboardingSession["profile"], start: string, end: string): PlanCapacitySummary {
  const weeks = resolveWeeksInRange(profile, start, end);
  const capacityWeeks: PlanCapacityWeek[] = weeks.map(week => ({
    monday: week.monday,
    budget_minutes: week.budget_override_minutes,
    resolved_minutes: week.resolved_minutes,
    estimated: Object.values(week.estimated).some(Boolean),
    conflicts: week.conflicts.map(conflict => ({ code: conflict.code, total: conflict.total, resolved: conflict.resolved })),
  }));
  const basis: CapacityBasis = profile.capacity_basis === "net" ? "net" : "gross_buffer";
  const baseline = profile.weekly_baseline_minutes ?? null;
  const min = profile.weekly_range_min_minutes ?? null;
  const max = profile.weekly_range_max_minutes ?? null;
  const adopted = baseline ?? min;
  const source = baseline !== null ? "baseline" as const
    : min !== null ? "range_min" as const
      : profile.weekly_minutes && Object.keys(profile.weekly_minutes).length === 7 ? "template" as const : "legacy_default" as const;
  const estimatedWeeks = capacityWeeks.filter(week => week.estimated).length;
  const assumptions = [
    basis === "net" ? "净学习预算：输入值即实际可安排的学习时间，不再额外扣除机动。" : "总时间预算：沿用旧口径，按天扣除一次机动时间。",
    adopted !== null
      ? `采用每周${adopted}分钟作为排程基线${max !== null && min !== null ? `；用户给出的${min}–${max}分钟范围仅用于说明容量充足时可达的进度，不直接用于排程` : ""}。`
      : "按已确认的默认周模板逐日安排；0分钟表示明确休息日。",
    "周界线按上海时区周一至周日；周期只与某周部分相交时，先按完整一周分配，排程只使用相交的日期。",
    ...(capacityWeeks.some(week => week.conflicts.length) ? ["存在周容量覆盖与日期覆盖的冲突，请调整或明确接受新的容量。"] : []),
  ];
  return {
    basis, adopted_weekly_minutes: adopted, source,
    weekly_baseline_minutes: baseline,
    weekly_range_minutes: min !== null || max !== null ? { min: min ?? 0, max: max ?? min ?? 0 } : null,
    weeks: capacityWeeks, estimated_weeks: estimatedWeeks,
    week_override_count: Object.keys(profile.week_capacity_overrides ?? {}).length,
    date_override_count: Object.keys(profile.date_capacity_overrides ?? {}).length,
    partial_week_rule: "full_week_distribution_cycle_clipped",
    assumptions,
  };
}

/**
 * Write the adopted capacity model into the document profile. The default template is the
 * user's own seven-day configuration; when a net plan has only a weekly baseline/range the
 * template stays absent so the shared resolver distributes the total instead of reading zeros.
 */
function applyCapacityProfile(document: PlannerDocument, session: OnboardingSession) {
  const profile = session.profile;
  const basis: CapacityBasis = profile.capacity_basis === "net" ? "net" : "gross_buffer";
  const capacityFields: Record<string, unknown> = { capacity_basis: basis };
  if (profile.weekly_baseline_minutes != null) capacityFields.weekly_baseline_minutes = profile.weekly_baseline_minutes;
  if (profile.weekly_range_min_minutes != null) capacityFields.weekly_range_min_minutes = profile.weekly_range_min_minutes;
  if (profile.weekly_range_max_minutes != null) capacityFields.weekly_range_max_minutes = profile.weekly_range_max_minutes;
  if (profile.week_capacity_overrides != null) capacityFields.week_capacity_overrides = structuredClone(profile.week_capacity_overrides);
  if (profile.date_capacity_overrides != null) capacityFields.date_capacity_overrides = structuredClone(profile.date_capacity_overrides);
  Object.assign(document.profile, capacityFields);
  if (isReliableWeek(profile.weekly_minutes)) {
    document.profile.weekly_minutes = normalizeWeek(profile.weekly_minutes);
    document.profile.daily_limit_minutes = Math.max(30, Math.min(480, Math.max(...Object.values(profile.weekly_minutes), 30)));
  } else if (basis === "net") {
    delete (document.profile as { weekly_minutes?: unknown }).weekly_minutes;
    document.profile.daily_limit_minutes = 480;
  }
}

/** Compact, user-facing capacity assumptions persisted as part of the confirmed plan. */
function capacityMetadata(profile: OnboardingSession["profile"], start: string, end: string) {
  const summary = summarizePlanCapacity(profile, start, end);
  return {
    basis: summary.basis,
    adopted_weekly_minutes: summary.adopted_weekly_minutes,
    source: summary.source,
    weekly_baseline_minutes: summary.weekly_baseline_minutes,
    weekly_range_minutes: summary.weekly_range_minutes,
    weeks_estimated: summary.estimated_weeks,
    week_override_count: summary.week_override_count,
    date_override_count: summary.date_override_count,
    partial_week_rule: summary.partial_week_rule,
    conflicts: summary.weeks.flatMap(week => week.conflicts.map(conflict => ({ ...conflict, monday: week.monday }))),
    assumptions: summary.assumptions,
    rules_version: PLANNING_RULES_VERSION,
  };
}

/**
 * Structured capacity-change impact: protected records stay, adjustable future records may be
 * released/added, the real remaining gap is explicit, and real deadlines that cannot be met
 * are listed instead of silently mutating the deadline.
 */
function buildCapacityImpact(base: PlannerDocument, finalBlocks: PlannerDocument["blocks"], session: OnboardingSession,
  mapping: Map<string, string>, forecast: { unscheduled_minutes: number }): CapacityImpact {
  const before = new Set(base.blocks.map(block => block.id));
  const finalIds = new Set(finalBlocks.map(block => block.id));
  const kept = finalBlocks.filter(block => before.has(block.id));
  const added = finalBlocks.filter(block => !before.has(block.id));
  const released = base.blocks.filter(block => !finalIds.has(block.id) && block.date >= session.start_date
    && !block.is_fixed && block.status !== "completed" && block.actual_minutes <= 0);
  const minutesOf = (blocks: PlannerDocument["blocks"]) => blocks.reduce((sum, block) => sum + block.duration_minutes, 0);
  const finalByTask = new Map<string, PlannerDocument["blocks"]>();
  for (const block of finalBlocks) finalByTask.set(block.task_id, [...(finalByTask.get(block.task_id) ?? []), block]);
  const deadlineAtRisk: CapacityImpact["deadline_at_risk"] = [];
  for (const item of session.items) {
    const taskId = mapping.get(item.id);
    if (!taskId || item.deadline_kind !== "deadline" || item.deadline > session.end_date) continue;
    const completed = base.tasks.find(task => task.id === taskId)?.completed_minutes ?? 0;
    const scheduledBeforeDeadline = (finalByTask.get(taskId) ?? [])
      .filter(block => block.date <= item.deadline).reduce((sum, block) => sum + block.duration_minutes, 0);
    const pending = Math.max(0, item.estimated_minutes - completed - scheduledBeforeDeadline);
    if (pending > 0) deadlineAtRisk.push({ item_id: item.id, title: item.title, deadline: item.deadline, unscheduled_minutes: pending });
  }
  return {
    kept_blocks: kept.length, kept_minutes: minutesOf(kept),
    released_blocks: released.length, released_minutes: minutesOf(released),
    added_blocks: added.length, added_minutes: minutesOf(added),
    unscheduled_minutes: forecast.unscheduled_minutes,
    deadline_at_risk: deadlineAtRisk,
  };
}

/** Validate execution output separately from the allocator; inherited records are protected, not rewritten. */
export function checkScheduledPlan(document: PlannerDocument, from: string, to: string,
  protectedIds = new Set<string>()): QualityIssue[] {
  const issues: QualityIssue[] = [], taskById = new Map(document.tasks.map(task => [task.id, task]));
  const instanceIds = new Set<string>();
  const fail = (code: string, message: string, item_id?: string, date?: string, expected?: unknown, actual?: unknown) =>
    issues.push({ code, severity: "error", item_id, date, expected, actual, message,
      evidence: "试排执行安排与冻结约束", repair: "保留受保护记录，重新试排可调整的未来安排" });
  for (const block of document.blocks) {
    if (block.activity_instance_id) {
      if (instanceIds.has(block.activity_instance_id)) fail("INSTANCE_DUPLICATE", "持续活动实例重复", block.task_id, block.date);
      instanceIds.add(block.activity_instance_id);
    }
    if (protectedIds.has(block.id)) continue;
    const task = taskById.get(block.task_id), activity = task?.planning?.activity;
    if (!task || task.user_id !== document.profile.user_id) { fail("SCHEDULE_REFERENCE", "安排引用不存在或其他账号的事项", block.task_id); continue; }
    if (block.date < from || block.date > to) fail("SCHEDULE_BOUNDARY", "本期安排超出详细区间", block.task_id, block.date);
    if (block.date > task.deadline || block.date < (task.earliest_date ?? from)
      || activity?.starts_on && block.date < activity.starts_on || activity?.ends_on && block.date > activity.ends_on)
      fail("SCHEDULE_WINDOW", "安排超出事项有效日期", block.task_id, block.date);
    // Explicit rest days are resolved from the shared capacity rules, so a date override of 0
    // and a template rest day behave exactly like the scheduler's own room calculation.
    if (resolveDayCapacity(document.profile, block.date).raw_minutes === 0)
      fail("REST_DAY", "在明确休息日生成了学习安排", block.task_id, block.date);
  }
  const blocksByDate = new Map<string, PlannerDocument["blocks"]>();
  for (const block of document.blocks) {
    const list = blocksByDate.get(block.date);
    if (list) list.push(block);
    else blocksByDate.set(block.date, [block]);
  }
  for (const [date, day] of blocksByDate) {
    if (day.every(block => protectedIds.has(block.id))) continue;
    const timed = document.profile.planning_mode === "timed";
    const loadOf = (block: PlannerDocument["blocks"][number]) => Math.max(block.actual_minutes, block.duration_minutes);
    const intervalOf = (block: PlannerDocument["blocks"][number]) => [block.start_minute, block.start_minute + loadOf(block)];
    const union = (intervals: number[][]) => {
      const begin = timed ? document.profile.study_start_minute : 0, endOfDay = timed ? document.profile.study_end_minute : 1440;
      let total = 0, last = begin;
      for (const [start, end] of [...intervals].sort((a, b) => a[0] - b[0])) {
        const clippedEnd = Math.min(endOfDay, end);
        total += Math.max(0, clippedEnd - Math.max(begin, start, last)); last = Math.max(last, clippedEnd);
      }
      return total;
    };
    // Same capacity resolution as scheduleStrategy.room(); only study blocks occupy it.
    const budget = resolveDayCapacity(document.profile, date).minutes;
    const load = timed ? union(day.map(intervalOf)) : day.reduce((sum, block) => sum + loadOf(block), 0);
    const protectedLoad = timed ? union(day.filter(block => protectedIds.has(block.id)).map(intervalOf))
      : day.filter(block => protectedIds.has(block.id)).reduce((sum, block) => sum + loadOf(block), 0);
    if (load > Math.max(budget, protectedLoad)) fail("DAILY_CAPACITY", "每日安排超出有效容量", undefined, date, budget, load);
  }
  // Weekly totals and specific dates must not silently fight each other.
  for (const week of resolveWeeksInRange(document.profile, from, to)) {
    for (const conflict of week.conflicts) issues.push({ code: "WEEK_CAPACITY_CONFLICT", severity: "warning",
      date: week.monday, expected: conflict.total, actual: conflict.resolved,
      message: conflict.code === "WEEK_TOTAL_EXCEEDED"
        ? `本周已确认总量${conflict.total}分钟，但具体日期/星期设置合计${conflict.resolved}分钟；请调整或明确接受新的容量`
        : `本周已确认总量${conflict.total}分钟，但模板中没有可分配的学习日（不应把休息日重新分配）；请调整周总量或模板`,
      evidence: "每周容量覆盖、日期覆盖与默认模板", repair: "调整该周总量、具体日期或默认模板后重新预览" });
  }
  for (const date of Object.keys(document.profile.date_capacity_overrides ?? {})) {
    if (date < from || date > to) continue;
    const override = document.profile.week_capacity_overrides?.[mondayOf(date)];
    const weekDay = String(weekdayOf(date)) as "0" | "1" | "2" | "3" | "4" | "5" | "6";
    if (override?.days && override.days[weekDay] !== undefined)
      issues.push({ code: "DATE_CAPACITY_CONFLICT", severity: "warning", date,
        message: "该日期同时设置了日期覆盖和所在周的单日覆盖；日期覆盖生效，请确认保留哪一个",
        evidence: "日期容量覆盖与周容量覆盖", repair: "删除其中一个覆盖，或明确保留日期覆盖" });
  }
  return issues;
}

export function frozenInputs(session: OnboardingSession) {
  return { profile: session.profile, learning_context: session.learning_context, research: session.research,
    start_date: session.start_date, end_date: session.end_date, plan_revision: session.plan_revision,
    current_plan: session.current_plan, items: session.items,
    planning: session.planning ? { ...session.planning, detailed_until: undefined, forecast: undefined, needs_review: undefined, capacity: undefined } : null };
}

/** Independent business validation; no model or database access. */
export function checkLearningStrategy(session: OnboardingSession): QualityIssue[] {
  const issues: QualityIssue[] = [];
  const report = (code: string, message: string, item_id?: string, expected?: unknown, actual?: unknown) =>
    issues.push({ code, severity: "error", item_id, expected, actual, message,
      evidence: "已确认事项、时间预算与结构化学习策略", repair: "核对事项日期、依赖与时间预算后重新检查；缩减范围需明确说明" });
  const ids = new Set(session.items.map(item => item.id));
  const existing = Array.isArray(session.current_plan?.items) ? session.current_plan.items as Array<Record<string, unknown>> : [];
  if (ids.size !== session.items.length) report("DUPLICATE_ITEM", "事项编号重复");
  for (const item of session.items) {
    if (item.earliest_date && item.earliest_date > item.deadline) report("DATE_ORDER", "事项开始日期晚于截止日期", item.id);
    const old = existing.find(row => row.id === item.id);
    if (old && old.deadline_kind !== "plan_end" && (old.deadline !== item.deadline || item.deadline_kind === "plan_end"))
      report("HARD_DEADLINE_CHANGED", "真实截止日期及其类型不能被生成结果修改", item.id, old.deadline, item.deadline);
    // 进度只有时间口径：estimated_minutes 是唯一预算参数，内容量与内容反馈字段已移除。
    const activity = item.planning?.activity;
    if (activity?.kind === "recurring" && (!activity.starts_on || !activity.ends_on || !activity.sessions_per_week || !activity.session_minutes))
      report("RECURRENCE_DEFINITION", "持续活动需要有限窗口、每周次数和每次时长", item.id);
    if (activity?.starts_on && activity.ends_on && activity.starts_on > activity.ends_on) report("ACTIVITY_WINDOW", "活动有效区间顺序有误", item.id);
    for (const dependency of item.planning?.dependencies ?? []) {
      if (!ids.has(dependency.task_id) && !existing.some(row => row.id === dependency.task_id && !(row.archived === true || (row.archived === undefined && row.status === "archived"))))
        report("DEPENDENCY_MISSING", "前置事项不存在或已归档", item.id, dependency.task_id);
    }
  }
  const visiting = new Set<string>(), visited = new Set<string>();
  const visit = (id: string) => {
    if (visiting.has(id)) { report("DEPENDENCY_CYCLE", "事项依赖存在循环", id); return; }
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dependency of session.items.find(item => item.id === id)?.planning?.dependencies ?? []) if (ids.has(dependency.task_id)) visit(dependency.task_id);
    visiting.delete(id); visited.add(id);
  };
  ids.forEach(visit);
  for (const phase of session.planning?.route ?? []) {
    if (phase.item_ids.some(id => !ids.has(id))) report("ROUTE_REFERENCE", `「${phase.title}」引用不存在的事项`);
    if (phase.start_date && phase.end_date && phase.start_date > phase.end_date) report("ROUTE_DATES", `「${phase.title}」的日期顺序有误`);
  }
  for (const subject of session.learning_context.subjects.filter(subject => subject.weakness)) {
    const relevant = session.items.some(item => [item.title, item.description, ...item.tag_names]
      .some(value => value.toLocaleLowerCase("en-US").includes(subject.name.toLocaleLowerCase("en-US"))));
    if (!relevant)
      issues.push({ code: "WEAKNESS_COVERAGE_UNKNOWN", severity: "warning", message: `尚不能确认计划是否回应「${subject.name}」的薄弱项`,
        evidence: subject.weakness, repair: "确认相关事项或将该内容明确列入未覆盖范围" });
  }
  for (const milestone of session.planning?.milestones ?? []) {
    if (milestone.source_kind === "verified" && (typeof milestone.source_ref !== "string" || !session.research.facts.some(fact => !fact.reference_only && fact.source_url === milestone.source_ref)))
      report("MILESTONE_SOURCE", "里程碑标记为已核实，但没有对应的有效原文依据");
    if (milestone.date_precision === "day" && milestone.source_kind === "unknown")
      report("MILESTONE_PRECISION", "未知日期不能被表达为准确的一天");
  }
  return issues;
}

function emptyDocument(session: OnboardingSession): PlannerDocument {
  return { version: 1, profile: { user_id: "planning-preview", planning_mode: "daily", target_school: "", target_program: "",
    daily_limit_minutes: 480, buffer_minutes: 30, granularity_minutes: 30,
    study_start_minute: 480, study_end_minute: 1320, foundation: "" },
    tags: [], tasks: [], blocks: [], logs: [], fixed_events: [], replan_runs: [], phases: [] };
}

/** Shared trial/commit calculation. Runtime identities are supplied by the caller. */
export function buildPlanningDocument(session: OnboardingSession, current?: PlannerDocument | null, owner = "planning-preview") {
  const base = current ?? emptyDocument(session);
  if (!current) base.profile.user_id = owner;
  const before = new Set(base.blocks.map(block => block.id));
  const fixedTaskIds = new Set([...base.tasks.filter(task => task.is_fixed).map(task => task.id),
    ...base.blocks.filter(block => block.is_fixed).map(block => block.task_id)]);
  const result = replanDocument(base, session);
  const document = result.document;
  const mapping = new Map<string, string>();
  const claimed = new Set<string>();
  const normalizeTagName = (value: string) => value.normalize("NFKC").trim().toLocaleLowerCase("en-US");
  const tagByName = new Map(document.tags.map(tag => [normalizeTagName(tag.name), tag]));
  const resolveItemTags = (item: OnboardingSession["items"][number], task: PlannerDocument["tasks"][number]) => {
    const names = (item as unknown as { tag_names?: unknown }).tag_names;
    if (names === undefined) return;
    if (!Array.isArray(names)) throw new Error(`事项「${item.title}」的标签格式无效`);
    const ids: string[] = [];
    for (const raw of names) {
      if (typeof raw !== "string" || !raw.trim()) continue;
      const name = raw.normalize("NFKC").trim();
      const key = normalizeTagName(name);
      let tag = tagByName.get(key);
      if (!tag) {
        const id = `tag-${createHash("sha256").update(`${owner}:${key}`).digest("hex").slice(0, 32)}`;
        tag = { id, user_id: owner, name, created_at: new Date().toISOString(), updated_at: new Date().toISOString() };
        tagByName.set(key, tag);
        document.tags.push(tag);
      }
      if (!ids.includes(tag.id)) ids.push(tag.id);
    }
    task.tag_ids = ids;
  };
  for (const item of session.items) {
    const task = document.tasks.find(task => task.id === item.id) ?? document.tasks.find(task => !claimed.has(task.id)
      && !taskArchived(task) && task.title === item.title);
    if (task) { mapping.set(item.id, task.id); claimed.add(task.id); resolveItemTags(item, task); }
  }
  const metadata = normalizePlanningMetadata(structuredClone(session.planning ?? newPlanning()), {
    start_date: session.start_date, end_date: session.end_date });
  const full = effectivePlanMode(metadata) === "full";
  const until = full ? session.end_date
    : [session.end_date, dateAdd(session.start_date, metadata.detail_days - 1)].sort()[0];
  for (const item of session.items) {
    const task = document.tasks.find(task => task.id === mapping.get(item.id));
    if (!task) continue;
    const previous = base.tasks.find(prior => prior.id === task.id);
    if (previous && previous.deadline_kind !== "plan_end"
      && (task.deadline !== previous.deadline || task.deadline_kind === "plan_end"))
      throw new Error(`事项「${task.title}」复用了已有记录，真实截止日期及其类型不能修改`);
    const planning = item.planning === undefined ? task.planning : item.planning ? { ...structuredClone(item.planning),
      dependencies: item.planning.dependencies?.map(dep => ({ ...dep, task_id: mapping.get(dep.task_id) ?? dep.task_id })) } : null;
    if (fixedTaskIds.has(task.id)) {
      if (planningHash(planning ?? null) !== planningHash(previous?.planning ?? null))
        throw new Error(`固定事项「${task.title}」的工作量与活动策略不能修改，请先在计划中解除固定`);
      continue;
    }
    task.planning = planning;
    if (task.planning?.activity?.kind === "recurring") {
      const cycleDemand = recurringDemand(task, session.start_date, session.end_date).reduce((sum, week) => sum + week.minutes, 0);
      if (cycleDemand > 0) task.estimated_minutes = cycleDemand;
    }
  }
  applyCapacityProfile(document, session);
  metadata.route = metadata.route.map(phase => ({ ...phase, item_ids: phase.item_ids.map(id => mapping.get(id) ?? id) }));
  metadata.mode = full ? "full" : "rolling";
  metadata.rolling = !full;
  metadata.detail_days = full
    ? Math.min(PLAN_CYCLE_MAX_DAYS, inclusiveDaySpan(session.start_date, session.end_date))
    : metadata.detail_days;
  metadata.detailed_until = until;
  metadata.forecast = until >= session.end_date ? null : metadata.forecast;
  metadata.capacity = capacityMetadata(session.profile, session.start_date, session.end_date);
  metadata.frozen_inputs = { fingerprint: planningHash(frozenInputs(session)), plan_revision: session.plan_revision,
    start_date: session.start_date, end_date: session.end_date, weekly_minutes: session.profile.weekly_minutes,
    capacity_basis: session.profile.capacity_basis ?? "gross_buffer" };
  document.planning = metadata;
  // Only the trial's new allocations are replaced; every protected original record stays intact.
  document.blocks = document.blocks.filter(block => before.has(block.id));
  const runtime = () => ({ now: () => new Date(), newId: () => crypto.randomUUID() });
  let generated: ReturnType<typeof scheduleStrategy>, forecast: ReturnType<typeof scheduleStrategy>;
  if (until >= session.end_date) {
    // Full mode: one deterministic full-cycle pass; the forecast is that same allocation, so
    // there is no inverted "to be detailed later" interval and no duplicate scheduler cost.
    generated = scheduleStrategy(document, session.start_date, session.end_date, runtime());
    forecast = generated;
  } else {
    forecast = scheduleStrategy(document, session.start_date, session.end_date, runtime());
    generated = scheduleStrategy(document, session.start_date, until, runtime());
  }
  document.blocks = generated.blocks.map(block => ({ ...block }));
  const impact = buildCapacityImpact(base, document.blocks, session, mapping, forecast);
  return { document, generated, forecast, mapping, until, protectedBlocks: document.blocks.filter(block => before.has(block.id)).length, impact };
}

export function evaluatePlanning(session: OnboardingSession, current?: PlannerDocument | null, repairs = 0): { planning: PlanPlanning; preview: PlanningPreview } {
  const collected: QualityIssue[] = checkLearningStrategy(session);
  let trial: ReturnType<typeof buildPlanningDocument> | undefined;
  if (!collected.some(issue => issue.severity === "error")) {
    try { trial = buildPlanningDocument(session, current); }
    catch (error) { collected.push({ code: "SCHEDULE_CONFLICT", severity: "error", message: error instanceof Error ? error.message : "试排失败",
      evidence: "受保护记录与当前约束", repair: "保留现有记录，调整未来范围后重试" }); }
  }
  const inverse = new Map([...(trial?.mapping ?? [])].map(([draft, actual]) => [actual, draft]));
  if (trial) collected.push(...checkScheduledPlan(trial.document, session.start_date, trial.until,
    new Set(current?.blocks.map(block => block.id) ?? [])));
  for (const issue of trial?.forecast.issues ?? []) collected.push({ code: issue.code, severity: issue.code === "DEPENDENCY_INVALID" ? "error" : "warning",
    item_id: inverse.get(issue.task_id) ?? issue.task_id, date: issue.date, expected: issue.expected, actual: issue.actual,
    message: issue.message, evidence: "逐日容量、活动窗口和确认的前置条件", repair: "缩减明确范围、延后建议目标或重新确认容量；不改变真实截止日期" });
  // Full mode resolves the whole cycle in one pass; identical findings from the trial and the
  // full-cycle horizon are reported once instead of duplicated hundreds of times.
  const seenIssues = new Set<string>();
  const issues = collected.filter(issue => {
    const key = `${issue.code}|${issue.item_id ?? ""}|${issue.date ?? ""}|${issue.message}`;
    if (seenIssues.has(key)) return false;
    seenIssues.add(key);
    return true;
  });
  const normalizedPlanning = normalizePlanningMetadata(structuredClone(session.planning ?? newPlanning()), {
    start_date: session.start_date, end_date: session.end_date });
  const fingerprint = planningHash({ ...frozenInputs(session), planning: { ...normalizedPlanning,
    detailed_until: undefined, forecast: undefined, needs_review: undefined, capacity: undefined } });
  const byDate = new Map<string, PlanningPreview["days"][number]>();
  const taskById = new Map((trial?.document.tasks ?? []).map(task => [task.id, task]));
  for (const block of trial?.document.blocks ?? []) {
    if (block.date < session.start_date || block.date > (trial?.until ?? session.end_date)) continue;
    const day = byDate.get(block.date) ?? { date: block.date, minutes: 0, items: [] };
    day.minutes += block.duration_minutes;
    const task = taskById.get(block.task_id)!;
    const itemId = inverse.get(block.task_id) ?? block.task_id;
    const existing = day.items.find(item => item.item_id === itemId);
    if (existing) existing.minutes += block.duration_minutes;
    else day.items.push({ item_id: itemId, title: task.title, minutes: block.duration_minutes });
    byDate.set(block.date, day);
  }
  const mode = effectivePlanMode(trial?.document.planning ?? session.planning);
  const capacity = summarizePlanCapacity(session.profile, session.start_date, session.end_date);
  const impact: CapacityImpact = trial?.impact ?? { kept_blocks: 0, kept_minutes: 0, released_blocks: 0, released_minutes: 0,
    added_blocks: 0, added_minutes: 0, unscheduled_minutes: trial?.forecast.unscheduled_minutes ?? 0, deadline_at_risk: [] };
  const preview: PlanningPreview = { token: fingerprint, fingerprint, detailed_until: trial?.until ?? session.end_date,
    scheduled_minutes: trial?.generated.scheduled_minutes ?? 0, unscheduled_minutes: trial?.forecast.unscheduled_minutes ?? 0,
    forecast_minutes: mode === "full" ? 0
      : Math.max(0, (trial?.forecast.scheduled_minutes ?? 0) - (trial?.generated.scheduled_minutes ?? 0)),
    protected_blocks: trial?.protectedBlocks ?? 0, days: [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date)),
    issues, repairs, status: issues.some(issue => issue.severity === "error") ? "blocked" : "ready",
    mode, capacity, capacity_impact: impact };
  const planning = normalizedPlanning;
  planning.detailed_until = preview.detailed_until;
  planning.needs_review = false;
  // Full mode has no "rest of the cycle still to be detailed" interval; never emit from > to.
  planning.forecast = mode === "full" || preview.detailed_until >= session.end_date ? null
    : { from: dateAdd(preview.detailed_until, 1), to: session.end_date, minutes: preview.forecast_minutes, confirmed: false };
  planning.capacity = capacityMetadata(session.profile, session.start_date, session.end_date);
  planning.frozen_inputs = { fingerprint, plan_revision: session.plan_revision };
  planning.quality = { rules_version: PLANNING_RULES_VERSION, status: preview.status, issues, repairs };
  return { planning, preview };
}
