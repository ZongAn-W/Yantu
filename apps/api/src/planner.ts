import { randomUUID } from "node:crypto";
import type pg from "pg";
import { adviceFor } from "./ai.js";
import { query, transaction } from "./db.js";
import type { OnboardingSession } from "./onboarding-contracts.js";
import type { PlannerDocument } from "./sync-contracts.js";
import type { ItemPlanning, PlanPlanning } from "./planning-contracts.js";

export type ProfileRow = {
  goal_text: string;
  goal_type: string;
  goal_subtype: string;
  target_date: string | null;
  target_date_confirmed: boolean;
  plan_start_date: string | null;
  plan_end_date: string | null;
  target_school: string;
  target_program: string;
  current_progress: string;
  weekly_minutes: Record<string, number>;
  constraints_text: string;
  // 灵活容量投影；缺失（null）表示旧数据/未设置，显式空对象表示清空覆盖。
  capacity_basis?: string | null;
  weekly_baseline_minutes?: number | null;
  weekly_range_min_minutes?: number | null;
  weekly_range_max_minutes?: number | null;
  week_capacity_overrides?: Record<string, unknown> | null;
  date_capacity_overrides?: Record<string, number> | null;
  planning_metadata?: PlanPlanning | null;
};
export type ItemRow = { id: string; course_id: string; course_name?: string; title: string; description: string; completion_criteria: string; estimated_minutes: number; earliest_date: string | null; deadline: string; deadline_kind: string; priority: number; status: string; planning_metadata?: ItemPlanning | null };
type DailyRow = { id: string; item_id: string; date: string; planned_minutes: number; actual_minutes: number; advice_text: string; advice_topics: string[]; completion_status: string; item_title?: string; course_name?: string; activity_instance_id?: string | null };
type LogRow = { id: string; item_id: string | null; ad_hoc_id: string | null; daily_plan_item_id: string | null; date: string; minutes: number; relation: string | null; session_id: string | null; quota_minutes: number | null; created_at: string };
type AdHocRow = { id: string; title: string; subject_id: string | null; archived: boolean; converted_task_id: string | null; created_at: string; updated_at: string };

export const PROFILE_COLUMNS = "goal_text,goal_type,goal_subtype,target_date::text,target_date_confirmed,plan_start_date::text,plan_end_date::text,target_school,target_program,current_progress,weekly_minutes,constraints_text,capacity_basis,weekly_baseline_minutes,weekly_range_min_minutes,weekly_range_max_minutes,week_capacity_overrides,date_capacity_overrides";
const ITEM_COLUMNS = "id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date::text,deadline::text,deadline_kind,priority,status,planning_metadata";

export function dateAdd(date: string, days: number) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

export function dateToday() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Shanghai" }).format(new Date());
}

/** 本次排程的有限区间结束日期；与用户的目标日期不同。 */
export function planBoundary(profile: ProfileRow | { plan_end_date?: string | null; target_date?: string | null }, from = dateToday()) {
  return profile.plan_end_date || profile.target_date || dateAdd(from, 27);
}

export async function getProfile(userId: string): Promise<ProfileRow | null> {
  const result = await query<ProfileRow>(`select ${PROFILE_COLUMNS} from profiles where user_id = $1`, [userId]);
  return result.rows[0] ?? null;
}

/** 旧列 exam_type / exam_date 只作为历史镜像保留，界面不再读取。 */
const legacyExamType = (profile: ProfileRow) =>
  profile.goal_subtype || (profile.goal_type === "exam" ? "其他" : profile.goal_type);

export async function saveProfile(userId: string, profile: ProfileRow, client?: pg.PoolClient) {
  const write = client ? client.query.bind(client) : query;
  await write(
    `insert into profiles(user_id,goal_text,goal_type,goal_subtype,target_date,target_date_confirmed,plan_start_date,plan_end_date,target_school,target_program,current_progress,weekly_minutes,constraints_text,exam_type,exam_date)
     values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
     on conflict(user_id) do update set goal_text=excluded.goal_text, goal_type=excluded.goal_type, goal_subtype=excluded.goal_subtype,
       target_date=excluded.target_date, target_date_confirmed=excluded.target_date_confirmed, plan_start_date=excluded.plan_start_date,
       plan_end_date=excluded.plan_end_date, target_school=excluded.target_school, target_program=excluded.target_program,
       current_progress=excluded.current_progress, weekly_minutes=excluded.weekly_minutes, constraints_text=excluded.constraints_text,
       exam_type=excluded.exam_type, exam_date=excluded.exam_date, updated_at=now()`,
    [userId, profile.goal_text, profile.goal_type, profile.goal_subtype, profile.target_date, profile.target_date_confirmed,
      profile.plan_start_date, profile.plan_end_date, profile.target_school, profile.target_program,
      profile.current_progress, JSON.stringify(profile.weekly_minutes), profile.constraints_text,
      legacyExamType(profile), profile.target_date]);
  // 容量投影随资料写入：字段缺失=保留数据库已有值；显式 null/空对象=清空。
  const fields = profile as Record<string, unknown>;
  const has = (key: string) => Object.prototype.hasOwnProperty.call(profile, key);
  const sets: string[] = [];
  const values: unknown[] = [];
  const add = (column: string, json = false) => {
    if (!has(column)) return;
    const value = fields[column];
    sets.push(`${column}=$${values.length + 2}`);
    values.push(value === null || value === undefined ? null : json ? JSON.stringify(value) : value);
  };
  add("capacity_basis");
  add("weekly_baseline_minutes");
  add("weekly_range_min_minutes");
  add("weekly_range_max_minutes");
  add("week_capacity_overrides", true);
  add("date_capacity_overrides", true);
  if (sets.length)
    await write(
      `update profiles set ${sets.join(",")},updated_at=now() where user_id=$1`,
      [userId, ...values],
    );
}

