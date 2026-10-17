import type {
  Conflict,
  FixedEvent,
  PlannerData,
  Profile,
  ReplanChange,
  ReplanInput,
  ReplanPreview,
  ReplanRun,
  ScheduleBlock,
  Task,
  TimeLog,
} from "./types";
import { defaultPlannerRuntime, type PlannerRuntime } from "./runtime";

const DAY = 86_400_000;
const copy = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const finiteMinutes = (value: number) =>
  Number.isFinite(value) ? Math.max(0, value) : 0;

/** Date-only arithmetic uses UTC, so daylight-saving transitions cannot shift a plan. */
export function addDays(date: string, days: number): string {
  const timestamp = Date.parse(`${date}T00:00:00Z`);
  if (!Number.isFinite(timestamp) || !Number.isInteger(days))
    throw new Error("日期格式无效");
  return new Date(timestamp + days * DAY).toISOString().slice(0, 10);
}

export function dateToday(now = new Date()): string {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}
export const getDate = dateToday;

export function eventOccursOn(event: FixedEvent, date: string): boolean {
  if (date < event.date) return false;
  if (event.repeat === "daily") return true;
  if (event.repeat === "weekly")
    return (
      ((Date.parse(`${date}T00:00:00Z`) -
        Date.parse(`${event.date}T00:00:00Z`)) /
        DAY) %
        7 ===
      0
    );
  return event.date === date;
}

/** Logs and the task counter are two views of the same work, never added together. */
export function taskCompletedMinutes(task: Task, logs: TimeLog[]): number {
  const logged = logs
    .filter((log) => log.task_id === task.id)
    .reduce((sum, log) => sum + finiteMinutes(log.minutes), 0);
  return Math.min(
    finiteMinutes(task.estimated_minutes),
    Math.max(finiteMinutes(task.completed_minutes), logged),
  );
}

export function remainingTaskMinutes(task: Task, logs: TimeLog[]): number {
  return Math.max(
    0,
    finiteMinutes(task.estimated_minutes) - taskCompletedMinutes(task, logs),
  );
}

function blockActual(block: ScheduleBlock, logs: TimeLog[]): number {
  return Math.max(
    finiteMinutes(block.actual_minutes),
    logs
      .filter((log) => log.block_id === block.id)
      .reduce((sum, log) => sum + finiteMinutes(log.minutes), 0),
  );
}

function blockPending(block: ScheduleBlock, logs: TimeLog[]): number {
  return block.status === "completed"
    ? 0
    : Math.max(0, block.duration_minutes - blockActual(block, logs));
}

function limits(profile: Profile) {
  return {
    daily: Math.max(
      0,
      Math.min(480, finiteMinutes(profile.daily_limit_minutes)) -
        Math.max(30, finiteMinutes(profile.buffer_minutes)),
    ),
    subject: Math.min(240, finiteMinutes(profile.subject_limit_minutes)),
    quantum: Math.max(30, finiteMinutes(profile.granularity_minutes)),
    start: Math.max(0, finiteMinutes(profile.study_start_minute)),
    end: Math.min(1440, finiteMinutes(profile.study_end_minute)),
  };
}

const overlap = (
  start: number,
  duration: number,
  otherStart: number,
  otherDuration: number,
) => start < otherStart + otherDuration && otherStart < start + duration;

/** Repeating events occupy their union of minutes, so overlapping events count once. */
export function fixedEventMinutesForDate(
  events: FixedEvent[],
  date: string,
  includeRest = true,
): number {
  const intervals = events
    .filter(
      (event) =>
        eventOccursOn(event, date) && (includeRest || event.kind !== "rest"),
    )
    .map(
      (event) =>
        [
          Math.max(0, Math.min(1440, event.start_minute)),
          Math.max(
            0,
            Math.min(
              1440,
              event.start_minute + finiteMinutes(event.duration_minutes),
            ),
          ),
        ] as const,
    )
    .filter(
      ([start, end]) =>
        Number.isFinite(start) && Number.isFinite(end) && end > start,
    )
    .sort((a, b) => a[0] - b[0]);
  let total = 0;
  let previousEnd = 0;
  for (const [start, end] of intervals) {
    total += Math.max(0, end - Math.max(start, previousEnd));
    previousEnd = Math.max(previousEnd, end);
  }
  return total;
}

