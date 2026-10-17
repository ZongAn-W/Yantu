import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { SignJWT } from "jose";
import { afterAll, beforeAll, describe, it, expect, vi } from "vitest";

describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)(
  "planner revision synchronization",
  () => {
    let app: Awaited<ReturnType<(typeof import("./server.js"))["buildApp"]>>;
    let db: typeof import("./db.js");
    const secret = "sync-test-access-01234567890123456789";
    async function account() {
      const id = randomUUID();
      await db.query(
        "insert into users(id,email,username,password_hash) values($1,$2,$3,$4)",
        [id, `${id}@example.test`, id, "test-only"],
      );
      const token = await new SignJWT({
        email: `${id}@example.test`,
        username: id,
        type: "access",
      })
        .setProtectedHeader({ alg: "HS256" })
        .setSubject(id)
        .setExpirationTime("1h")
        .sign(new TextEncoder().encode(secret));
      return { id, headers: { authorization: `Bearer ${token}` } };
    }
    async function fixture(owner: string) {
      const raw = JSON.parse(
        await readFile(
          new URL(
            "../../flutter_client/test/fixtures/planner_v1.json",
            import.meta.url,
          ),
          "utf8",
        ),
      );
      const ids = new Map<string, string>();
      const retag = (value: any): any =>
        typeof value === "string" && /^[a-f0-9-]{36}$/.test(value)
          ? (ids.get(value) ?? (ids.set(value, randomUUID()), ids.get(value)))
          : Array.isArray(value)
            ? value.map(retag)
            : value && typeof value === "object"
              ? Object.fromEntries(
                  Object.entries(value).map(([key, v]) => [
                    key,
                    key === "user_id" ? owner : retag(v),
                  ]),
                )
              : value;
      return retag(raw);
    }
    beforeAll(async () => {
      vi.stubEnv("DATABASE_URL", process.env.AUTH_TEST_DATABASE_URL!);
      vi.stubEnv("JWT_ACCESS_SECRET", secret);
      vi.stubEnv("NODE_ENV", "test");
      db = await import("./db.js");
      await db.query(
        await readFile(new URL("../db/schema.sql", import.meta.url), "utf8"),
      );
      app = await (await import("./server.js")).buildApp();
      await app.ready();
    });
    afterAll(async () => {
      await app?.close();
      await db?.pool.end();
      vi.unstubAllEnvs();
    });
    it("requires authentication and rejects invalid graph or cross-account documents", async () => {
      expect((await app.inject({ url: "/api/planner/sync" })).statusCode).toBe(
        401,
      );
      const user = await account(),
        data = await fixture(user.id);
      expect(
        (
          await app.inject({
            method: "PUT",
            url: "/api/planner/sync",
            headers: user.headers,
            payload: { data: {}, base: null, expectedRevision: 0 },
          })
        ).statusCode,
      ).toBe(400);
      const other = await account();
      expect(
        (
          await app.inject({
            method: "PUT",
            url: "/api/planner/sync",
            headers: other.headers,
            payload: { data, base: null, expectedRevision: 0 },
          })
        ).statusCode,
      ).toBe(403);
      data.blocks[0].task_id = "missing";
      expect(
        (
          await app.inject({
            method: "PUT",
            url: "/api/planner/sync",
            headers: user.headers,
            payload: { data, base: null, expectedRevision: 0 },
          })
        ).statusCode,
      ).toBe(400);
    });
    it("round-trips legacy string ids, extensions, metadata and native relationship rows", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const empty = (
        await app.inject({ url: "/api/planner/sync", headers: user.headers })
      ).json();
      expect(empty).toEqual({ data: null, revision: 0 });
      const saved = await app.inject({
        method: "PUT",
        url: "/api/planner/sync",
        headers: user.headers,
        payload: { data, base: null, expectedRevision: 0 },
      });
      expect(saved.statusCode, saved.body).toBe(200);
      const pulled = (
        await app.inject({ url: "/api/planner/sync", headers: user.headers })
      ).json();
      expect(pulled.data).toEqual(data);
      expect(pulled.revision).toBeGreaterThan(0);
      const native = (
        await app.inject({
          url: "/api/planner/snapshot",
          headers: user.headers,
        })
      ).json().data;
      expect(native.tasks[0].title).toBe(data.tasks[0].title);
      expect(native.subjects[0].id).toMatch(/^[a-f0-9-]{36}$/);
      expect(native.logs[0].minutes).toBe(35);
      expect(pulled.data.fixed_events).toEqual(data.fixed_events);
      expect(pulled.data.replan_runs).toEqual(data.replan_runs);
      expect(pulled.data.phases).toEqual(data.phases);
    });
    it("does not let a stale revision or a wrong base overwrite a cloud edit", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const put = (value: any, base: any, revision: number) =>
        app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data: value, base, expectedRevision: revision },
        });
      const initial = await put(data, null, 0);
      expect(initial.statusCode, initial.body).toBe(200);
      const first = initial.json();
      const changed = structuredClone(data);
      changed.tasks[0].title = "云端修改";
      const updated = await put(changed, first.data, first.revision);
      expect(updated.statusCode).toBe(200);
      const stale = await put(data, first.data, first.revision);
      expect(stale.statusCode).toBe(409);
      expect(stale.json().data.tasks[0].title).toBe("云端修改");
      expect((await put(data, data, updated.json().revision)).statusCode).toBe(
        409,
      );
    });
    it("preserves split scheduler IDs, status snapshots and local undo guard across projection", async () => {
      const user = await account();
      const goldens = JSON.parse(await readFile(new URL("../../../packages/planner-engine/fixtures/planner-goldens.json", import.meta.url), "utf8"));
      const sample = goldens.cases.find((row: any) => row.name === "daily partial completion");
      const retag = (value: any): any => Array.isArray(value)
        ? value.map(retag)
        : value && typeof value === "object"
          ? Object.fromEntries(Object.entries(value).map(([key, child]) => [key, key === "user_id" ? user.id : retag(child)]))
          : value;
      const data = retag(sample.expected.confirmed);
      const { replan_runs: _history, ...guard } = structuredClone(data);
      data.replan_runs[0].local_undo_guard = guard;
      const saved = await app.inject({
        method: "PUT", url: "/api/planner/sync", headers: user.headers,
        payload: { data, base: null, expectedRevision: 0 },
      });
      expect(saved.statusCode, saved.body).toBe(200);
      for (let attempt = 0; attempt < 2; attempt++) {
        const pulled = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
        expect(pulled.data).toEqual(data);
      }
      const native = (await app.inject({ url: "/api/planner/snapshot", headers: user.headers })).json().data;
      expect(data.blocks.filter((row: any) => row.date === "2026-10-17")).toHaveLength(2);
      expect(native.blocks.filter((row: any) => row.date === "2026-10-17")).toHaveLength(1);
      expect(native.blocks.find((row: any) => row.date === "2026-10-17").duration_minutes).toBe(60);
      expect(native.logs[0].minutes).toBe(60);
    });
    it("merges native actuals and advice without flattening split timed blocks", async () => {
      const user = await account(), data = await fixture(user.id);
      data.profile.planning_mode = "timed";
      data.daily_feedback = { "2026-10-16": "保留整体反馈" };
      const first = { ...data.blocks[0], start_minute: 480, duration_minutes: 60, actual_minutes: 0, is_fixed: true, feedback: "保留原反馈" };
      const second = { ...first, id: randomUUID(), start_minute: 600, is_fixed: false, feedback: "另一条反馈" };
      data.blocks = [first, second];
      data.logs = [];
      const saved = await app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data, base: null, expectedRevision: 0 } });
      expect(saved.statusCode, saved.body).toBe(200);
      await db.query("update daily_plan_items set actual_minutes=75,advice_text='新建议',advice_topics='[\"极限\"]',completion_status='partial' where user_id=$1", [user.id]);
      const pulled = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(pulled.data.blocks.map((block: any) => ({ id: block.id, start: block.start_minute, fixed: block.is_fixed, duration: block.duration_minutes, created: block.created_at, feedback: block.feedback }))).toEqual(
        data.blocks.map((block: any) => ({ id: block.id, start: block.start_minute, fixed: block.is_fixed, duration: block.duration_minutes, created: block.created_at, feedback: block.feedback })),
      );
      expect(pulled.data.blocks.map((block: any) => block.actual_minutes)).toEqual([60, 15]);
      expect(pulled.data.daily_feedback).toEqual(data.daily_feedback);
      for (const block of pulled.data.blocks) {
        expect(block.advice_text).toBe("新建议");
        expect(block.advice_topics).toEqual(["极限"]);
        expect(block.completion_status).toBe("partial");
      }
      const again = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(again.data).toEqual(pulled.data);
      const pushed = await app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data: pulled.data, base: pulled.data, expectedRevision: pulled.revision } });
      expect(pushed.statusCode, pushed.body).toBe(200);
    });
    it("preserves split log links when another native task-day total changes", async () => {
      const user = await account(), data = await fixture(user.id);
      const first = { ...data.blocks[0], start_minute: 480, duration_minutes: 60 };
      const second = { ...first, id: randomUUID(), start_minute: 600 };
      data.blocks = [first, second];
      data.logs = [{ ...data.logs[0], block_id: second.id }];
      const saved = await app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data, base: null, expectedRevision: 0 } });
      expect(saved.statusCode, saved.body).toBe(200);
      await db.query("update daily_plan_items set advice_text='只改建议' where user_id=$1", [user.id]);
      const pulled = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(pulled.data.logs).toEqual(data.logs);
      expect(pulled.data.blocks.map((block: any) => block.id)).toEqual([first.id, second.id]);
      await db.query("update study_logs set minutes=50 where user_id=$1", [user.id]);
      const corrected = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(corrected.data.logs[0].minutes).toBe(50);
      expect(corrected.data.logs[0].block_id).toBe(second.id);
    });
    it("does not discard a detailed layout when a native aggregate duration cannot represent it", async () => {
      const user = await account(), data = await fixture(user.id);
      data.profile.planning_mode = "timed";
      data.blocks = [{ ...data.blocks[0], start_minute: 480, is_fixed: true }];
      const saved = await app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data, base: null, expectedRevision: 0 } });
      expect(saved.statusCode, saved.body).toBe(200);
      await db.query("update daily_plan_items set planned_minutes=120 where user_id=$1", [user.id]);
      const pulled = await app.inject({ url: "/api/planner/sync", headers: user.headers });
      expect(pulled.statusCode).toBe(409);
      expect(pulled.json().error).toContain("时间块");
      expect((await db.query("select document from planner_sync_state where user_id=$1", [user.id])).rows[0].document).toEqual(data);
    });
    it("concurrent clients cannot both commit the same expected revision", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const first = (
        await app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data, base: null, expectedRevision: 0 },
        })
      ).json();
      const responses = await Promise.all(
        ["device A", "device B"].map((title) =>
          app.inject({
            method: "PUT",
            url: "/api/planner/sync",
            headers: user.headers,
            payload: {
              data: { ...data, tasks: [{ ...data.tasks[0], title }] },
              base: first.data,
              expectedRevision: first.revision,
            },
          }),
        ),
      );
      expect(responses.map((response) => response.statusCode).sort()).toEqual([
        200, 409,
      ]);
    });
    it("legacy study-log writes increase revision and preserve sidecar fields", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const first = (
        await app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data, base: null, expectedRevision: 0 },
        })
      ).json();
      const native = (
        await app.inject({
          url: "/api/planner/snapshot",
          headers: user.headers,
        })
      ).json().data;
      const recorded = await app.inject({
        method: "POST",
        url: "/api/study-logs",
        headers: user.headers,
        payload: {
          item_id: native.tasks[0].id,
          date: "2026-10-16",
          minutes: 110,
        },
      });
      expect(recorded.statusCode).toBe(201);
      const remote = (
        await app.inject({ url: "/api/planner/sync", headers: user.headers })
      ).json();
      expect(remote.revision).toBeGreaterThan(first.revision);
      expect(
        remote.data.logs
          .filter((row: any) => row.date === "2026-10-16")
          .reduce((sum: number, row: any) => sum + row.minutes, 0),
      ).toBe(110);
      expect(remote.data.tasks[0].id).toBe(data.tasks[0].id);
      expect(remote.data.fixed_events).toEqual(data.fixed_events);
      const rejected = await app.inject({
        method: "PUT",
        url: "/api/planner/sync",
        headers: user.headers,
        payload: { data, base: first.data, expectedRevision: first.revision },
      });
      expect(rejected.statusCode).toBe(409);
    });
  },
);
