import { adoptedWeeklyCapacity, plusDays } from "./capacity.js";
import { scheduleStrategy } from "./planning-scheduler.js";
import {
  PLAN_CYCLE_MAX_DAYS,
  checkScheduledPlan,
  inclusiveDaySpan,
  newPlanning,
  summarizePlanCapacity,
} from "./planning-service.js";
import { isReliableWeek } from "./planner.js";
import type { OnboardingSession } from "./onboarding-contracts.js";
import type { PlanAdjustment } from "./plan-adjust-ai.js";
import { PlannerDocumentSchema, type PlannerDocument } from "./sync-contracts.js";

type Task = PlannerDocument["tasks"][number];
type Block = PlannerDocument["blocks"][number];

export class PlanAdjustmentError extends Error {
  /** 只写服务端日志的诊断信息；给用户看的 `message` 保持简短可读。 */
  readonly detail: string;
  constructor(message: string, detail = message) {
    super(message);
    this.name = "PlanAdjustmentError";
    this.detail = detail;
  }
}

/** 纯函数运行环境：时间戳与新增 id 都由调用方注入，测试无需真实时钟或 UUID。 */
export type AdjustmentRuntime = { now: () => Date; newId: () => string };
export const adjustmentRuntime: AdjustmentRuntime = {
  now: () => new Date(),
  newId: () => crypto.randomUUID(),
};

export type PlanAdjustmentPreview = {
  assessment: string;
  verdict: PlanAdjustment["verdict"];
  hours: {
    current_minutes: number;
    next_minutes: number;
    remaining_minutes: number;
    required_min_minutes: number;
    required_max_minutes: number;
  };
  cycle: {
    start_date: string;
    previous_end_date: string;
    end_date: string;
    previous_days: number;
    days: number;
    remaining_days: number;
  };
  intensity: {
    previous_weekly_minutes: number | null;
    weekly_minutes: number | null;
    reason: string;
  };
  workload: {
    updated_tasks: Array<{
      task_id: string;
      title: string;
      tag_names: string[];
      previous_minutes: number;
      minutes: number;
      reason: string;
    }>;
    new_tasks: Array<{
      title: string;
      tag_names: string[];
      minutes: number;
      deadline_kind: "deadline" | "plan_end";
      deadline: string;
      reason: string;
    }>;
    tags: Array<{
      tag_id: string;
      name: string;
      task_count: number;
      previous_minutes: number;
      minutes: number;
    }>;
    tag_totals_note: string;
  };
  schedule: {
    protected_blocks: number;
    released_blocks: number;
    released_minutes: number;
    added_blocks: number;
    added_minutes: number;
    unscheduled_minutes: number;
  };
  deadline_risks: Array<{
    task_id: string;
    title: string;
    deadline: string;
    unscheduled_minutes: number;
  }>;
  warnings: string[];
  notes: string[];
};

/** 存进 ai_jobs 的预览：客户端按设计文档 §3 从 preview 中读取 id / base_revision。 */
export type PlanAdjustmentJobPreview = PlanAdjustmentPreview & {
  id: string;
  base_revision: number;
};
export type PlanAdjustmentResult = {
  document: PlannerDocument;
  preview: PlanAdjustmentPreview;
};

const DAY_MS = 86_400_000;
const dateValue = (value: string) => Date.parse(`${value}T00:00:00Z`);
const dayCount = (start: string, end: string) =>
  end < start ? 0 : Math.round((dateValue(end) - dateValue(start)) / DAY_MS) + 1;
const clampInt = (value: number, min: number, max: number) =>
  Math.min(max, Math.max(min, Math.floor(value)));
const remainingOf = (task: Task) => Math.max(0, task.estimated_minutes - task.completed_minutes);
const deadlineKind = (task: Task) => task.deadline_kind ?? "deadline";
const isPlainDate = (value: unknown): value is string =>
  typeof value === "string" &&
  /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(dateValue(value)) &&
  new Date(dateValue(value)).toISOString().slice(0, 10) === value;

function activeTasks(document: PlannerDocument): Task[] {
  return document.tasks.filter((task) => task.status !== "archived");
}

function tagStats(document: PlannerDocument): Map<string, { task_count: number; minutes: number }> {
  const totals = new Map<string, { task_count: number; minutes: number }>();
  for (const tag of document.tags) totals.set(tag.id, { task_count: 0, minutes: 0 });
  for (const task of activeTasks(document)) for (const tagId of task.tag_ids) {
    const current = totals.get(tagId);
    if (!current) continue;
    current.task_count++;
    current.minutes += task.estimated_minutes;
  }
  return totals;
}