/** Daily plans do not impose start/end times; all fixed events reduce the daily budget. */
export function availableDailyMinutes(
  profile: Profile,
  events: FixedEvent[],
  date: string,
): number {
  return Math.max(
    0,
    limits(profile).daily -
      fixedEventMinutesForDate(events, date, profile.planning_mode !== "timed"),
  );
}

function placementError(
  input: ReplanInput,
  blocks: ScheduleBlock[],
  candidate: ScheduleBlock,
  enforceTask = true,
): string | null {
  const task = input.tasks.find((item) => item.id === candidate.task_id);
  if (!task) return "找不到对应任务";
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(candidate.date) ||
    !Number.isFinite(Date.parse(`${candidate.date}T00:00:00Z`))
  )
    return "日期格式无效";
  const capacity = limits(input.profile);
  const timed = input.profile.planning_mode === "timed";
  if (
    !Number.isFinite(candidate.duration_minutes) ||
    candidate.duration_minutes <= 0
  )
    return "时间块时长必须大于零";
  if (
    timed &&
    (!Number.isFinite(candidate.start_minute) ||
      candidate.start_minute < capacity.start ||
      candidate.start_minute + candidate.duration_minutes > capacity.end)
  )
    return "时间块超出每日学习时间范围";
  if (timed && candidate.start_minute % capacity.quantum !== 0)
    return "开始时间需要对齐计划时间粒度";
  if (
    enforceTask &&
    (task.status === "completed" ||
      remainingTaskMinutes(task, input.logs) === 0)
  )
    return "已完成任务无需再次安排";
  if (candidate.date < (task.earliest_date ?? "0000-01-01"))
    return "任务尚未到开始日期";
  if (candidate.date > task.deadline) return "时间块不能晚于任务截止日期";
  const dayBlocks = blocks.filter((block) => block.date === candidate.date);
  if (
    timed &&
    dayBlocks.some((block) =>
      overlap(
        candidate.start_minute,
        candidate.duration_minutes,
        block.start_minute,
        Math.max(block.duration_minutes, blockActual(block, input.logs)),
      ),
    )
  )
    return "与已有时间块冲突";
  const events = input.fixed_events.filter((event) =>
    eventOccursOn(event, candidate.date),
  );
  if (
    timed &&
    events.some((event) =>
      overlap(
        candidate.start_minute,
        candidate.duration_minutes,
        event.start_minute,
        event.duration_minutes,
      ),
    )
  )
    return "与固定课程、考试或休息时间冲突";
  const orphanLogs = input.logs.filter(
    (log) =>
      log.date === candidate.date &&
      (!log.block_id || !dayBlocks.some((block) => block.id === log.block_id)),
  );
  const load = dayBlocks.reduce(
    (sum, block) =>
      sum +
      (block.status === "completed"
        ? blockActual(block, input.logs)
        : Math.max(block.duration_minutes, blockActual(block, input.logs))),
    0,
  );
  const eventLoad = fixedEventMinutesForDate(events, candidate.date, !timed);
  if (
    load +
      eventLoad +
      orphanLogs.reduce((sum, log) => sum + finiteMinutes(log.minutes), 0) +
      candidate.duration_minutes >
    capacity.daily
  )
    return "超出每日上限，须保留至少30分钟机动时间";
  const subjectLoad = dayBlocks
    .filter(
      (block) =>
        input.tasks.find((item) => item.id === block.task_id)?.subject_id ===
        task.subject_id,
    )
    .reduce(
      (sum, block) =>
        sum +
        (block.status === "completed"
          ? blockActual(block, input.logs)
          : Math.max(block.duration_minutes, blockActual(block, input.logs))),
      0,
    );
  const orphanSubjectLoad = orphanLogs
    .filter(
      (log) =>
        input.tasks.find((item) => item.id === log.task_id)?.subject_id ===
        task.subject_id,
    )
    .reduce((sum, log) => sum + finiteMinutes(log.minutes), 0);
  if (
    subjectLoad + orphanSubjectLoad + candidate.duration_minutes >
    capacity.subject
  )
    return "同一科目每天最多安排4小时";
  return null;
}

