/**
 * 问题七（服务端）结构性计数测量：GET /api/planner/sync 与 PUT /api/planner/sync。
 *
 * 只在显式开启时运行（避免拖慢常规集成测试）：
 *   $env:AUTH_TEST_DATABASE_URL='本机隔离测试库'
 *   $env:SYNC_PERF_CAPTURE='1'
 *   $env:SYNC_PERF_LABEL='before'   # 产出 .dsh-verify/optfix/perf/server-before.json
 *
 * 口径：
 * - 合成数据，普通计划（1 日程块/1 日志）与历史计划（1000 日程块/1000 日志）。
 * - 每次操作统计：请求数、请求/响应字节、客户端可用 SQL 语句数（按表分类）、
 *   写入语句数、写入行数（客户端驱动看到的 rowCount 之和）、SQL 参数字节
 *   （写入 JSON 的近似字节量）、revision 增量（关系表写入会触发 revision 触发器，
 *   能反映服务端投影实际改写了多少历史行）、耗时（单次观测，仅同环境可比）。
 * - 计时 checkpoint 用同一份文档连续修改一条日志/一个时间块模拟，不依赖 sleep。
 */
import { mkdir, writeFile } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { platform, release, version as osVersion } from "node:os";
import { SignJWT } from "jose";
import pg from "pg";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

const capture = process.env.SYNC_PERF_CAPTURE === "1";
const label = process.env.SYNC_PERF_LABEL ?? "current";
const secret = "sync-perf-access-0123456789012345678";

type Statement = { text: string; values: unknown; rows: number };
type Metrics = {
  elapsedMs: number;
  requestBytes: number;
  responseBytes: number;
  sqlStatements: number;
  sqlByCategory: Record<string, number>;
  writeStatements: number;
  rowsWritten: number;
  parameterBytes: number;
  revisionDelta: number | null;
  responseShape: string;
};

const clientQuery = (pg as { Client: { prototype: { query: (...args: any[]) => any } } })
  .Client.prototype.query;
let recording = false;
let statements: Statement[] = [];

const tablePatterns: Array<[string, RegExp]> = [
  ["profiles", /\bprofiles\b/],
  ["courses", /\bcourses\b/],
  ["items", /\bitems\b/],
  ["daily_plan_items", /\bdaily_plan_items\b/],
  ["study_logs", /\bstudy_logs\b/],
  ["planner_sync_state", /\bplanner_sync_state\b/],
];

function categoryOf(text: string) {
  const normalized = text.trim().toLowerCase();
  if (["begin", "commit", "rollback"].includes(normalized) || normalized.startsWith("set transaction"))
    return "transaction";
  for (const [name, pattern] of tablePatterns) if (pattern.test(normalized)) return name;
  if (normalized.startsWith("insert into users")) return "users";
  return "other";
}

function writeStatement(text: string) {
  return /^\s*(insert|update|delete)/i.test(text);
}

function parameterBytes(values: unknown) {
  if (values === undefined || values === null) return 0;
  if (!Array.isArray(values)) return Buffer.byteLength(JSON.stringify(values));
  return values.reduce<number>((sum, value) => {
    if (typeof value === "string") return sum + Buffer.byteLength(value);
    if (value === null || value === undefined) return sum + 4;
    if (typeof value === "number" || typeof value === "boolean") return sum + 8;
    return sum + Buffer.byteLength(JSON.stringify(value));
  }, 0);
}

/**
 * 记录一次 HTTP 操作期间的 SQL 语句。计数包装只包在测量窗口内，
 * 窗口外查询不受影响；操作本身成功与否都会还原计数状态。
 */
async function measure<T>(
  run: () => Promise<T>,
  describeResult: (value: T) => {
    requestBytes: number;
    responseBytes: number;
    revisionDelta: number | null;
    responseShape: string;
  },
): Promise<{ value: T; metrics: Metrics }> {
  statements = [];
  recording = true;
  const started = performance.now();
  try {
    const value = await run();
    const elapsedMs = performance.now() - started;
    const captured = statements;
    const extra = describeResult(value);
    const metrics: Metrics = {
      elapsedMs: Math.round(elapsedMs * 100) / 100,
      requestBytes: extra.requestBytes,
      responseBytes: extra.responseBytes,
      sqlStatements: captured.length,
      sqlByCategory: captured.reduce<Record<string, number>>((counts, row) => {
        const key = categoryOf(row.text);
        counts[key] = (counts[key] ?? 0) + 1;
        return counts;
      }, {}),
      writeStatements: captured.filter(row => writeStatement(row.text)).length,
      rowsWritten: captured.filter(row => writeStatement(row.text)).reduce((sum, row) => sum + row.rows, 0),
      parameterBytes: captured
        .filter(row => writeStatement(row.text))
        .reduce((sum, row) => sum + parameterBytes(row.values), 0),
      revisionDelta: extra.revisionDelta,
      responseShape: extra.responseShape,
    };
    return { value, metrics };
  } finally {
    recording = false;
    statements = [];
  }
}

