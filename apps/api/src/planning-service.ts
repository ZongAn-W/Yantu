import { createHash } from "node:crypto";
import type { OnboardingSession } from "./onboarding-contracts.js";
import type { PlanPlanning } from "./planning-contracts.js";
import type { PlannerDocument } from "./sync-contracts.js";
import { dateAdd, replanDocument } from "./planner.js";
import { recurringDemand, scheduleStrategy } from "./planning-scheduler.js";

export const PLANNING_PROMPT_VERSION = "learning-route-1";
export const PLANNING_RULES_VERSION = "workload-rhythm-1";
export type QualityIssue = {
  code: string; severity: "error" | "warning" | "info"; item_id?: string; date?: string;
  expected?: unknown; actual?: unknown; message: string; evidence: string; repair: string;
};
export type PlanningPreview = {
  token: string; detailed_until: string; scheduled_minutes: number; unscheduled_minutes: number;
  protected_blocks: number; days: Array<{ date: string; minutes: number; items: Array<{ item_id: string; title: string; minutes: number }> }>;
  issues: QualityIssue[]; repairs: number; status: "ready" | "blocked"; fingerprint: string;
  forecast_minutes: number;
};

function canonical(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !["updated_at", "created_at", "quality", "frozen_inputs"].includes(key))
    .sort(([a], [b]) => a.localeCompare(b)).map(([key, item]) => [key, canonical(item)]));
  return value;
}
export const planningHash = (value: unknown) => createHash("sha256").update(JSON.stringify(canonical(value))).digest("hex");

export function workloadMinutes(workload: NonNullable<OnboardingSession["items"][number]["planning"]>["workload"]) {
  return workload ? Math.ceil(workload.components.filter(component => component.selected !== false)
    .reduce((total, component) => total + component.quantity * component.minutes_per_unit, 0)) : null;
}

export function newPlanning(): PlanPlanning {
  return { version: 1, prompt_version: PLANNING_PROMPT_VERSION, rules_version: PLANNING_RULES_VERSION,
    detail_days: 14, rolling: true, route: [], milestones: [], assumptions: [], risks: [], uncovered: [] };
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
    const raw = document.profile.weekly_minutes?.[String(new Date(`${block.date}T00:00:00Z`).getUTCDay())] ?? document.profile.daily_limit_minutes;
    if (raw === 0) fail("REST_DAY", "在明确休息日生成了学习安排", block.task_id, block.date);
  }
  for (const date of new Set(document.blocks.filter(block => !protectedIds.has(block.id)).map(block => block.date))) {
    const day = document.blocks.filter(block => block.date === date);
    const weekday = new Date(`${date}T00:00:00Z`).getUTCDay();
    const events = document.fixed_events.filter(event => date >= event.date && (date === event.date || event.repeat === "daily"
      || event.repeat === "weekly" && new Date(`${event.date}T00:00:00Z`).getUTCDay() === weekday));
    const timed = document.profile.planning_mode === "timed";
    const loadOf = (block: PlannerDocument["blocks"][number]) => Math.max(block.actual_minutes, block.duration_minutes);
    const intervalOf = (block: PlannerDocument["blocks"][number]) => [block.start_minute, block.start_minute + loadOf(block)];
    const eventIntervals = events.map(event => [event.start_minute, event.start_minute + event.duration_minutes]);
    const union = (intervals: number[][]) => {
      const begin = timed ? document.profile.study_start_minute : 0, endOfDay = timed ? document.profile.study_end_minute : 1440;
      let total = 0, last = begin;
      for (const [start, end] of [...intervals].sort((a, b) => a[0] - b[0])) {
        const clippedEnd = Math.min(endOfDay, end);
        total += Math.max(0, clippedEnd - Math.max(begin, start, last)); last = Math.max(last, clippedEnd);
      }
      return total;
    };
    const fixed = union(eventIntervals);
    const budget = Math.max(0, Math.min(480, document.profile.weekly_minutes?.[String(weekday)] ?? document.profile.daily_limit_minutes)
      - Math.max(30, document.profile.buffer_minutes) - fixed);
    const load = timed ? union([...eventIntervals, ...day.map(intervalOf)]) - fixed : day.reduce((sum, block) => sum + loadOf(block), 0);
    const protectedLoad = timed ? union([...eventIntervals, ...day.filter(block => protectedIds.has(block.id)).map(intervalOf)]) - fixed
      : day.filter(block => protectedIds.has(block.id)).reduce((sum, block) => sum + loadOf(block), 0);
    if (load > Math.max(budget, protectedLoad)) fail("DAILY_CAPACITY", "每日安排超出有效容量", undefined, date, budget, load);
    for (const subject of new Set(day.map(block => taskById.get(block.task_id)?.subject_id))) {
      const courseBlocks = day.filter(block => taskById.get(block.task_id)?.subject_id === subject);
      const amount = timed ? union(courseBlocks.map(intervalOf)) : courseBlocks.reduce((sum, block) => sum + loadOf(block), 0);
      const protectedAmount = timed ? union(courseBlocks.filter(block => protectedIds.has(block.id)).map(intervalOf))
        : courseBlocks.filter(block => protectedIds.has(block.id)).reduce((sum, block) => sum + loadOf(block), 0);
      if (amount > Math.max(Math.min(240, document.profile.subject_limit_minutes), protectedAmount))
        fail("COURSE_CAPACITY", "同课程安排超出每日上限", undefined, date, Math.min(240, document.profile.subject_limit_minutes), amount);
    }
  }
  return issues;
}

