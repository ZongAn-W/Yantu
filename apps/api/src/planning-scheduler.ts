import {
  blockQuantum,
  hasConfirmedWeekBudget,
  isNetCapacity,
  minBlockMinutes,
  resolveDayCapacity,
  type CapacityProfile,
} from "./capacity.js";

/** Pure scheduling contract shared by the API and TypeScript reference fixtures. */
export type {
  CapacityBasis,
  CapacityConflict,
  CapacityProfile,
  CapacitySource,
  DayCapacity,
  WeekCapacity,
  WeekCapacityOverride,
} from "./capacity.js";
export {
  blockQuantum,
  distributeMinutes,
  hasConfirmedWeekBudget,
  isNetCapacity,
  minBlockMinutes,
  mondayOf,
  resolveDayCapacity,
  resolveRangeCapacity,
  resolveWeekCapacity,
  resolveWeeksInRange,
  weekDates,
  weekdayOf,
} from "./capacity.js";

export interface StrategyTask {
  id: string; user_id: string; subject_id: string; title: string;
  estimated_minutes: number; completed_minutes: number; priority: number;
  deadline: string; earliest_date?: string; is_fixed: boolean; status: string;
  planning?: {
    activity?: { kind: "finite" | "recurring"; starts_on?: string; ends_on?: string;
      sessions_per_week?: number; session_minutes?: number; state?: "active" | "paused" | "ended" };
    dependencies?: Array<{ task_id: string; mode: "planned" | "confirmed" }>;
    [key: string]: unknown;
  } | null;
}
export interface StrategyBlock {
  id: string; user_id: string; task_id: string; date: string; start_minute: number;
  duration_minutes: number; actual_minutes: number; is_fixed: boolean; status: "planned" | "completed";
  created_at: string; updated_at: string; activity_instance_id?: string | null;
}
export interface StrategyInput {
  profile: CapacityProfile & { user_id: string; planning_mode?: "daily" | "timed"; weekly_minutes?: Record<string, number>;
    daily_limit_minutes: number; buffer_minutes: number; subject_limit_minutes: number; granularity_minutes: number;
    study_start_minute: number; study_end_minute: number; plan_start_date?: string; plan_end_date?: string };
  tasks: StrategyTask[]; blocks: StrategyBlock[];
  logs: Array<{ task_id: string | null; block_id: string | null; date: string; minutes: number }>;
  fixed_events: Array<{ date: string; start_minute: number; duration_minutes: number; repeat: string; kind: string }>;
}
export interface StrategyIssue {
  code: string; task_id: string; date?: string; expected: number; actual: number; message: string;
}
export interface StrategyResult {
  blocks: StrategyBlock[]; added: number; scheduled_minutes: number; unscheduled_minutes: number;
  issues: StrategyIssue[];
}