/**
 * 同步结构化工作量与预算。
 *
 * `PlannerDocumentSchema` 要求 finite 事项满足 `ceil(Σ quantity*minutes_per_unit) === estimated_minutes`；
 * AI 只被允许改总预算、不编造单价，所以按比例缩放各部分数量（保留单价、单位与标签）让两者继续一致。
 * 持续活动（recurring）的一致性基准是单次组成 `session_minutes`，不随总预算变化，这里不调整。
 */
function rebalanceFiniteWorkload(task: Task): boolean {
  const workload = task.planning?.workload;
  if (!workload || task.planning?.activity?.kind === "recurring") return false;
  const selected = workload.components.filter((component) => component.selected !== false);
  if (!selected.length) return false;
  const computed = selected.reduce(
    (sum, component) => sum + component.quantity * component.minutes_per_unit,
    0,
  );
  if (Math.ceil(computed) === task.estimated_minutes) return false;
  // 目标总和取 estimated-0.5：ceil 恰好等于预算，浮点误差也不会进到下一个整数。
  const target = Math.max(0.0001, task.estimated_minutes - 0.5);
  const factor = target / computed;
  for (const component of selected)
    component.quantity = Math.max(0.0001, component.quantity * factor);
  return true;
}

/** True when [end] is an acceptable plan boundary: ≥ today, within the goal date and the 1095-day cap. */
function resolveEndDate(
  ai: PlanAdjustment,
  document: PlannerDocument,
  today: string,
  warnings: string[],
): string {
  if (!isPlainDate(ai.cycle.end_date))
    throw new PlanAdjustmentError("AI 给出的规划周期结束日期无效，请重试", `end_date=${String(ai.cycle.end_date)}`);
  if (ai.cycle.end_date < today)
    throw new PlanAdjustmentError("AI 给出的规划周期结束日期早于今天，请重试", `end_date=${ai.cycle.end_date}, today=${today}`);
  const start = document.profile.plan_start_date ?? today;
  const target =
    document.profile.target_date && document.profile.target_date >= today
      ? document.profile.target_date
      : null;
  const hardCap = plusDays(today, PLAN_CYCLE_MAX_DAYS);
  const spanCap = plusDays(start, PLAN_CYCLE_MAX_DAYS - 1);
  if (spanCap < today)
    throw new PlanAdjustmentError(
      "当前规划周期的开始日期距今已超过 1095 天，无法继续延长周期；请重新生成计划",
      `start=${start}, spanCap=${spanCap}, today=${today}`,
    );
  const cap = [hardCap, spanCap, ...(target ? [target] : [])].sort()[0];
  let end = ai.cycle.end_date;
  if (end > cap) {
    if (target && cap === target)
      warnings.push(`AI 建议的周期结束日期晚于目标日期，已截断到目标日期 ${target}`);
    else warnings.push(`规划周期最长 ${PLAN_CYCLE_MAX_DAYS} 天，结束日期已截断到 ${cap}`);
    end = cap;
  }
  if (end < start)
    throw new PlanAdjustmentError(
      "AI 给出的新周期结束日期早于周期开始日期，请重试",
      `end=${end}, start=${start}`,
    );
  return end;
}

/**
 * 把 AI 输出应用到当前文档（设计文档 §5）。
 *
 * 纯函数：不修改入参、不访问数据库、不在失败时返回半成品。任何硬约束不满足都抛
 * `PlanAdjustmentError`，路由映射 422 并保留原计划。规则顺序为
 * 周期 → 强度 → 事项预算 → 新增事项/课程 → planning 元数据 → 释放并重排 → 预览统计。
 */
