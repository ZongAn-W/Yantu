import { randomUUID } from "node:crypto";
import type pg from "pg";
import { adviceFor } from "./ai.js";
import { query, transaction } from "./db.js";

type ProfileRow = { exam_type: string; exam_date: string; target_school: string; target_program: string; current_progress: string; weekly_minutes: Record<string, number>; constraints_text: string };
export type ItemRow = { id: string; course_id: string; course_name?: string; title: string; description: string; completion_criteria: string; estimated_minutes: number; earliest_date: string | null; deadline: string; priority: number; status: string };
type DailyRow = { id: string; item_id: string; date: string; planned_minutes: number; actual_minutes: number; advice_text: string; advice_topics: string[]; completion_status: string; item_title?: string; course_name?: string };

export function dateAdd(date: string, days: number) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}

export function dateToday() { return new Date().toISOString().slice(0, 10); }

export async function getProfile(userId: string): Promise<ProfileRow | null> {
  const result = await query<ProfileRow>("select exam_type, exam_date::text, target_school, target_program, current_progress, weekly_minutes, constraints_text from profiles where user_id = $1", [userId]);
  return result.rows[0] ?? null;
}

export async function saveProfile(userId: string, profile: ProfileRow) {
  await query(`insert into profiles(user_id, exam_type, exam_date, target_school, target_program, current_progress, weekly_minutes, constraints_text)
    values($1,$2,$3,$4,$5,$6,$7,$8)
    on conflict(user_id) do update set exam_type=excluded.exam_type, exam_date=excluded.exam_date, target_school=excluded.target_school, target_program=excluded.target_program, current_progress=excluded.current_progress, weekly_minutes=excluded.weekly_minutes, constraints_text=excluded.constraints_text, updated_at=now()`,
    [userId, profile.exam_type, profile.exam_date, profile.target_school, profile.target_program, profile.current_progress, JSON.stringify(profile.weekly_minutes), profile.constraints_text]);
}

