import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { SignJWT } from "jose";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

/**
 * 真实隔离 PostgreSQL 上的同步投影测试（新概念：临时学习 / 三类执行关系 / 灵活容量）。
 *
 * 覆盖：PUT→GET→关系投影往返、旧文档兼容、旧写入方保留策略与 426 升级提示、
 * 容量覆盖显式清空、revision 增量有界、账号隔离、task_id 为空的临时学习日志存活。
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

    /**
     * 带全新概念的完整文档：容量口径/基线/范围/周与日期覆盖、临时学习实体、
     * scheduled/extra/ad_hoc 三类日志与稳定 session 关联。
     */
    async function learningDocument(
      owner: string,
      options: { adHocLog?: boolean; label?: string } = {},
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
      const photo = {
        id: `${label}-photo`,
        user_id: owner,
        title: "临时了解摄影构图",
        created_at: "2026-10-18T09:00:00.000Z",
        updated_at: "2026-10-18T09:00:00.000Z",
        archived: false,
      };
      const converted = {
        id: randomUUID(),
        user_id: owner,
        title: "已关联到正式事项的临时学习",
        subject_id: data.subjects[0].id,
        created_at: "2026-10-18T11:00:00.000Z",
        updated_at: "2026-10-18T11:00:00.000Z",
        archived: true,
        converted_task_id: data.tasks[0].id,
      };
      data.ad_hoc_learnings = [photo, converted];
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
        ...(options.adHocLog === false
          ? []
          : [
              {
                id: `${label}-log-photo`,
                user_id: owner,
                task_id: null,
                block_id: null,
                date: "2026-10-18",
                minutes: 20,
                started_at: "2026-10-18T10:00:00.000Z",
                ended_at: "2026-10-18T10:20:00.000Z",
                source: "timer",
                relation: "ad_hoc",
                session_id: "session-photo",
                ad_hoc_id: photo.id,
                quota_minutes: 20,
              },
            ]),
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
      delete legacy.ad_hoc_learnings;
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
        delete log.ad_hoc_id;
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

      // 1) 同步文档往返：新字段一个都不能丢。
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

      // 2) 关系投影：临时学习实体、三类执行关系、会话与额度、容量列全部落库。
      const native = await nativeSnapshot(user);
      const nativeAdHoc = new Map<string, any>(
        (native.ad_hoc_learnings as any[]).map((row: any) => [row.id, row]),
      );
      expect(nativeAdHoc.size).toBe(2);
      const nativePhoto = [...nativeAdHoc.values()].find(
        (row: any) => row.title === "临时了解摄影构图",
      );
      expect(nativePhoto.archived).toBe(false);
      expect(native.ad_hoc_learnings.every((row: any) => row.user_id === user.id)).toBe(true);
      const nativeConverted = [...nativeAdHoc.values()].find(
        (row: any) => row.title === "已关联到正式事项的临时学习",
      );
      expect(nativeConverted.archived).toBe(true);
      expect(nativeConverted.subject_id).toBe(native.subjects[0].id);
      expect(nativeConverted.converted_task_id).toBe(native.tasks[0].id);

      const storedAdHoc = await db.query<any>(
        "select id,user_id,title,subject_id,archived,converted_task_id from ad_hoc_learnings where user_id=$1 order by created_at",
        [user.id],
      );
      expect(storedAdHoc.rows).toHaveLength(2);
      expect(storedAdHoc.rows[0]).toMatchObject({
        user_id: user.id,
        title: "临时了解摄影构图",
        archived: false,
        subject_id: null,
        converted_task_id: null,
      });
      const nativePhotoRow = storedAdHoc.rows[0];

      const storedLogs = (
        await db.query<any>(
          `select id,item_id,ad_hoc_id,daily_plan_item_id,date::text as date,minutes,
             relation,session_id,quota_minutes
           from study_logs where user_id=$1 order by created_at`,
          [user.id],
        )
      ).rows;
      expect(storedLogs).toHaveLength(3);
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
        { id: expect.any(String), relation: "ad_hoc", minutes: 20, session: "session-photo", quota: 20, hasItem: false },
      ]);
      // 临时学习日志没有正式事项，但仍能稳定归属临时学习实体。
      const storedPhotoLog = storedLogs[2];
      expect(storedPhotoLog.item_id).toBeNull();
      expect(storedPhotoLog.ad_hoc_id).toBe(nativePhotoRow.id);

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

      // 3) 账号隔离：其他账号既看不到实体，也不能复用别人的原生标识。
      const other = await account();
      expect(await pull(other)).toEqual({ data: null, revision: 0 });
      const foreignDocument: any = await fixture(other.id);
      foreignDocument.ad_hoc_learnings = [
        {
          id: nativePhotoRow.id,
          user_id: other.id,
          title: "盗用别账号标识",
          created_at: "2026-10-18T09:00:00.000Z",
          updated_at: "2026-10-18T09:00:00.000Z",
          archived: false,
        },
      ];
      const foreign = await put(other, {
        data: foreignDocument,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(foreign.statusCode, foreign.body).toBe(409);
      expect(
        (
          await db.query<any>(
            "select title from ad_hoc_learnings where id=$1",
            [nativePhotoRow.id],
          )
        ).rows[0].title,
      ).toBe("临时了解摄影构图");
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
          `select (select count(*)::int from ad_hoc_learnings where user_id=$1) as ad_hoc,
                  (select capacity_basis from profiles where user_id=$1) as capacity_basis,
                  (select relation from study_logs where user_id=$1 limit 1) as relation`,
          [legacyUser.id],
        )
      ).rows[0];
      expect(legacyProjection).toEqual({
        ad_hoc: 0,
        capacity_basis: null,
        relation: "legacy_unknown",
      });

      // 云端已有新数据时，旧写入方缺字段 → 保留而不是清空（修复前会静默清除）。
      const user = await account();
      const data = await learningDocument(user.id, { adHocLog: false, label: "preserve" });
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);
      const before = await pull(user);
      expect(before.data.ad_hoc_learnings).toHaveLength(2);

      const legacyWriterData = asLegacyWriter(before.data);
      const written = await put(user, {
        data: legacyWriterData,
        base: before.data,
        expectedRevision: before.revision,
      });
      expect(written.statusCode, written.body).toBe(200);
      const after = await pull(user);
      // 临时学习、容量覆盖、执行关系/会话/额度全部保留。
      expect(after.data.ad_hoc_learnings).toEqual(before.data.ad_hoc_learnings);
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

    it("asks old writers to upgrade instead of deleting task-less ad-hoc logs", async () => {
      const user = await account();
      const data = await learningDocument(user.id);
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);
      const before = await pull(user);
      const revisionBefore = Number(before.revision);

      // 旧写入方无法表达 task_id=null 的临时学习日志：它会把这些行整个丢掉。
      const legacyWriterData = asLegacyWriter(before.data);
      legacyWriterData.logs = legacyWriterData.logs.filter(
        (log: any) => log.task_id !== null,
      );
      const rejected = await put(user, {
        data: legacyWriterData,
        base: before.data,
        expectedRevision: before.revision,
      });
      expect(rejected.statusCode, rejected.body).toBe(426);
      expect(rejected.json()).toMatchObject({
        upgradeRequired: true,
        code: "learning_writer_upgrade_required",
      });
      expect(rejected.json().error).toContain("升级客户端");

      // 拒绝时事务回滚：revision、文档、数据库里的真实计时全部不变。
      const after = await pull(user);
      expect(Number(after.revision)).toBe(revisionBefore);
      expect(after.data.logs).toHaveLength(3);
      expect(
        (
          await db.query<any>(
            "select count(*)::int as n from study_logs where user_id=$1 and item_id is null",
            [user.id],
          )
        ).rows[0].n,
      ).toBe(1);
      // 升级后（发送能力声明）同一 revision/base 可以正常重试，不会变成 409。
      const upgraded = await put(user, {
        data: before.data,
        base: before.data,
        expectedRevision: before.revision,
        writer_learning_version: 1,
      });
      expect(upgraded.statusCode, upgraded.body).toBe(200);
    });

    it("clears capacity only when the capable writer explicitly sends an empty value", async () => {
      const user = await account();
      const data = await learningDocument(user.id, { adHocLog: false, label: "capacity" });
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
      const data = await learningDocument(user.id, { adHocLog: false, label: "blob" });
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

    it("removes ad-hoc entities and their logs in FK-safe order and converts without duplicating minutes", async () => {
      const user = await account();
      const data = await learningDocument(user.id, { label: "convert" });
      const saved = await put(user, {
        data,
        base: null,
        expectedRevision: 0,
        writer_learning_version: 1,
      });
      expect(saved.statusCode, saved.body).toBe(200);
      const before = await pull(user);
      const beforeAdHoc = await db.query<any>(
        "select id,title,archived,converted_task_id from ad_hoc_learnings where user_id=$1 order by created_at",
        [user.id],
      );
      const photoNative = beforeAdHoc.rows.find(
        (row: any) => row.title === "临时了解摄影构图",
      );
      const photoLog = before.data.logs.find(
        (log: any) => log.ad_hoc_id === "convert-photo",
      );
      expect(photoLog.minutes).toBe(20);

      // 1) 关联到已有事项（转换）：原日志 id/session/分钟全部保留，只改归属并归档实体。
      const converted = structuredClone(before.data);
      converted.tasks.push({
        ...converted.tasks[0],
        id: randomUUID(),
        title: "摄影构图正式事项",
        estimated_minutes: 120,
      });
      converted.logs = converted.logs.map((log: any) =>
        log.ad_hoc_id === "convert-photo"
          ? { ...log, task_id: converted.tasks.at(-1).id }
          : log,
      );
      converted.ad_hoc_learnings = converted.ad_hoc_learnings.map((row: any) =>
        row.id === "convert-photo"
          ? {
              ...row,
              archived: true,
              converted_task_id: converted.tasks.at(-1).id,
              updated_at: "2026-10-19T09:00:00.000Z",
            }
          : row,
      );
      const convertedResult = await put(user, {
        data: converted,
        base: before.data,
        expectedRevision: before.revision,
        writer_learning_version: 1,
      });
      expect(convertedResult.statusCode, convertedResult.body).toBe(200);
      const convertedPull = await pull(user);
      // 任务顺序按 deadline/created_at 排序（并列时顺序不保证），只断言转换相关字段。
      expect(
        convertedPull.data.tasks.some(
          (task: any) => task.id === converted.tasks.at(-1).id,
        ),
      ).toBe(true);
      expect(
        convertedPull.data.logs.find(
          (log: any) => log.ad_hoc_id === "convert-photo",
        ),
      ).toMatchObject({ task_id: converted.tasks.at(-1).id, minutes: 20 });
      expect(
        convertedPull.data.ad_hoc_learnings.find(
          (row: any) => row.id === "convert-photo",
        ),
      ).toMatchObject({
        archived: true,
        converted_task_id: converted.tasks.at(-1).id,
      });
      const storedConvertedLog = (
        await db.query<any>(
          `select item_id,ad_hoc_id,relation,session_id,minutes from study_logs
           where user_id=$1 and ad_hoc_id=$2`,
          [user.id, photoNative.id],
        )
      ).rows[0];
      // 不复制分钟：原记录仍是唯一一条，只是归属变成正式事项，历史 ad_hoc 关系保留。
      expect(storedConvertedLog).toMatchObject({
        item_id: converted.tasks.at(-1).id,
        ad_hoc_id: photoNative.id,
        relation: "ad_hoc",
        session_id: "session-photo",
        minutes: 20,
      });
      expect(
        (
          await db.query<any>(
            "select archived,converted_task_id from ad_hoc_learnings where id=$1",
            [photoNative.id],
          )
        ).rows[0],
      ).toEqual({
        archived: true,
        converted_task_id: converted.tasks.at(-1).id,
      });

      // 2) capable writer 同时删除实体与其日志：sync 必须先删日志再删实体（restrict 外键）。
      const removed = structuredClone(convertedPull.data);
      removed.logs = removed.logs.filter(
        (log: any) => log.ad_hoc_id !== "convert-photo",
      );
      removed.ad_hoc_learnings = removed.ad_hoc_learnings.filter(
        (row: any) => row.id !== "convert-photo",
      );
      const removedResult = await put(user, {
        data: removed,
        base: convertedPull.data,
        expectedRevision: convertedPull.revision,
        writer_learning_version: 1,
      });
      expect(removedResult.statusCode, removedResult.body).toBe(200);
      expect(
        (
          await db.query<any>("select count(*)::int as n from ad_hoc_learnings where id=$1", [
            photoNative.id,
          ])
        ).rows[0].n,
      ).toBe(0);
      expect(
        (
          await db.query<any>("select count(*)::int as n from study_logs where ad_hoc_id=$1", [
            photoNative.id,
          ])
        ).rows[0].n,
      ).toBe(0);
      expect((await pull(user)).data.logs).toHaveLength(removed.logs.length);
    });

    it("keeps revision deltas bounded for single-record changes", async () => {
      const user = await account();
      const data = await learningDocument(user.id, { adHocLog: false, label: "revision" });
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
      next.ad_hoc_learnings[0].title = "临时了解摄影用光";
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
      // 一行日志 + 一行临时学习 + 一行 profile + 状态行，不能被全量重写放大。
      const delta = Number(changed.json().revision) - beforeRevision;
      expect(delta).toBeGreaterThan(0);
      expect(delta).toBeLessThan(20);
      expect(changed.json().data.ad_hoc_learnings[0].title).toBe("临时了解摄影用光");
    });
  },
);
