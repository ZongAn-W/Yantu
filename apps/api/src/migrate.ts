import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { pool, transaction } from "./db.js";

export async function migrateDatabase() {
  const directory = new URL("../db/migrations/", import.meta.url);
  const files = (await readdir(directory)).filter(name => name.endsWith(".sql")).sort();
  await transaction(async client => {
    await client.query("select pg_advisory_xact_lock(21410408)");
    await client.query("create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())");
    for (const name of files) {
      const applied = await client.query("select 1 from schema_migrations where name=$1", [name]);
      if (applied.rowCount) continue;
      await client.query(await readFile(new URL(name, directory), "utf8"));
      await client.query("insert into schema_migrations(name) values($1)", [name]);
    }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { await migrateDatabase(); console.log("Database migrations applied."); }
  catch { console.error("Database migration failed; check the database connection and schema."); process.exitCode = 1; }
  finally { await pool.end(); }
}
