import { readFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import pg from "pg";
import { describe, expect, it } from "vitest";

describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL)("additive planning metadata migration", () => {
  it("upgrades populated legacy tables without changing learning records and is repeatable", async () => {
    const client = new pg.Client({ connectionString: process.env.AUTH_TEST_DATABASE_URL });
    await client.connect();
    try {
      const schemaName = `planning_upgrade_${randomUUID().replaceAll("-", "")}`;
      await client.query(`create schema ${schemaName}`);
      await client.query(`set search_path to ${schemaName},public`);
      const installation = await readFile(new URL("../db/schema.sql", import.meta.url), "utf8");
      const legacy = installation
        .replaceAll(/^  planning_metadata jsonb,\r?\n/gm, "")
        .replaceAll(/^  activity_instance_id text,\r?\n/gm, "")
        .replace(/create index if not exists daily_plan_activity_instance[\s\S]*?;/, "");
      await client.query(legacy);
      const owner = randomUUID(), course = randomUUID(), item = randomUUID(), block = randomUUID();
      await client.query("insert into users(id,email,password_hash) values($1,'migration@example.test','test-only')", [owner]);
      await client.query("insert into profiles(user_id,goal_text,weekly_minutes) values($1,'A finite reading goal','{\"0\":0,\"1\":90,\"2\":90,\"3\":0,\"4\":90,\"5\":90,\"6\":120}')", [owner]);
      await client.query("insert into courses(id,user_id,name) values($1,$2,'Reading')", [course, owner]);
      await client.query("insert into items(id,user_id,course_id,title,estimated_minutes,deadline,confirmed) values($1,$2,$3,'Read and summarize',120,'2026-11-12',true)", [item, owner, course]);
      await client.query("insert into daily_plan_items(id,user_id,item_id,date,planned_minutes,actual_minutes) values($1,$2,$3,'2026-10-17',60,45)", [block, owner, item]);
      await client.query("insert into study_logs(user_id,item_id,daily_plan_item_id,date,minutes,feedback) values($1,$2,$3,'2026-10-17',45,'Keep this evidence')", [owner, item, block]);
      const tables = ["users", "profiles", "courses", "items", "daily_plan_items", "study_logs"];
      const records = async () => {
        const result = [];
        for (const table of tables) result.push({ table, rows: (await client.query(
          `select to_jsonb(t)-'planning_metadata'-'activity_instance_id' as record from ${table} t order by 1::text`,
        )).rows });
        return result;
      };
      const before = await records();
      const migration = await readFile(new URL("../db/migrations/202610190001_ai_planning_metadata.sql", import.meta.url), "utf8");
      await client.query(migration);
      await client.query(migration);
      expect(await records()).toEqual(before);
      const columns = await client.query("select table_name,column_name,is_nullable from information_schema.columns where table_schema=$1 and column_name in ('planning_metadata','activity_instance_id') order by table_name", [schemaName]);
      expect(columns.rows).toEqual([
        { table_name: "daily_plan_items", column_name: "activity_instance_id", is_nullable: "YES" },
        { table_name: "items", column_name: "planning_metadata", is_nullable: "YES" },
        { table_name: "profiles", column_name: "planning_metadata", is_nullable: "YES" },
      ]);
      expect((await client.query("select planning_metadata from profiles")).rows[0].planning_metadata).toBeNull();
      expect((await client.query("select planning_metadata from items")).rows[0].planning_metadata).toBeNull();
      expect((await client.query("select activity_instance_id from daily_plan_items")).rows[0].activity_instance_id).toBeNull();
    } finally {
      await client.end();
    }
  });
});
