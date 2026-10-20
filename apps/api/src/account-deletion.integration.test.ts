import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import argon2 from "argon2";
import { SignJWT } from "jose";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)("account deletion against PostgreSQL", () => {
  let app: Awaited<ReturnType<typeof import("./server.js")["buildApp"]>>;
  let db: typeof import("./db.js");
  let passwordHash: string;
  let ip = 0;
  const password = "DeleteStudy4089";
  const accessSecret = "delete-test-access-01234567890123456789";
  const refreshSecret = "delete-test-refresh-01234567890123456789";
  const ownedTables = ["profiles", "courses", "items", "daily_plan_items", "study_logs", "daily_reviews", "replan_runs", "plan_versions", "ai_jobs", "onboarding_sessions", "planner_sync_state", "auth_refresh_tokens", "account_deletion_attempts"];
  async function signed(id: string, email: string, type = "access") {
    return new SignJWT({ type, email, username: id }).setProtectedHeader({ alg: "HS256" }).setSubject(id).setExpirationTime("1h")
      .sign(new TextEncoder().encode(type === "access" ? accessSecret : refreshSecret));
  }
  async function account() {
    const id = randomUUID(), email = `${id}@example.test`;
    await db.query("insert into users(id,email,username,password_hash) values($1,$2,$3,$4)", [id, email, id, passwordHash]);
    const accessToken = await signed(id, email);
    const { issueBearerSession } = await import("./auth.js");
    const native = await issueBearerSession({ id, email, username: id });
    const refreshToken = await signed(id, email, "refresh");
    return { id, email, headers: { authorization: `Bearer ${accessToken}` }, cookies: `planner_access=${accessToken}; planner_refresh=${refreshToken}`, native };
  }
  type Account = Awaited<ReturnType<typeof account>>;
  const remove = (user: Account, entered = password, address = `192.0.2.${++ip}`) => app.inject({
    method: "POST", url: "/api/auth/delete-account", headers: { ...user.headers, "x-forwarded-for": address }, payload: { password: entered },
  });
  async function populate(user: Account) {
    const course = randomUUID(), item = randomUUID(), block = randomUUID();
    await db.query("insert into profiles(user_id,goal_text) values($1,'注销测试')", [user.id]);
    await db.query("insert into courses(id,user_id,name) values($1,$2,'课程')", [course, user.id]);
    await db.query("insert into items(id,user_id,course_id,title,estimated_minutes,deadline) values($1,$2,$3,'事项',60,'2026-10-25')", [item, user.id, course]);
    await db.query("insert into daily_plan_items(id,user_id,item_id,date,planned_minutes) values($1,$2,$3,'2026-10-19',30)", [block, user.id, item]);
    await db.query("insert into study_logs(user_id,item_id,daily_plan_item_id,date,minutes) values($1,$2,$3,'2026-10-19',10)", [user.id, item, block]);
    // 第二条日志没有日程关联，只归属事项（加学），用于验证级联删除覆盖到所有学习事实。
    await db.query("insert into study_logs(user_id,item_id,date,minutes,relation) values($1,$2,'2026-10-19',15,'extra')", [user.id, item]);
    await db.query("insert into daily_reviews(user_id,date) values($1,'2026-10-19')", [user.id]);
    await db.query("insert into replan_runs(user_id,date,before_payload,after_payload) values($1,'2026-10-19','{}','{}')", [user.id]);
    await db.query("insert into plan_versions(user_id,kind,payload) values($1,'confirmed','{}')", [user.id]);
    await db.query("insert into ai_jobs(user_id,kind,input_payload) values($1,'plan_draft','{}')", [user.id]);
    await db.query("insert into onboarding_sessions(user_id,payload) values($1,'{}')", [user.id]);
    await db.query("update planner_sync_state set document='{\"private\":true}',projection='{}' where user_id=$1", [user.id]);
    await db.query("insert into registration_codes(email,code_hash,expires_at,sent_at,window_started_at,consumed) values($1,'private',now()+interval '10 minutes',now(),now(),true)", [user.email]);
    return { course, item, block };
  }
  async function expectGone(user: Account) {
    expect((await db.query("select 1 from users where id=$1", [user.id])).rowCount).toBe(0);
    for (const table of ownedTables) expect((await db.query(`select 1 from ${table} where user_id=$1`, [user.id])).rowCount, table).toBe(0);
    expect((await db.query("select 1 from registration_codes where lower(email)=lower($1)", [user.email])).rowCount).toBe(0);
  }
  beforeAll(async () => {
    vi.stubEnv("DATABASE_URL", process.env.AUTH_TEST_DATABASE_URL!);
    vi.stubEnv("JWT_ACCESS_SECRET", accessSecret);
    vi.stubEnv("JWT_REFRESH_SECRET", refreshSecret);
    vi.stubEnv("NODE_ENV", "test");
    db = await import("./db.js");
    await db.query(await readFile(new URL("../db/schema.sql", import.meta.url), "utf8"));
    app = await (await import("./server.js")).buildApp();
    await app.ready();
    passwordHash = await argon2.hash(password, { type: argon2.argon2id });
  });
  afterAll(async () => { await app?.close(); await db?.pool.end(); vi.unstubAllEnvs(); });

  it("requires a valid access identity and current password, ignoring client-supplied identities", async () => {
    const user = await account(), other = await account();
    for (const headers of [{}, { authorization: "Bearer invalid" }, { authorization: `Bearer ${user.native.refreshToken}` }])
      expect((await app.inject({ method: "POST", url: "/api/auth/delete-account", headers, payload: { password } })).statusCode).toBe(401);
    expect((await app.inject({ method: "POST", url: "/api/auth/delete-account", headers: user.headers, payload: { password, user_id: other.id } })).statusCode).toBe(400);
    expect((await remove(user, "wrong")).statusCode).toBe(403);
    const result = await db.query("select 1 from users where id=$1", [user.id]);
    expect(result.rowCount).toBe(1);
    expect((await db.query("select 1 from users where id=$1", [other.id])).rowCount).toBe(1);
  });

  it("deletes a populated account atomically, preserves another account, and immediately invalidates both session types", async () => {
    const user = await account(), other = await account();
    await populate(user); await populate(other);
    const response = await app.inject({ method: "POST", url: "/api/auth/delete-account", headers: { cookie: user.cookies }, payload: { password } });
    expect(response.statusCode, response.body).toBe(200);
    expect(response.json()).toEqual({ ok: true });
    expect(response.cookies).toHaveLength(2);
    expect(response.cookies.every(value => value.value === "")).toBe(true);
    expect(response.headers["cache-control"]).toBe("no-store");
    await expectGone(user);
    expect((await db.query("select 1 from study_logs where user_id=$1", [other.id])).rowCount).toBe(2);
    for (const headers of [user.headers, { cookie: user.cookies }]) {
      for (const url of ["/api/me", "/api/planner/sync", "/api/planner/snapshot", "/api/onboarding/session", "/api/items", "/api/progress"]) {
        const denied = await app.inject({ url, headers });
        expect(denied.statusCode, url).toBe(410);
        expect(denied.json().code).toBe("ACCOUNT_DELETED");
      }
    }
    for (const url of ["/api/auth/refresh", "/api/auth/token/refresh"]) {
      const denied = await app.inject({ method: "POST", url, headers: { cookie: user.cookies }, payload: { refreshToken: user.native.refreshToken } });
      expect(denied.statusCode).toBe(410);
      expect(denied.json().code).toBe("ACCOUNT_DELETED");
    }
    expect((await app.inject({ method: "POST", url: "/api/auth/login", payload: { email: user.email, password } })).statusCode).toBe(401);
  });

  it("rolls back all data and leaves cookies intact if deletion fails", async () => {
    const user = await account(); await populate(user);
    const trigger = `delete_failure_${user.id.replaceAll("-", "")}`;
    await db.query(`create function ${trigger}() returns trigger language plpgsql as $$ begin raise exception 'injected deletion failure'; end $$`);
    await db.query(`create trigger ${trigger} before delete on users for each row when (OLD.id='${user.id}'::uuid) execute function ${trigger}()`);
    try {
      const response = await remove(user);
      expect(response.statusCode).toBe(500);
      expect(response.cookies).toHaveLength(0);
      expect((await db.query("select 1 from users where id=$1", [user.id])).rowCount).toBe(1);
      expect((await db.query("select 1 from study_logs where user_id=$1", [user.id])).rowCount).toBe(2);
      expect((await db.query("select 1 from registration_codes where email=$1", [user.email])).rowCount).toBe(1);
      expect((await app.inject({ url: "/api/me", headers: user.headers })).statusCode).toBe(200);
    } finally {
      await db.query(`drop trigger ${trigger} on users`);
      await db.query(`drop function ${trigger}()`);
    }
    expect((await remove(user)).statusCode).toBe(200);
  });

  it("permits duplicate requests and lost-response retries without touching a re-registered email", async () => {
    const user = await account(); await populate(user);
    const results = await Promise.all([remove(user), remove(user)]);
    expect(results.map(value => value.statusCode)).toEqual([200, 200]);
    const replacement = randomUUID();
    await db.query("insert into users(id,email,username,password_hash) values($1,$2,$3,$4)", [replacement, user.email, replacement, passwordHash]);
    await db.query("insert into registration_codes(email,code_hash,expires_at,sent_at,window_started_at) values($1,'new',now()+interval '10 minutes',now(),now())", [user.email]);
    expect((await remove(user)).statusCode).toBe(200);
    expect((await db.query("select 1 from users where id=$1", [replacement])).rowCount).toBe(1);
    expect((await db.query("select code_hash from registration_codes where email=$1", [user.email])).rows[0].code_hash).toBe("new");
  });

  it("limits password attempts across IPs and also applies an IP limit", async () => {
    const user = await account();
    for (let index = 0; index < 5; index++) expect((await remove(user, "wrong")).statusCode).toBe(403);
    const limited = await remove(user);
    expect(limited.statusCode).toBe(429);
    expect(Number(limited.headers["retry-after"])).toBeGreaterThan(0);
    await db.query("update account_deletion_attempts set window_started_at=now()-interval '16 minutes' where user_id=$1", [user.id]);
    expect((await remove(user)).statusCode).toBe(200);
    const address = "198.51.100.198";
    for (let index = 0; index < 10; index++) expect((await app.inject({ method: "POST", url: "/api/auth/delete-account", headers: { "x-forwarded-for": address }, payload: { password } })).statusCode).toBe(401);
    expect((await app.inject({ method: "POST", url: "/api/auth/delete-account", headers: { "x-forwarded-for": address }, payload: { password } })).statusCode).toBe(429);
  });

  it("serializes in-flight planner work and refresh rotation with deletion without resurrection", async () => {
    const user = await account(); await populate(user);
    const writer = await db.pool.connect();
    try {
      await writer.query("begin");
      await writer.query("select id from users where id=$1 for key share", [user.id]);
      await writer.query("select user_id from planner_sync_state where user_id=$1 for update", [user.id]);
      // Refresh and deletion must both finish when the existing writer commits;
      // neither may deadlock by locking refresh/state rows before the parent.
      const removing = remove(user);
      const refreshing = app.inject({ method: "POST", url: "/api/auth/token/refresh", payload: { refreshToken: user.native.refreshToken } });
      await writer.query("update planner_sync_state set revision=revision+1 where user_id=$1", [user.id]);
      await writer.query("commit");
      const [deleted, refreshed] = await Promise.all([removing, refreshing]);
      expect(deleted.statusCode, deleted.body).toBe(200);
      expect([200, 410]).toContain(refreshed.statusCode);
      if (refreshed.statusCode === 200) expect((await app.inject({ url: "/api/me", headers: { authorization: `Bearer ${refreshed.json().accessToken}` } })).statusCode).toBe(410);
      await expectGone(user);
      expect((await app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: {} })).statusCode).toBe(410);
    } finally { await writer.query("rollback"); writer.release(); }
  });
});