export function itemToJson(row: ItemRow) {
  return { id: row.id, course_id: row.course_id, title: row.title, description: row.description, completion_criteria: row.completion_criteria, estimated_minutes: row.estimated_minutes, earliest_date: row.earliest_date ?? undefined, deadline: row.deadline, deadline_kind: row.deadline_kind ?? "deadline", priority: row.priority, status: row.status, ...(row.planning_metadata ? { planning: row.planning_metadata } : {}) };
}

export async function listCourses(userId: string) {
  const result = await query("select id, name, description, priority, created_at from courses where user_id = $1 order by created_at", [userId]);
  return result.rows;
}

export async function listItems(userId: string) {
  const result = await query<ItemRow>(`select i.*, c.name as course_name from items i join courses c on c.id=i.course_id where i.user_id=$1 order by i.deadline, i.priority desc, i.created_at`, [userId]);
  return result.rows.map((row) => ({ ...itemToJson(row), course_name: row.course_name }));
}

export async function listDailyPlans(userId: string, from: string, to: string) {
  const result = await query<DailyRow>(`select d.id, d.item_id, d.date::text, d.planned_minutes, d.actual_minutes, d.advice_text, d.advice_topics, d.completion_status, i.title as item_title, c.name as course_name
    from daily_plan_items d join items i on i.id=d.item_id join courses c on c.id=i.course_id
    where d.user_id=$1 and d.date between $2 and $3 order by d.date, c.name, i.title`, [userId, from, to]);
  return result.rows;
}

