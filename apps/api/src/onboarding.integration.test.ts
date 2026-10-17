import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { SignJWT } from "jose";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { ProfileSchema } from "./contracts.js";
import { newSession, type OnboardingSession } from "./onboarding-contracts.js";

describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)("persisted onboarding", () => {
  let app: Awaited<ReturnType<(typeof import("./server.js"))["buildApp"]>>;
  let db: typeof import("./db.js");
  const secret = "onboarding-test-012345678901234567890";
  async function account() {
    const id = randomUUID();
    await db.query("insert into users(id,email,username,password_hash) values($1,$2,$3,$4)", [id, `${id}@example.test`, id, "test-only"]);
    const token = await new SignJWT({ email: `${id}@example.test`, username: id, type: "access" }).setProtectedHeader({ alg: "HS256" }).setSubject(id).setExpirationTime("1h").sign(new TextEncoder().encode(secret));
    return { id, headers: { authorization: `Bearer ${token}` } };
  }
  type Account = Awaited<ReturnType<typeof account>>;
  const get = (user: Account, url = "/api/onboarding/session") => app.inject({ url, headers: user.headers });
  const act = (user: Account, session: OnboardingSession, action: unknown) => app.inject({ method: "POST", url: "/api/ai/onboarding/advance", headers: user.headers, payload: { revision: session.revision, action } });

  beforeAll(async () => {
    vi.stubEnv("DATABASE_URL", process.env.AUTH_TEST_DATABASE_URL!);
    vi.stubEnv("JWT_ACCESS_SECRET", secret);
    vi.stubEnv("AI_API_KEY", "");
    vi.stubEnv("NODE_ENV", "test");
    db = await import("./db.js");
    await db.query(await readFile(new URL("../db/schema.sql", import.meta.url), "utf8"));
    app = await (await import("./server.js")).buildApp();
    await app.ready();
  });
  afterAll(async () => { await app?.close(); await db?.pool.end(); vi.unstubAllEnvs(); });

  it("isolates accounts, resumes answers and rejects stale submissions", async () => {
    expect((await app.inject({ url: "/api/onboarding/session" })).statusCode).toBe(401);
    const user = await account();
    const initial = (await get(user)).json().session;
    expect(initial.question_options).toContain("考试备考");
    expect(initial.question_multiple).toBe(false);
    const answered = await act(user, initial, { type: "answer", answer: "准备雅思7分" });
    expect(answered.statusCode, answered.body).toBe(200);
    expect((await get(user)).json().session.answers[0].answer).toBe("准备雅思7分");
    const resumed = (await get(user)).json().session;
    expect(resumed.recommendations.plan_end_date).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(Object.keys(resumed.recommendations.weekly_minutes)).toHaveLength(7);
    expect(resumed.profile.target_date).toBeNull();
    expect((await act(user, initial, { type: "answer", answer: "重复" })).statusCode).toBe(409);
    expect((await get(await account())).json().session.answers).toEqual([]);
    expect((await get(user, "/api/onboarding/profile")).json().profile).toBeNull();
  });

  it("creates the confirmed plan once, respecting the selected start and daily limits", async () => {
    const user = await account();
    let session: OnboardingSession = (await get(user)).json().session;
    async function next(action: unknown) {
      const response = await act(user, session, action);
      expect(response.statusCode, response.body).toBe(200);
      session = response.json().session;
    }
    for (const text of ["考研", "上海交通大学", "计算机", "2027年", "高数一轮"]) await next({ type: "answer", answer: text });
    expect(session.stage).toBe("checkpoint");
    const { shanghaiDate: cycleToday } = await import("./onboarding-ai.js");
    const { dateAdd: cycleAdd } = await import("./planner.js");
    expect(session.recommendations.target_date).toBe("");
    expect(session.recommendations.plan_end_date).toBe(cycleAdd(cycleToday(), 27));
    await next({ type: "generate_courses" });
    expect(session.items).toEqual([]);
    expect((await get(user, "/api/onboarding/profile")).json().profile).toBeNull();
    await next({ type: "confirm_courses", courses: [
      { id: "math", name: "高数", priority: 3 }, { id: "english", name: "英语", priority: 2 },
    ] });
    expect(session.items.every(item => item.deadline === session.recommendations.plan_end_date && item.deadline_kind === "plan_end")).toBe(true);
    const { shanghaiDate } = await import("./onboarding-ai.js");
    const { dateAdd } = await import("./planner.js");
    const start = dateAdd(shanghaiDate(), 5), end = dateAdd(start, 3);
    await next({ type: "confirm_items", items: session.items.map(i => ({ ...i, estimated_minutes: 300, earliest_date: start, deadline: end })) });
    const before = session;
    const finish = { type: "finish", start_date: start, end_date: end, weekly_minutes: { "0": 480, "1": 480, "2": 480, "3": 480, "4": 480, "5": 480, "6": 480 } };
    await next(finish);
    expect(session.stage).toBe("complete");
    expect((await get(user, "/api/onboarding/profile")).json().profile.plan_end_date).toBe(end);
    const daily = await db.query<{ date: string; total: number }>("select date::text,sum(planned_minutes)::int as total from daily_plan_items where user_id=$1 group by date order by date", [user.id]);
    expect(daily.rows[0].date).toBe(start);
    expect(daily.rows.every(row => row.date <= end && row.total <= 450)).toBe(true);
    expect(daily.rows.reduce((sum, row) => sum + row.total, 0)).toBe(1200);
    const perCourse = await db.query<{ total: number }>("select sum(d.planned_minutes)::int as total from daily_plan_items d join items i on i.id=d.item_id where d.user_id=$1 group by d.date,i.course_id", [user.id]);
    expect(perCourse.rows.every(row => row.total <= 240)).toBe(true);
    expect((await act(user, before, finish)).statusCode).toBe(200);
    expect((await db.query<{ count: number }>("select count(*)::int as count from courses where user_id=$1", [user.id])).rows[0].count).toBe(2);
    expect((await get(user, "/api/planner/sync")).json().data.blocks.length).toBeGreaterThan(0);
  });

  async function existingPlan(user: Account) {
    const { saveProfile, confirmDraft, dateAdd } = await import("./planner.js");
    const { shanghaiDate } = await import("./onboarding-ai.js");
    const start = shanghaiDate(), end = dateAdd(start, 10);
    await saveProfile(user.id, { ...newSession().profile, goal_text: "考研复习", goal_type: "exam", goal_subtype: "考研",
      plan_start_date: start, plan_end_date: end, target_school: "上海交通大学",
      weekly_minutes: Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map(day => [String(day), 240])) });
    await confirmDraft(user.id, { courses: [{ id: "math", name: "高数", description: "", priority: 2 }], items: ["继续复习", "旧事项"].map((title, i) => ({
      id: `task-${i}`, course_id: "math", title, description: "复习", completion_criteria: "", estimated_minutes: 1200, earliest_date: start, deadline: end, deadline_kind: "plan_end" as const, priority: 2 })), analysis_summary: "", assumptions: [], warnings: [] }, { from: start, advice: false });
    return { start, end, state: (await get(user, "/api/planner/sync")).json() };
  }

  it("persists an uneven week through confirmation, sync, re-interview and re-read", async () => {
    const user = await account();
    const { shanghaiDate } = await import("./onboarding-ai.js");
    const { dateAdd } = await import("./planner.js");
    const start = shanghaiDate(), end = dateAdd(start, 6);
    const week = { "0": 0, "1": 90, "2": 90, "3": 0, "4": 90, "5": 90, "6": 180 };
    // 与真实访谈一致的已确认阶段会话：字段名和结构与 /advance 写回的 payload 相同。
    const schedule = (extra: Partial<OnboardingSession> = {}): OnboardingSession => ({
      ...newSession(),
      stage: "schedule",
      start_date: start,
      end_date: end,
      profile: ProfileSchema.parse({ goal_text: "从零学习 Python", goal_type: "skill",
        plan_start_date: start, plan_end_date: end, weekly_minutes: week }),
      courses: [{ id: "python", name: "Python 基础", description: "", priority: 2 }],
      items: [0, 1].map(index => ({ id: `item-${index}`, course_id: "python", title: `练习 ${index}`,
        description: "", completion_criteria: "", estimated_minutes: 600,
        earliest_date: start, deadline: end, deadline_kind: "plan_end" as const, priority: 2 })),
      ...extra,
    });
    const save = (session: OnboardingSession) => db.query(
      "insert into onboarding_sessions(user_id,revision,payload) values($1,$2,$3) on conflict(user_id) do update set revision=excluded.revision,payload=excluded.payload",
      [user.id, session.revision, JSON.stringify(session)]);

    const first = schedule();
    await save(first);
    const done = await act(user, first, { type: "finish", start_date: start, end_date: end, weekly_minutes: week });
    expect(done.statusCode, done.body).toBe(200);
    expect(done.json().session.stage).toBe("complete");

    // 数据库、计划文档和资料接口读到的都是逐日配置。
    const stored = await db.query<{ weekly_minutes: Record<string, number> }>("select weekly_minutes from profiles where user_id=$1", [user.id]);
    expect(stored.rows[0].weekly_minutes).toEqual(week);
    const sync = (await get(user, "/api/planner/sync")).json();
    expect(sync.data.profile.weekly_minutes).toEqual(week);
    expect((await get(user, "/api/onboarding/profile")).json().profile.weekly_minutes).toEqual(week);
    // 周三和周日是 0，不能生成任何安排。
    const weekday = (date: string) => new Date(`${date}T00:00:00Z`).getUTCDay();
    const dates: string[] = [...new Set<string>(sync.data.blocks.map((block: { date: string }) => block.date))];
    expect(dates.length).toBeGreaterThan(0);
    expect(dates.some(date => weekday(date) === 3)).toBe(false);
    expect(dates.some(date => weekday(date) === 0)).toBe(false);

    // 重新访谈只改周三：其他六天保持各自的值。
    const replanned = schedule({
      revision: done.json().session.revision,
      replanning: true,
      has_plan: true,
      plan_revision: sync.revision,
      current_plan: null,
      end_date: dateAdd(start, 13),
    });
    await save(replanned);
    const changed = { ...week, "3": 120 };
    const revised = await act(user, replanned, { type: "finish", start_date: dateAdd(start, 7), end_date: dateAdd(start, 13), weekly_minutes: changed });
    expect(revised.statusCode, revised.body).toBe(200);
    const after = await db.query<{ weekly_minutes: Record<string, number> }>("select weekly_minutes from profiles where user_id=$1", [user.id]);
    expect(after.rows[0].weekly_minutes).toEqual(changed);
    const resynced = (await get(user, "/api/planner/sync")).json();
    expect(resynced.data.profile.weekly_minutes).toEqual(changed);
    expect(resynced.data.profile.weekly_minutes["3"]).toBe(120);
    expect(resynced.data.profile.weekly_minutes["1"]).toBe(90);
  });
  it("confirms an item whose real deadline is beyond the cycle and schedules only inside it", async () => {
    const user = await account();
    const { shanghaiDate } = await import("./onboarding-ai.js");
    const { dateAdd } = await import("./planner.js");
    const start = shanghaiDate(), end = dateAdd(start, 6);
    const week = { "0": 120, "1": 120, "2": 120, "3": 120, "4": 120, "5": 120, "6": 120 };
    const realDeadline = dateAdd(end, 60);
    const schedule: OnboardingSession = {
      ...newSession(),
      stage: "schedule",
      start_date: start,
      end_date: end,
      profile: ProfileSchema.parse({ goal_text: "长期阅读", goal_type: "self_study",
        plan_start_date: start, plan_end_date: end, weekly_minutes: week }),
      courses: [{ id: "reading", name: "阅读", description: "", priority: 2 }],
      items: [{ id: "far", course_id: "reading", title: "读完一本书", description: "",
        completion_criteria: "读完并写笔记", estimated_minutes: 600,
        earliest_date: start, deadline: realDeadline, deadline_kind: "deadline", priority: 2 }],
    };
    await db.query(
      "insert into onboarding_sessions(user_id,revision,payload) values($1,$2,$3) on conflict(user_id) do update set revision=excluded.revision,payload=excluded.payload",
      [user.id, schedule.revision, JSON.stringify(schedule)],
    );
    const response = await act(user, schedule, { type: "finish", start_date: start, end_date: end, weekly_minutes: week });
    expect(response.statusCode, response.body).toBe(200);

    const items = await db.query<{ deadline: string; deadline_kind: string }>(
      "select deadline::text, deadline_kind from items where user_id=$1",
      [user.id],
    );
    expect(items.rows[0]).toEqual({ deadline: realDeadline, deadline_kind: "deadline" });
    const sync = (await get(user, "/api/planner/sync")).json();
    expect(sync.data.tasks[0].deadline).toBe(realDeadline);
    // 本次只安排与周期相交的部分。
    expect(sync.data.blocks.length).toBeGreaterThan(0);
    for (const block of sync.data.blocks) expect(block.date <= end).toBe(true);
  });

  it("opens legacy accounts in the interview hub and preserves their live plan throughout restart and resume", async () => {
    const user = await account();
    const { state } = await existingPlan(user);
    let session: OnboardingSession = (await get(user)).json().session;
    expect(session).toMatchObject({ stage: "complete", has_plan: true, replanning: false, plan_revision: state.revision });
    expect(session.profile.target_school).toBe("上海交通大学");
    expect(session.answers).toEqual([]);
    const resumed = await act(user, session, { type: "resume_interview" });
    expect(resumed.statusCode, resumed.body).toBe(200);
    session = resumed.json().session;
    expect(session).toMatchObject({ stage: "interview", has_plan: true, replanning: true, revision: 1 });
    expect(session.question).not.toBe(newSession().question);
    expect((await get(user, "/api/onboarding/profile")).json().profile.target_school).toBe("上海交通大学");
    expect((await get(user, "/api/planner/sync")).json().data).toEqual(state.data);
    const restarted = await act(user, session, { type: "restart_interview" });
    expect(restarted.statusCode, restarted.body).toBe(200);
    const restart: OnboardingSession = restarted.json().session;
    expect(restart).toMatchObject({ revision: 2, has_plan: true, replanning: true, answers: [], question: newSession().question });
    expect((await get(user, "/api/onboarding/profile")).json().profile).not.toBeNull();
    expect((await get(await account())).json().session.has_plan).toBe(false);
  });

  it("applies one revised plan atomically, preserving history, logs, fixed events, IDs and completed minutes", async () => {
    const user = await account();
    const { start, end, state } = await existingPlan(user);
    const { dateAdd } = await import("./planner.js");
    const original = structuredClone(state.data), stamp = new Date().toISOString();
    const reused = original.tasks[0], removed = original.tasks[1];
    const actual = original.blocks.find((block: any) => block.task_id === reused.id);
    actual.actual_minutes = 30;
    reused.completed_minutes = 30;
    const fixed = { ...reused, id: randomUUID(), title: "固定复习", completed_minutes: 0, is_fixed: true };
    original.tasks.push(fixed);
    const fixedBlock = { ...actual, id: randomUUID(), task_id: fixed.id, date: dateAdd(start, 3), duration_minutes: 30, actual_minutes: 0, is_fixed: true };
    original.blocks.push(fixedBlock);
    original.logs.push({ id: randomUUID(), user_id: user.id, task_id: reused.id, block_id: actual.id, date: actual.date, minutes: 30, started_at: stamp, ended_at: stamp, source: "manual" });
    original.fixed_events.push({ id: randomUUID(), user_id: user.id, title: "固定课程", date: dateAdd(start, 2), start_minute: 600, duration_minutes: 30, repeat: "daily", kind: "course", created_at: stamp, updated_at: stamp });
    const put = await app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data: original, base: state.data, expectedRevision: state.revision } });
    expect(put.statusCode, put.body).toBe(200);
    let session: OnboardingSession = (await get(user)).json().session;
    const resumed = await act(user, session, { type: "resume_interview" });
    expect(resumed.statusCode, resumed.body).toBe(200);
    session = resumed.json().session;
    session.stage = "schedule";
    session.items = session.items.filter(item => item.id !== removed.id);
    await db.query("update onboarding_sessions set payload=$2 where user_id=$1", [user.id, JSON.stringify(session)]);
    const finish = { type: "finish", start_date: dateAdd(start, 2), end_date: end, weekly_minutes: Object.fromEntries([0, 1, 2, 3, 4, 5, 6].map(day => [String(day), 240])) };
    const response = await act(user, session, finish);
    expect(response.statusCode, response.body).toBe(200);
    const data = (await get(user, "/api/planner/sync")).json().data;
    expect(data.tasks.find((task: any) => task.id === removed.id).status).toBe("archived");
    expect(data.tasks.find((task: any) => task.id === reused.id).completed_minutes).toBe(30);
    expect(data.logs).toEqual(original.logs);
    expect(data.fixed_events).toEqual(original.fixed_events);
    for (const block of original.blocks.filter((block: any) => block.date < finish.start_date || block.is_fixed || block.actual_minutes > 0))
      expect(data.blocks.find((row: any) => row.id === block.id)).toEqual(block);
    expect(data.blocks.some((block: any) => block.task_id === removed.id && block.date >= finish.start_date)).toBe(false);
    expect((await act(user, session, finish)).statusCode).toBe(200);
    expect((await db.query<{ count: number }>("select count(*)::int as count from plan_versions where user_id=$1 and kind='replan'", [user.id])).rows[0].count).toBe(1);
    const version = (await db.query<{ payload: any }>("select payload from plan_versions where user_id=$1 and kind='replan'", [user.id])).rows[0].payload;
    expect(version.previous_document.fixed_events).toEqual(original.fixed_events);
    expect(version.previous_session.answers).toEqual(session.answers);
  });

  it("rejects a stale planner revision and allows explicit refresh while retaining the reviewed draft", async () => {
    const user = await account();
    const { start, end, state } = await existingPlan(user);
    const session: OnboardingSession = (await act(user, (await get(user)).json().session, { type: "resume_interview" })).json().session;
    session.stage = "schedule";
    await db.query("update onboarding_sessions set payload=$2 where user_id=$1", [user.id, JSON.stringify(session)]);
    const changed = structuredClone(state.data);
    changed.profile.foundation = "学习进度已更新";
    const put = await app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data: changed, base: state.data, expectedRevision: state.revision } });
    expect(put.statusCode, put.body).toBe(200);
    const finish = { type: "finish", start_date: start, end_date: end, weekly_minutes: { "0": 240, "1": 240, "2": 240, "3": 240, "4": 240, "5": 240, "6": 240 } };
    const conflict = await act(user, session, finish);
    expect(conflict.statusCode, conflict.body).toBe(409);
    expect((await get(user)).json().session.items).toEqual(session.items);
    expect((await get(user, "/api/planner/sync")).json().data).toEqual(changed);
    const refreshed = await act(user, session, { type: "refresh_plan" });
    expect(refreshed.statusCode, refreshed.body).toBe(200);
    expect(refreshed.json().session.items).toEqual(session.items);
    expect(refreshed.json().session.plan_revision).toBe(put.json().revision);
    expect((await act(user, refreshed.json().session, finish)).statusCode).toBe(200);
  });

  it("rolls back an unsuccessful replan and leaves the previously active plan visible", async () => {
    const user = await account();
    const { start, state } = await existingPlan(user);
    const session: OnboardingSession = (await act(user, (await get(user)).json().session, { type: "resume_interview" })).json().session;
    session.stage = "schedule";
    await db.query("update onboarding_sessions set payload=$2 where user_id=$1", [user.id, JSON.stringify(session)]);
    const weekday = new Date(`${start}T00:00:00Z`).getUTCDay();
    const before = (await get(user, "/api/planner/sync")).json();
    const failed = await act(user, session, { type: "finish", start_date: start, end_date: start,
      weekly_minutes: { [String((weekday + 1) % 7)]: 120 } });
    expect(failed.statusCode, failed.body).toBe(400);
    const after = (await get(user, "/api/planner/sync")).json();
    expect(after).toEqual(before);
    expect(after.data).toEqual(state.data);
    expect((await get(user)).json().session.stage).toBe("schedule");
    expect((await get(user, "/api/onboarding/profile")).json().profile.plan_end_date).toBe(state.data.profile.plan_end_date);
    expect((await db.query<{ count: number }>("select count(*)::int as count from plan_versions where user_id=$1 and kind='replan'", [user.id])).rows[0].count).toBe(0);
  });

  it("rolls back profile, courses and items together when scheduling cannot produce a day", async () => {
    const user = await account();
    const { shanghaiDate } = await import("./onboarding-ai.js");
    const date = shanghaiDate();
    const weekday = new Date(`${date}T00:00:00Z`).getUTCDay();
    const session: OnboardingSession = { ...newSession(), stage: "schedule", courses: [{ id: "test", name: "测试", description: "", priority: 2 }],
      items: [{ id: "task", course_id: "test", title: "事项", description: "", completion_criteria: "", estimated_minutes: 60, deadline: date, deadline_kind: "plan_end", priority: 2 }] };
    await db.query("insert into onboarding_sessions(user_id,payload) values($1,$2)", [user.id, JSON.stringify(session)]);
    const response = await act(user, session, { type: "finish", start_date: date, end_date: date, weekly_minutes: { [String((weekday + 1) % 7)]: 120 } });
    expect(response.statusCode).toBe(400);
    expect((await get(user)).json().session.stage).toBe("schedule");
    for (const table of ["profiles", "courses", "items", "daily_plan_items", "plan_versions"]) {
      expect((await db.query<{ count: number }>(`select count(*)::int as count from ${table} where user_id=$1`, [user.id])).rows[0].count).toBe(0);
    }
  });
});