const plus = (date: string, days: number) => new Date(Date.parse(`${date}T00:00:00Z`) + days * 86400000).toISOString().slice(0, 10);
const weekday = (date: string) => new Date(`${date}T00:00:00Z`).getUTCDay();
const monday = (date: string) => plus(date, -((weekday(date) + 6) % 7));
const maxDate = (...dates: string[]) => dates.reduce((a, b) => a > b ? a : b);
const minDate = (...dates: string[]) => dates.reduce((a, b) => a < b ? a : b);
const daysBetween = (start: string, end: string) => Math.floor((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86400000) + 1;
const minutes = (value: number) => Number.isFinite(value) ? Math.max(0, value) : 0;
function occupiedMinutes(intervals: number[][], from = 0, to = 1440) {
  let total = 0, last = from;
  for (const [a, b] of [...intervals].sort((left, right) => left[0] - right[0])) {
    const start = Math.max(from, a), end = Math.min(to, b);
    if (end <= start) continue;
    total += Math.max(0, end - Math.max(start, last));
    last = Math.max(last, end);
  }
  return total;
}
const compare = (a: string, b: string) => a < b ? -1 : a > b ? 1 : 0;
const taskOrder = (a: StrategyTask, b: StrategyTask) => compare(a.deadline, b.deadline)
  || b.priority - a.priority || compare(a.title, b.title) || compare(a.id, b.id);

/** Whether a fixed event occupies time on [date]; mirrors `eventOccursOn` in the engine. */
export function eventOccursOnDate(event: StrategyInput["fixed_events"][number], date: string): boolean {
  return date >= event.date && (date === event.date || event.repeat === "daily"
    || event.repeat === "weekly" && weekday(date) === weekday(event.date));
}

/** Occupied intervals of every fixed event on a date, clamped to the calendar day. */
export function fixedEventIntervals(events: StrategyInput["fixed_events"], date: string): number[][] {
  return events.filter(event => eventOccursOnDate(event, date))
    .map(event => [Math.max(0, event.start_minute), Math.min(1440, event.start_minute + event.duration_minutes)])
    .sort((a, b) => a[0] - b[0]);
}

/** Logs and the block counter are two views of the same recorded work, never added. */
export function blockActualMinutes(block: StrategyBlock, logs: StrategyInput["logs"]): number {
  return Math.max(minutes(block.actual_minutes),
    logs.filter(log => log.block_id === block.id).reduce((sum, log) => sum + minutes(log.minutes), 0));
}

/**
 * Minutes a block reserves for capacity. Recorded work wins when it exists; a completed
 * block without actual history still holds its planned slot instead of freeing it.
 */
export function blockOccupiedMinutes(block: StrategyBlock, logs: StrategyInput["logs"]): number {
  const actual = blockActualMinutes(block, logs);
  return block.status === "completed" && actual > 0 ? actual : Math.max(block.duration_minutes, actual);
}

/** Half-open interval a block occupies; an overrun of actual work extends the interval. */
export function blockInterval(block: StrategyBlock, logs: StrategyInput["logs"]): [number, number] {
  return [block.start_minute, block.start_minute + Math.max(block.duration_minutes, blockActualMinutes(block, logs))];
}

/**
 * Capacity occupied on one day, shared by the automatic scheduler and manual placement.
 * Fixed events always count as their union. Timed plans clip the union of events and
 * block intervals to the study window; daily plans add the per-block occupied load.
 */
export function occupiedDayMinutes(profile: StrategyInput["profile"], events: StrategyInput["fixed_events"],
  dayBlocks: StrategyBlock[], logs: StrategyInput["logs"], date: string): number {
  if (profile.planning_mode !== "timed") {
    return occupiedMinutes(fixedEventIntervals(events, date))
      + dayBlocks.reduce((sum, block) => sum + blockOccupiedMinutes(block, logs), 0);
  }
  return occupiedMinutes([
    ...fixedEventIntervals(events, date),
    ...dayBlocks.map(block => blockInterval(block, logs)),
  ], profile.study_start_minute, profile.study_end_minute);
}

/** Real content confirmation: completed status or an explicit planning confirmation. */
export function contentConfirmed(task: StrategyTask): boolean {
  if (task.status === "completed") return true;
  return (task.planning?.content_progress as { confirmed?: boolean } | undefined)?.confirmed === true;
}

/**
 * Minutes of [task] not covered by confirmed time or blocks already scheduled on/after
 * [from]. The automatic scheduler scopes this to its window because protected history is
 * kept outside it; manual placement validates one date and considers every block.
 */
export function forecastRemainingMinutes(task: StrategyTask, logs: StrategyInput["logs"],
  blocks: StrategyBlock[], from?: string): number {
  const completed = Math.max(minutes(task.completed_minutes),
    logs.filter(log => log.task_id === task.id).reduce((sum, log) => sum + minutes(log.minutes), 0));
  const pending = blocks.filter(block => block.task_id === task.id && block.status !== "completed"
    && (!from || block.date >= from))
    .reduce((sum, block) => sum + Math.max(0, block.duration_minutes - blockActualMinutes(block, logs)), 0);
  return Math.max(0, minutes(task.estimated_minutes) - completed - pending);
}

/**
 * Three-state prerequisite rule reused by scheduling, manual placement and execution:
 * 1. completed status or explicit content confirmation satisfies any dependency;
 * 2. a "planned" dependency may also be met by a forecast: the predecessor's remaining
 *    minutes are zero and every one of its blocks is before the target date;
 * 3. merely exhausting the estimated time never confirms content.
 */
export function dependencySatisfied(options: {
  prior: StrategyTask;
  dependency: { mode: "planned" | "confirmed" };
  priorBlocks: StrategyBlock[];
  date: string;
  remaining: number;
  allowForecast?: boolean;
}): boolean {
  const { prior, dependency, priorBlocks, date, remaining, allowForecast = true } = options;
  if (contentConfirmed(prior)) return true;
  if (dependency.mode === "confirmed" || !allowForecast) return false;
  return remaining === 0 && priorBlocks.length > 0 && priorBlocks.every(block => block.date < date);
}

/** Monday weeks; partial weeks use ceil(frequency * active calendar days / 7). */
export function recurringDemand(task: StrategyTask, from: string, to: string) {
  const a = task.planning?.activity;
  if (a?.kind !== "recurring" || a.state === "paused" || a.state === "ended") return [];
  const start = maxDate(from, a.starts_on ?? from, task.earliest_date ?? from);
  const end = minDate(to, a.ends_on ?? to, task.deadline);
  const result: Array<{ week: string; start: string; end: string; sessions: number; minutes: number }> = [];
  for (let week = monday(start); week <= end; week = plus(week, 7)) {
    const first = maxDate(start, week), last = minDate(end, plus(week, 6));
    if (last < first) continue;
    const sessions = Math.ceil((a.sessions_per_week ?? 1) * daysBetween(first, last) / 7);
    result.push({ week, start: first, end: last, sessions, minutes: sessions * (a.session_minutes ?? 30) });
  }
  return result;
}

/** Preserves every supplied block. Callers release only explicitly adjustable future records. */
export function scheduleStrategy(input: StrategyInput, from: string, to: string,
  runtime: { now: () => Date; newId: () => string }): StrategyResult {
  if (from > to) throw new Error("规划结束日期不能早于开始日期");
  from = maxDate(from, input.profile.plan_start_date || from);
  to = minDate(to, input.profile.plan_end_date || to);
  const blocks = structuredClone(input.blocks);
  const stamp = runtime.now().toISOString(), issues: StrategyIssue[] = [];
  const byId = new Map(input.tasks.map(task => [task.id, task]));
  let added = 0, scheduled = 0, unscheduled = 0;
  const remaining = (task: StrategyTask) => forecastRemainingMinutes(task, input.logs, blocks, from);
  function room(task: StrategyTask, date: string) {
    const day = blocks.filter(block => block.date === date);
    const orphanLogs = input.logs.filter(log => log.date === date && (!log.block_id || !day.some(block => block.id === log.block_id)));
    const courseBlocks = day.filter(block => byId.get(block.task_id)?.subject_id === task.subject_id);
    // The same occupancy accounting is used by manual placement; timed records and events
    // that overlap each other count once and are clipped to the study window.
    const dailyOccupied = occupiedDayMinutes(input.profile, input.fixed_events, day, input.logs, date);
    const courseOccupied = occupiedDayMinutes(input.profile, [], courseBlocks, input.logs, date);
    // One shared capacity resolution: gross keeps its single buffer deduction, net is the
    // study budget itself, and weekly/date overrides always win over the default template.
    const daily = resolveDayCapacity(input.profile, date).minutes - dailyOccupied
      - orphanLogs.reduce((sum, log) => sum + minutes(log.minutes), 0);
    const course = Math.min(240, minutes(input.profile.subject_limit_minutes)) - courseOccupied
      - orphanLogs.filter(log => log.task_id !== null && byId.get(log.task_id)?.subject_id === task.subject_id).reduce((sum, log) => sum + minutes(log.minutes), 0);
    return Math.max(0, Math.min(daily, course));
  }
  function add(task: StrategyTask, date: string, duration: number, instance?: string) {
    if (room(task, date) < duration) return false;
    let start = 0;
    if (input.profile.planning_mode === "timed") {
      const intervals = [...fixedEventIntervals(input.fixed_events, date),
        ...blocks.filter(block => block.date === date).map(block => blockInterval(block, input.logs))].sort((a, b) => a[0] - b[0]);
      const quantum = Math.max(30, input.profile.granularity_minutes);
      start = Math.ceil(input.profile.study_start_minute / quantum) * quantum;
      for (const [a, b] of intervals) {
        if (start + duration <= a) break;
        if (b > start) start = Math.ceil(b / quantum) * quantum;
      }
      if (start + duration > input.profile.study_end_minute) return false;
    }
    blocks.push({ id: runtime.newId(), user_id: input.profile.user_id, task_id: task.id, date, start_minute: start,
      duration_minutes: duration, actual_minutes: 0, is_fixed: false, status: "planned", created_at: stamp, updated_at: stamp,
      ...(instance ? { activity_instance_id: instance } : {}) });
    added++; scheduled += duration;
    return true;
  }
  const visiting = new Set<string>(), visited = new Set<string>(), ordered: StrategyTask[] = [], invalid = new Set<string>();
  function visit(task: StrategyTask) {
    if (visited.has(task.id)) return;
    if (visiting.has(task.id)) { invalid.add(task.id); return; }
    visiting.add(task.id);
    for (const dependency of task.planning?.dependencies ?? []) {
      const prior = byId.get(dependency.task_id);
      if (!prior || prior.user_id !== task.user_id || prior.status === "archived") invalid.add(task.id);
      else { visit(prior); if (invalid.has(prior.id)) invalid.add(task.id); }
    }
    visiting.delete(task.id); visited.add(task.id); ordered.push(task);
  }
  for (const task of [...input.tasks].sort(taskOrder)) visit(task);
  function unlocked(task: StrategyTask, date: string) {
    if (invalid.has(task.id)) return false;
    return (task.planning?.dependencies ?? []).every(dependency => dependencySatisfied({
      prior: byId.get(dependency.task_id)!,
      dependency,
      priorBlocks: blocks.filter(block => block.task_id === dependency.task_id),
      date,
      remaining: remaining(byId.get(dependency.task_id)!),
    }));
  }
  const active = ordered.filter(task => task.user_id === input.profile.user_id && !["completed", "archived"].includes(task.status)
    && !contentConfirmed(task)
    && task.planning?.activity?.state !== "paused" && task.planning?.activity?.state !== "ended");
  function fillFinite(task: StrategyTask, date: string) {
    if (date < maxDate(task.earliest_date ?? from, task.planning?.activity?.starts_on ?? from)
      || date > minDate(task.deadline, task.planning?.activity?.ends_on ?? to) || !unlocked(task, date)) return;
    const net = isNetCapacity(input.profile);
    const quantum = blockQuantum(input.profile);
    const minBlock = minBlockMinutes(input.profile);
    while (remaining(task) > 0 && room(task, date) > 0) {
      const amount = Math.min(quantum, remaining(task), room(task, date));
      // Light net plans may place short blocks (down to the 10-minute minimum); legacy
      // gross plans keep the old rule where only the last block of a task may be short.
      if (net ? amount < minBlock : amount < quantum && remaining(task) > amount) break;
      if (!add(task, date, amount)) break;
    }
  }
  const prepared = new Set<string>();
  function preparePredecessors(task: StrategyTask) {
    if (prepared.has(task.id) || invalid.has(task.id)) return;
    prepared.add(task.id);
    for (const dependency of task.planning?.dependencies ?? []) {
      if (dependency.mode !== "planned") continue;
      const prior = byId.get(dependency.task_id)!;
      preparePredecessors(prior);
      if (active.includes(prior) && prior.planning?.activity?.kind !== "recurring") {
        for (let date = from; date <= to; date = plus(date, 1)) fillFinite(prior, date);
      }
    }
  }
  const finite = active.filter(task => task.planning?.activity?.kind !== "recurring");
  // §6.5: with the flexible capacity model the allocation is a single per-day pass in the
  // shared dependency/priority order, so a low-priority recurring practice no longer reserves
  // every session before finite work that is due earlier or more important. Legacy gross
  // documents keep the historical recurring-first order so their goldens stay byte-identical.
  const priorityMixing = isNetCapacity(input.profile) || hasConfirmedWeekBudget(input.profile)
    || Object.keys(input.profile.week_capacity_overrides ?? {}).length > 0
    || Object.keys(input.profile.date_capacity_overrides ?? {}).length > 0;
  const activeSet = new Set(active.map(task => task.id));
  if (priorityMixing) {
    type Session = { task: StrategyTask; instance: string; needed: number; preferred: string; available: string[] };
    const sessions: Session[] = [];
    const weeks = new Map<string, { task: StrategyTask; week: string; expected: number; oldSessions: number; placed: number }>();
    for (const task of active.filter(task => task.planning?.activity?.kind === "recurring")) {
      const size = task.planning!.activity!.session_minutes ?? 30;
      for (const week of recurringDemand(task, input.profile.plan_start_date || from, input.profile.plan_end_date || to)) {
        if (week.end < from || week.start > to) continue;
        const existing = blocks.filter(block => block.task_id === task.id && block.date >= week.start && block.date <= week.end);
        const orphanWork = input.logs.filter(log => log.task_id === task.id && log.date >= week.start && log.date <= week.end
          && !existing.some(block => block.date === log.date)).reduce((sum, log) => sum + minutes(log.minutes), 0);
        const oldSessions = new Set(existing.filter(block => !block.activity_instance_id).map(block => block.date)).size + Math.floor(orphanWork / size);
        const credit = orphanWork % size;
        const availableDates = Array.from({ length: daysBetween(week.start, week.end) }, (_, i) => plus(week.start, i));
        const record = { task, week: week.week, expected: week.sessions, oldSessions, placed: 0 };
        weeks.set(`${task.id}:${week.week}`, record);
        for (let i = 0; i < week.sessions; i++) {
          const instance = `${task.id}:${week.week}:${i}`;
          if (i < oldSessions || blocks.some(block => block.activity_instance_id === instance)) continue;
          const preferred = availableDates[Math.floor((i + 0.5) * availableDates.length / week.sessions)];
          if (preferred > to) continue;
          sessions.push({ task, instance, needed: size - (i === oldSessions ? credit : 0), preferred, available: availableDates });
        }
      }
    }
    // A session participates on its preferred date inside the shared priority order.
    const byPreferred = new Map<string, Map<string, Session[]>>();
    for (const session of sessions) {
      const byDate = byPreferred.get(session.task.id) ?? new Map<string, Session[]>();
      byDate.set(session.preferred, [...(byDate.get(session.preferred) ?? []), session]);
      byPreferred.set(session.task.id, byDate);
    }
    const placedSessions = new Set<string>();
    for (let date = from; date <= to; date = plus(date, 1)) {
      for (const task of ordered) {
        if (!activeSet.has(task.id)) continue;
        if (task.planning?.activity?.kind === "recurring") {
          for (const session of byPreferred.get(task.id)?.get(date) ?? []) {
            if (placedSessions.has(session.instance)) continue;
            if (blocks.some(block => block.task_id === task.id && block.date === date)) continue;
            if (unlocked(task, date) && add(task, date, session.needed, session.instance)) placedSessions.add(session.instance);
          }
        } else fillFinite(task, date);
      }
    }
    // An unplaced session retries once on the remaining dates of its own week (nearest
    // preferred first), then reports the real weekly deficit instead of silently vanishing.
    for (const session of sessions) {
      if (placedSessions.has(session.instance)) continue;
      const preferredIndex = session.available.indexOf(session.preferred);
      const dates = session.available.filter(date => date >= from && date <= to)
        .sort((a, b) => Math.abs(session.available.indexOf(a) - preferredIndex) - Math.abs(session.available.indexOf(b) - preferredIndex) || a.localeCompare(b));
      const placed = dates.some(date => !blocks.some(block => block.task_id === session.task.id && block.date === date)
        && unlocked(session.task, date) && add(session.task, date, session.needed, session.instance));
      if (placed) placedSessions.add(session.instance);
      else unscheduled += session.needed;
    }
    for (const record of weeks.values()) {
      record.placed = sessions.filter(session => session.task.id === record.task.id && session.instance.startsWith(`${record.task.id}:${record.week}:`)
        && placedSessions.has(session.instance)).length + record.oldSessions;
      if (record.placed >= record.expected) continue;
      const size = record.task.planning!.activity!.session_minutes ?? 30;
      issues.push({ code: invalid.has(record.task.id) ? "DEPENDENCY_INVALID" : "RECURRENCE_SHORTFALL", task_id: record.task.id, date: record.week,
        expected: record.expected, actual: record.placed,
        message: `每周练习尚缺${Math.max(1, record.expected - record.placed)}次（${size}分钟）；请核对可用时间、有效日期和前置条件` });
    }
  } else {
    // Recurring sessions reserve capacity before finite work and retain their logical week/ordinal identity when moved.
    for (const task of active.filter(task => task.planning?.activity?.kind === "recurring")) {
      preparePredecessors(task);
      const size = task.planning!.activity!.session_minutes ?? 30;
      for (const week of recurringDemand(task, input.profile.plan_start_date || from, input.profile.plan_end_date || to)) {
        if (week.end < from || week.start > to) continue;
        const existing = blocks.filter(block => block.task_id === task.id && block.date >= week.start && block.date <= week.end);
        const orphanWork = input.logs.filter(log => log.task_id === task.id && log.date >= week.start && log.date <= week.end
          && !existing.some(block => block.date === log.date)).reduce((sum, log) => sum + minutes(log.minutes), 0);
        const oldSessions = new Set(existing.filter(block => !block.activity_instance_id).map(block => block.date)).size + Math.floor(orphanWork / size);
        const credit = orphanWork % size;
        const availableDates = Array.from({ length: daysBetween(week.start, week.end) }, (_, i) => plus(week.start, i));
        for (let i = 0; i < week.sessions; i++) {
          const instance = `${task.id}:${week.week}:${i}`;
          if (i < oldSessions || blocks.some(block => block.activity_instance_id === instance)) continue;
          const preferred = Math.floor((i + 0.5) * availableDates.length / week.sessions);
          if (availableDates[preferred] > to) continue;
          const needed = size - (i === oldSessions ? credit : 0);
          const dates = availableDates.filter(date => date >= from && date <= to).sort((a, b) => Math.abs(availableDates.indexOf(a) - preferred) - Math.abs(availableDates.indexOf(b) - preferred) || a.localeCompare(b));
          const placed = dates.some(date => !blocks.some(block => block.task_id === task.id && block.date === date)
            && unlocked(task, date) && add(task, date, needed, instance));
          if (!placed) { unscheduled += needed; issues.push({ code: invalid.has(task.id) ? "DEPENDENCY_INVALID" : "RECURRENCE_SHORTFALL", task_id: task.id, date: week.week,
            expected: week.sessions, actual: oldSessions + blocks.filter(block => block.task_id === task.id && block.activity_instance_id?.startsWith(`${task.id}:${week.week}:`)).length,
            message: `每周练习尚缺一次（${size}分钟）；请核对可用时间、有效日期和前置条件` }); }
        }
      }
    }
    for (let date = from; date <= to; date = plus(date, 1)) {
      for (const task of finite) fillFinite(task, date);
    }
  }
  for (const task of finite) {
    const left = remaining(task);
    unscheduled += left;
    if (left > 0) issues.push({ code: invalid.has(task.id) ? "DEPENDENCY_INVALID" : (task.planning?.dependencies ?? []).some(d => d.mode === "confirmed" && byId.get(d.task_id)?.status !== "completed") ? "DEPENDENCY_UNCONFIRMED" : "WORK_UNSCHEDULED",
      task_id: task.id, expected: task.estimated_minutes, actual: task.estimated_minutes - left,
      message: `还有${left}分钟未安排；请核对容量、事项日期和前置内容进度` });
  }
  return { blocks, added, scheduled_minutes: scheduled, unscheduled_minutes: unscheduled, issues };
}
