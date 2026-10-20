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
    it("keeps a reliable weekly configuration when a document omits it", async () => {
      const user = await account();
      const data = await fixture(user.id);
      const week = { "0": 0, "1": 90, "2": 90, "3": 0, "4": 90, "5": 90, "6": 180 };
      data.profile.weekly_minutes = week;
      const put = (value: any, base: any, revision: number) =>
        app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data: value, base, expectedRevision: revision } });
      const first = await put(data, null, 0);
      expect(first.statusCode, first.body).toBe(200);
      const stored = await db.query<{ weekly_minutes: any }>("select weekly_minutes from profiles where user_id=$1", [user.id]);
      expect(stored.rows[0].weekly_minutes).toEqual(week);

      // 旧文档缺少 weekly_minutes 时，不能把整周改成每日上限。
      const withoutWeek = structuredClone(first.json().data);
      delete withoutWeek.profile.weekly_minutes;
      const second = await put(withoutWeek, first.json().data, first.json().revision);
      expect(second.statusCode, second.body).toBe(200);
      const after = await db.query<{ weekly_minutes: any }>("select weekly_minutes from profiles where user_id=$1", [user.id]);
      expect(after.rows[0].weekly_minutes).toEqual(week);
      const pulled = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(pulled.data.profile.weekly_minutes).toEqual(week);
      expect(pulled.data.profile.weekly_minutes["3"]).toBe(0);
      // 再次往返保留休息日 0。
      const third = await put(pulled.data, pulled.data, pulled.revision);
      expect(third.statusCode, third.body).toBe(200);
      const final = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(final.data.profile.weekly_minutes).toEqual(week);
      expect((await db.query<{ weekly_minutes: any }>("select weekly_minutes from profiles where user_id=$1", [user.id])).rows[0].weekly_minutes).toEqual(week);
    });

    it("does not treat an empty optional list materialized by a client model as a base change", async () => {
      const user = await account(), data = await fixture(user.id);
      // 服务端生成的文档只在有内容时携带可选集合；旧客户端模型可能把可选列表
      // 持久化为显式空数组并随 base 回传。同一份内容的两种空值写法不能被判成
      // base 冲突，否则同步会永久停留在 409。
      const first = await app.inject({
        method: "PUT", url: "/api/planner/sync", headers: user.headers,
        payload: { data, base: null, expectedRevision: 0 },
      });
      expect(first.statusCode, first.body).toBe(200);
      const pulled = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(Object.prototype.hasOwnProperty.call(pulled.data, "legacy_optional_list")).toBe(false);
      const clientBase = { ...pulled.data, legacy_optional_list: [] };
      const changed = { ...structuredClone(pulled.data), legacy_optional_list: [] };
      changed.profile.goal_text = "更新后的学习目标";
      const next = await app.inject({
        method: "PUT", url: "/api/planner/sync", headers: user.headers,
        payload: { data: changed, base: clientBase, expectedRevision: pulled.revision },
      });
      expect(next.statusCode, next.body).toBe(200);
      expect(next.json().data.profile.goal_text).toBe("更新后的学习目标");
      // 空数组被忽略不等于忽略真实差异：base 里出现未知的非空内容仍按不一致处理。
      const stale = { ...structuredClone(next.json().data), legacy_optional_list: [] };
      const now = new Date().toISOString();
      const conflict = await app.inject({
        method: "PUT", url: "/api/planner/sync", headers: user.headers,
        payload: {
          data: stale,
          base: {
            ...clientBase,
            legacy_optional_list: [{ id: randomUUID(), title: "旧数据", created_at: now, updated_at: now }],
          },
          expectedRevision: next.json().revision,
        },
      });
      expect(conflict.statusCode, conflict.body).toBe(409);
    });

    it("persists strategy projections and refuses older writers without losing metadata", async () => {
      const user = await account(), data = await fixture(user.id);
      data.planning = { version: 1, prompt_version: "planning-1", rules_version: "rules-1", detail_days: 14,
        rolling: true, route: [{ id: "route", title: "Project", item_ids: [data.tasks[0].id], outcome: "Working result", check: "Run it" }],
        milestones: [], assumptions: ["estimated"], risks: [], uncovered: [] };
      data.tasks[0].planning = { workload: { components: [{ id: "papers", label: "Past papers", quantity: 21, unit: "paper", minutes_per_unit: 180 }],
        source: "confirmed scope", confidence: "medium", calibration: "Review after 3 attempts" } };
      data.tasks[0].estimated_minutes = 3780;
      data.blocks[0].activity_instance_id = "task:2026-10-12:1";
      const put = (value: unknown, base: unknown, expectedRevision: number, writer?: number) => app.inject({
        method: "PUT", url: "/api/planner/sync", headers: user.headers,
        payload: { data: value, base, expectedRevision, ...(writer ? { writer_planning_version: writer } : {}) },
      });
      const first = await put(data, null, 0, 1);
      expect(first.statusCode, first.body).toBe(200);
      const saved = first.json();
      const native = (await app.inject({ url: "/api/planner/snapshot", headers: user.headers })).json().data;
      expect(native.planning.route[0].item_ids).toContain(native.tasks[0].id);
      expect(native.tasks[0].planning.workload.components[0].quantity).toBe(21);
      expect(native.blocks[0].activity_instance_id).toBe("task:2026-10-12:1");
      const stripped = structuredClone(saved.data);
      delete stripped.planning;
      delete stripped.tasks[0].planning;
      delete stripped.blocks[0].activity_instance_id;
      const rejected = await put(stripped, saved.data, saved.revision);
      expect(rejected.statusCode, rejected.body).toBe(426);
      const unchanged = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      expect(unchanged.data.planning).toEqual(data.planning);
      expect(unchanged.revision).toBe(saved.revision);
      const renamed = structuredClone(stripped);
      renamed.tasks[0].title = "An ordinary edit";
      const preserved = await put(renamed, saved.data, saved.revision, 1);
      expect(preserved.statusCode, preserved.body).toBe(200);
      expect(preserved.json().data.tasks[0].planning).toEqual(data.tasks[0].planning);
      const clear = structuredClone(preserved.json().data);
      clear.planning = null;
      clear.tasks[0].planning = null;
      clear.blocks[0].activity_instance_id = null;
      const cleared = await put(clear, preserved.json().data, preserved.json().revision, 1);
      expect(cleared.statusCode, cleared.body).toBe(200);
      expect(cleared.json().data.planning).toBeNull();
      expect((await db.query("select planning_metadata from profiles where user_id=$1", [user.id])).rows[0].planning_metadata).toBeNull();
    });

    it("clears the target date instead of reviving the legacy exam date", async () => {
      const user = await account();
      const data = await fixture(user.id);
      const put = (value: any, base: any, revision: number) =>
        app.inject({ method: "PUT", url: "/api/planner/sync", headers: user.headers, payload: { data: value, base, expectedRevision: revision } });
      // 只有旧字段的历史文档：新目标日期缺失，考试日期作为兼容来源。
      delete data.profile.target_date;
      data.profile.exam_date = "2027-06-01";
      const first = await put(data, null, 0);
      expect(first.statusCode, first.body).toBe(200);
      const legacy = (await app.inject({ url: "/api/onboarding/profile", headers: user.headers })).json().profile;
      expect(legacy.target_date).toBe("2027-06-01");

      // 新字段明确为 null：用户主动清空，不能再回退到旧考试日期。
      const cleared = structuredClone(first.json().data);
      cleared.profile.target_date = null;
      const second = await put(cleared, first.json().data, first.json().revision);
      expect(second.statusCode, second.body).toBe(200);
      const row = await db.query<{ td: string | null; ed: string | null }>(
        "select target_date::text as td, exam_date::text as ed from profiles where user_id=$1",
        [user.id],
      );
      expect(row.rows[0]).toEqual({ td: null, ed: null });
      expect((await app.inject({ url: "/api/onboarding/profile", headers: user.headers })).json().profile.target_date).toBeNull();
      const pulled = (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      // 新字段存在即为准：即使旧镜像仍随文档保存，也不能再作为有效目标日期。
      // 文档统一用空字符串表示“没有目标日期”，与客户端模型一致。
      expect(pulled.data.profile.target_date).toBe("");
      expect(pulled.data.profile.target_date).toBeFalsy();
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
      // Keep this projection regression independent of how the engine releases a
      // partially used day: the sync document deliberately contains two slots.
      data.tasks[0].estimated_minutes = 180;
      for (let index = 0; index < 2; index++) data.blocks.push({ ...data.blocks[0],
        id: `split-${index}`, date: "2026-10-17", start_minute: 480 + index * 60,
        duration_minutes: 30, actual_minutes: 0, completion_status: "not_started", status: "planned" });
      // 文档用空字符串表示“没有目标日期”；数据库的日期列保存 NULL。
      data.profile.target_date = "";
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
    it("projects learning constraints into the relational profile and every read path", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const put = (value: any, base: any, revision: number) =>
        app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data: value, base, expectedRevision: revision },
        });
      const pull = async () =>
        (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      const profile = async () =>
        (await app.inject({ url: "/api/onboarding/profile", headers: user.headers })).json()
          .profile;
      const native = async () =>
        (await app.inject({ url: "/api/planner/snapshot", headers: user.headers })).json()
          .data;
      const storedConstraints = async () =>
        (
          await db.query<{ constraints_text: string }>(
            "select constraints_text from profiles where user_id=$1",
            [user.id],
          )
        ).rows[0]?.constraints_text;
      // 第一次导入：客户端设置的学习限制必须进入关系表，并被三种读取路径读到。
      data.profile.constraints = "每周三晚上有课，22:00 后不安排";
      const first = await put(data, null, 0);
      expect(first.statusCode, first.body).toBe(200);
      const firstPull = await pull();
      expect(firstPull.data.profile.constraints).toBe("每周三晚上有课，22:00 后不安排");
      expect((await profile()).constraints_text).toBe("每周三晚上有课，22:00 后不安排");
      expect((await native()).profile.constraints).toBe("每周三晚上有课，22:00 后不安排");
      expect(await storedConstraints()).toBe("每周三晚上有课，22:00 后不安排");

      // 修改已有值：同步读取、资料读取、原生快照三者一致。
      const changed = structuredClone(first.json().data);
      changed.profile.constraints = "仅周末可安排 4 小时";
      const second = await put(changed, first.json().data, first.json().revision);
      expect(second.statusCode, second.body).toBe(200);
      expect((await pull()).data.profile.constraints).toBe("仅周末可安排 4 小时");
      expect((await profile()).constraints_text).toBe("仅周末可安排 4 小时");
      expect((await native()).profile.constraints).toBe("仅周末可安排 4 小时");
      expect(await storedConstraints()).toBe("仅周末可安排 4 小时");

      // 显式清空：空字符串表示用户主动清空，关系表与三条读取路径同步为空。
      const cleared = structuredClone(second.json().data);
      cleared.profile.constraints = "";
      const third = await put(cleared, second.json().data, second.json().revision);
      expect(third.statusCode, third.body).toBe(200);
      expect(await storedConstraints()).toBe("");
      expect((await pull()).data.profile.constraints).toBe("");
      expect((await profile()).constraints_text).toBe("");
      expect((await native()).profile.constraints).toBe("");

      // null 同样表示明确清空，读取端统一用空字符串表示，避免表示差异反复误报。
      const nullCleared = structuredClone(third.json().data);
      nullCleared.profile.constraints = null;
      const fourth = await put(nullCleared, third.json().data, third.json().revision);
      expect(fourth.statusCode, fourth.body).toBe(200);
      expect(await storedConstraints()).toBe("");
      expect(fourth.json().data.profile.constraints).toBe("");
      expect((await pull()).data.profile.constraints).toBe("");
      expect((await native()).profile.constraints).toBe("");

      // 旧客户端兼容：文档缺少 constraints 字段时保留关系表已有值，不能被空值覆盖。
      const withValue = structuredClone(fourth.json().data);
      withValue.profile.constraints = "旧客户端不能清空的限制";
      const fifth = await put(withValue, fourth.json().data, fourth.json().revision);
      expect(fifth.statusCode, fifth.body).toBe(200);
      expect(await storedConstraints()).toBe("旧客户端不能清空的限制");
      const legacy = structuredClone(fifth.json().data);
      delete legacy.profile.constraints;
      const sixth = await put(legacy, fifth.json().data, fifth.json().revision);
      expect(sixth.statusCode, sixth.body).toBe(200);
      expect(await storedConstraints()).toBe("旧客户端不能清空的限制");
      // 投影补回缺失字段：响应和后续读取仍然一致。
      expect(sixth.json().data.profile.constraints).toBe("旧客户端不能清空的限制");
      expect((await pull()).data.profile.constraints).toBe("旧客户端不能清空的限制");
      expect((await profile()).constraints_text).toBe("旧客户端不能清空的限制");
      expect((await native()).profile.constraints).toBe("旧客户端不能清空的限制");

      // 再次同步不产生伪冲突：用刚读到的文档和 revision 原样回传必须成功。
      const pulled = await pull();
      const resync = await put(pulled.data, pulled.data, pulled.revision);
      expect(resync.statusCode, resync.body).toBe(200);
      expect(resync.json().data.profile.constraints).toBe("旧客户端不能清空的限制");

      // 反向读取：通过资料接口写入后，同步文档与原生快照必须反映关系表权威值。
      const patched = await app.inject({
        method: "PATCH",
        url: "/api/onboarding/profile",
        headers: user.headers,
        payload: { constraints_text: "资料接口写入的限制" },
      });
      expect(patched.statusCode, patched.body).toBe(200);
      expect((await profile()).constraints_text).toBe("资料接口写入的限制");
      expect((await pull()).data.profile.constraints).toBe("资料接口写入的限制");
      expect((await native()).profile.constraints).toBe("资料接口写入的限制");
      expect(await storedConstraints()).toBe("资料接口写入的限制");
    });

    it("returns a conditional unchanged response only while the revision matches", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const get = (query = "") =>
        app.inject({ url: `/api/planner/sync${query}`, headers: user.headers });
      const put = (value: any, base: any, revision: number) =>
        app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data: value, base, expectedRevision: revision },
        });
      // 没有任何状态行时，完整路径与老客户端行为不变。
      expect((await get()).json()).toEqual({ data: null, revision: 0 });
      // 状态行存在且 revision 相等：快速路径不返回文档。
      expect((await get("?revision=0")).json()).toEqual({ revision: 0, unchanged: true });

      const first = await put(data, null, 0);
      expect(first.statusCode, first.body).toBe(200);
      const revision = Number(first.json().revision);
      expect(revision).toBeGreaterThan(0);

      // 无变化轮询：返回 unchanged 小响应，不再传输完整文档。
      const unchanged = await get(`?revision=${revision}`);
      expect(unchanged.statusCode, unchanged.body).toBe(200);
      expect(unchanged.json()).toEqual({ revision, unchanged: true });
      expect("data" in unchanged.json()).toBe(false);
      expect(unchanged.body.length).toBeLessThan(100);

      // 旧 revision 仍走完整路径；无参数老客户端行为完全不变；非法参数按无参数处理。
      const stale = await get(`?revision=${revision - 1}`);
      expect(stale.statusCode, stale.body).toBe(200);
      expect(stale.json().revision).toBe(revision);
      expect(stale.json().data.profile.user_id).toBe(user.id);
      expect((await get()).json().data).toEqual(stale.json().data);
      expect((await get("?revision=abc")).json().data.profile.user_id).toBe(user.id);

      // 关系表变化（含旧兼容接口写入）会触发 revision，快速路径必须失效并返回完整文档。
      const native = (
        await app.inject({ url: "/api/planner/snapshot", headers: user.headers })
      ).json().data;
      const recorded = await app.inject({
        method: "POST",
        url: "/api/study-logs",
        headers: user.headers,
        payload: { item_id: native.tasks[0].id, date: "2026-10-16", minutes: 11 },
      });
      expect(recorded.statusCode, recorded.body).toBe(201);
      const changed = await get(`?revision=${revision}`);
      expect(changed.statusCode, changed.body).toBe(200);
      expect(changed.json().unchanged).toBeUndefined();
      const nextRevision = Number(changed.json().revision);
      expect(nextRevision).toBeGreaterThan(revision);
      expect(changed.json().data.logs.some((row: any) => row.minutes === 11)).toBe(true);
      // 追上远端变化后再次无变化。
      expect((await get(`?revision=${nextRevision}`)).json()).toEqual({
        revision: nextRevision,
        unchanged: true,
      });

      // 冲突语义不变：旧 revision/base 仍返回 409。
      expect((await put(first.json().data, first.json().data, revision)).statusCode).toBe(409);
      expect((await put(changed.json().data, first.json().data, nextRevision)).statusCode).toBe(409);
      const confirmed = await put(changed.json().data, changed.json().data, nextRevision);
      expect(confirmed.statusCode, confirmed.body).toBe(200);

      // 账号隔离：另一个账号不能拿别人的 revision 换取 unchanged。
      const other = await account();
      const otherPull = (
        await app.inject({
          url: `/api/planner/sync?revision=${nextRevision}`,
          headers: other.headers,
        })
      ).json();
      expect(otherPull.unchanged).toBeUndefined();
      expect(otherPull).toEqual({ data: null, revision: 0 });
    });

    it("only rewrites changed projection rows for a single timer checkpoint", async () => {
      const user = await account();
      const data = await fixture(user.id);
      const start = Date.parse("2026-11-01T00:00:00Z");
      const day = (index: number) =>
        new Date(start + index * 86_400_000).toISOString().slice(0, 10);
      const extraBlocks = Array.from({ length: 40 }, (_, index) => ({
        ...data.blocks[0],
        id: randomUUID(),
        date: day(index),
        actual_minutes: 0,
      }));
      const extraLogs = extraBlocks.map((block, index) => ({
        ...data.logs[0],
        id: randomUUID(),
        block_id: block.id,
        date: day(index),
        minutes: 0,
      }));
      data.blocks = [...data.blocks, ...extraBlocks];
      data.logs = [...data.logs, ...extraLogs];
      const put = (value: any, base: any, revision: number) =>
        app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data: value, base, expectedRevision: revision },
        });
      const first = await put(data, null, 0);
      expect(first.statusCode, first.body).toBe(200);
      const beforeRevision = Number(first.json().revision);
      const next = structuredClone(first.json().data);
      next.logs[0].minutes += 1;
      next.blocks[0].actual_minutes += 1;
      const checkpoint = await put(next, first.json().data, first.json().revision);
      expect(checkpoint.statusCode, checkpoint.body).toBe(200);
      // 一条日志 + 一个时间块的变化只能触发少数关系行写入，不能等量重写全部历史行。
      const delta = Number(checkpoint.json().revision) - beforeRevision;
      expect(delta).toBeLessThan(20);
      const counts = await db.query<{ blocks: number; logs: number }>(
        `select (select count(*)::int from daily_plan_items where user_id=$1) as blocks,
                (select count(*)::int from study_logs where user_id=$1) as logs`,
        [user.id],
      );
      expect(counts.rows[0]).toEqual({ blocks: data.blocks.length, logs: data.logs.length });
      const pulled = (
        await app.inject({ url: "/api/planner/sync", headers: user.headers })
      ).json();
      expect(pulled.data.logs.filter((row: any) => row.minutes === next.logs[0].minutes)).toHaveLength(1);
      expect(pulled.data.blocks.filter((row: any) => row.actual_minutes === 1)).toHaveLength(1);
    });

    it("removes vanished projection rows and keeps the remaining history", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const extraSubject = { ...data.subjects[0], id: randomUUID(), name: "第二门课" };
      const extraTask = {
        ...data.tasks[0],
        id: randomUUID(),
        subject_id: extraSubject.id,
        title: "第二个事项",
      };
      const extraBlock = { ...data.blocks[0], id: randomUUID(), task_id: extraTask.id, date: "2026-12-01" };
      const extraLog = {
        ...data.logs[0],
        id: randomUUID(),
        block_id: extraBlock.id,
        task_id: extraTask.id,
        date: "2026-12-01",
      };
      data.subjects = [...data.subjects, extraSubject];
      data.tasks = [...data.tasks, extraTask];
      data.blocks = [...data.blocks, extraBlock];
      data.logs = [...data.logs, extraLog];
      const put = (value: any, base: any, revision: number) =>
        app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data: value, base, expectedRevision: revision },
        });
      const first = await put(data, null, 0);
      expect(first.statusCode, first.body).toBe(200);
      const reduced = structuredClone(first.json().data);
      reduced.subjects = reduced.subjects.filter((row: any) => row.id !== extraSubject.id);
      reduced.tasks = reduced.tasks.filter((row: any) => row.id !== extraTask.id);
      reduced.blocks = reduced.blocks.filter((row: any) => row.id !== extraBlock.id);
      reduced.logs = reduced.logs.filter((row: any) => row.id !== extraLog.id);
      const second = await put(reduced, first.json().data, first.json().revision);
      expect(second.statusCode, second.body).toBe(200);
      expect(Number(second.json().revision)).toBeGreaterThan(Number(first.json().revision));
      const counts = await db.query<{
        subjects: number;
        tasks: number;
        blocks: number;
        logs: number;
      }>(
        `select (select count(*)::int from courses where user_id=$1) as subjects,
                (select count(*)::int from items where user_id=$1) as tasks,
                (select count(*)::int from daily_plan_items where user_id=$1) as blocks,
                (select count(*)::int from study_logs where user_id=$1) as logs`,
        [user.id],
      );
      expect(counts.rows[0]).toEqual({
        subjects: data.subjects.length - 1,
        tasks: data.tasks.length - 1,
        blocks: data.blocks.length - 1,
        logs: data.logs.length - 1,
      });
      const pulled = (
        await app.inject({ url: "/api/planner/sync", headers: user.headers })
      ).json();
      expect(pulled.data).toEqual(reduced);
    });

    it("rolls back a partially written projection when a relationship write fails", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const put = (value: any, base: any, revision: number) =>
        app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data: value, base, expectedRevision: revision },
        });
      const saved = await put(data, null, 0);
      expect(saved.statusCode, saved.body).toBe(200);
      const savedState = saved.json();
      const functionName = "optfix_fail_study_logs";
      try {
        // 注入一次真实的事务内失败：study_logs 写入抛错时，之前的 profiles/items/days 写入必须回滚。
        await db.query(
          `create or replace function ${functionName}() returns trigger language plpgsql as $$
           begin
             if NEW.user_id = '${user.id}'::uuid then
               raise exception 'injected projection write failure';
             end if;
             return NEW;
           end $$`,
        );
        await db.query(`drop trigger if exists ${functionName} on study_logs`);
        await db.query(
          `create trigger ${functionName} before insert or update on study_logs
           for each row execute function ${functionName}()`,
        );
        const broken = structuredClone(savedState.data);
        broken.tasks[0].title = "不应提交的标题";
        broken.logs[0].minutes += 7;
        const failed = await put(broken, savedState.data, savedState.revision);
        expect(failed.statusCode, failed.body).toBe(500);
      } finally {
        await db.query(`drop trigger if exists ${functionName} on study_logs`);
        await db.query(`drop function if exists ${functionName}()`);
      }
      // 事务回滚：关系表没有半套投影，同步状态与 revision 保持失败前值。
      const stored = await db.query<{ title: string; minutes: number }>(
        `select i.title, l.minutes from items i join study_logs l on l.item_id=i.id
         where i.user_id=$1`,
        [user.id],
      );
      expect(stored.rows[0]).toEqual({
        title: data.tasks[0].title,
        minutes: data.logs[0].minutes,
      });
      const state = (
        await app.inject({ url: "/api/planner/sync", headers: user.headers })
      ).json();
      expect(state.revision).toBe(savedState.revision);
      expect(state.data).toEqual(savedState.data);
      // 失败清理后同一文档可以正常提交。
      const repaired = structuredClone(savedState.data);
      repaired.tasks[0].title = "恢复后的标题";
      const retried = await put(repaired, savedState.data, savedState.revision);
      expect(retried.statusCode, retried.body).toBe(200);
    });

    it("moves blocks to new dates without reusing an occupied daily plan row id", async () => {
      const user = await account(),
        data = await fixture(user.id);
      const put = (value: any, base: any, revision: number) =>
        app.inject({
          method: "PUT",
          url: "/api/planner/sync",
          headers: user.headers,
          payload: { data: value, base, expectedRevision: revision },
        });
      const pull = async () =>
        (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
      const dayRows = async () =>
        (
          await db.query<{ date: string; planned_minutes: number }>(
            "select date::text as date, planned_minutes from daily_plan_items where user_id=$1 order by date",
            [user.id],
          )
        ).rows;
      const first = await put(data, null, 0);
      expect(first.statusCode, first.body).toBe(200);

      // 问题二的服务端路径：block id 不变、只把 date 移到新日期（移动日程）。
      const moved = structuredClone(first.json().data);
      moved.blocks[0].date = "2026-12-20";
      for (const log of moved.logs)
        if (log.block_id === moved.blocks[0].id) log.date = "2026-12-20";
      const movedResult = await put(moved, first.json().data, first.json().revision);
      expect(movedResult.statusCode, movedResult.body).toBe(200);
      // 新日期行正确、旧日期行移除。
      expect(await dayRows()).toEqual([{ date: "2026-12-20", planned_minutes: 30 }]);
      // 同步读取读到移动后的文档；原样回传不产生伪冲突。
      const afterMove = await pull();
      expect(afterMove.data.blocks[0].date).toBe("2026-12-20");
      expect(afterMove.data).toEqual(movedResult.json().data);
      const resync = await put(afterMove.data, afterMove.data, afterMove.revision);
      expect(resync.statusCode, resync.body).toBe(200);
      expect(await dayRows()).toEqual([{ date: "2026-12-20", planned_minutes: 30 }]);

      // 移动回原日期：日行 id 选择必须稳定且可重复。
      const back = structuredClone(resync.json().data);
      back.blocks[0].date = "2026-10-16";
      const backResult = await put(back, resync.json().data, resync.json().revision);
      expect(backResult.statusCode, backResult.body).toBe(200);
      expect(await dayRows()).toEqual([{ date: "2026-10-16", planned_minutes: 30 }]);
      const backAgain = await put(
        backResult.json().data,
        backResult.json().data,
        backResult.json().revision,
      );
      expect(backAgain.statusCode, backAgain.body).toBe(200);

      // 多块同时移动到全新日期：每个目标日行 id 都不能复用被其他 (item,date) 占用的行 id。
      const multi = structuredClone(backAgain.json().data);
      multi.blocks = [
        ...multi.blocks,
        ...[
          { ...multi.blocks[0], id: randomUUID(), date: "2026-10-17" },
          { ...multi.blocks[0], id: randomUUID(), date: "2026-10-18" },
        ],
      ];
      const seeded = await put(multi, backAgain.json().data, backAgain.json().revision);
      expect(seeded.statusCode, seeded.body).toBe(200);
      expect((await dayRows()).map((row) => row.date)).toEqual([
        "2026-10-16",
        "2026-10-17",
        "2026-10-18",
      ]);
      const movedMulti = structuredClone(seeded.json().data);
      movedMulti.blocks = movedMulti.blocks.map((block: any, index: number) => ({
        ...block,
        date: `2026-11-0${index + 1}`,
      }));
      const movedMultiResult = await put(
        movedMulti,
        seeded.json().data,
        seeded.json().revision,
      );
      expect(movedMultiResult.statusCode, movedMultiResult.body).toBe(200);
      expect((await dayRows()).map((row) => row.date)).toEqual([
        "2026-11-01",
        "2026-11-02",
        "2026-11-03",
      ]);
      const movedMultiPull = await pull();
      expect(
        movedMultiPull.data.blocks.map((block: any) => block.date).sort(),
      ).toEqual(["2026-11-01", "2026-11-02", "2026-11-03"]);
      const multiResync = await put(
        movedMultiPull.data,
        movedMultiPull.data,
        movedMultiPull.revision,
      );
      expect(multiResync.statusCode, multiResync.body).toBe(200);

      // 账号隔离不受影响：其他账号仍是空计划。
      const other = await account();
      expect(
        (await app.inject({ url: "/api/planner/sync", headers: other.headers })).json(),
      ).toEqual({ data: null, revision: 0 });
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