/** The same constraints are used by drag-and-drop and the automatic scheduler. */
export function validateBlockPlacement(
  data: PlannerData,
  block: ScheduleBlock,
  ignoreId?: string,
): string | null {
  const old = ignoreId
    ? data.blocks.find((item) => item.id === ignoreId)
    : undefined;
  if (
    old &&
    (old.is_fixed ||
      old.status === "completed" ||
      data.tasks.find((task) => task.id === old.task_id)?.is_fixed) &&
    (old.date !== block.date ||
      (data.profile.planning_mode === "timed" &&
        old.start_minute !== block.start_minute) ||
      old.duration_minutes !== block.duration_minutes)
  )
    return "固定或已完成的时间块不可移动";
  return placementError(
    { ...data, today: dateToday(), mode: "unfinished" },
    data.blocks.filter((item) => item.id !== ignoreId),
    block,
  );
}

function urgency(a: Task, b: Task): number {
  return (
    a.deadline.localeCompare(b.deadline) ||
    b.priority - a.priority ||
    a.created_at.localeCompare(b.created_at) ||
    a.id.localeCompare(b.id)
  );
}

function findSlot(
  input: ReplanInput,
  blocks: ScheduleBlock[],
  task: Task,
  duration: number,
  firstDate: string,
  lastDate: string,
  timestamp: string,
  runtime: PlannerRuntime,
): ScheduleBlock | null {
  const capacity = limits(input.profile);
  const first =
    firstDate < (task.earliest_date ?? "") ? task.earliest_date! : firstDate;
  const last = lastDate < task.deadline ? lastDate : task.deadline;
  for (let date = first; date <= last; date = addDays(date, 1)) {
    if (input.profile.planning_mode !== "timed") {
      const block: ScheduleBlock = {
        id: runtime.newId(),
        user_id: input.profile.user_id,
        task_id: task.id,
        date,
        start_minute: 0,
        duration_minutes: duration,
        actual_minutes: 0,
        is_fixed: false,
        status: "planned",
        created_at: timestamp,
        updated_at: timestamp,
      };
      if (!placementError(input, blocks, block)) return block;
      continue;
    }
    for (
      let start =
        Math.ceil(capacity.start / capacity.quantum) * capacity.quantum;
      start + duration <= capacity.end;
      start += capacity.quantum
    ) {
      const block: ScheduleBlock = {
        id: runtime.newId(),
        user_id: input.profile.user_id,
        task_id: task.id,
        date,
        start_minute: start,
        duration_minutes: duration,
        actual_minutes: 0,
        is_fixed: false,
        status: "planned",
        created_at: timestamp,
        updated_at: timestamp,
      };
      if (!placementError(input, blocks, block)) return block;
    }
  }
  return null;
}

function snapshotKey(blocks: ScheduleBlock[]): string {
  // Explicit keys also make equality independent of the property order of imported JSON.
  return JSON.stringify(
    [...blocks]
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((block) => [
        block.id,
        block.user_id,
        block.task_id,
        block.date,
        block.start_minute,
        block.duration_minutes,
        block.actual_minutes,
        block.is_fixed,
        block.status,
        block.created_at,
        block.updated_at,
      ]),
  );
}