function bytesOf(value: unknown) {
  return Buffer.byteLength(JSON.stringify(value));
}

function median(values: number[]) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

function summarize(runs: Metrics[]) {
  const numbers = (pick: (row: Metrics) => number) => median(runs.map(pick));
  const categoriesHeld = Object.keys(runs[0]?.sqlByCategory ?? {});
  return {
    runs: runs.length,
    sqlStatements: numbers(row => row.sqlStatements),
    sqlByCategory: Object.fromEntries(
      categoriesHeld.map(name => [name, numbers(row => row.sqlByCategory[name] ?? 0)]),
    ),
    writeStatements: numbers(row => row.writeStatements),
    rowsWritten: numbers(row => row.rowsWritten),
    parameterBytes: numbers(row => row.parameterBytes),
    requestBytes: numbers(row => row.requestBytes),
    responseBytes: numbers(row => row.responseBytes),
    revisionDelta: numbers(row => row.revisionDelta ?? 0),
    elapsedMs: numbers(row => row.elapsedMs),
    perRun: runs,
  };
}

type Sample = { name: string; data: any; documentBytes: number };

function sample(name: "normal" | "large", owner: string): Sample {
  const stamp = "2026-10-01T08:00:00.000Z";
  const count = name === "large" ? 1000 : 1;
  const start = Date.parse("2024-01-01T00:00:00Z");
  const day = (index: number) => new Date(start + index * 86_400_000).toISOString().slice(0, 10);
  const subjectId = randomUUID();
  const taskId = randomUUID();
  const blocks = Array.from({ length: count }, (_, index) => ({
    id: randomUUID(),
    user_id: owner,
    task_id: taskId,
    date: day(index),
    start_minute: 480,
    duration_minutes: 30,
    actual_minutes: 0,
    is_fixed: false,
    status: "planned",
    created_at: stamp,
    updated_at: stamp,
  }));
  const logs = Array.from({ length: count }, (_, index) => ({
    id: randomUUID(),
    user_id: owner,
    task_id: taskId,
    block_id: blocks[index].id,
    date: day(index),
    minutes: 20,
    started_at: stamp,
    ended_at: stamp,
    source: "timer",
  }));
  const data = {
    version: 1,
    profile: {
      user_id: owner,
      planning_mode: "daily",
      goal_text: "合成压力测试计划",
      goal_type: "exam",
      goal_subtype: "考研",
      target_school: "",
      target_program: "",
      plan_start_date: day(0),
      plan_end_date: day(Math.max(count - 1, 0)),
      daily_limit_minutes: 480,
      granularity_minutes: 30,
      buffer_minutes: 30,
      subject_limit_minutes: 240,
      study_start_minute: 480,
      study_end_minute: 1320,
      foundation: "",
      weekly_minutes: { "0": 480, "1": 480, "2": 480, "3": 480, "4": 480, "5": 480, "6": 480 },
    },
    subjects: [{ id: subjectId, user_id: owner, name: "合成课程", color: "#275e91", priority: 2 }],
    tasks: [
      {
        id: taskId,
        user_id: owner,
        subject_id: subjectId,
        title: "合成事项",
        description: "",
        estimated_minutes: 60000,
        completed_minutes: 0,
        priority: 2,
        deadline: "2030-12-31",
        deadline_kind: "deadline",
        earliest_date: day(0),
        is_fixed: false,
        status: "in_progress",
        created_at: stamp,
        updated_at: stamp,
      },
    ],
    blocks,
    logs,
    fixed_events: [
      {
        id: randomUUID(),
        user_id: owner,
        title: "固定安排",
        date: day(0),
        start_minute: 720,
        duration_minutes: 60,
        kind: "course",
        repeat: "daily",
        created_at: stamp,
        updated_at: stamp,
      },
    ],
    replan_runs: [],
    phases: [],
  };
  return { name, data, documentBytes: bytesOf(data) };
}