export async function snapshot(userId: string, client?: pg.PoolClient) {
  const read = <T extends pg.QueryResultRow>(sql: string, values: unknown[] = []) => client ? client.query<T>(sql, values) : query<T>(sql, values);
  const profile = (await read<ProfileRow>(`select ${PROFILE_COLUMNS},planning_metadata from profiles where user_id=$1`, [userId])).rows[0];
  if (!profile) return null;
  const courses = await read<{ id: string; name: string; priority: number }>("select id,name,priority from courses where user_id=$1 order by created_at", [userId]);
  const items = await read<ItemRow>(`select ${ITEM_COLUMNS} from items where user_id=$1 order by deadline,created_at`, [userId]);
  const days = await read<DailyRow>("select d.id,d.item_id,d.date::text,d.planned_minutes,d.actual_minutes,d.advice_text,d.advice_topics,d.completion_status,d.activity_instance_id,i.title as item_title,c.name as course_name from daily_plan_items d join items i on i.id=d.item_id join courses c on c.id=i.course_id where d.user_id=$1 order by d.date,d.id", [userId]);
  const logs = await read<LogRow>("select id,item_id,ad_hoc_id,daily_plan_item_id,date::text,minutes,relation,session_id,quota_minutes,created_at from study_logs where user_id=$1 order by created_at", [userId]);
  const adHocLearnings = await read<AdHocRow>("select id,title,subject_id,archived,converted_task_id,created_at,updated_at from ad_hoc_learnings where user_id=$1 order by created_at,id", [userId]);
  const logged = new Map<string, number>();
  for (const log of logs.rows) {
    if (log.item_id === null) continue;
    logged.set(log.item_id, (logged.get(log.item_id) ?? 0) + log.minutes);
  }
  const now = new Date().toISOString();
  const today = dateToday();
  const boundary = profile.plan_end_date ?? profile.target_date ?? dateAdd(today, 27);
  return {
    version: 1 as const,
    ...(profile.planning_metadata ? { planning: profile.planning_metadata } : {}),
    profile: {
      user_id: userId, planning_mode: "daily" as const,
      goal_text: profile.goal_text, goal_type: profile.goal_type, goal_subtype: profile.goal_subtype,
      target_date: profile.target_date, target_date_confirmed: profile.target_date_confirmed,
      plan_start_date: profile.plan_start_date ?? today, plan_end_date: profile.plan_end_date ?? boundary,
      target_school: profile.target_school, target_program: profile.target_program,
      constraints: profile.constraints_text,
      // 一周七天的实际可用时间：排程的唯一来源，不能用全周最大值代替。
      weekly_minutes: normalizeWeek(profile.weekly_minutes),
      // 容量投影：只有数据库确实存了值才输出，缺失保持缺失（旧数据语义）。
      ...(profile.capacity_basis ? { capacity_basis: profile.capacity_basis as "gross_buffer" | "net" } : {}),
      ...(profile.weekly_baseline_minutes !== null && profile.weekly_baseline_minutes !== undefined ? { weekly_baseline_minutes: profile.weekly_baseline_minutes } : {}),
      ...(profile.weekly_range_min_minutes !== null && profile.weekly_range_min_minutes !== undefined ? { weekly_range_min_minutes: profile.weekly_range_min_minutes } : {}),
      ...(profile.weekly_range_max_minutes !== null && profile.weekly_range_max_minutes !== undefined ? { weekly_range_max_minutes: profile.weekly_range_max_minutes } : {}),
      ...(profile.week_capacity_overrides ? { week_capacity_overrides: profile.week_capacity_overrides } : {}),
      ...(profile.date_capacity_overrides ? { date_capacity_overrides: profile.date_capacity_overrides } : {}),
      // 旧客户端读取的镜像字段：目标日期存在时才写入，避免伪造日期。
      ...(profile.target_date ? { exam_date: profile.target_date, exam_end_date: profile.target_date } : {}),
      // 仅用于展示与旧数据兜底；排程按每周配置逐日计算。
      daily_limit_minutes: Math.max(30, Math.min(480, Math.max(...Object.values(profile.weekly_minutes), 30))),
      granularity_minutes: 30, buffer_minutes: 30, subject_limit_minutes: 240, study_start_minute: 480, study_end_minute: 1320,
      foundation: profile.current_progress,
    },
    subjects: courses.rows.map((course) => ({ id: course.id, user_id: userId, name: course.name, color: "#275e91", priority: course.priority as 1 | 2 | 3 })),
    tasks: items.rows.map((item) => ({ id: item.id, user_id: userId, subject_id: item.course_id, title: item.title, description: [item.description, item.completion_criteria ? `完成标准：${item.completion_criteria}` : ""].filter(Boolean).join("\n"), estimated_minutes: item.estimated_minutes, completed_minutes: logged.get(item.id) ?? 0, priority: item.priority as 1 | 2 | 3, deadline: item.deadline, deadline_kind: item.deadline_kind ?? "deadline", earliest_date: item.earliest_date ?? undefined, is_fixed: false, status: (item.status === "archived" ? "archived" : item.status === "completed" ? "completed" : (logged.get(item.id) ?? 0) > 0 ? "in_progress" : "not_started") as "not_started" | "in_progress" | "completed" | "archived", created_at: now, updated_at: now, ...(item.planning_metadata ? { planning: item.planning_metadata } : {}) })),
    blocks: days.rows.map((day) => ({ id: day.id, user_id: userId, task_id: day.item_id, date: day.date, start_minute: 0, duration_minutes: day.planned_minutes, actual_minutes: day.actual_minutes, is_fixed: false, status: (day.completion_status === "completed" ? "completed" : "planned") as "planned" | "completed", created_at: now, updated_at: now, advice_text: day.advice_text, advice_topics: day.advice_topics, completion_status: day.completion_status, ...(day.activity_instance_id ? { activity_instance_id: day.activity_instance_id } : {}) })),
    logs: logs.rows.map((log) => ({ id: log.id, user_id: userId, task_id: log.item_id, block_id: log.daily_plan_item_id, date: log.date, minutes: log.minutes, started_at: log.created_at, ended_at: log.created_at, source: "manual" as const,
      // 旧数据/旧语义保持缺失；只有真实存在的执行关系、会话与临时学习引用才投影出来。
      ...(log.relation && log.relation !== "legacy_unknown" ? { relation: log.relation as "scheduled" | "extra" | "ad_hoc" } : {}),
      ...(log.session_id ? { session_id: log.session_id } : {}),
      ...(log.ad_hoc_id ? { ad_hoc_id: log.ad_hoc_id } : {}),
      ...(log.quota_minutes !== null && log.quota_minutes !== undefined ? { quota_minutes: log.quota_minutes } : {}) })),
    ...(adHocLearnings.rows.length ? { ad_hoc_learnings: adHocLearnings.rows.map((row) => ({ id: row.id, user_id: userId, title: row.title, ...(row.subject_id ? { subject_id: row.subject_id } : {}), created_at: row.created_at, updated_at: row.updated_at, archived: row.archived, ...(row.converted_task_id ? { converted_task_id: row.converted_task_id } : {}) })) } : {}),
    fixed_events: [], replan_runs: [], phases: [],
  };
}

/**
 * 只把完整合法的一周配置当作可靠来源：缺键、非数字或越界都说明数据不可用。
 * 0 是明确的休息日，必须保留。
 */