function makePreview(
  input: ReplanInput,
  after: ScheduleBlock[],
  conflicts: Conflict[],
  timestamp: string,
  runtime: PlannerRuntime,
): ReplanPreview {
  const before = copy(input.blocks);
  const id = runtime.newId();
  const oldMap = new Map(before.map((block) => [block.id, block]));
  const nextMap = new Map(after.map((block) => [block.id, block]));
  const changes: ReplanChange[] = [];
  for (const block of before) {
    const next = nextMap.get(block.id);
    if (!next || snapshotKey([block]) !== snapshotKey([next]))
      changes.push({
        id: runtime.newId(),
        user_id: input.profile.user_id,
        run_id: id,
        type: next ? "moved" : "deleted",
        block_id: block.id,
        before: copy(block),
        after: next ? copy(next) : null,
      });
  }
  for (const block of after)
    if (!oldMap.has(block.id))
      changes.push({
        id: runtime.newId(),
        user_id: input.profile.user_id,
        run_id: id,
        type: "added",
        block_id: block.id,
        before: null,
        after: copy(block),
      });
  const postponed = new Set<string>();
  const advanced = new Set<string>();
  for (const change of changes) {
    if (change.before && change.after && change.after.date > change.before.date)
      postponed.add(change.after.task_id);
    if (change.before && change.after && change.after.date < change.before.date)
      advanced.add(change.after.task_id);
  }
  for (const change of changes.filter((item) => item.type === "added")) {
    if (
      before.some(
        (block) =>
          block.task_id === change.after!.task_id &&
          block.date === input.today &&
          block.status !== "completed",
      ) &&
      change.after!.date > input.today
    )
      postponed.add(change.after!.task_id);
  }
  const dates = [
    ...new Set([...before, ...after].map((block) => block.date)),
  ].sort();
  const daily_changes = dates
    .map((date) => ({
      date,
      before_minutes: before
        .filter((block) => block.date === date)
        .reduce((sum, block) => sum + block.duration_minutes, 0),
      after_minutes: after
        .filter((block) => block.date === date)
        .reduce((sum, block) => sum + block.duration_minutes, 0),
    }))
    .filter((day) => day.before_minutes !== day.after_minutes);
  return {
    id,
    user_id: input.profile.user_id,
    created_at: timestamp,
    before,
    after: copy(after),
    changes,
    postponed: [...postponed],
    advanced: [...advanced],
    conflicts,
    daily_changes,
  };
}