describe.skipIf(!process.env.AUTH_TEST_DATABASE_URL || !capture)(
  "planner sync server structural counts (problem 7)",
  () => {
    let app: Awaited<ReturnType<(typeof import("../server.js"))["buildApp"]>>;
    let db: typeof import("../db.js");
    const report: {
      label: string;
      environment: Record<string, unknown>;
      samples: Record<string, unknown>;
      scenarios: Record<string, unknown>;
    } = {
      label,
      environment: {
        runner: "vitest / node（app.inject 进程内请求，本机隔离测试库）",
        platform,
        osVersion,
        nodeVersion: process.version,
        processors: 32,
        notes: "合成数据；结构性计数为主要验收依据；耗时为单次观测，仅同一环境内可比。",
      },
      samples: {},
      scenarios: {},
    };

    async function account() {
      const id = randomUUID();
      await db.query(
        "insert into users(id,email,username,password_hash) values($1,$2,$3,$4)",
        [id, `${id}@example.test`, id, "test-only"],
      );
      const token = await new SignJWT({ email: `${id}@example.test`, username: id, type: "access" })
        .setProtectedHeader({ alg: "HS256" })
        .setSubject(id)
        .setExpirationTime("1h")
        .sign(new TextEncoder().encode(secret));
      return { id, headers: { authorization: `Bearer ${token}` } };
    }

    beforeAll(async () => {
      vi.stubEnv("DATABASE_URL", process.env.AUTH_TEST_DATABASE_URL!);
      vi.stubEnv("JWT_ACCESS_SECRET", secret);
      vi.stubEnv("NODE_ENV", "test");
      db = await import("../db.js");
      const { readFile } = await import("node:fs/promises");
      await db.query(await readFile(new URL("../../db/schema.sql", import.meta.url), "utf8"));
      app = await (await import("../server.js")).buildApp();
      await app.ready();
      (pg as { Client: { prototype: { query: (...args: any[]) => any } } }).Client.prototype.query =
        function (this: unknown, ...args: any[]) {
          const active = recording;
          const text = typeof args[0] === "string" ? args[0] : String(args[0]?.text ?? "");
          const values = Array.isArray(args[1])
            ? args[1]
            : args[0] && typeof args[0] === "object"
              ? args[0].values
              : undefined;
          const pending = clientQuery.apply(this, args);
          if (!active || !pending || typeof pending.then !== "function") return pending;
          return pending.then(
            (result: { rowCount?: number | null }) => {
              statements.push({ text, values, rows: Number(result?.rowCount ?? 0) });
              return result;
            },
            (error: unknown) => {
              statements.push({ text, values, rows: 0 });
              throw error;
            },
          );
        };
    });

    afterAll(async () => {
      (pg as { Client: { prototype: { query: (...args: any[]) => any } } }).Client.prototype.query =
        clientQuery;
      await app?.close();
      await db?.pool.end();
      vi.unstubAllEnvs();
      if (capture) {
        const target = new URL(
          `../../../../.dsh-verify/optfix/perf/server-${label}.json`,
          import.meta.url,
        );
        await mkdir(new URL("../../../../.dsh-verify/optfix/perf/", import.meta.url), { recursive: true });
        await writeFile(target, JSON.stringify(report, null, 2) + "\n", "utf8");
      }
    });

    it("measures upload, idle polling, timer checkpoint and offline recovery", async () => {
      for (const size of ["normal", "large"] as const) {
        const sampleValue = sample(size, "owner");
        report.samples[size] = {
          name: sampleValue.name,
          subjects: sampleValue.data.subjects.length,
          tasks: sampleValue.data.tasks.length,
          blocks: sampleValue.data.blocks.length,
          logs: sampleValue.data.logs.length,
          documentBytes: sampleValue.documentBytes,
        };

        // 1) 首次上传（新计划/历史计划各一份）。
        {
          const runs: Metrics[] = [];
          for (let rep = 0; rep < 3; rep++) {
            const user = await account();
            const data = sample(size, user.id).data;
            const payload = { data, base: null, expectedRevision: 0 };
            const measured = await measure(
              () =>
                app.inject({
                  method: "PUT",
                  url: "/api/planner/sync",
                  headers: user.headers,
                  payload,
                }),
              response => ({
                requestBytes: bytesOf(payload),
                responseBytes: Buffer.byteLength(response.body),
                revisionDelta: Number(response.json().revision),
                responseShape: "full",
              }),
            );
            expect(measured.value.statusCode, measured.value.body).toBe(200);
            runs.push(measured.metrics);
          }
          report.scenarios[`upload-${size}`] = summarize(runs);
        }

        // 2) 空闲轮询：客户端携带已知 revision 轮询（未实现快速路径时服务端忽略参数返回完整文档）。
        {
          const user = await account();
          const data = sample(size, user.id).data;
          const saved = await app.inject({
            method: "PUT",
            url: "/api/planner/sync",
            headers: user.headers,
            payload: { data, base: null, expectedRevision: 0 },
          });
          expect(saved.statusCode, saved.body).toBe(200);
          let revision = Number(saved.json().revision);
          const runs: Metrics[] = [];
          for (let poll = 0; poll < 5; poll++) {
            const url = `/api/planner/sync?revision=${revision}`;
            const measured = await measure(
              () => app.inject({ url, headers: user.headers }),
              response => {
                const body = response.json();
                return {
                  requestBytes: 0,
                  responseBytes: Buffer.byteLength(response.body),
                  revisionDelta: 0,
                  responseShape: body.unchanged === true ? "unchanged" : "full",
                };
              },
            );
            expect(measured.value.statusCode, measured.value.body).toBe(200);
            revision = Number(measured.value.json().revision);
            runs.push(measured.metrics);
          }
          report.scenarios[`idlePoll-${size}`] = summarize(runs);
        }

        // 3) 单次计时 checkpoint：改一条日志与对应时间块后上传；之后以响应为准连续 5 次。
        {
          const user = await account();
          const data = sample(size, user.id).data;
          const saved = await app.inject({
            method: "PUT",
            url: "/api/planner/sync",
            headers: user.headers,
            payload: { data, base: null, expectedRevision: 0 },
          });
          expect(saved.statusCode, saved.body).toBe(200);
          let current = saved.json();
          const runs: Metrics[] = [];
          for (let checkpoint = 0; checkpoint < 5; checkpoint++) {
            const next = structuredClone(current.data);
            next.logs[checkpoint % next.logs.length].minutes += 1;
            next.blocks[checkpoint % next.blocks.length].actual_minutes += 1;
            const payload = {
              data: next,
              base: current.data,
              expectedRevision: current.revision,
            };
            const measured = await measure(
              () =>
                app.inject({
                  method: "PUT",
                  url: "/api/planner/sync",
                  headers: user.headers,
                  payload,
                }),
              response => {
                const body = response.json();
                return {
                  requestBytes: bytesOf(payload),
                  responseBytes: Buffer.byteLength(response.body),
                  revisionDelta: Number(body.revision) - Number(current.revision),
                  responseShape: "full",
                };
              },
            );
            expect(measured.value.statusCode, measured.value.body).toBe(200);
            current = measured.value.json();
            runs.push(measured.metrics);
          }
          report.scenarios[`checkpoint-${size}`] = summarize(runs);
        }

        // 4) 离线后恢复同步：本机累计 20 条改动后一次上传。
        {
          const user = await account();
          const data = sample(size, user.id).data;
          const saved = await app.inject({
            method: "PUT",
            url: "/api/planner/sync",
            headers: user.headers,
            payload: { data, base: null, expectedRevision: 0 },
          });
          expect(saved.statusCode, saved.body).toBe(200);
          const current = saved.json();
          const next = structuredClone(current.data);
          for (let index = 0; index < Math.min(20, next.logs.length); index++) {
            next.logs[index].minutes += 5;
            next.blocks[index].actual_minutes += 5;
          }
          const payload = { data: next, base: current.data, expectedRevision: current.revision };
          const measured = await measure(
            () =>
              app.inject({
                method: "PUT",
                url: "/api/planner/sync",
                headers: user.headers,
                payload,
              }),
            response => {
              const body = response.json();
              return {
                requestBytes: bytesOf(payload),
                responseBytes: Buffer.byteLength(response.body),
                revisionDelta: Number(body.revision) - Number(current.revision),
                responseShape: "full",
              };
            },
          );
          expect(measured.value.statusCode, measured.value.body).toBe(200);
          report.scenarios[`resumeOffline-${size}`] = summarize([measured.metrics]);
        }
      }
      // 测量本身不设性能断言：计数写入报告，由 after 运行对比后判定。
      expect(Object.keys(report.scenarios)).toHaveLength(8);
    }, 240_000);
  },
);