export function frozenInputs(session: OnboardingSession) {
  return { profile: session.profile, learning_context: session.learning_context, research: session.research,
    start_date: session.start_date, end_date: session.end_date, plan_revision: session.plan_revision,
    current_plan: session.current_plan, courses: session.courses, items: session.items,
    planning: session.planning ? { ...session.planning, detailed_until: undefined, forecast: undefined, needs_review: undefined } : null };
}

/** Independent business validation; no model or database access. */
export function checkLearningStrategy(session: OnboardingSession): QualityIssue[] {
  const issues: QualityIssue[] = [];
  const report = (code: string, message: string, item_id?: string, expected?: unknown, actual?: unknown) =>
    issues.push({ code, severity: "error", item_id, expected, actual, message,
      evidence: "已确认事项及结构化学习范围", repair: "核对工作量或事项引用后重新检查；缩减范围需明确说明" });
  const ids = new Set(session.items.map(item => item.id)), courses = new Set(session.courses.map(course => course.id));
  const existing = Array.isArray(session.current_plan?.items) ? session.current_plan.items as Array<Record<string, unknown>> : [];
  const evidenceIds = new Set([...session.answers.map((_, index) => `answer:${index}`), ...session.research.sources.map(source => source.url)]);
  if (ids.size !== session.items.length) report("DUPLICATE_ITEM", "事项编号重复");
  for (const item of session.items) {
    if (!courses.has(item.course_id)) report("COURSE_REFERENCE", "事项引用的课程不存在", item.id);
    if (item.earliest_date && item.earliest_date > item.deadline) report("DATE_ORDER", "事项开始日期晚于截止日期", item.id);
    const old = existing.find(row => row.id === item.id);
    if (old && old.deadline_kind !== "plan_end" && (old.deadline !== item.deadline || item.deadline_kind === "plan_end"))
      report("HARD_DEADLINE_CHANGED", "真实截止日期及其类型不能被生成结果修改", item.id, old.deadline, item.deadline);
    const planning = item.planning;
    const previousPlanning = old?.planning as Record<string, unknown> | undefined;
    if (planning?.content_progress && planningHash(planning.content_progress) !== planningHash(previousPlanning?.content_progress ?? null)
      || planning?.feedback && planningHash(planning.feedback) !== planningHash(previousPlanning?.feedback ?? null))
      report("EXECUTION_FACT_CHANGED", "规划草案不能虚构或修改已经发生的内容进度和困难反馈", item.id);
    if (!planning) {
      issues.push({ code: "LEGACY_ESTIMATE", severity: "warning", item_id: item.id, message: `「${item.title}」仍使用总时长估算，范围需要核对`,
        evidence: "未提供结构化工作量", repair: "补充学习单位和数量，或先校准少量内容" });
      continue;
    }
    const a = planning.activity;
    if (a?.kind === "recurring" && (!a.starts_on || !a.ends_on || !a.sessions_per_week || !a.session_minutes))
      report("RECURRENCE_DEFINITION", "持续活动需要有限窗口、每周次数和每次时长", item.id);
    if (a?.starts_on && a.ends_on && a.starts_on > a.ends_on) report("ACTIVITY_WINDOW", "活动有效区间顺序有误", item.id);
    const expected = workloadMinutes(planning.workload);
    if (expected !== null) {
      for (const ref of planning.workload!.evidence_refs ?? []) if (!evidenceIds.has(ref))
        report("EVIDENCE_REFERENCE", "工作量引用的回答或资料不存在", item.id, [...evidenceIds], ref);
      const declared = a?.kind === "recurring" ? a.session_minutes : item.estimated_minutes;
      if (expected !== declared) report("WORKLOAD_MISMATCH", `「${item.title}」的工作量计算为${expected}分钟，与声明时长不一致`, item.id, expected, declared);
      const components = planning.workload!.components;
      if (new Set(components.map(c => c.id)).size !== components.length) report("COMPONENT_DUPLICATE", "工作量组成编号重复", item.id);
      if (!components.some(c => c.selected !== false)) report("WORKLOAD_EMPTY", "至少选择一种实际学习范围", item.id);
      for (const component of components) {
        if (component.range_min !== undefined && component.minutes_per_unit < component.range_min
          || component.range_max !== undefined && component.minutes_per_unit > component.range_max
          || component.range_min !== undefined && component.range_max !== undefined && component.range_min > component.range_max)
          report("WORKLOAD_RANGE", "采用的单位时长不在声明区间内", item.id);
      }
    } else issues.push({ code: "WORKLOAD_UNKNOWN", severity: "warning", item_id: item.id,
      message: `「${item.title}」的单位工作量尚待校准`, evidence: "缺少材料或学习速度", repair: "先做少量诊断，再根据实际内容进度调整" });
    for (const dependency of planning.dependencies ?? []) {
      if (!ids.has(dependency.task_id) && !existing.some(row => row.id === dependency.task_id && row.status !== "archived"))
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
    if (!session.courses.some(course => course.name.includes(subject.name) || subject.name.includes(course.name)))
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
    daily_limit_minutes: 480, buffer_minutes: 30, granularity_minutes: 30, subject_limit_minutes: 240,
    study_start_minute: 480, study_end_minute: 1320, foundation: "" },
    subjects: [], tasks: [], blocks: [], logs: [], fixed_events: [], replan_runs: [], phases: [] };
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
  for (const item of session.items) {
    const task = document.tasks.find(task => task.id === item.id) ?? document.tasks.find(task => !claimed.has(task.id)
      && task.status !== "archived" && task.title === item.title
      && document.subjects.find(subject => subject.id === task.subject_id)?.name === session.courses.find(course => course.id === item.course_id)?.name);
    if (task) { mapping.set(item.id, task.id); claimed.add(task.id); }
  }
  const metadata = structuredClone(session.planning ?? newPlanning());
  const until = metadata.rolling ? [session.end_date, dateAdd(session.start_date, metadata.detail_days - 1)].sort()[0] : session.end_date;
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
    if (previous?.planning?.feedback || previous?.planning?.content_progress) task.planning = { ...task.planning,
      ...(previous.planning.feedback ? { feedback: structuredClone(previous.planning.feedback) } : {}),
      ...(previous.planning.content_progress ? { content_progress: structuredClone(previous.planning.content_progress) } : {}) };
    if (task.planning?.activity?.kind === "recurring") {
      const cycleDemand = recurringDemand(task, session.start_date, session.end_date).reduce((sum, week) => sum + week.minutes, 0);
      if (cycleDemand > 0) task.estimated_minutes = cycleDemand;
    }
  }
  metadata.route = metadata.route.map(phase => ({ ...phase, item_ids: phase.item_ids.map(id => mapping.get(id) ?? id) }));
  metadata.detailed_until = until;
  metadata.frozen_inputs = { fingerprint: planningHash(frozenInputs(session)), plan_revision: session.plan_revision,
    start_date: session.start_date, end_date: session.end_date, weekly_minutes: session.profile.weekly_minutes };
  document.planning = metadata;
  // Only the trial's new allocations are replaced; every protected original record stays intact.
  document.blocks = document.blocks.filter(block => before.has(block.id));
  const forecast = scheduleStrategy(document, session.start_date, session.end_date,
    { now: () => new Date(), newId: () => crypto.randomUUID() });
  const generated = scheduleStrategy(document, session.start_date, until,
    { now: () => new Date(), newId: () => crypto.randomUUID() });
  document.blocks = generated.blocks.map(block => ({ ...block }));
  return { document, generated, forecast, mapping, until, protectedBlocks: document.blocks.filter(block => before.has(block.id)).length };
}