/** Generate a proposal only: this function never mutates its input. */
export function generateReplanPreview(input: ReplanInput, runtime: PlannerRuntime = defaultPlannerRuntime): ReplanPreview {
  const timestamp = runtime.now().toISOString();
  const horizon = addDays(input.today, input.mode === "overcompleted" ? 7 : 14);
  const tasks = new Map(input.tasks.map((task) => [task.id, task]));
  const immutable = (block: ScheduleBlock) =>
    block.is_fixed ||
    block.status === "completed" ||
    tasks.get(block.task_id)?.is_fixed ||
    block.date < input.today ||
    block.date > horizon;
  if (input.mode === "overcompleted") {
    const after = copy(
      input.blocks.filter((block) => {
        const task = tasks.get(block.task_id);
        return (
          immutable(block) ||
          block.date === input.today ||
          !task ||
          (task.status !== "completed" &&
            remainingTaskMinutes(task, input.logs) > 0)
        );
      }),
    );
    let available = finiteMinutes(input.excess_minutes ?? 0);
    const eligible = input.blocks
      .filter(
        (block) =>
          block.date > input.today &&
          block.date <= horizon &&
          !immutable(block) &&
          blockActual(block, input.logs) === 0,
      )
      .sort((a, b) => {
        const ta = tasks.get(a.task_id),
          tb = tasks.get(b.task_id);
        return ta && tb
          ? tb.priority - ta.priority ||
              ta.deadline.localeCompare(tb.deadline) ||
              a.date.localeCompare(b.date) ||
              a.start_minute - b.start_minute
          : 0;
      });
    const spent = new Map<string, number>();
    for (const source of eligible) {
      const task = tasks.get(source.task_id);
      if (
        !task ||
        task.status === "completed" ||
        remainingTaskMinutes(task, input.logs) === 0
      )
        continue;
      const remaining =
        remainingTaskMinutes(task, input.logs) - (spent.get(task.id) ?? 0);
      const pending = Math.min(source.duration_minutes, remaining, available);
      let moved = 0;
      let firstMovedId: string | null = null;
      while (moved < pending) {
        const duration = Math.min(
          limits(input.profile).quantum,
          pending - moved,
        );
        // Do not use a partial unit simply to exhaust the excess allowance.
        if (
          duration < limits(input.profile).quantum &&
          remaining - moved > duration &&
          source.duration_minutes - moved > duration
        )
          break;
        const slot = findSlot(
          input,
          after,
          task,
          duration,
          input.today,
          input.today,
          timestamp,
          runtime,
        );
        if (!slot) break;
        after.push(slot);
        firstMovedId ??= slot.id;
        moved += duration;
        available -= duration;
      }
      if (moved > 0) {
        const index = after.findIndex((block) => block.id === source.id);
        const pulled = after.find((block) => block.id === firstMovedId)!;
        // Reuse the source identity for the first moved unit, keeping diff history useful.
        const pulledIndex = after.indexOf(pulled);
        after[pulledIndex] = {
          ...pulled,
          id: source.id,
          created_at: source.created_at,
        };
        if (moved === source.duration_minutes) after.splice(index, 1);
        else
          after[index] = {
            ...source,
            id: runtime.newId(),
            duration_minutes: source.duration_minutes - moved,
            updated_at: timestamp,
          };
        spent.set(task.id, (spent.get(task.id) ?? 0) + moved);
      }
      if (available <= 0) break;
    }
    return makePreview(input, after, [], timestamp, runtime);
  }

  const after: ScheduleBlock[] = [];
  const candidates = new Map<string, ScheduleBlock[]>();
  const immutableReserved = new Map<string, number>();
  for (const block of input.blocks) {
    if (immutable(block)) {
      after.push(copy(block));
      if (block.date >= input.today && block.status !== "completed")
        immutableReserved.set(
          block.task_id,
          (immutableReserved.get(block.task_id) ?? 0) +
            blockPending(block, input.logs),
        );
      continue;
    }
    const task = tasks.get(block.task_id);
    if (!task) {
      after.push(copy(block));
      continue;
    }
    if (blockActual(block, input.logs) > 0) {
      // Retain the execution record on its original day; only its unfinished part moves.
      after.push({
        ...copy(block),
        status: "completed",
        actual_minutes: blockActual(block, input.logs),
        updated_at: timestamp,
      });
    }
    if (
      task.status !== "completed" &&
      remainingTaskMinutes(task, input.logs) > 0 &&
      blockPending(block, input.logs) > 0
    )
      candidates.set(task.id, [...(candidates.get(task.id) ?? []), block]);
  }
  const conflicts: Conflict[] = [];
  const queuedTasks = input.tasks
    .filter((task) => candidates.has(task.id))
    .sort(urgency);
  for (const task of queuedTasks) {
    let budget = Math.max(
      0,
      remainingTaskMinutes(task, input.logs) -
        (immutableReserved.get(task.id) ?? 0),
    );
    let missed = 0;
    const sources = candidates
      .get(task.id)!
      .sort(
        (a, b) =>
          a.date.localeCompare(b.date) || a.start_minute - b.start_minute,
      );
    for (const source of sources) {
      let pending = Math.min(blockPending(source, input.logs), budget);
      budget -= pending;
      let first = true;
      let offset = 0;
      while (pending > 0) {
        const duration = Math.min(limits(input.profile).quantum, pending);
        let next: ScheduleBlock | null = null;
        // Keep a valid existing future placement whenever the earlier urgent queue permits it.
        const preferred: ScheduleBlock = {
          ...copy(source),
          id:
            first && blockActual(source, input.logs) === 0
              ? source.id
              : runtime.newId(),
          start_minute:
            input.profile.planning_mode === "timed"
              ? source.start_minute + offset
              : source.start_minute,
          duration_minutes: duration,
          actual_minutes: 0,
          status: "planned",
        };
        if (
          source.date > input.today &&
          !placementError(input, after, preferred)
        )
          next = preferred;
        if (!next) {
          const slot = findSlot(
            input,
            after,
            task,
            duration,
            addDays(input.today, 1),
            horizon,
            timestamp,
            runtime,
          );
          if (slot)
            next = {
              ...slot,
              id:
                first && blockActual(source, input.logs) === 0
                  ? source.id
                  : slot.id,
              created_at:
                first && blockActual(source, input.logs) === 0
                  ? source.created_at
                  : timestamp,
            };
        }
        if (next) {
          if (snapshotKey([source]) !== snapshotKey([next]))
            next.updated_at = timestamp;
          after.push(next);
        } else missed += duration;
        pending -= duration;
        offset += duration;
        first = false;
      }
    }
    if (missed > 0)
      conflicts.push({
        task_id: task.id,
        title: task.title,
        minutes: missed,
        reason:
          task.deadline <= input.today
            ? "截止日期已到，未来没有可安排的日期"
            : "截止日期前或未来14天内容量不足；未突破每日上限、机动时间和科目上限",
      });
  }
  return makePreview(input, after, conflicts, timestamp, runtime);
}