export function applyPlanAdjustment(
  source: PlannerDocument,
  ai: PlanAdjustment,
  today: string,
  runtime: AdjustmentRuntime = adjustmentRuntime,
): PlanAdjustmentResult {
  if (!isPlainDate(today))
    throw new PlanAdjustmentError("无法确定今天的日期，请重试", `today=${String(today)}`);
  if (ai.required_minutes.min > ai.required_minutes.max)
    throw new PlanAdjustmentError(
      "AI 给出的目标所需总时长区间不合法，请重试",
      `required_minutes=${JSON.stringify(ai.required_minutes)}`,
    );

  const before = structuredClone(source);
  const document = structuredClone(source);
  const owner = document.profile.user_id;
  const stamp = runtime.now().toISOString();
  const warnings: string[] = [];
  const notes: string[] = [];
  const startDate = before.profile.plan_start_date ?? today;
  const previousEnd = before.profile.plan_end_date ?? before.profile.target_date ?? plusDays(today, 27);
  const currentMinutes = activeTasks(before).reduce((sum, task) => sum + task.estimated_minutes, 0);

  // §5.1 周期：开始日期不变；结束日期受今天、目标日期和 1095 天上限约束。
  const endDate = resolveEndDate(ai, before, today, warnings);
  document.profile.plan_end_date = endDate;
  if (endDate !== previousEnd) notes.push(`规划周期结束日期由 ${previousEnd} 调整为 ${endDate}`);
  else notes.push(`规划周期结束日期保持 ${endDate}`);

  // plan_end 类事项随周期边界移动；真实截止日期（deadline）绝不修改。
  let followedPlanEnd = 0;
  for (const task of document.tasks) {
    if (deadlineKind(task) !== "plan_end") continue;
    if (task.is_fixed || task.status === "archived" || task.status === "completed") continue;
    if (task.earliest_date && endDate < task.earliest_date) {
      warnings.push(`「${task.title}」的最早开始日期晚于新周期结束日期，保留原截止日期 ${task.deadline}`);
      continue;
    }
    if (task.deadline !== endDate) {
      task.deadline = endDate;
      task.updated_at = stamp;
      followedPlanEnd++;
    }
    // 周期拉长时同步延长活动窗口：否则 scheduler 会停在旧窗口，延长出来的时间仍排不进内容。
    const activity = task.planning?.activity;
    if (activity?.ends_on !== undefined && activity.ends_on < endDate) activity.ends_on = endDate;
  }
  if (followedPlanEnd) notes.push(`${followedPlanEnd} 个 plan_end 事项的截止日期已跟随新周期`);
  // 周期拉长时，原本结束于旧周期边界的活动窗口必须一起延展，否则延长出来的时间排不进已有事项；
  // 窄于旧周期边界的自定义窗口保持不变（那是有意的范围），真实截止日期仍然限制排程。
  let extendedWindows = 0;
  for (const task of document.tasks) {
    if (deadlineKind(task) !== "deadline") continue;
    if (task.is_fixed || task.status === "archived" || task.status === "completed") continue;
    const activity = task.planning?.activity;
    if (!activity?.ends_on || activity.ends_on !== previousEnd || activity.ends_on >= endDate) continue;
    activity.ends_on = endDate;
    extendedWindows++;
  }
  if (extendedWindows) notes.push(`${extendedWindows} 个事项的活动窗口已随新周期延展`);

  // §5.2 强度：写入逐日模板并清空 baseline/range（旧口径不再覆盖新模板）。
  if (ai.intensity) {
    const currentTemplate = isReliableWeek(before.profile.weekly_minutes) ? before.profile.weekly_minutes : null;
    const weekly = ai.intensity.weekly_minutes as Record<string, number | undefined>;
    const template = Object.fromEntries(
      [0, 1, 2, 3, 4, 5, 6].map((day) => [
        String(day),
        clampInt(weekly[String(day)] ?? currentTemplate?.[String(day)] ?? 0, 0, 1440),
      ]),
    );
    document.profile.weekly_minutes = template;
    document.profile.weekly_baseline_minutes = null;
    document.profile.weekly_range_min_minutes = null;
    document.profile.weekly_range_max_minutes = null;
    document.profile.daily_limit_minutes = clampInt(Math.max(...Object.values(template)), 30, 1440);
    const weeklyTotal = Object.values(template).reduce((sum, value) => sum + value, 0);
    notes.push(`学习强度调整为每周 ${weeklyTotal} 分钟（每天 0–1440 分钟，0 表示休息）`);
    if (
      Object.keys(document.profile.week_capacity_overrides ?? {}).length +
        Object.keys(document.profile.date_capacity_overrides ?? {}).length >
      0
    )
      notes.push("已有的周容量/日期容量覆盖仍然生效，实际每日可用时间以覆盖为准");
  } else {
    notes.push("本次未调整每周学习强度");
  }

  // §5.3 事项预算：只改未归档、非固定、未完成事项的 estimated_minutes，且不低于已完成分钟。
  const beforeTaskById = new Map(before.tasks.map((task) => [task.id, task]));
  const updatedTasks = new Map<
    string,
    { previous: number; minutes: number; reason: string }
  >();
  let rebalancedWorkloads = 0;
  for (const update of ai.task_updates) {
    const task = document.tasks.find((row) => row.id === update.task_id);
    if (!task) {
      warnings.push(`忽略未知事项的预算调整（${update.task_id}）`);
      continue;
    }
    if (task.is_fixed) {
      warnings.push(`「${task.title}」是固定事项，预算未改动`);
      continue;
    }
    if (task.status === "archived") {
      warnings.push(`「${task.title}」已归档，预算未改动`);
      continue;
    }
    if (task.status === "completed") {
      warnings.push(`「${task.title}」已完成，预算未改动`);
      continue;
    }
    const value = Math.min(10_000_000, Math.max(update.estimated_minutes, task.completed_minutes));
    if (value > update.estimated_minutes)
      warnings.push(`「${task.title}」的新预算低于已完成分钟，已按 ${value} 分钟保留`);
    if (value !== task.estimated_minutes) {
      task.estimated_minutes = value;
      task.updated_at = stamp;
      // 文档带 planning 元数据时 schema 会校验工作量一致性，必须同时缩放结构化组成。
      if (document.planning && rebalanceFiniteWorkload(task)) rebalancedWorkloads++;
    }
    const original = beforeTaskById.get(task.id)?.estimated_minutes ?? value;
    if (task.estimated_minutes !== original) {
      const existing = updatedTasks.get(task.id);
      updatedTasks.set(task.id, {
        previous: existing?.previous ?? original,
        minutes: task.estimated_minutes,
        reason: update.reason,
      });
    }
  }

  if (rebalancedWorkloads)
    notes.push(`${rebalancedWorkloads} 个事项的结构化工作量已按新预算等比例同步`);

  // AI returns names only. Resolve existing labels case-insensitively and assign server IDs.
  const tagByName = new Map(document.tags.map(tag => [tag.name.trim().toLowerCase(), tag]));
  const resolveTagNames = (names: readonly string[]) => [...new Set(names.map(name => name.trim()).filter(Boolean))].map(name => {
    const key = name.toLowerCase();
    let tag = tagByName.get(key);
    if (!tag) {
      tag = { id: runtime.newId(), user_id: owner, name, color: null };
      tagByName.set(key, tag);
      document.tags.push(tag);
    }
    return tag.id;
  });
  const createdTasks: Array<{ task: Task; reason: string }> = [];
  for (const spec of ai.new_tasks) {
    const tagIds = resolveTagNames(spec.tag_names);
    let deadline: string;
    if (spec.deadline_kind === "plan_end") deadline = endDate;
    else {
      if (!spec.deadline || !isPlainDate(spec.deadline))
        throw new PlanAdjustmentError(
          `AI 新增事项「${spec.title}」缺少有效的真实截止日期，请重试`,
          `new_tasks key=${spec.key} deadline=${String(spec.deadline)}`,
        );
      if (spec.deadline < today)
        throw new PlanAdjustmentError(
          `AI 新增事项「${spec.title}」的真实截止日期早于今天，请重试`,
          `new_tasks key=${spec.key} deadline=${spec.deadline}`,
        );
      deadline = spec.deadline;
    }
    if (spec.earliest_date && spec.earliest_date > deadline)
      throw new PlanAdjustmentError(
        `AI 新增事项「${spec.title}」的最早开始日期晚于截止日期，请重试`,
        `new_tasks key=${spec.key} earliest=${spec.earliest_date} deadline=${deadline}`,
      );
    const task: Task = {
      id: runtime.newId(),
      user_id: owner,
      tag_ids: tagIds,
      title: spec.title,
      description: spec.description,
      estimated_minutes: spec.estimated_minutes,
      completed_minutes: 0,
      priority: spec.priority as 1 | 2 | 3,
      deadline,
      deadline_kind: spec.deadline_kind,
      ...(spec.earliest_date ? { earliest_date: spec.earliest_date } : {}),
      is_fixed: false,
      status: "not_started",
      created_at: stamp,
      updated_at: stamp,
    };
    document.tasks.push(task);
    createdTasks.push({ task, reason: spec.reason });
  }

  // §5.5 planning：保留路线/里程碑/假设，切换为全周期模式并写入容量摘要。
  const planning = structuredClone(document.planning ?? newPlanning());
  planning.mode = "full";
  planning.rolling = false;
  planning.detail_days = Math.max(
    1,
    Math.min(PLAN_CYCLE_MAX_DAYS, inclusiveDaySpan(startDate, endDate)),
  );
  planning.detailed_until = endDate;
  planning.forecast = null;
  planning.needs_review = false;
  planning.quality = null;
  planning.capacity = summarizePlanCapacity(
    document.profile as unknown as OnboardingSession["profile"],
    startDate,
    endDate,
  ) as unknown as Record<string, unknown>;
  const assumptions = [
    ...(ai.cycle.reason ? [`周期调整：${ai.cycle.reason}`] : []),
    ...(ai.intensity ? [`强度调整：${ai.intensity.reason}`] : []),
  ].map((value) => value.slice(0, 2000));
  planning.assumptions = [...planning.assumptions, ...assumptions].slice(-100);
  planning.risks = [...planning.risks, ...ai.warnings].slice(-100);
  document.planning = planning;
  if (ai.cycle.reason) notes.push(`周期调整理由：${ai.cycle.reason}`);
  if (ai.intensity?.reason) notes.push(`强度调整理由：${ai.intensity.reason}`);

  // §5.6 释放今天及以后所有可调整块，保留历史/固定/完成/有实际执行/有日志引用/固定完成归档事项的块。
  const loggedBlockIds = new Set(
    document.logs
      .map((log) => log.block_id)
      .filter((blockId): blockId is string => Boolean(blockId)),
  );
  const loggedTaskDates = new Set(
    document.logs
      .filter((log) => !log.block_id && log.task_id)
      .map((log) => `${log.task_id}:${log.date}`),
  );
  const taskById = new Map(document.tasks.map((task) => [task.id, task]));
  const protectedIds = new Set<string>();
  for (const block of document.blocks) {
    const task = taskById.get(block.task_id);
    const guarded =
      block.date < today ||
      block.is_fixed ||
      block.status === "completed" ||
      block.actual_minutes > 0 ||
      loggedBlockIds.has(block.id) ||
      loggedTaskDates.has(`${block.task_id}:${block.date}`) ||
      !task ||
      task.is_fixed ||
      task.status === "completed" ||
      task.status === "archived";
    if (guarded) protectedIds.add(block.id);
  }
  const released: Block[] = document.blocks.filter((block) => !protectedIds.has(block.id));
  const releasedMinutes = released.reduce((sum, block) => sum + block.duration_minutes, 0);
  document.blocks = document.blocks.filter((block) => protectedIds.has(block.id));
  if (released.length)
    notes.push(`释放 ${released.length} 个可调整时间块（${releasedMinutes} 分钟）并按新周期重排`);
  const scheduleFrom = startDate > today ? startDate : today;
  const scheduled = scheduleStrategy(document, scheduleFrom, endDate, runtime);
  // 展开成新的字面量对象，避免 StrategyBlock（无索引签名）与同步文档 block 类型不兼容。
  document.blocks = scheduled.blocks.map((block) => ({ ...block }));
  // §5.6 校验：error 级问题写入 warnings；正常不应出现。
  for (const issue of checkScheduledPlan(document, today, endDate, protectedIds)) {
    if (issue.severity === "error") warnings.push(`排程校验：${issue.message}`);
  }
  if (scheduled.unscheduled_minutes > 0)
    warnings.push(`新周期内仍有 ${scheduled.unscheduled_minutes} 分钟未能安排，请检查容量与事项日期`);

  // §5.7 预览统计：所有数值由服务端计算，客户端只负责展示。
  const nextTasks = activeTasks(document);
  const nextMinutes = nextTasks.reduce((sum, task) => sum + task.estimated_minutes, 0);
  const remainingMinutes = nextTasks.reduce((sum, task) => sum + remainingOf(task), 0);
  if (ai.required_minutes.min > 0 && nextMinutes < ai.required_minutes.min)
    warnings.push("调整后总时长仍低于目标所需下限");
  if (ai.required_minutes.max > 0 && nextMinutes > ai.required_minutes.max)
    warnings.push("调整后总时长仍高于目标所需上限");

  const beforeTagStats = tagStats(before);
  const afterTagStats = tagStats(document);
  const tagName = new Map(document.tags.map((tag) => [tag.id, tag.name]));
  const workloadTags = document.tags
    .map((tag) => ({
      tag_id: tag.id,
      name: tag.name,
      task_count: afterTagStats.get(tag.id)?.task_count ?? 0,
      previous_minutes: beforeTagStats.get(tag.id)?.minutes ?? 0,
      minutes: afterTagStats.get(tag.id)?.minutes ?? 0,
    }))
    .filter((row) => row.previous_minutes !== row.minutes || (beforeTagStats.get(row.tag_id)?.task_count ?? 0) !== row.task_count);

  const loggedMinutes = new Map<string, number>();
  for (const log of document.logs)
    if (log.task_id)
      loggedMinutes.set(log.task_id, (loggedMinutes.get(log.task_id) ?? 0) + log.minutes);
  const finalBlocksByTask = new Map<string, Block[]>();
  for (const block of document.blocks)
    finalBlocksByTask.set(block.task_id, [...(finalBlocksByTask.get(block.task_id) ?? []), block]);
  const deadlineRisks: PlanAdjustmentPreview["deadline_risks"] = [];
  for (const task of nextTasks) {
    if (deadlineKind(task) !== "deadline") continue;
    if (task.deadline < today || task.deadline > endDate) continue;
    const completed = Math.max(task.completed_minutes, loggedMinutes.get(task.id) ?? 0);
    const scheduledBefore = (finalBlocksByTask.get(task.id) ?? [])
      .filter((block) => block.date >= today && block.date <= task.deadline)
      .reduce((sum, block) => sum + block.duration_minutes, 0);
    const pending = Math.max(0, task.estimated_minutes - completed - scheduledBefore);
    if (pending > 0)
      deadlineRisks.push({
        task_id: task.id,
        title: task.title,
        deadline: task.deadline,
        unscheduled_minutes: pending,
      });
  }

  notes.push("真实截止日期、固定事项、已完成记录与历史安排均未改动");
  if (createdTasks.length) {
    const createdMinutes = createdTasks.reduce((sum, { task }) => sum + task.estimated_minutes, 0);
    notes.push(`新增 ${createdTasks.length} 个事项，共 ${createdMinutes} 分钟`);
  }

  const preview: PlanAdjustmentPreview = {
    assessment: ai.assessment,
    verdict: ai.verdict,
    hours: {
      current_minutes: currentMinutes,
      next_minutes: nextMinutes,
      remaining_minutes: remainingMinutes,
      required_min_minutes: ai.required_minutes.min,
      required_max_minutes: ai.required_minutes.max,
    },
    cycle: {
      start_date: startDate,
      previous_end_date: previousEnd,
      end_date: endDate,
      previous_days: Math.max(1, dayCount(startDate, previousEnd)),
      days: dayCount(startDate, endDate),
      remaining_days: dayCount(today, endDate),
    },
    intensity: {
      previous_weekly_minutes: adoptedWeeklyCapacity(before.profile).minutes,
      weekly_minutes: adoptedWeeklyCapacity(document.profile).minutes,
      reason: ai.intensity?.reason ?? "本次未调整每周学习强度",
    },
    workload: {
      updated_tasks: [...updatedTasks.entries()].map(([taskId, change]) => {
        const task = document.tasks.find((row) => row.id === taskId)!;
        return {
          task_id: taskId,
          title: task.title,
          tag_names: task.tag_ids.map(id => tagName.get(id)).filter((name): name is string => Boolean(name)),
          previous_minutes: change.previous,
          minutes: change.minutes,
          reason: change.reason,
        };
      }),
      new_tasks: createdTasks.map(({ task, reason }) => ({
        title: task.title,
        tag_names: task.tag_ids.map(id => tagName.get(id)).filter((name): name is string => Boolean(name)),
        minutes: task.estimated_minutes,
        deadline_kind: deadlineKind(task) as "deadline" | "plan_end",
        deadline: task.deadline,
        reason,
      })),
      tags: workloadTags,
      tag_totals_note: "按标签分别统计，同一事项可属于多个标签，因此不同标签的分钟数不能相加。",
    },
    schedule: {
      protected_blocks: protectedIds.size,
      released_blocks: released.length,
      released_minutes: releasedMinutes,
      added_blocks: scheduled.added,
      added_minutes: scheduled.scheduled_minutes,
      unscheduled_minutes: scheduled.unscheduled_minutes,
    },
    deadline_risks: deadlineRisks,
    warnings: [...new Set([...warnings, ...ai.warnings])],
    notes: [...new Set(notes)],
  };

  // 最终文档必须能通过同步契约校验：非法方案整体拒绝，不产生可部分应用的半成品。
  try {
    return { document: PlannerDocumentSchema.parse(document), preview };
  } catch (error) {
    throw new PlanAdjustmentError(
      "调整后的计划未通过校验，请重试",
      error instanceof Error ? error.message : String(error),
    );
  }
}

/** 设计文档 §5 使用 `applyAdjustment` 名称，提供别名避免契约文本与实现命名不一致。 */
export const applyAdjustment = applyPlanAdjustment;
