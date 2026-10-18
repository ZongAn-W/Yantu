import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { describe, expect, it } from "vitest";

/**
 * 真实隔离 PostgreSQL 上的迁移测试：
 * 1) 在“迁移前”的结构上保留已有学习记录，应用新迁移后数据不变；
 * 2) 迁移可重复执行（幂等），历史迁移不受影响；
 * 3) 新表/新列/默认值/约束/触发器真实可用（临时学习日志、归属校验、revision）。
 */
describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)(
  "learning relations and capacity migration",
  () => {
    it("upgrades a populated legacy database without touching learning records and is repeatable", async () => {
      const client = new pg.Client({
        connectionString: process.env.AUTH_TEST_DATABASE_URL,
      });
      await client.connect();
      const schemaName = `learning_upgrade_${randomUUID().replaceAll("-", "")}`;
      try {
        await client.query(`create schema ${schemaName}`);
        await client.query(`set search_path to ${schemaName},public`);
        const installation = await readFile(
          new URL("../db/schema.sql", import.meta.url),
          "utf8",
        );
        await client.query(installation);
        // 把新装库回退成“迁移前”的结构：删除本迁移新增的表/列/约束，保留旧数据形态。
        await client.query(`
          drop table if exists ad_hoc_learnings cascade;
          alter table study_logs drop constraint if exists study_logs_owner_check;
          alter table study_logs drop constraint if exists study_logs_relation_check;
          alter table study_logs drop constraint if exists study_logs_quota_minutes_check;
          alter table study_logs drop column if exists ad_hoc_id;
          alter table study_logs drop column if exists relation;
          alter table study_logs drop column if exists session_id;
          alter table study_logs drop column if exists quota_minutes;
          alter table study_logs alter column item_id set not null;
          drop index if exists logs_user_ad_hoc;
          drop index if exists ad_hoc_learnings_user;
          alter table profiles drop constraint if exists profiles_capacity_basis_check;
          alter table profiles drop constraint if exists profiles_capacity_minutes_check;
          alter table profiles drop constraint if exists profiles_capacity_overrides_shape_check;
          alter table profiles drop column if exists capacity_basis;
          alter table profiles drop column if exists weekly_baseline_minutes;
          alter table profiles drop column if exists weekly_range_min_minutes;
          alter table profiles drop column if exists weekly_range_max_minutes;
          alter table profiles drop column if exists week_capacity_overrides;
          alter table profiles drop column if exists date_capacity_overrides;
        `);
        const owner = randomUUID(),
          course = randomUUID(),
          item = randomUUID(),
          day = randomUUID();
        await client.query(
          "insert into users(id,email,password_hash) values($1,$2,'test-only')",
          [owner, `migration-${owner}@example.test`],
        );
        await client.query(
          `insert into profiles(user_id,goal_text,weekly_minutes,constraints_text)
           values($1,'有限周期阅读目标','{"0":0,"1":90,"2":90,"3":0,"4":90,"5":90,"6":120}','保留旧学习限制')`,
          [owner],
        );
        await client.query(
          "insert into courses(id,user_id,name) values($1,$2,'阅读')",
          [course, owner],
        );
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
          `insert into study_logs(user_id,item_id,daily_plan_item_id,date,minutes,feedback)
           values($1,$2,$3,'2026-10-17',45,'保留真实学习记录')`,
          [owner, item, day],
        );
        const legacyLog = (
          await client.query(
            `select id,user_id,item_id,daily_plan_item_id,date::text as date,minutes,feedback
             from study_logs order by id`,
          )
        ).rows;
        expect(legacyLog).toHaveLength(1);

        // 历史迁移先提供 planner_sync_state / planner_touch_revision，再应用本次新迁移。
        const history = await readFile(
          new URL("../db/migrations/202610160003_planner_sync.sql", import.meta.url),
          "utf8",
        );
        const migration = await readFile(
          new URL(
            "../db/migrations/202610200001_learning_relations_capacity.sql",
            import.meta.url,
          ),
          "utf8",
        );
        await client.query(history);
        await client.query(migration);
        const afterFirst = (
          await client.query(
            `select id,user_id,item_id,daily_plan_item_id,date::text as date,minutes,feedback,relation,session_id,quota_minutes
             from study_logs order by id`,
          )
        ).rows;
        const profileAfterFirst = (
          await client.query(
            `select weekly_minutes,constraints_text,capacity_basis,weekly_baseline_minutes,
               weekly_range_min_minutes,weekly_range_max_minutes,week_capacity_overrides,date_capacity_overrides
             from profiles`,
          )
        ).rows;
        // 重复执行：幂等，且不改变已有学习记录。
        await client.query(migration);
        expect(
          (
            await client.query(
              `select id,user_id,item_id,daily_plan_item_id,date::text as date,minutes,feedback,relation,session_id,quota_minutes
               from study_logs order by id`,
            )
          ).rows,
        ).toEqual(afterFirst);
        expect(
          (
            await client.query(
              `select weekly_minutes,constraints_text,capacity_basis,weekly_baseline_minutes,
                 weekly_range_min_minutes,weekly_range_max_minutes,week_capacity_overrides,date_capacity_overrides
               from profiles`,
            )
          ).rows,
        ).toEqual(profileAfterFirst);

        // 旧日志：原有字段不变，执行关系默认 legacy_unknown（不擅自推断成原定学习）。
        expect(afterFirst[0]).toMatchObject({
          ...legacyLog[0],
          relation: "legacy_unknown",
          session_id: null,
          quota_minutes: null,
        });
        // Profile 容量投影默认缺失（null），旧 weekly_minutes 与学习限制原样保留。
        expect(profileAfterFirst[0]).toMatchObject({
          capacity_basis: null,
          weekly_baseline_minutes: null,
          weekly_range_min_minutes: null,
          weekly_range_max_minutes: null,
          week_capacity_overrides: null,
          date_capacity_overrides: null,
          constraints_text: "保留旧学习限制",
        });

        // 新列/新表真实存在（含可空性与默认值）。
        const columns = (
          await client.query<{
            table_name: string;
            column_name: string;
            is_nullable: string;
            column_default: string | null;
          }>(
            `select table_name,column_name,is_nullable,column_default
             from information_schema.columns
             where table_schema=$1 and (
               (table_name='study_logs' and column_name in ('item_id','relation','session_id','ad_hoc_id','quota_minutes'))
               or (table_name='profiles' and column_name in ('capacity_basis','weekly_baseline_minutes','weekly_range_min_minutes','weekly_range_max_minutes','week_capacity_overrides','date_capacity_overrides'))
               or (table_name='ad_hoc_learnings')
             ) order by table_name,column_name`,
            [schemaName],
          )
        ).rows;
        const nullability = new Map(
          columns.map((row) => [`${row.table_name}.${row.column_name}`, row.is_nullable]),
        );
        expect(nullability.get("study_logs.item_id")).toBe("YES");
        expect(nullability.get("study_logs.relation")).toBe("NO");
        expect(nullability.get("study_logs.session_id")).toBe("YES");
        expect(nullability.get("study_logs.ad_hoc_id")).toBe("YES");
        expect(nullability.get("study_logs.quota_minutes")).toBe("YES");
        expect(nullability.get("profiles.capacity_basis")).toBe("YES");
        expect(
          columns.find((row) => row.table_name === "study_logs" && row.column_name === "relation")
            ?.column_default,
        ).toContain("legacy_unknown");
        const adHocColumns = columns
          .filter((row) => row.table_name === "ad_hoc_learnings")
          .map((row) => row.column_name);
        expect(adHocColumns).toEqual(
          expect.arrayContaining([
            "id", "user_id", "title", "subject_id", "archived",
            "converted_task_id", "created_at", "updated_at",
          ]),
        );

        // 新表触发器：临时学习实体的写入必须让 revision 增长（客户端据此失效缓存）。
        const adHoc = randomUUID();
        await client.query(
          "insert into ad_hoc_learnings(id,user_id,title) values($1,$2,'临时了解摄影构图')",
          [adHoc, owner],
        );
        const revision = async () =>
          Number(
            (
              await client.query<{ revision: string }>(
                "select revision from planner_sync_state where user_id=$1",
                [owner],
              )
            ).rows[0]?.revision ?? 0,
          );
        expect(await revision()).toBe(1);
        // 临时学习没有正式事项：item_id 为空、ad_hoc_id 必填，记录关系/会话/额度。
        await client.query(
          `insert into study_logs(user_id,ad_hoc_id,date,minutes,relation,session_id,quota_minutes)
           values($1,$2,'2026-10-18',20,'ad_hoc','session-cross-midnight',20)`,
          [owner, adHoc],
        );
        expect(await revision()).toBe(2);
        const adHocLog = (
          await client.query(
            "select item_id,ad_hoc_id,relation,session_id,quota_minutes from study_logs where ad_hoc_id=$1",
            [adHoc],
          )
        ).rows[0];
        expect(adHocLog).toEqual({
          item_id: null,
          ad_hoc_id: adHoc,
          relation: "ad_hoc",
          session_id: "session-cross-midnight",
          quota_minutes: 20,
        });
        // 每条日志必须能归属正式事项或临时学习之一；非法关系被真实约束拒绝。
        await expect(
          client.query(
            "insert into study_logs(user_id,date,minutes) values($1,'2026-10-18',5)",
            [owner],
          ),
        ).rejects.toThrow(/study_logs_owner_check/);
        await expect(
          client.query(
            "insert into study_logs(user_id,item_id,date,minutes,relation) values($1,$2,'2026-10-18',5,'unknown_relation')",
            [owner, item],
          ),
        ).rejects.toThrow(/study_logs_relation_check/);
        // 外键 restrict：删除临时学习实体不能无声带走真实学习分钟（必须先显式删除日志）。
        await expect(
          client.query("delete from ad_hoc_learnings where id=$1", [adHoc]),
        ).rejects.toThrow(/study_logs_ad_hoc_id_fkey|foreign key/);
        await client.query("delete from study_logs where ad_hoc_id=$1", [adHoc]);
        await client.query("delete from ad_hoc_learnings where id=$1", [adHoc]);
        // 旧日志（item_id 非空）不因临时学习删除而消失。
        expect(
          (
            await client.query("select count(*)::int as n from study_logs where item_id=$1", [
              item,
            ])
          ).rows[0].n,
        ).toBe(1);
      } finally {
        await client.query(`drop schema if exists ${schemaName} cascade`);
        await client.end();
      }
    });
  },
);