export function isReliableWeek(value: unknown): value is Record<string, number> {
  if (!value || typeof value !== "object") return false;
  const row = value as Record<string, unknown>;
  const keys = Object.keys(row);
  if (keys.length !== 7) return false;
  for (let day = 0; day < 7; day++) {
    const minutes = row[String(day)];
    if (typeof minutes !== "number" || !Number.isFinite(minutes) || minutes < 0 || minutes > 1440) return false;
  }
  return true;
}

/** 归一化为一周七天，键固定为 0(周日) 到 6(周六)。 */
export function normalizeWeek(value: Record<string, number> | null | undefined): Record<string, number> {
  const source = isReliableWeek(value) ? value : null;
  return Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map(day => [String(day), Math.max(0, Math.min(480, Number(source?.[String(day)] ?? 0)))]));
}

function dayMinutes(profile: ProfileRow, date: string) {
  const day = new Date(`${date}T00:00:00Z`).getUTCDay().toString();
  return Math.max(0, Number(profile.weekly_minutes?.[day] ?? 0));
}

const normalizedTitle = (value: string) => value.trim().replace(/\s+/g, "").toLocaleLowerCase();

function occupiedMinutes(intervals: number[][], from = 0, to = 1440) {
  let total = 0, last = from;
  for (const [start, end] of [...intervals].sort((a, b) => a[0] - b[0])) {
    const next = Math.min(to, end);
    total += Math.max(0, next - Math.max(last, from, start));
    last = Math.max(last, next);
  }
  return total;
}

