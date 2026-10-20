import { readdir, readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { describe, expect, it } from "vitest";

/**
 * 真实隔离 PostgreSQL 上的迁移测试（二期：删除临时学习）：
 * 1) 在“二期迁移前”的结构上保留真实学习记录，应用新迁移后按规则清理历史数据；
 * 2) 迁移可重复执行（幂等），重复执行不改变结果；
 * 3) 全新安装 schema.sql 已经是删除临时学习后的最终结构，且随后执行全部历史迁移
 *    仍能得到同一结构。
 */
describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)(
  "remove ad-hoc learning migration",
  () => {
    const installation = () => readFile(new URL("../db/schema.sql", import.meta.url), "utf8");
    const migration = (name: string) =>
      readFile(new URL(`../db/migrations/${name}`, import.meta.url), "utf8");

    it("cleans historical ad-hoc data and drops the structures without losing real minutes", async () => {
      const client = new pg.Client({
        connectionString: process.env.AUTH_TEST_DATABASE_URL,
      });
      await client.connect();
      const schemaName = `remove_ad_hoc_${randomUUID().replaceAll("-", "")}`;
      try {
        await client.query(`create schema ${schemaName}`);
        await client.query(`set search_path to ${schemaName},public`);
        // 全新安装的最终 schema，再回退成“二期迁移前”的结构：历史迁移 202610160003
        // 提供 planner_sync_state / revision 触发器，202610200001 重建临时学习表与列。
        await client.query(await installation());
        await client.query(await migration("202610160003_planner_sync.sql"));
        await client.query(await migration("202610200001_learning_relations_capacity.sql"));

        const owner = randomUUID(),
          course = randomUUID(),
          item = randomUUID(),
          day = randomUUID(),
          adHocPhoto = randomUUID(),
          adHocConverted = randomUUID(),
          pureLog = randomUUID(),
          convertedLog = randomUUID(),
          scheduledLog = randomUUID(),
          legacyLog = randomUUID(),
          timestamp = "2026-10-18T09:00:00.000Z";
        await client.query(
          "insert into users(id,email,password_hash) values($1,$2,'test-only')",
          [owner, `migration-${owner}@example.test`],
        );
        await client.query(
          `insert into profiles(user_id,goal_text,weekly_minutes,constraints_text)
           values($1,'旧学习目标','{"0":0,"1":90,"2":90,"3":0,"4":90,"5":90,"6":120}','保留旧学习限制')`,
          [owner],
        );
        await client.query("insert into courses(id,user_id,name) values($1,$2,'阅读')", [course, owner]);
        await client.query(
          `insert into items(id,user_id,course_id,title,estimated_minutes,deadline,confirmed)
           values($1,$2,$3,'读完并总结',120,'2026-11-12',true)`,
          [item, owner, course],
        );
        await client.query(
          `insert into daily_plan_items(id,user_id,item_id,date,planned_minutes,actual_minutes)
           values($1,$2,$3,'2026-10-17',60,45)`,
          [day, owner, item],
        );
        await client.query(
          "insert into ad_hoc_learnings(id,user_id,title) values($1,$2,'临时了解摄影构图')",
          [adHocPhoto, owner],
        );
        await client.query(
          `insert into ad_hoc_learnings(id,user_id,title,subject_id,archived,converted_task_id)
           values($1,$2,'已关联事项的临时学习',$3,true,$4)`,
          [adHocConverted, owner, course, item],
        );
        // 纯临时学习计时：没有正式事项，按确认规则直接删除。
        await client.query(
          `insert into study_logs(id,user_id,ad_hoc_id,date,minutes,relation,session_id,quota_minutes)
           values($1,$2,$3,'2026-10-18',20,'ad_hoc','session-photo',20)`,
          [pureLog, owner, adHocPhoto],
        );
        // 已转为正式事项的计时：真实用时必须保留，只改执行关系并清空引用。
        await client.query(
          `insert into study_logs(id,user_id,item_id,ad_hoc_id,date,minutes,relation,session_id,quota_minutes)
           values($1,$2,$3,$4,'2026-10-17',30,'ad_hoc','session-converted',30)`,
          [convertedLog, owner, item, adHocConverted],
        );
        await client.query(
          `insert into study_logs(id,user_id,item_id,daily_plan_item_id,date,minutes,relation,session_id)
           values($1,$2,$3,$4,'2026-10-17',45,'scheduled','session-scheduled')`,
          [scheduledLog, owner, item, day],
        );
        // 旧数据没有执行关系：保持 legacy_unknown，不能被迁移擅自改写。
        await client.query(
          "insert into study_logs(id,user_id,item_id,date,minutes) values($1,$2,$3,'2026-10-16',10)",
          [legacyLog, owner, item],
        );

        // 权威同步文档 blob 里同样存放着临时学习实体与 task_id 为空的日志。
        const document = {
          version: 1,
          profile: { user_id: owner, goal_text: "旧文档" },
          subjects: [],
          tasks: [],
          blocks: [],
          logs: [
            {
              id: "doc-pure", user_id: owner, task_id: null, block_id: null,
              date: "2026-10-18", minutes: 20, started_at: timestamp, ended_at: timestamp,
              source: "timer", relation: "ad_hoc", session_id: "session-photo",
              ad_hoc_id: adHocPhoto, quota_minutes: 20,
            },
            {
              id: "doc-converted", user_id: owner, task_id: "task-1", block_id: null,
              date: "2026-10-17", minutes: 30, started_at: timestamp, ended_at: timestamp,
              source: "timer", relation: "ad_hoc", session_id: "session-converted",
              ad_hoc_id: adHocConverted, quota_minutes: 30,
            },
            {
              id: "doc-scheduled", user_id: owner, task_id: "task-1", block_id: null,
              date: "2026-10-17", minutes: 45, started_at: timestamp, ended_at: timestamp,
              source: "manual", relation: "scheduled", session_id: "session-scheduled",
            },
          ],
          ad_hoc_learnings: [
            { id: adHocPhoto, user_id: owner, title: "临时了解摄影构图", created_at: timestamp, updated_at: timestamp },
          ],
          fixed_events: [],
          replan_runs: [],
          phases: [],
        };
        await client.query(
          "update planner_sync_state set document=$2::jsonb, projection=$2::jsonb where user_id=$1",
          [owner, JSON.stringify(document)],
        );
        const revisionBefore = Number(
          (await client.query("select revision from planner_sync_state where user_id=$1", [owner])).rows[0].revision,
        );

        const logRows = async () =>
          (
            await client.query(
              `select id,item_id,date::text as date,minutes,relation,session_id,quota_minutes
               from study_logs order by id`,
            )
          ).rows;
        const stateRows = async () =>
          (
            await client.query(
              "select revision,document,projection from planner_sync_state where user_id=$1",
              [owner],
            )
          ).rows[0];

        const sql = await migration("202610230001_remove_ad_hoc_learning.sql");
        await client.query(sql);
        const logsAfterFirst = await logRows();
        const stateAfterFirst = await stateRows();

        // 1) 纯临时学习日志被删除；真实学习记录一条不少。
        expect(logsAfterFirst).toHaveLength(3);
        expect(logsAfterFirst.map((row) => row.id)).toEqual(
          expect.arrayContaining([convertedLog, scheduledLog, legacyLog]),
        );
        expect(logsAfterFirst.map((row) => row.id)).not.toContain(pureLog);
        // 2) 转为正式事项的计时保留 id / 分钟 / 会话 / 额度，关系改写为 extra。
        expect(logsAfterFirst.find((row) => row.id === convertedLog)).toMatchObject({
          item_id: item,
          date: "2026-10-17",
          minutes: 30,
          relation: "extra",
          session_id: "session-converted",
          quota_minutes: 30,
        });
        expect(logsAfterFirst.find((row) => row.id === scheduledLog)).toMatchObject({
          minutes: 45,
          relation: "scheduled",
          session_id: "session-scheduled",
        });
        expect(logsAfterFirst.find((row) => row.id === legacyLog)).toMatchObject({
          minutes: 10,
          relation: "legacy_unknown",
        });

        // 3) ad_hoc 结构已彻底删除：表、列、索引、旧约束都不存在。
        expect(
          (await client.query("select to_regclass('ad_hoc_learnings') as table_name")).rows[0].table_name,
        ).toBeNull();
        expect(
          (
            await client.query(
              `select table_name,column_name from information_schema.columns
               where table_schema=$1 and column_name like '%ad_hoc%'
               order by table_name,column_name`,
              [schemaName],
            )
          ).rows,
        ).toEqual([]);
        expect(
          (
            await client.query(
              `select indexname from pg_indexes
               where schemaname=$1 and (indexname='logs_user_ad_hoc' or indexname='ad_hoc_learnings_user')`,
              [schemaName],
            )
          ).rows,
        ).toEqual([]);
        const studyLogConstraints = (
          await client.query(
            `select conname,pg_get_constraintdef(oid) as definition
             from pg_constraint where conrelid='study_logs'::regclass and contype='c'
             order by conname`,
          )
        ).rows;
        expect(studyLogConstraints.map((row) => row.conname)).not.toContain("study_logs_owner_check");
        const relationCheck = studyLogConstraints.find((row) => row.conname === "study_logs_relation_check");
        expect(relationCheck?.definition).toContain("scheduled");
        expect(relationCheck?.definition).toContain("extra");
        expect(relationCheck?.definition).toContain("legacy_unknown");
        expect(relationCheck?.definition).not.toContain("ad_hoc");
        expect(
          (
            await client.query(
              `select is_nullable from information_schema.columns
               where table_schema=$1 and table_name='study_logs' and column_name in ('item_id','ad_hoc_id')`,
              [schemaName],
            )
          ).rows,
        ).toEqual([{ is_nullable: "NO" }]);

        // 4) 权威同步文档 blob 同步清理，并让 revision 前进以促使客户端重新拉取。
        expect(Number(stateAfterFirst.revision)).toBeGreaterThan(revisionBefore);
        expect(stateAfterFirst.document).not.toHaveProperty("ad_hoc_learnings");
        expect(stateAfterFirst.projection).not.toHaveProperty("ad_hoc_learnings");
        expect(stateAfterFirst.document.logs.map((row: any) => row.id)).toEqual([
          "doc-converted",
          "doc-scheduled",
        ]);
        expect(stateAfterFirst.document.logs[0]).toMatchObject({ task_id: "task-1", relation: "extra", minutes: 30 });
        expect(stateAfterFirst.document.logs[0]).not.toHaveProperty("ad_hoc_id");
        expect(stateAfterFirst.projection.logs[0]).toMatchObject({ relation: "extra" });

        // 5) 新的约束真实生效：无主日志与 ad_hoc 关系都被拒绝。
        await expect(
          client.query(
            `insert into study_logs(user_id,date,minutes) values($1,'2026-10-18',5)`,
            [owner],
          ),
        ).rejects.toThrow(/null value in column "item_id"|not-null/);
        await expect(
          client.query(
            `insert into study_logs(user_id,item_id,date,minutes,relation)
             values($1,$2,'2026-10-18',5,'ad_hoc')`,
            [owner, item],
          ),
        ).rejects.toThrow(/study_logs_relation_check/);

        // 6) 幂等：重复执行不报错，也不再改写任何数据。
        await client.query(sql);
        expect(await logRows()).toEqual(logsAfterFirst);
        expect(await stateRows()).toEqual(stateAfterFirst);
      } finally {
        await client.query(`drop schema if exists ${schemaName} cascade`);
        await client.end();
      }
    });

    it("installation schema already matches the post-removal structure after every migration", async () => {
      const client = new pg.Client({
        connectionString: process.env.AUTH_TEST_DATABASE_URL,
      });
      await client.connect();
      const schemaName = `fresh_install_${randomUUID().replaceAll("-", "")}`;
      const structure = async () => ({
        studyLogColumns: (
          await client.query(
            `select column_name,is_nullable,column_default from information_schema.columns
             where table_schema=$1 and table_name='study_logs' order by column_name`,
            [schemaName],
          )
        ).rows,
        constraints: (
          await client.query(
            `select conname,pg_get_constraintdef(oid) as definition from pg_constraint
             where conrelid='study_logs'::regclass and contype='c' order by conname`,
          )
        ).rows,
        foreignKeys: (
          await client.query(
            `select pg_get_constraintdef(oid) as definition from pg_constraint
             where conrelid='study_logs'::regclass and contype='f' order by definition`,
          )
        ).rows,
      });
      try {
        await client.query(`create schema ${schemaName}`);
        await client.query(`set search_path to ${schemaName},public`);
        await client.query(await installation());
        const installed = await structure();

        // 全新安装的最终结构：没有临时学习表/列，日志必须归属事项。
        expect(
          (await client.query("select to_regclass('ad_hoc_learnings') as table_name")).rows[0].table_name,
        ).toBeNull();
        expect(
          (
            await client.query(
              `select table_name,column_name from information_schema.columns
               where table_schema=$1 and column_name like '%ad_hoc%'`,
              [schemaName],
            )
          ).rows,
        ).toEqual([]);
        expect(installed.studyLogColumns.find((row) => row.column_name === "item_id")).toMatchObject({
          is_nullable: "NO",
        });
        expect(installed.constraints.map((row) => row.definition).join("\n")).not.toContain("ad_hoc");
        expect(installed.constraints.map((row) => row.conname)).not.toContain("study_logs_owner_check");
        expect(
          installed.constraints.find((row) => row.conname === "study_logs_relation_check")?.definition,
        ).toContain("legacy_unknown");

        // 全新安装随后仍会执行全部历史增量迁移；迁移后结构必须与最终 schema 一致。
        const files = (await readdir(new URL("../db/migrations/", import.meta.url)))
          .filter((name) => name.endsWith(".sql"))
          .sort();
        for (const name of files) await client.query(await migration(name));
        expect(await structure()).toEqual(installed);
        expect(
          (await client.query("select to_regclass('ad_hoc_learnings') as table_name")).rows[0].table_name,
        ).toBeNull();
      } finally {
        await client.query(`drop schema if exists ${schemaName} cascade`);
        await client.end();
      }
    });
  },
);