type RunWithTaskSnapshot = ReplanRun & {
  task_status_before?: Array<{ id: string; status: Task["status"] }>;
  task_status_after?: Array<{ id: string; status: Task["status"] }>;
};

export function confirmReplan(
  data: PlannerData,
  preview: ReplanPreview,
): PlannerData {
  if (preview.user_id !== data.profile.user_id)
    throw new Error("不能确认其他用户的计划");
  if (data.replan_runs.some((run) => run.id === preview.id))
    throw new Error("这次调整已经确认");
  if (snapshotKey(data.blocks) !== snapshotKey(preview.before))
    throw new Error("计划已发生变化，请重新生成预览");
  const result = copy(data);
  result.blocks = copy(preview.after);
  const before = result.tasks.map((task) => ({
    id: task.id,
    status: task.status,
  }));
  result.tasks = result.tasks.map((task) => ({
    ...task,
    status:
      task.status === "completed" ||
      remainingTaskMinutes(task, result.logs) === 0
        ? "completed"
        : preview.conflicts.some((conflict) => conflict.task_id === task.id)
          ? "conflict"
          : preview.postponed.includes(task.id)
            ? "delayed"
            : task.status,
    updated_at:
      preview.changes.some(
        (change) => (change.after ?? change.before)?.task_id === task.id,
      ) || preview.conflicts.some((conflict) => conflict.task_id === task.id)
        ? preview.created_at
        : task.updated_at,
  }));
  const run: RunWithTaskSnapshot = {
    ...copy(preview),
    status: "confirmed",
    task_status_before: before,
    task_status_after: result.tasks.map((task) => ({
      id: task.id,
      status: task.status,
    })),
  };
  result.replan_runs.push(run);
  return result;
}

export function undoLastReplan(data: PlannerData): PlannerData {
  const index = data.replan_runs
    .map((run) => run.status)
    .lastIndexOf("confirmed");
  if (index < 0) throw new Error("没有可撤销的调整");
  const run = data.replan_runs[index] as RunWithTaskSnapshot;
  if (snapshotKey(data.blocks) !== snapshotKey(run.after))
    throw new Error("调整后计划已被修改，请先恢复该版本再撤销");
  const result = copy(data);
  result.blocks = copy(run.before);
  result.replan_runs[index].status = "undone";
  if (run.task_status_before)
    result.tasks = result.tasks.map((task) => {
      const previous = run.task_status_before!.find(
        (item) => item.id === task.id,
      );
      return previous ? { ...task, status: previous.status } : task;
    });
  return result;
}