export function replanDocument(current: PlannerDocument, session: OnboardingSession) {
  const document = structuredClone(current);
  const owner = document.profile.user_id, now = new Date().toISOString();
  const boundary = session.profile.plan_end_date || session.profile.target_date || dateAdd(session.start_date, 27);
  const fixedTaskIds = new Set([...current.tasks.filter(task => task.is_fixed).map(task => task.id),
    ...current.blocks.filter(block => block.is_fixed).map(block => block.task_id)]);
  const courses = new Map<string, string>();
  const usedSubjects = new Set<string>();
  for (const course of session.courses) {
    const existing = document.subjects.find(subject => subject.id === course.id)
      ?? document.subjects.find(subject => !usedSubjects.has(subject.id) && normalizedTitle(subject.name) === normalizedTitle(course.name));
    const id = existing?.id ?? randomUUID();
    usedSubjects.add(id);
    courses.set(course.id, id);
    if (existing) {
      if (current.tasks.some(task => task.subject_id === id && fixedTaskIds.has(task.id)) && existing.name !== course.name)
        throw new Error(`课程「${existing.name}」包含固定事项，不能在重新规划时改名`);
      Object.assign(existing, { name: course.name, priority: course.priority });
    } else document.subjects.push({ id, user_id: owner, name: course.name, color: "#275e91", priority: course.priority as 1 | 2 | 3 });
  }
  const usedTasks = new Set<string>();
  for (const item of session.items) {
    const subject = courses.get(item.course_id);
    if (!subject) throw new Error(`事项「${item.title}」引用的课程不存在`);
    const existing = document.tasks.find(task => task.id === item.id)
      ?? document.tasks.find(task => !usedTasks.has(task.id) && task.status !== "archived" && task.subject_id === subject && normalizedTitle(task.title) === normalizedTitle(item.title));
    const id = existing?.id ?? randomUUID();
    if (usedTasks.has(id)) throw new Error("多个草案事项指向同一已有事项，请修改后重试");
    usedTasks.add(id);
    const description = [item.description, item.completion_criteria ? `完成标准：${item.completion_criteria}` : ""].filter(Boolean).join("\n");
    const completed = Math.max(existing?.completed_minutes ?? 0, current.logs.filter(log => log.task_id === id).reduce((sum, log) => sum + log.minutes, 0));
    if (item.estimated_minutes < completed) throw new Error(`事项「${item.title}」的总预算不能少于已完成的${completed}分钟`);
    // 本期安排边界随新周期延展；真实截止日期原样保留。
    const deadline = item.deadline_kind === "plan_end" ? boundary : item.deadline;
    if (existing && fixedTaskIds.has(existing.id)) {
      if (existing.subject_id !== subject || existing.title !== item.title || (existing.description ?? "") !== description
        || existing.estimated_minutes !== item.estimated_minutes || existing.priority !== item.priority
        || existing.earliest_date !== item.earliest_date)
        throw new Error(`固定事项「${existing.title}」不能在重新规划时修改，请在计划中先解除固定`);
      continue;
    }
    const task: PlannerDocument["tasks"][number] = { ...existing, id, user_id: owner, subject_id: subject,
      title: item.title, description, estimated_minutes: item.estimated_minutes, completed_minutes: completed,
      priority: item.priority as 1 | 2 | 3, earliest_date: item.earliest_date, deadline, deadline_kind: item.deadline_kind ?? "deadline", is_fixed: false,
      status: existing?.status === "completed" ? "completed" : completed > 0 ? "in_progress" : "not_started",
      created_at: existing?.created_at ?? now, updated_at: now };
    if (existing) Object.assign(existing, task);
    else document.tasks.push(task);
  }
  for (const task of document.tasks) {
    if (usedTasks.has(task.id)) continue;
    if (fixedTaskIds.has(task.id)) throw new Error(`请保留固定事项「${task.title}」，或先在计划中解除固定`);
    if (task.status !== "completed") task.status = "archived";
  }
  const loggedBlocks = new Set(document.logs.map(log => log.block_id).filter(Boolean));
  const protectedTaskIds = new Set(document.tasks.filter(task => task.is_fixed).map(task => task.id));
  document.blocks = document.blocks.filter(block => block.date < session.start_date || block.is_fixed
    || protectedTaskIds.has(block.task_id) || block.status === "completed" || block.actual_minutes > 0 || loggedBlocks.has(block.id));
  const remaining = new Map(document.tasks.filter(task => usedTasks.has(task.id) && !task.is_fixed && task.status !== "completed")
    .map(task => [task.id, Math.max(0, task.estimated_minutes - task.completed_minutes - document.blocks
      .filter(block => block.task_id === task.id && block.date >= session.start_date && block.status !== "completed")
      .reduce((sum, block) => sum + Math.max(0, block.duration_minutes - block.actual_minutes), 0))]));
  Object.assign(document.profile, {
    goal_text: session.profile.goal_text, goal_type: session.profile.goal_type, goal_subtype: session.profile.goal_subtype,
    target_date: session.profile.target_date, target_date_confirmed: session.profile.target_date_confirmed,
    plan_start_date: session.start_date, plan_end_date: boundary,
    target_school: session.profile.target_school, target_program: session.profile.target_program, foundation: session.profile.current_progress,
    // 访谈确认的学习限制随重新规划写回文档，否则关系表投影会用旧值覆盖刚保存的资料。
    constraints: session.profile.constraints_text,
    // 重新访谈确认的一周配置必须写回文档，否则后续同步会退回每日上限。
    weekly_minutes: normalizeWeek(session.profile.weekly_minutes),
    daily_limit_minutes: Math.max(...Object.values(session.profile.weekly_minutes), 30),
    // 灵活容量假设随规划确认写回文档；字段缺失表示旧会话/未修改，保留文档已有值。
    ...(session.profile.capacity_basis !== undefined ? { capacity_basis: session.profile.capacity_basis } : {}),
    ...(session.profile.weekly_baseline_minutes !== undefined ? { weekly_baseline_minutes: session.profile.weekly_baseline_minutes } : {}),
    ...(session.profile.weekly_range_min_minutes !== undefined ? { weekly_range_min_minutes: session.profile.weekly_range_min_minutes } : {}),
    ...(session.profile.weekly_range_max_minutes !== undefined ? { weekly_range_max_minutes: session.profile.weekly_range_max_minutes } : {}),
    ...(session.profile.week_capacity_overrides !== undefined ? { week_capacity_overrides: structuredClone(session.profile.week_capacity_overrides) } : {}),
    ...(session.profile.date_capacity_overrides !== undefined ? { date_capacity_overrides: structuredClone(session.profile.date_capacity_overrides) } : {}),
    ...(session.profile.target_date ? { exam_date: session.profile.target_date, exam_end_date: session.profile.target_date } : { exam_date: undefined, exam_end_date: undefined }),
  });
  let generatedCount = 0;
  for (let date = session.start_date; date <= boundary; date = dateAdd(date, 1)) {
    const weekday = new Date(`${date}T00:00:00Z`).getUTCDay();
    const protectedBlocks = document.blocks.filter(block => block.date === date);
    const events = document.fixed_events.filter(event => event.date <= date && (event.date === date
      || event.repeat === "daily" || event.repeat === "weekly" && new Date(`${event.date}T00:00:00Z`).getUTCDay() === weekday));
    const eventIntervals = events.map(event => [event.start_minute, event.start_minute + event.duration_minutes]);
    const intervals = [...eventIntervals, ...protectedBlocks.map(block => [block.start_minute,
      block.start_minute + Math.max(block.duration_minutes, block.actual_minutes)])].sort((a, b) => a[0] - b[0]);
    const reserved = document.profile.planning_mode === "timed"
      ? occupiedMinutes(intervals, document.profile.study_start_minute, document.profile.study_end_minute)
      : occupiedMinutes(eventIntervals) + protectedBlocks.reduce((sum, block) => sum + Math.max(block.duration_minutes, block.actual_minutes), 0);
    let capacity = Math.max(0, Math.min(480, session.profile.weekly_minutes[String(weekday)] ?? 0)
      - Math.max(30, document.profile.buffer_minutes) - reserved);
    const usedCourse = new Map<string, number>();
    for (const block of protectedBlocks) {
      const subject = document.tasks.find(task => task.id === block.task_id)?.subject_id;
      if (subject) usedCourse.set(subject, (usedCourse.get(subject) ?? 0) + block.duration_minutes);
    }
    const available = document.tasks.filter(task => remaining.has(task.id) && (task.earliest_date ?? date) <= date && task.deadline >= date)
      .sort((a, b) => a.deadline.localeCompare(b.deadline) || b.priority - a.priority);
    for (const task of available) {
      const amount = Math.min(capacity, remaining.get(task.id) ?? 0, Math.min(240, document.profile.subject_limit_minutes) - (usedCourse.get(task.subject_id) ?? 0));
      if (amount <= 0) continue;
      let pending = amount;
      while (pending > 0) {
        let start = 0, minutes = pending;
        if (document.profile.planning_mode === "timed") {
          start = document.profile.study_start_minute;
          for (const [a, b] of intervals) {
            if (b <= start) continue;
            if (a > start) break;
            start = Math.max(start, b);
          }
          const end = Math.min(document.profile.study_end_minute, intervals.find(([a, b]) => a > start && b > start)?.[0] ?? 1440);
          minutes = Math.min(pending, end - start);
          if (minutes <= 0) break;
          intervals.push([start, start + minutes]);
          intervals.sort((a, b) => a[0] - b[0]);
        }
        document.blocks.push({ id: randomUUID(), user_id: owner, task_id: task.id, date, start_minute: start,
          duration_minutes: minutes, actual_minutes: 0, is_fixed: false, status: "planned", completion_status: "not_started",
          created_at: now, updated_at: now, advice_text: `${task.title}：按完成标准推进，并记录学习进度。`, advice_topics: [] });
        pending -= minutes;
        generatedCount++;
      }
      const allocated = amount - pending;
      capacity -= allocated;
      remaining.set(task.id, (remaining.get(task.id) ?? 0) - allocated);
      usedCourse.set(task.subject_id, (usedCourse.get(task.subject_id) ?? 0) + allocated);
    }
  }
  return { document, generatedCount, unscheduledMinutes: [...remaining.values()].reduce((sum, value) => sum + value, 0),
    unfinishedMinutes: [...remaining.keys()].reduce((sum, id) => {
      const task = document.tasks.find(task => task.id === id)!;
      return sum + Math.max(0, task.estimated_minutes - task.completed_minutes);
    }, 0) };
}

