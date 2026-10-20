import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { SignJWT } from "jose";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

/**
 * 真实隔离 PostgreSQL 上的同步投影测试（二期：临时学习已从服务端删除）。
 *
 * 覆盖：PUT→GET→关系投影往返、旧文档/旧写入方兼容、容量覆盖显式清空、
 * revision 增量有界、账号隔离，以及不含任何临时学习结构（表/列/日志归属）。
 */
describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)(
  "learning relations synchronization",
  () => {
    let app: Awaited<ReturnType<(typeof import("./server.js"))["buildApp"]>>;
    let db: typeof import("./db.js");
    const secret = "learning-sync-test-01234567890123456789";

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

    const monday = (() => {
      const date = new Date("2026-10-19T00:00:00Z");
      while (date.getUTCDay() !== 1) date.setUTCDate(date.getUTCDate() + 1);
      return date.toISOString().slice(0, 10);
    })();

    /** 带新概念的完整文档：容量口径/基线/范围/周与日期覆盖、两类执行关系与稳定 session。 */
    async function learningDocument(
      owner: string,
      options: { label?: string } = {},
    ) {
      const data: any = await fixture(owner);
      const label = options.label ?? "learning";
      data.profile.capacity_basis = "net";
      data.profile.weekly_baseline_minutes = 540;
      data.profile.weekly_range_min_minutes = 300;
      data.profile.weekly_range_max_minutes = 600;
      data.profile.week_capacity_overrides = {
        [monday]: { total_minutes: 180, days: { "6": 60 } },
      };
      data.profile.date_capacity_overrides = { "2026-11-02": 0, "2026-11-03": 90 };
      data.logs = [
        {
          ...data.logs[0],
          id: `${label}-scheduled`,
          relation: "scheduled",
          session_id: "session-mixed",
          quota_minutes: 60,
        },
        {
          ...data.logs[0],
          id: `${label}-extra`,
          minutes: 30,
          relation: "extra",
          session_id: "session-mixed",
          started_at: "2026-10-16T14:00:00.000Z",
          ended_at: "2026-10-16T14:30:00.000Z",
        },
      ];
      return data;
    }

    const put = (
      user: { headers: Record<string, string> },
      payload: Record<string, unknown>,
    ) =>
      app.inject({
        method: "PUT",
        url: "/api/planner/sync",
        headers: user.headers,
        payload,
      });
    const pull = async (user: { headers: Record<string, string> }) =>
      (await app.inject({ url: "/api/planner/sync", headers: user.headers })).json();
    const nativeSnapshot = async (
      user: { headers: Record<string, string> },
    ): Promise<any> =>
      (
        await app.inject({
          url: "/api/planner/snapshot",
          headers: user.headers,
        })
      ).json().data;

    /** 模拟旧写入方：它不理解新字段，重新序列化时会把它们全部丢掉。 */
    function asLegacyWriter(document: any) {
      const legacy = structuredClone(document);
      for (const key of [
        "capacity_basis",
        "weekly_baseline_minutes",
        "weekly_range_min_minutes",
        "weekly_range_max_minutes",
        "week_capacity_overrides",
        "date_capacity_overrides",
      ])
        delete legacy.profile[key];
      legacy.logs = legacy.logs.map((log: any) => {
        delete log.relation;
        delete log.session_id;
        delete log.quota_minutes;
        return log;
      });
      return legacy;
    }

    /** 多个集成测试文件并行执行时，建库语句存在 PostgreSQL 已知的 if-not-exists 目录竞态；重试即可。 */
    async function applyInstallationSchema() {
      const installation = await readFile(
        new URL("../db/schema.sql", import.meta.url),
        "utf8",
      );
      for (let attempt = 0; ; attempt++) {
        try {
          await db.query(installation);
          return;
        } catch (error) {
          const code = (error as { code?: string }).code;
          if (attempt < 5 && ["23505", "40P01", "40001"].includes(code ?? "")) {
            await new Promise((resolve) => setTimeout(resolve, 60 * (attempt + 1)));
            continue;
          }
          throw error;
        }
      }
    }

    beforeAll(async () => {
      vi.stubEnv("DATABASE_URL", process.env.AUTH_TEST_DATABASE_URL!);
      vi.stubEnv("JWT_ACCESS_SECRET", secret);
      vi.stubEnv("NODE_ENV", "test");
      db = await import("./db.js");
      await applyInstallationSchema();
      app = await (await import("./server.js")).buildApp();
      await app.ready();
    });
    afterAll(async () => {
      await app?.close();
      await db?.pool.end();
      vi.unstubAllEnvs();
    });

    it("round-trips new document fields through the relational projection", async () => {
      const user = await account();
      const data = await learningDocument(user.id);
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_planning_version: 1,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);

      // 1) 同步文档往返：容量与执行关系字段一个都不能丢。
      const pulled = await pull(user);
      expect(pulled.data).toEqual(data);
      expect((await pull(user)).data).toEqual(data);
      // 原样回传不产生伪冲突。
      const resync = await put(user, {
        data: pulled.data,
        base: pulled.data,
        expectedRevision: pulled.revision,
        writer_learning_version: 1,
      });
      expect(resync.statusCode, resync.body).toBe(200);
      expect(resync.json().data).toEqual(data);

      // 2) 关系投影：执行关系、会话与额度、容量列全部落库；不再有临时学习结构。
      const native = await nativeSnapshot(user);
      expect(native).not.toHaveProperty("ad_hoc_learnings");
      const storedLogs = (
        await db.query<any>(
          `select id,item_id,daily_plan_item_id,date::text as date,minutes,
             relation,session_id,quota_minutes
           from study_logs where user_id=$1 order by created_at`,
          [user.id],
        )
      ).rows;
      expect(storedLogs).toHaveLength(2);
      // 计时发生关系原样保存；同一件事当天可同时有 scheduled 与 extra。
      expect(
        storedLogs.map((row: any) => ({
          id: row.id,
          relation: row.relation,
          minutes: row.minutes,
          session: row.session_id,
          quota: row.quota_minutes,
          hasItem: row.item_id !== null,
        })),
      ).toEqual([
        { id: expect.any(String), relation: "scheduled", minutes: 35, session: "session-mixed", quota: 60, hasItem: true },
        { id: expect.any(String), relation: "extra", minutes: 30, session: "session-mixed", quota: null, hasItem: true },
      ]);
      const storedProfile = (
        await db.query<any>(
          `select capacity_basis,weekly_baseline_minutes,weekly_range_min_minutes,
             weekly_range_max_minutes,week_capacity_overrides,date_capacity_overrides
           from profiles where user_id=$1`,
          [user.id],
        )
      ).rows[0];
      expect(storedProfile).toEqual({
        capacity_basis: "net",
        weekly_baseline_minutes: 540,
        weekly_range_min_minutes: 300,
        weekly_range_max_minutes: 600,
        week_capacity_overrides: {
          [monday]: { total_minutes: 180, days: { "6": 60 } },
        },
        date_capacity_overrides: { "2026-11-02": 0, "2026-11-03": 90 },
      });
      // 迁移后数据库里不再有临时学习表或列。
      expect(
        (await db.query("select to_regclass('ad_hoc_learnings') as table_name")).rows[0].table_name,
      ).toBeNull();
      expect(
        (
          await db.query(
            `select column_name from information_schema.columns
             where table_schema=current_schema() and column_name like '%ad_hoc%'`,
          )
        ).rows,
      ).toEqual([]);

      // 3) 账号隔离：其他账号既看不到计划，也不能复用别人的原生标识。
      const other = await account();
      expect(await pull(other)).toEqual({ data: null, revision: 0 });
      const foreignDocument: any = await fixture(other.id);
      foreignDocument.logs[0] = { ...foreignDocument.logs[0], id: native.logs[0].id };
      const foreign = await put(other, {
        data: foreignDocument,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(foreign.statusCode, foreign.body).toBe(409);
      expect(
        (
          await db.query<any>("select minutes from study_logs where id=$1", [native.logs[0].id])
        ).rows[0].minutes,
      ).toBe(data.logs[0].minutes);
    });

    it("keeps legacy documents working and never silently clears new data for old writers", async () => {
      // 旧文档（不包含任何新字段）继续可用：这是旧客户端/旧导出的正常路径。
      const legacyUser = await account();
      const legacyData = await fixture(legacyUser.id);
      const legacySaved = await put(legacyUser, {
        data: legacyData,
        base: null,
        expectedRevision: 0,
      });
      expect(legacySaved.statusCode, legacySaved.body).toBe(200);
      const legacyPulled = await pull(legacyUser);
      expect(legacyPulled.data).toEqual(legacyData);
      const legacyProjection = (
        await db.query<any>(
          `select (select count(*)::int from study_logs where user_id=$1 and item_id is null) as missing_item,
                  (select capacity_basis from profiles where user_id=$1) as capacity_basis,
                  (select relation from study_logs where user_id=$1 limit 1) as relation`,
          [legacyUser.id],
        )
      ).rows[0];
      expect(legacyProjection).toEqual({
        missing_item: 0,
        capacity_basis: null,
        relation: "legacy_unknown",
      });

      // 云端已有新数据时，旧写入方缺字段 → 保留而不是清空（修复前会静默清除）。
      const user = await account();
      const data = await learningDocument(user.id, { label: "preserve" });
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);
      const before = await pull(user);

      const legacyWriterData = asLegacyWriter(before.data);
      const written = await put(user, {
        data: legacyWriterData,
        base: before.data,
        expectedRevision: before.revision,
      });
      expect(written.statusCode, written.body).toBe(200);
      const after = await pull(user);
      // 容量覆盖、执行关系/会话/额度全部保留。
      expect(after.data.profile.capacity_basis).toBe("net");
      expect(after.data.profile.weekly_baseline_minutes).toBe(540);
      expect(after.data.profile.week_capacity_overrides).toEqual(
        before.data.profile.week_capacity_overrides,
      );
      expect(after.data.profile.date_capacity_overrides).toEqual(
        before.data.profile.date_capacity_overrides,
      );
      expect(
        after.data.logs.map((log: any) => ({
          relation: log.relation,
          session: log.session_id,
          quota: log.quota_minutes,
        })),
      ).toEqual(
        before.data.logs.map((log: any) => ({
          relation: log.relation,
          session: log.session_id,
          quota: log.quota_minutes,
        })),
      );
      // 旧写入方也同步了普通修改：两边都生效，互不覆盖。
      expect(after.data.profile.goal_text).toBe(data.profile.goal_text);
      expect(written.json().data.tasks[0].title).toBe(data.tasks[0].title);
    });

    it("rejects documents that still contain task-less or ad_hoc-relation logs", async () => {
      const user = await account();
      const data = await learningDocument(user.id, { label: "removed" });
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);
      const revisionBefore = saved.json().revision;
      const logCount = async () =>
        (
          await db.query<{ count: number }>("select count(*)::int as count from study_logs where user_id=$1", [user.id])
        ).rows[0].count;
      expect(await logCount()).toBe(2);

      // 旧的临时学习日志没有正式事项：服务端已删除该能力，返回 400 且不写任何数据。
      const taskLess = structuredClone(saved.json().data);
      taskLess.logs.push({
        ...taskLess.logs[0],
        id: "legacy-ad-hoc-log",
        task_id: null,
        block_id: null,
        relation: "ad_hoc",
        session_id: "legacy-session",
      });
      const rejectedTaskLess = await put(user, {
        data: taskLess,
        base: saved.json().data,
        expectedRevision: saved.json().revision,
        writer_learning_version: 1,
      });
      expect(rejectedTaskLess.statusCode, rejectedTaskLess.body).toBe(400);
      // relation=ad_hoc 也不再是合法执行关系。
      const adHocRelation = structuredClone(saved.json().data);
      adHocRelation.logs[0].relation = "ad_hoc";
      const rejectedRelation = await put(user, {
        data: adHocRelation,
        base: saved.json().data,
        expectedRevision: saved.json().revision,
        writer_learning_version: 1,
      });
      expect(rejectedRelation.statusCode, rejectedRelation.body).toBe(400);

      // 拒绝时事务整体回滚：revision、日志数量与内容都不变。
      expect((await pull(user)).revision).toBe(revisionBefore);
      expect(await logCount()).toBe(2);
      expect((await pull(user)).data.logs.map((row: any) => row.relation)).toEqual(
        ["scheduled", "extra"],
      );
    });

    it("clears capacity only when the capable writer explicitly sends an empty value", async () => {
      const user = await account();
      const data = await learningDocument(user.id, { label: "capacity" });
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);

      // 旧写入方缺字段：保留（前面用例已覆盖），这里验证“具备新能力时显式空=清除”。
      const cleared = structuredClone(saved.json().data);
      cleared.profile.week_capacity_overrides = {};
      cleared.profile.date_capacity_overrides = {};
      delete cleared.profile.weekly_baseline_minutes;
      delete cleared.profile.weekly_range_min_minutes;
      delete cleared.profile.weekly_range_max_minutes;
      const clearedResult = await put(user, {
        data: cleared,
        base: saved.json().data,
        expectedRevision: saved.json().revision,
        writer_learning_version: 1,
      });
      expect(clearedResult.statusCode, clearedResult.body).toBe(200);
      const stored = (
        await db.query<any>(
          `select capacity_basis,weekly_baseline_minutes,weekly_range_min_minutes,
             weekly_range_max_minutes,week_capacity_overrides,date_capacity_overrides
           from profiles where user_id=$1`,
          [user.id],
        )
      ).rows[0];
      expect(stored).toEqual({
        capacity_basis: "net",
        weekly_baseline_minutes: null,
        weekly_range_min_minutes: null,
        weekly_range_max_minutes: null,
        week_capacity_overrides: {},
        date_capacity_overrides: {},
      });
      const pulled = await pull(user);
      expect(pulled.data.profile.week_capacity_overrides).toEqual({});
      expect(pulled.data.profile.date_capacity_overrides).toEqual({});
      expect(pulled.data.profile.weekly_baseline_minutes).toBeUndefined();

      // 显式 0 是有效的休息日容量，不是“未设置”。
      const zero = structuredClone(clearedResult.json().data);
      zero.profile.date_capacity_overrides = { "2026-11-02": 0 };
      const zeroResult = await put(user, {
        data: zero,
        base: clearedResult.json().data,
        expectedRevision: clearedResult.json().revision,
        writer_learning_version: 1,
      });
      expect(zeroResult.statusCode, zeroResult.body).toBe(200);
      expect(
        (
          await db.query<any>(
            "select date_capacity_overrides from profiles where user_id=$1",
            [user.id],
          )
        ).rows[0].date_capacity_overrides,
      ).toEqual({ "2026-11-02": 0 });
      expect((await pull(user)).data.profile.date_capacity_overrides).toEqual({
        "2026-11-02": 0,
      });
    });

    it("reads blob capacity values when the projection columns are still missing", async () => {
      const user = await account();
      const data = await learningDocument(user.id, { label: "blob" });
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);
      // 模拟“迁移还没投影这些列”的旧行：列全为 NULL，但文档 blob 已有新值。
      await db.query(
        `update profiles set capacity_basis=null,weekly_baseline_minutes=null,
           weekly_range_min_minutes=null,weekly_range_max_minutes=null,
           week_capacity_overrides=null,date_capacity_overrides=null where user_id=$1`,
        [user.id],
      );
      const pulled = await pull(user);
      expect(pulled.data.profile.capacity_basis).toBe("net");
      expect(pulled.data.profile.weekly_baseline_minutes).toBe(540);
      expect(pulled.data.profile.week_capacity_overrides).toEqual(
        data.profile.week_capacity_overrides,
      );
      // 关系投影（native）没有列值时不伪造默认值。
      const native = await nativeSnapshot(user);
      expect(native.profile.capacity_basis).toBeUndefined();
      expect(native.profile.weekly_baseline_minutes).toBeUndefined();

      // 旧写入方再同步：blob 中的容量值保留，并自愈关系列。
      const legacyWriterData = asLegacyWriter(pulled.data);
      const resync = await put(user, {
        data: legacyWriterData,
        base: pulled.data,
        expectedRevision: pulled.revision,
      });
      expect(resync.statusCode, resync.body).toBe(200);
      const healed = (
        await db.query<any>(
          "select capacity_basis,weekly_baseline_minutes from profiles where user_id=$1",
          [user.id],
        )
      ).rows[0];
      expect(healed).toEqual({
        capacity_basis: "net",
        weekly_baseline_minutes: 540,
      });
    });

    it("keeps revision deltas bounded for single-record changes", async () => {
      const user = await account();
      const data = await learningDocument(user.id, { label: "revision" });
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);
      const beforeRevision = Number(saved.json().revision);
      const next = structuredClone(saved.json().data);
      next.logs[0].minutes += 1;
      next.profile.week_capacity_overrides = {
        [monday]: { total_minutes: 240 },
      };
      const changed = await put(user, {
        data: next,
        base: saved.json().data,
        expectedRevision: saved.json().revision,
        writer_learning_version: 1,
      });
      expect(changed.statusCode, changed.body).toBe(200);
      // 一行日志 + 一行 profile + 状态行，不能被全量重写放大。
      const delta = Number(changed.json().revision) - beforeRevision;
      expect(delta).toBeGreaterThan(0);
      expect(delta).toBeLessThan(20);
      expect(changed.json().data.profile.week_capacity_overrides).toEqual({
        [monday]: { total_minutes: 240 },
      });
    });
  },
);