export function itemToJson(row: ItemRow) {
  return { id: row.id, course_id: row.course_id, title: row.title, description: row.description, completion_criteria: row.completion_criteria, estimated_minutes: row.estimated_minutes, earliest_date: row.earliest_date ?? undefined, deadline: row.deadline, priority: row.priority, status: row.status };
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

export async function snapshot(userId: string) {
  const profile = await getProfile(userId);
  if (!profile) return null;
  const courses = await query<{ id: string; name: string; priority: number }>("select id,name,priority from courses where user_id=$1 order by created_at", [userId]);
  const items = await query<ItemRow>("select id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date::text,deadline::text,priority,status from items where user_id=$1 order by deadline,created_at", [userId]);
  const days = await query<DailyRow>("select d.id,d.item_id,d.date::text,d.planned_minutes,d.actual_minutes,d.advice_text,d.advice_topics,d.completion_status,i.title as item_title,c.name as course_name from daily_plan_items d join items i on i.id=d.item_id join courses c on c.id=i.course_id where d.user_id=$1 order by d.date,d.id", [userId]);
  const logs = await query<{ id: string; item_id: string; daily_plan_item_id: string | null; date: string; minutes: number; created_at: string }>("select id,item_id,daily_plan_item_id,date::text,minutes,created_at from study_logs where user_id=$1 order by created_at", [userId]);
  const logged = new Map<string, number>();
  for (const log of logs.rows) logged.set(log.item_id, (logged.get(log.item_id) ?? 0) + log.minutes);
  const now = new Date().toISOString();
  return {
    version: 1 as const,
    profile: { user_id: userId, planning_mode: "daily" as const, target_school: profile.target_school, target_program: profile.target_program, exam_date: profile.exam_date, exam_end_date: profile.exam_date, daily_limit_minutes: Math.max(30, Math.min(480, Math.max(...Object.values(profile.weekly_minutes), 30))), granularity_minutes: 30, buffer_minutes: 30, subject_limit_minutes: 240, study_start_minute: 480, study_end_minute: 1320, foundation: profile.current_progress },
    subjects: courses.rows.map((course) => ({ id: course.id, user_id: userId, name: course.name, color: "#275e91", priority: course.priority as 1 | 2 | 3 })),
    tasks: items.rows.map((item) => ({ id: item.id, user_id: userId, subject_id: item.course_id, title: item.title, description: [item.description, item.completion_criteria ? `完成标准：${item.completion_criteria}` : ""].filter(Boolean).join("\n"), estimated_minutes: item.estimated_minutes, completed_minutes: Math.min(item.estimated_minutes, logged.get(item.id) ?? 0), priority: item.priority as 1 | 2 | 3, deadline: item.deadline, earliest_date: item.earliest_date ?? undefined, is_fixed: false, status: (item.status === "completed" ? "completed" : (logged.get(item.id) ?? 0) > 0 ? "in_progress" : "not_started") as "not_started" | "in_progress" | "completed", created_at: now, updated_at: now })),
    blocks: days.rows.map((day) => ({ id: day.id, user_id: userId, task_id: day.item_id, date: day.date, start_minute: 0, duration_minutes: day.planned_minutes, actual_minutes: day.actual_minutes, is_fixed: false, status: (day.completion_status === "completed" ? "completed" : "planned") as "planned" | "completed", created_at: now, updated_at: now, advice_text: day.advice_text, advice_topics: day.advice_topics, completion_status: day.completion_status })),
    logs: logs.rows.map((log) => ({ id: log.id, user_id: userId, task_id: log.item_id, block_id: log.daily_plan_item_id, date: log.date, minutes: log.minutes, started_at: log.created_at, ended_at: log.created_at, source: "manual" as const })),
    fixed_events: [], replan_runs: [], phases: [],
  };
}

function dayMinutes(profile: ProfileRow, date: string) {
  const day = new Date(`${date}T00:00:00Z`).getUTCDay().toString();
  return Math.max(0, Number(profile.weekly_minutes?.[day] ?? 0));
}

async function generateRows(client: pg.PoolClient, userId: string, from: string, profile: ProfileRow, items: ItemRow[], advice = true) {
  const rows: Array<{ itemId: string; date: string; minutes: number; advice: string; topics: string[] }> = [];
  const logTotals = await client.query<{ item_id: string; total: number }>("select item_id, coalesce(sum(minutes),0)::int as total from study_logs where user_id=$1 group by item_id", [userId]);
  const totals = new Map(logTotals.rows.map((row) => [row.item_id, row.total]));
  const remaining = new Map(items.map((item) => [item.id, Math.max(0, item.estimated_minutes - (totals.get(item.id) ?? 0))]));
  const first = from;
  for (let date = first; date <= profile.exam_date; date = dateAdd(date, 1)) {
    let capacity = dayMinutes(profile, date);
    if (capacity <= 0) continue;
    const usedCourse = new Map<string, number>();
    const available = items.filter((item) => (item.earliest_date ?? first) <= date && item.deadline >= date && (remaining.get(item.id) ?? 0) > 0)
      .sort((a, b) => a.deadline.localeCompare(b.deadline) || b.priority - a.priority);
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

export async function generatePlan(userId: string, from = dateToday()) {
  return transaction(async (client) => {
    const profileResult = await client.query<ProfileRow>("select exam_type, exam_date::text, target_school, target_program, current_progress, weekly_minutes, constraints_text from profiles where user_id=$1", [userId]);
    const profile = profileResult.rows[0];
    if (!profile) throw new Error("请先完成备考资料");
    const itemResult = await client.query<ItemRow>("select id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date::text,deadline::text,priority,status from items where user_id=$1 and confirmed=true and status <> 'completed' order by deadline, priority desc", [userId]);
    await client.query("delete from daily_plan_items where user_id=$1 and date >= $2", [userId, from]);
    const rows = await generateRows(client, userId, from, profile, itemResult.rows);
    return { from, to: profile.exam_date, count: rows.length };
  });
}

export async function confirmDraft(userId: string, draft: { courses: Array<{ id: string; name: string; description: string; priority: number }>; items: Array<{ id: string; course_id: string; title: string; description: string; completion_criteria: string; estimated_minutes: number; earliest_date?: string; deadline: string; priority: number }>; analysis_summary: string; assumptions: string[]; warnings: string[] }) {
  return transaction(async (client) => {
    const profile = (await client.query<{ exam_date: string }>("select exam_date::text from profiles where user_id=$1", [userId])).rows[0];
    if (!profile) throw new Error("请先保存备考资料");
    for (const item of draft.items) {
      if (item.deadline > profile.exam_date || (item.earliest_date && item.earliest_date > item.deadline)) throw new Error(`事项 ${item.title} 的日期超出考试范围`);
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
      const inserted = await client.query<{ id: string }>(`insert into items(user_id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date,deadline,priority,confirmed)
        values($1,$2,$3,$4,$5,$6,$7,$8,$9,true) returning id`, [userId, courseId, item.title, item.description, item.completion_criteria, item.estimated_minutes, item.earliest_date ?? null, item.deadline, item.priority]);
      itemIds.set(item.id, inserted.rows[0].id);
    }
    const version = await client.query<{ id: string }>("insert into plan_versions(user_id,kind,payload) values($1,'confirmed',$2) returning id", [userId, JSON.stringify({ ...draft, courseIds: Object.fromEntries(courseIds), itemIds: Object.fromEntries(itemIds) })]);
    return { versionId: version.rows[0].id, courseIds: Object.fromEntries(courseIds), itemIds: Object.fromEntries(itemIds) };
  }).then(async (result) => ({ ...result, generated: await generatePlan(userId) }));
}

export async function settleDay(userId: string, date: string, entries: Array<{ item_id: string; actual_minutes: number; completion_status: string; feedback: string }>, feedback: string) {
  return transaction(async (client) => {
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
    const profile = (await client.query<ProfileRow>("select exam_type, exam_date::text, target_school, target_program, current_progress, weekly_minutes, constraints_text from profiles where user_id=$1", [userId])).rows[0];
    const items = (await client.query<ItemRow>("select id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date::text,deadline::text,priority,status from items where user_id=$1 and confirmed=true and status <> 'completed' order by deadline,priority desc", [userId])).rows;
    await client.query("delete from daily_plan_items where user_id=$1 and date >= $2 and actual_minutes=0 and completion_status <> 'completed'", [userId, dateAdd(date, 1)]);
    const afterRows = await generateRows(client, userId, dateAdd(date, 1), profile, items);
    const after = await client.query("select * from daily_plan_items where user_id=$1 and date >= $2 order by date, item_id", [userId, dateAdd(date, 1)]);
    const run = await client.query<{ id: string }>("insert into replan_runs(user_id,date,before_payload,after_payload,explanation) values($1,$2,$3,$4,$5) returning id", [userId, date, JSON.stringify(before), JSON.stringify(after.rows), `根据 ${date} 的实际用时和完成反馈，重新安排了未来 ${afterRows.length} 个事项日程。`]);
    return { runId: run.rows[0].id, changed: JSON.stringify(before) !== JSON.stringify(after.rows), futureCount: afterRows.length };
  });
}

export async function undoRun(userId: string, runId: string) {
  return transaction(async (client) => {
    const result = await client.query<{ before_payload: DailyRow[]; after_payload: DailyRow[]; date: string }>("select before_payload,after_payload,date::text from replan_runs where id=$1 and user_id=$2 and undone_at is null", [runId, userId]);
    const run = result.rows[0];
    if (!run) throw new Error("找不到可撤销的调整");
    await client.query("delete from daily_plan_items where user_id=$1 and date > $2", [userId, run.date]);
    for (const row of run.before_payload) await client.query(`insert into daily_plan_items(id,user_id,item_id,date,planned_minutes,actual_minutes,advice_text,advice_topics,completion_status) values($1,$2,$3,$4,$5,$6,$7,$8,$9) on conflict(user_id,item_id,date) do update set planned_minutes=excluded.planned_minutes, advice_text=excluded.advice_text, advice_topics=excluded.advice_topics, completion_status=excluded.completion_status, updated_at=now()`, [row.id ?? randomUUID(), userId, row.item_id, row.date, row.planned_minutes, row.actual_minutes ?? 0, row.advice_text ?? "", JSON.stringify(row.advice_topics ?? []), row.completion_status ?? "not_started"]);
    await client.query("update replan_runs set undone_at=now() where id=$1 and user_id=$2", [runId, userId]);
    return { undone: true };
  });
}