async function generateRows(client: pg.PoolClient, userId: string, from: string, profile: ProfileRow, items: ItemRow[], advice = true) {
  const rows: Array<{ itemId: string; date: string; minutes: number; advice: string; topics: string[] }> = [];
  const logTotals = await client.query<{ item_id: string; total: number }>("select item_id, coalesce(sum(minutes),0)::int as total from study_logs where user_id=$1 group by item_id", [userId]);
  const totals = new Map(logTotals.rows.map((row) => [row.item_id, row.total]));
  const remaining = new Map(items.map((item) => [item.id, Math.max(0, item.estimated_minutes - (totals.get(item.id) ?? 0))]));
  const first = from;
  const boundary = planBoundary(profile, from);
  for (let date = first; date <= boundary; date = dateAdd(date, 1)) {
    let capacity = Math.max(0, Math.min(480, dayMinutes(profile, date)) - 30);
    if (capacity <= 0) continue;
    const usedCourse = new Map<string, number>();
    const available = items.filter((item) => (item.earliest_date ?? first) <= date && item.deadline >= date && (remaining.get(item.id) ?? 0) > 0)
      .sort((a, b) => a.deadline.localeCompare(b.deadline) || b.priority - a.priority);
    while (capacity > 0) {
      let allocated = false;
      for (const item of available) {
        if (capacity <= 0) break;
        const courseUsed = usedCourse.get(item.course_id) ?? 0;
        const amount = Math.min(30, capacity, remaining.get(item.id) ?? 0, 240 - courseUsed);
        if (amount <= 0) continue;
        const existing = rows.find((row) => row.itemId === item.id && row.date === date);
        if (existing) existing.minutes += amount;
        else rows.push({ itemId: item.id, date, minutes: amount, advice: "", topics: [] });
        remaining.set(item.id, (remaining.get(item.id) ?? 0) - amount);
        usedCourse.set(item.course_id, courseUsed + amount);
        capacity -= amount;
        allocated = true;
      }
      if (!allocated) break;
    }
  }
  for (const row of rows) {
    const item = items.find((candidate) => candidate.id === row.itemId)!;
    const generated = advice && row.date <= dateAdd(first, 14) ? await adviceFor(item, row.date) : { advice_text: `${item.title}：按完成标准推进一小段，记录具体卡点。`, advice_topics: [] };
    row.advice = generated.advice_text;
    row.topics = generated.advice_topics;
  }
  for (const row of rows) {
    await client.query(`insert into daily_plan_items(user_id,item_id,date,planned_minutes,advice_text,advice_topics)
      values($1,$2,$3,$4,$5,$6) on conflict(user_id,item_id,date) do update set planned_minutes=excluded.planned_minutes, advice_text=excluded.advice_text, advice_topics=excluded.advice_topics, updated_at=now()`,
      [userId, row.itemId, row.date, row.minutes, row.advice, JSON.stringify(row.topics)]);
  }
  return rows;
}