export function evaluatePlanning(session: OnboardingSession, current?: PlannerDocument | null, repairs = 0): { planning: PlanPlanning; preview: PlanningPreview } {
  const issues = checkLearningStrategy(session);
  let trial: ReturnType<typeof buildPlanningDocument> | undefined;
  if (!issues.some(issue => issue.severity === "error")) {
    try { trial = buildPlanningDocument(session, current); }
    catch (error) { issues.push({ code: "SCHEDULE_CONFLICT", severity: "error", message: error instanceof Error ? error.message : "试排失败",
      evidence: "受保护记录与当前约束", repair: "保留现有记录，调整未来范围后重试" }); }
  }
  const inverse = new Map([...(trial?.mapping ?? [])].map(([draft, actual]) => [actual, draft]));
  if (trial) issues.push(...checkScheduledPlan(trial.document, session.start_date, trial.until,
    new Set(current?.blocks.map(block => block.id) ?? [])));
  for (const issue of trial?.forecast.issues ?? []) issues.push({ code: issue.code, severity: issue.code === "DEPENDENCY_INVALID" ? "error" : "warning",
    item_id: inverse.get(issue.task_id) ?? issue.task_id, date: issue.date, expected: issue.expected, actual: issue.actual,
    message: issue.message, evidence: "逐日容量、活动窗口和确认的前置条件", repair: "缩减明确范围、延后建议目标或重新确认容量；不改变真实截止日期" });
  const fingerprint = planningHash(frozenInputs(session));
  const byDate = new Map<string, PlanningPreview["days"][number]>();
  for (const block of trial?.document.blocks ?? []) {
    if (block.date < session.start_date || block.date > (trial?.until ?? session.end_date)) continue;
    const day = byDate.get(block.date) ?? { date: block.date, minutes: 0, items: [] };
    day.minutes += block.duration_minutes;
    const task = trial!.document.tasks.find(task => task.id === block.task_id)!;
    const itemId = inverse.get(block.task_id) ?? block.task_id;
    const existing = day.items.find(item => item.item_id === itemId);
    if (existing) existing.minutes += block.duration_minutes;
    else day.items.push({ item_id: itemId, title: task.title, minutes: block.duration_minutes });
    byDate.set(block.date, day);
  }
  const preview: PlanningPreview = { token: fingerprint, fingerprint, detailed_until: trial?.until ?? session.end_date,
    scheduled_minutes: trial?.generated.scheduled_minutes ?? 0, unscheduled_minutes: trial?.forecast.unscheduled_minutes ?? 0,
    forecast_minutes: Math.max(0, (trial?.forecast.scheduled_minutes ?? 0) - (trial?.generated.scheduled_minutes ?? 0)),
    protected_blocks: trial?.protectedBlocks ?? 0, days: [...byDate.values()].sort((a, b) => a.date.localeCompare(b.date)),
    issues, repairs, status: issues.some(issue => issue.severity === "error") ? "blocked" : "ready" };
  const planning = structuredClone(session.planning ?? newPlanning());
  planning.detailed_until = preview.detailed_until;
  planning.needs_review = false;
  planning.forecast = { from: dateAdd(preview.detailed_until, 1), to: session.end_date,
    minutes: preview.forecast_minutes, confirmed: false };
  planning.frozen_inputs = { fingerprint, plan_revision: session.plan_revision };
  planning.quality = { rules_version: PLANNING_RULES_VERSION, status: preview.status, issues, repairs };
  return { planning, preview };
}
