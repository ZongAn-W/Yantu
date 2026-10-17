/** Pure scheduling contract shared by the API and TypeScript reference fixtures. */
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
  profile: { user_id: string; planning_mode?: "daily" | "timed"; weekly_minutes?: Record<string, number>;
    daily_limit_minutes: number; buffer_minutes: number; subject_limit_minutes: number; granularity_minutes: number;
    study_start_minute: number; study_end_minute: number; plan_start_date?: string; plan_end_date?: string };
  tasks: StrategyTask[]; blocks: StrategyBlock[];
  logs: Array<{ task_id: string; block_id: string | null; date: string; minutes: number }>;
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
  const completed = (task: StrategyTask) => Math.max(minutes(task.completed_minutes), input.logs.filter(log => log.task_id === task.id).reduce((sum, log) => sum + minutes(log.minutes), 0));
  const actual = (block: StrategyBlock) => Math.max(minutes(block.actual_minutes), input.logs.filter(log => log.block_id === block.id).reduce((sum, log) => sum + minutes(log.minutes), 0));
  const pending = (task: StrategyTask) => blocks.filter(block => block.task_id === task.id && block.date >= from && block.status !== "completed")
    .reduce((sum, block) => sum + Math.max(0, block.duration_minutes - actual(block)), 0);
  const remaining = (task: StrategyTask) => Math.max(0, task.estimated_minutes - completed(task) - pending(task));
  const eventIntervals = (date: string) => input.fixed_events.filter(event => date >= event.date &&
    (date === event.date || event.repeat === "daily" || event.repeat === "weekly" && weekday(date) === weekday(event.date)))
    .map(event => [Math.max(0, event.start_minute), Math.min(1440, event.start_minute + event.duration_minutes)]).sort((a, b) => a[0] - b[0]);
  function room(task: StrategyTask, date: string) {
    const week = input.profile.weekly_minutes;
    const raw = week && Object.keys(week).length === 7 ? week[String(weekday(date))] ?? 0 : input.profile.daily_limit_minutes;
    const day = blocks.filter(block => block.date === date);
    const orphanLogs = input.logs.filter(log => log.date === date && (!log.block_id || !day.some(block => block.id === log.block_id)));
    const load = (block: StrategyBlock) => block.status === "completed" && actual(block) > 0 ? actual(block) : Math.max(block.duration_minutes, actual(block));
    const timed = input.profile.planning_mode === "timed";
    const blockIntervals = (source: StrategyBlock[]) => source.map(block => [block.start_minute, block.start_minute + Math.max(block.duration_minutes, actual(block))]);
    const courseBlocks = day.filter(block => byId.get(block.task_id)?.subject_id === task.subject_id);
    // Timed records can overlap events or each other; their occupied minutes count once.
    const occupied = timed ? occupiedMinutes([...eventIntervals(date), ...blockIntervals(day)], input.profile.study_start_minute, input.profile.study_end_minute)
      : occupiedMinutes(eventIntervals(date)) + day.reduce((sum, block) => sum + load(block), 0);
    const courseOccupied = timed ? occupiedMinutes(blockIntervals(courseBlocks), input.profile.study_start_minute, input.profile.study_end_minute)
      : courseBlocks.reduce((sum, block) => sum + load(block), 0);
    const daily = Math.min(480, minutes(raw)) - Math.max(30, minutes(input.profile.buffer_minutes)) - occupied
      - orphanLogs.reduce((sum, log) => sum + minutes(log.minutes), 0);
    const course = Math.min(240, minutes(input.profile.subject_limit_minutes)) - courseOccupied
      - orphanLogs.filter(log => byId.get(log.task_id)?.subject_id === task.subject_id).reduce((sum, log) => sum + minutes(log.minutes), 0);
    return Math.max(0, Math.min(daily, course));
  }
  function add(task: StrategyTask, date: string, duration: number, instance?: string) {
    if (room(task, date) < duration) return false;
    let start = 0;
    if (input.profile.planning_mode === "timed") {
      const intervals = [...eventIntervals(date), ...blocks.filter(block => block.date === date).map(block => [block.start_minute, block.start_minute + Math.max(block.duration_minutes, actual(block))])].sort((a, b) => a[0] - b[0]);
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
    return (task.planning?.dependencies ?? []).every(dependency => {
      const prior = byId.get(dependency.task_id)!;
      if (prior.status === "completed" || (prior.planning?.content_progress as { confirmed?: boolean } | undefined)?.confirmed === true) return true;
      if (dependency.mode === "confirmed") return false;
      const priorBlocks = blocks.filter(block => block.task_id === prior.id);
      return remaining(prior) === 0 && priorBlocks.length > 0 && priorBlocks.every(block => block.date < date);
    });
  }
  const active = ordered.filter(task => task.user_id === input.profile.user_id && !["completed", "archived"].includes(task.status)
    && (task.planning?.content_progress as { confirmed?: boolean } | undefined)?.confirmed !== true
    && task.planning?.activity?.state !== "paused" && task.planning?.activity?.state !== "ended");
  function fillFinite(task: StrategyTask, date: string) {
    if (date < maxDate(task.earliest_date ?? from, task.planning?.activity?.starts_on ?? from)
      || date > minDate(task.deadline, task.planning?.activity?.ends_on ?? to) || !unlocked(task, date)) return;
    const quantum = Math.max(30, input.profile.granularity_minutes);
    while (remaining(task) > 0 && room(task, date) > 0) {
      const amount = Math.min(quantum, remaining(task), room(task, date));
      if (amount < quantum && remaining(task) > amount) break;
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
  const finite = active.filter(task => task.planning?.activity?.kind !== "recurring");
  for (let date = from; date <= to; date = plus(date, 1)) {
    for (const task of finite) fillFinite(task, date);
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