async function requireLegacyPlan(client: pg.PoolClient, userId: string) {
  const state = (await client.query<{ document: PlannerDocument | null }>(
    "select document from planner_sync_state where user_id=$1 for update", [userId])).rows[0];
  const stored = await client.query<{ present: boolean }>(`select exists(
    select 1 from profiles where user_id=$1 and planning_metadata is not null
    union all select 1 from items where user_id=$1 and planning_metadata is not null
    union all select 1 from daily_plan_items where user_id=$1 and activity_instance_id is not null
  ) as present`, [userId]);
  const document = state?.document;
  if (stored.rows[0].present || document?.planning || document?.tasks.some(task => task.planning)
    || document?.blocks.some(block => block.activity_instance_id))
    throw new Error("当前计划包含学习路线与活动策略，请使用新版检查和调整预览后确认；旧版直接写入已停止，当前计划已保留");
}

export async function generatePlan(userId: string, from = dateToday()) {
  return transaction(async (client) => {
    await requireLegacyPlan(client, userId);
    const profile = (await client.query<ProfileRow>(`select ${PROFILE_COLUMNS} from profiles where user_id=$1`, [userId])).rows[0];
    if (!profile) throw new Error("请先完成学习目标设置");
    const itemResult = await client.query<ItemRow>(`select ${ITEM_COLUMNS} from items where user_id=$1 and confirmed=true and status not in ('completed','archived') order by deadline, priority desc`, [userId]);
    await client.query("delete from daily_plan_items where user_id=$1 and date >= $2", [userId, from]);
    const rows = await generateRows(client, userId, from, profile, itemResult.rows);
    return { from, to: planBoundary(profile, from), count: rows.length };
  });
}

export async function confirmDraft(userId: string, draft: { courses: Array<{ id: string; name: string; description: string; priority: number }>; items: Array<{ id: string; course_id: string; title: string; description: string; completion_criteria: string; estimated_minutes: number; earliest_date?: string; deadline: string; deadline_kind?: string; priority: number }>; analysis_summary: string; assumptions: string[]; warnings: string[] }, options: { client?: pg.PoolClient; from?: string; advice?: boolean } = {}) {
  const persist = async (client: pg.PoolClient) => {
    if ((draft as { planning?: unknown }).planning || draft.items.some(item => (item as { planning?: unknown }).planning))
      throw new Error("新版学习策略需要先检查和预览，请从规划访谈确认；当前草案已保留");
    await requireLegacyPlan(client, userId);
    const profile = (await client.query<ProfileRow>(`select ${PROFILE_COLUMNS} from profiles where user_id=$1`, [userId])).rows[0];
    if (!profile) throw new Error("请先保存学习目标设置");
    const from = options.from ?? dateToday();
    const boundary = planBoundary(profile, from);
    for (const item of draft.items) {
      // 真实截止日期是业务约束，可以晚于本期结束日：本次只安排与周期相交的部分。
      // 本期安排边界类事项跟随确认的规划周期，且不能早于事项开始日期。
      if (item.earliest_date && item.earliest_date > item.deadline) throw new Error(`事项 ${item.title} 的开始日期晚于截止日期`);
    }
    const courseIds = new Map<string, string>();
    for (const course of draft.courses) {
      const inserted = await client.query<{ id: string }>("insert into courses(user_id,name,description,priority) values($1,$2,$3,$4) returning id", [userId, course.name, course.description, course.priority]);
      courseIds.set(course.id, inserted.rows[0].id);
    }
    const itemIds = new Map<string, string>();
    for (const item of draft.items) {
      const courseId = courseIds.get(item.course_id);
      if (!courseId) throw new Error(`事项 ${item.title} 引用的课程不存在`);
      // 本期安排边界跟随周期结束日期；真实截止日期原样保存，可以晚于本期。
      const kind = item.deadline_kind ?? "deadline";
      const deadline = kind === "plan_end"
        ? (item.earliest_date && item.earliest_date > boundary ? item.earliest_date : boundary)
        : item.deadline;
      const inserted = await client.query<{ id: string }>(`insert into items(user_id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date,deadline,deadline_kind,priority,confirmed)
        values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,true) returning id`, [userId, courseId, item.title, item.description, item.completion_criteria, item.estimated_minutes, item.earliest_date ?? null, deadline, kind, item.priority]);
      itemIds.set(item.id, inserted.rows[0].id);
    }
    const version = await client.query<{ id: string }>("insert into plan_versions(user_id,kind,payload) values($1,'confirmed',$2) returning id", [userId, JSON.stringify({ ...draft, courseIds: Object.fromEntries(courseIds), itemIds: Object.fromEntries(itemIds) })]);
    const items = await client.query<ItemRow>(`select ${ITEM_COLUMNS} from items where user_id=$1 and confirmed=true and status not in ('completed','archived') order by deadline,priority desc`, [userId]);
    const rows = await generateRows(client, userId, from, profile, items.rows, options.advice ?? true);
    const total = draft.items.reduce((sum, item) => sum + item.estimated_minutes, 0);
    return { versionId: version.rows[0].id, courseIds: Object.fromEntries(courseIds), itemIds: Object.fromEntries(itemIds),
      generated: { from, to: boundary, count: rows.length, unscheduled_minutes: Math.max(0, total - rows.reduce((sum, row) => sum + row.minutes, 0)) } };
  };
  return options.client ? persist(options.client) : transaction(persist);
}

export async function settleDay(userId: string, date: string, entries: Array<{ item_id: string; actual_minutes: number; completion_status: string; feedback: string }>, feedback: string) {
  return transaction(async (client) => {
    await requireLegacyPlan(client, userId);
    const before = (await client.query("select * from daily_plan_items where user_id=$1 and date >= $2 order by date, item_id", [userId, dateAdd(date, 1)])).rows;
    for (const entry of entries) {
      const daily = await client.query<{ id: string }>("select id from daily_plan_items where user_id=$1 and item_id=$2 and date=$3", [userId, entry.item_id, date]);
      if (!daily.rows[0]) continue;
      await client.query("update daily_plan_items set actual_minutes=$1, completion_status=$2, updated_at=now() where id=$3 and user_id=$4", [entry.actual_minutes, entry.completion_status, daily.rows[0].id, userId]);
      await client.query("delete from study_logs where user_id=$1 and item_id=$2 and date=$3", [userId, entry.item_id, date]);
      await client.query("insert into study_logs(user_id,item_id,daily_plan_item_id,date,minutes,feedback) values($1,$2,$3,$4,$5,$6)", [userId, entry.item_id, daily.rows[0].id, date, entry.actual_minutes, entry.feedback]);
      if (entry.completion_status === "completed") await client.query("update items set status='completed', updated_at=now() where id=$1 and user_id=$2", [entry.item_id, userId]);
    }
    await client.query("insert into daily_reviews(user_id,date,feedback,result) values($1,$2,$3,$4) on conflict(user_id,date) do update set feedback=excluded.feedback,result=excluded.result,settled_at=now()", [userId, date, feedback, JSON.stringify({ entries })]);
    const profile = (await client.query<ProfileRow>(`select ${PROFILE_COLUMNS} from profiles where user_id=$1`, [userId])).rows[0];
    const items = (await client.query<ItemRow>(`select ${ITEM_COLUMNS} from items where user_id=$1 and confirmed=true and status not in ('completed','archived') order by deadline,priority desc`, [userId])).rows;
    await client.query("delete from daily_plan_items where user_id=$1 and date >= $2 and actual_minutes=0 and completion_status <> 'completed'", [userId, dateAdd(date, 1)]);
    const afterRows = await generateRows(client, userId, dateAdd(date, 1), profile, items);
    const after = await client.query("select * from daily_plan_items where user_id=$1 and date >= $2 order by date, item_id", [userId, dateAdd(date, 1)]);
    const run = await client.query<{ id: string }>("insert into replan_runs(user_id,date,before_payload,after_payload,explanation) values($1,$2,$3,$4,$5) returning id", [userId, date, JSON.stringify(before), JSON.stringify(after.rows), `根据 ${date} 的实际用时和完成反馈，重新安排了未来 ${afterRows.length} 个事项日程。`]);
    return { runId: run.rows[0].id, changed: JSON.stringify(before) !== JSON.stringify(after.rows), futureCount: afterRows.length };
  });
}

export async function undoRun(userId: string, runId: string) {
  return transaction(async (client) => {
    await requireLegacyPlan(client, userId);
    const result = await client.query<{ before_payload: DailyRow[]; after_payload: DailyRow[]; date: string }>("select before_payload,after_payload,date::text from replan_runs where id=$1 and user_id=$2 and undone_at is null", [runId, userId]);
    const run = result.rows[0];
    if (!run) throw new Error("找不到可撤销的调整");
    await client.query("delete from daily_plan_items where user_id=$1 and date > $2", [userId, run.date]);
    for (const row of run.before_payload) await client.query(`insert into daily_plan_items(id,user_id,item_id,date,planned_minutes,actual_minutes,advice_text,advice_topics,completion_status) values($1,$2,$3,$4,$5,$6,$7,$8,$9) on conflict(user_id,item_id,date) do update set planned_minutes=excluded.planned_minutes, advice_text=excluded.advice_text, advice_topics=excluded.advice_topics, completion_status=excluded.completion_status, updated_at=now()`, [row.id ?? randomUUID(), userId, row.item_id, row.date, row.planned_minutes, row.actual_minutes ?? 0, row.advice_text ?? "", JSON.stringify(row.advice_topics ?? []), row.completion_status ?? "not_started"]);
    await client.query("update replan_runs set undone_at=now() where id=$1 and user_id=$2", [runId, userId]);
    return { undone: true };
  });
}
