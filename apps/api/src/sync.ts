import { createHash } from "node:crypto";
import type pg from "pg";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { transaction } from "./db.js";
import { requireUser } from "./auth.js";
import { isReliableWeek, normalizeWeek, snapshot } from "./planner.js";
import {
  PlannerDocumentSchema,
  type PlannerDocument,
} from "./sync-contracts.js";

type Row = Record<string, any>;
type StateRow = {
  revision: string;
  document: PlannerDocument | null;
  projection: PlannerDocument | null;
};
const clone = <T>(value: T): T => structuredClone(value);
/**
 * 缺失字段、null 和空字符串都表示“没有值”。
 *
 * 客户端与历史文档对这些空值的写法不同（客户端的模型会写出空字符串，
 * 服务端快照可能直接省略），比较时统一忽略，避免每次同步都误报冲突。
 */
const emptyValue = (value: unknown) =>
  value === null || value === undefined || value === "";

const stable = (value: unknown): string =>
  JSON.stringify(value, (_key, child) => {
    if (child && typeof child === "object" && !Array.isArray(child))
      return Object.fromEntries(
        Object.entries(child)
          .filter(([key]) => !["updated_at", "created_at"].includes(key))
          .filter(([, value]) => !emptyValue(value))
          .sort(([a], [b]) => a.localeCompare(b)),
      );
    return child;
  });
const same = (a: unknown, b: unknown) => stable(a) === stable(b);

class ProjectionConflict extends Error {}
export class PlannerRevisionConflict extends Error {}

export function hasPlanningMetadata(document: PlannerDocument | null): boolean {
  return Boolean(document && (document.planning || document.tasks.some(task => task.planning)
    || document.blocks.some(block => block.activity_instance_id)));
}

/** Missing fields from a capable writer are not an implicit request to clear metadata. */
export function preservePlanningMetadata(data: PlannerDocument, current: PlannerDocument | null): PlannerDocument {
  if (!current) return data;
  const result = clone(data);
  if (result.planning === undefined && current.planning !== undefined) result.planning = clone(current.planning);
  const priorTasks = new Map(current.tasks.map(task => [task.id, task]));
  for (const task of result.tasks) {
    const previous = priorTasks.get(task.id);
    if (task.planning === undefined && previous?.planning !== undefined) task.planning = clone(previous.planning);
  }
  const priorBlocks = new Map(current.blocks.map(block => [block.id, block]));
  for (const block of result.blocks) {
    const previous = priorBlocks.get(block.id);
    if (block.activity_instance_id === undefined && previous?.activity_instance_id !== undefined)
      block.activity_instance_id = previous.activity_instance_id;
  }
  return result;
}

function mergeProjectedDay(
  blocks: PlannerDocument["blocks"],
  before: PlannerDocument["blocks"][number],
  after: PlannerDocument["blocks"][number],
  document: PlannerDocument,
) {
  const durationChanged = before.duration_minutes !== after.duration_minutes;
  if (durationChanged && (
    blocks.length !== 1 ||
    document.profile.planning_mode === "timed" ||
    blocks.some((block) => block.is_fixed || block.status === "completed") ||
    document.tasks.some((task) => task.id === before.task_id && task.is_fixed)
  )) {
    throw new ProjectionConflict("云端汇总时长与已有时间块冲突，原计划已保留；请先核对云端时长再重试同步");
  }
  const changes: Row = {};
  for (const key of ["duration_minutes", "status", "completion_status", "advice_text", "advice_topics"] as const) {
    if (!same(before[key], after[key])) changes[key] = after[key];
  }
  const result = blocks.map((block) => ({ ...block, ...changes, updated_at: after.updated_at }));
  if (before.actual_minutes !== after.actual_minutes) {
    // The relational row is a daily total; allocate it without changing slot identities.
    let remaining = after.actual_minutes;
    const ordered = [...result].sort((a, b) => a.start_minute - b.start_minute);
    for (const [index, block] of ordered.entries()) {
      block.actual_minutes = index === ordered.length - 1
        ? remaining
        : Math.min(block.duration_minutes, remaining);
      remaining -= block.actual_minutes;
    }
  }
  return result;
}

// Legacy exports use string ids; relational tables keep UUIDs. Map without changing exports.
function dbId(owner: string, table: string, id: string): string {
  if (
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)
  )
    return id;
  const hex = createHash("sha256")
    .update(`${owner}:${table}:${id}`)
    .digest("hex")
    .slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20)}`;
}

function mappedNative(
  native: PlannerDocument,
  document: PlannerDocument,
): PlannerDocument {
  const owner = document.profile.user_id;
  const ids = (table: string, rows: { id: string }[]) =>
    new Map(rows.map((row) => [dbId(owner, table, row.id), row.id]));
  const subjects = ids("courses", document.subjects),
    tasks = ids("items", document.tasks),
    logs = ids("study_logs", document.logs);
  const blocks = new Map<string, string>();
  for (const block of document.blocks) {
    const key = `${block.task_id}:${block.date}`;
    if (!blocks.has(key)) blocks.set(key, block.id);
  }
  const nativeBlocks = new Map(
    native.blocks.map((row) => [
      row.id,
      blocks.get(`${tasks.get(row.task_id) ?? row.task_id}:${row.date}`) ??
        row.id,
    ]),
  );
  return {
    ...native,
    ...(native.planning ? { planning: { ...native.planning, route: native.planning.route.map(stage => ({ ...stage,
      item_ids: stage.item_ids.map(id => tasks.get(id) ?? id) })) } } : {}),
    subjects: native.subjects.map((row) => ({
      ...row,
      id: subjects.get(row.id) ?? row.id,
    })),
    tasks: native.tasks.map((row) => ({
      ...row,
      id: tasks.get(row.id) ?? row.id,
      subject_id: subjects.get(row.subject_id) ?? row.subject_id,
      ...(row.planning ? { planning: { ...row.planning,
        ...(row.planning.dependencies ? { dependencies: row.planning.dependencies.map(dependency => ({ ...dependency, task_id: tasks.get(dependency.task_id) ?? dependency.task_id })) } : {}) } } : {}),
    })),
    blocks: native.blocks.map((row) => ({
      ...row,
      id: nativeBlocks.get(row.id)!,
      task_id: tasks.get(row.task_id) ?? row.task_id,
    })),
    logs: native.logs.map((row) => ({
      ...row,
      id: logs.get(row.id) ?? row.id,
      task_id: tasks.get(row.task_id) ?? row.task_id,
      block_id: row.block_id
        ? (nativeBlocks.get(row.block_id) ?? row.block_id)
        : null,
    })),
  };
}

function applyRemoteRows(base: Row[], local: Row[], remote: Row[]): Row[] {
  const before = new Map(base.map((row) => [row.id, row]));
  const after = new Map(remote.map((row) => [row.id, row]));
  const result = new Map(local.map((row) => [row.id, row]));
  for (const [id, old] of before) {
    const next = after.get(id);
    if (!next) result.delete(id);
    else if (!same(old, next)) {
      const current = { ...result.get(id) };
      for (const key of Object.keys({ ...old, ...next }))
        if (!same(old[key], next[key])) current[key] = next[key];
      result.set(id, current);
    }
  }
  for (const [id, row] of after) if (!before.has(id)) result.set(id, row);
  return [...result.values()];
}

function rebase(
  document: PlannerDocument,
  previous: PlannerDocument,
  next: PlannerDocument,
): PlannerDocument {
  const base = mappedNative(previous, document),
    remote = mappedNative(next, document);
  const result = clone(document);
  for (const key of Object.keys(remote.profile))
    if (!same(base.profile[key], remote.profile[key]))
      result.profile[key] = remote.profile[key];
  if (!same(base.planning, remote.planning)) result.planning = clone(remote.planning);
  for (const key of ["subjects", "tasks"] as const)
    result[key] = applyRemoteRows(base[key], result[key], remote[key]) as any;
  const blockGroup = (row: Row) => `${row.task_id}:${row.date}`;
  for (const key of new Set(
    [...base.blocks, ...remote.blocks].map(blockGroup),
  )) {
    const old = base.blocks.filter((row) => blockGroup(row) === key),
      fresh = remote.blocks.filter((row) => blockGroup(row) === key);
    if (same(old, fresh)) continue;
    const existing = result.blocks.filter((row) => blockGroup(row) === key);
    if (!fresh.length && existing.some((block) => block.is_fixed || block.status === "completed" || document.tasks.some((task) => task.id === block.task_id && task.is_fixed))) {
      throw new ProjectionConflict("云端日计划已移除，但本机仍有固定或已完成时间块；原计划已保留，请先核对后重试同步");
    }
    if (old.length && fresh.length && existing.length) {
      const merged = new Map(mergeProjectedDay(existing, old[0], fresh[0], document).map((block) => [block.id, block]));
      result.blocks = result.blocks.map((block) => merged.get(block.id) ?? block);
    } else {
      result.blocks = [
        ...result.blocks.filter((row) => blockGroup(row) !== key),
        ...fresh,
      ];
    }
  }
  // Native corrections delete/replace the day's rows. Patch surviving IDs so a
  // lossy block_id projection cannot detach unchanged logs from their split slots.
  result.logs = applyRemoteRows(base.logs, result.logs, remote.logs) as PlannerDocument["logs"];
  const tasks = new Set(result.tasks.map((row) => row.id));
  result.blocks = result.blocks.filter((row) => tasks.has(row.task_id));
  const blocks = new Set(result.blocks.map((row) => row.id));
  result.logs = result.logs
    .filter((row) => tasks.has(row.task_id))
    .map((row) => ({
      ...row,
      block_id: row.block_id && blocks.has(row.block_id) ? row.block_id : null,
    }));
  return result;
}

/**
 * 文档缺失的 Profile 字段用投影里的权威值补回。
 *
 * 字段缺失表示“未知/旧格式”，`null` 或空字符串才是用户主动清空；
 * 因此这里只补缺失的键，绝不覆盖客户端明确写下的值。
 */
function withProjectedProfile(
  document: PlannerDocument,
  projection: PlannerDocument | null,
): PlannerDocument {
  if (!projection) return document;
  const result = clone(document);
  for (const key of Object.keys(projection.profile)) {
    if (!Object.prototype.hasOwnProperty.call(result.profile, key)) {
      (result.profile as Record<string, unknown>)[key] = (
        projection.profile as Record<string, unknown>
      )[key];
    }
  }
  return normalizeEmptyDates(result);
}

/**
 * 空目标日期统一用空字符串表达。
 *
 * 客户端模型和本机导出都用空值，服务端文档保持同一个字面量；
 * 读写比较前都要归一化，否则每次同步都会因为 null 与 '' 不一致而误报冲突。
 */
function normalizeEmptyDates(document: PlannerDocument): PlannerDocument {
  const result = clone(document);
  const target = (result.profile as Record<string, unknown>).target_date;
  if (target === null || target === undefined) {
    (result.profile as Record<string, unknown>).target_date = "";
  }
  return result;
}

async function lockedState(client: pg.PoolClient, owner: string) {
  // SERIALIZABLE captures state and all relationship rows from one database snapshot.
  await client.query(
    "insert into planner_sync_state(user_id) values($1) on conflict do nothing",
    [owner],
  );
  return (
    await client.query<StateRow>(
      "select revision,document,projection from planner_sync_state where user_id=$1 for update",
      [owner],
    )
  ).rows[0];
}

async function currentState(
  client: pg.PoolClient,
  owner: string,
  row: StateRow,
) {
  const raw = (await snapshot(owner, client)) as PlannerDocument | null;
  const rebased =
    row.document && raw && row.projection
      ? rebase(row.document, row.projection, raw)
      : (row.document ?? raw);
  // 关系表是权威来源：文档里没有的字段（例如旧客户端的 weekly_minutes）必须补回。
  const data = rebased ? withProjectedProfile(rebased, raw) : rebased;
  if (data)
    await client.query(
      "update planner_sync_state set document=$2,projection=$3 where user_id=$1",
      [owner, JSON.stringify(data), JSON.stringify(raw)],
    );
  return { data, revision: Number(row.revision) };
}

export async function readPlannerState(client: pg.PoolClient, owner: string) {
  return currentState(client, owner, await lockedState(client, owner));
}

export async function commitPlannerState(client: pg.PoolClient, owner: string, data: PlannerDocument, expectedRevision: number) {
  const row = await lockedState(client, owner);
  if (Number(row.revision) !== expectedRevision) throw new PlannerRevisionConflict("当前计划已更新，请重新读取当前计划后再确认");
  const current = await currentState(client, owner, row);
  const validated = PlannerDocumentSchema.parse(preservePlanningMetadata(data, current.data));
  await writeProjection(client, owner, validated);
  const projection = await snapshot(owner, client);
  const document = withProjectedProfile(validated, projection as PlannerDocument | null);
  const result = await client.query<{ revision: string }>(
    "update planner_sync_state set document=$2,projection=$3,revision=revision+1,updated_at=now() where user_id=$1 returning revision",
    [owner, JSON.stringify(document), JSON.stringify(projection)],
  );
  return Number(result.rows[0].revision);
}

async function assertOwnership(
  client: pg.PoolClient,
  owner: string,
  table: string,
  ids: string[],
) {
  const found = await client.query(
    `select 1 from ${table} where id=any($1::uuid[]) and user_id<>$2 limit 1`,
    [ids, owner],
  );
  if (found.rowCount) throw new Error("导入包含其他账号的标识");
}

async function upsert(client: pg.PoolClient, sql: string, values: unknown[]) {
  const result = await client.query(sql, values);
  if (result.rowCount !== 1) throw new Error("导入包含其他账号的标识");
}

async function writeProjection(
  client: pg.PoolClient,
  owner: string,
  data: PlannerDocument,
) {
  const id = (table: string, value: string) => dbId(owner, table, value);
  const groups = new Map<string, Row>();
  const blockToDay = new Map<string, string>();
  const existingDays = await client.query<{
    id: string;
    item_id: string;
    date: string;
  }>("select id,item_id,date::text from daily_plan_items where user_id=$1", [
    owner,
  ]);
  const existingByKey = new Map(
    existingDays.rows.map((row) => [`${row.item_id}:${row.date}`, row.id]),
  );
  for (const block of data.blocks) {
    const key = `${block.task_id}:${block.date}`;
    let day = groups.get(key);
    if (!day) {
      day = {
        ...block,
        id:
          existingByKey.get(`${id("items", block.task_id)}:${block.date}`) ??
          id("daily_plan_items", block.id),
        task_id: id("items", block.task_id),
        duration_minutes: 0,
        actual_minutes: 0,
      };
      groups.set(key, day);
    }
    day.duration_minutes += block.duration_minutes;
    day.actual_minutes += block.actual_minutes;
    if (day.activity_instance_id && block.activity_instance_id && day.activity_instance_id !== block.activity_instance_id)
      throw new ProjectionConflict("同一事项同一天含不同的活动实例，请先核对安排后重试同步");
    if (block.activity_instance_id) day.activity_instance_id = block.activity_instance_id;
    blockToDay.set(block.id, day.id);
  }
  const days = [...groups.values()];
  for (const [table, rows] of [
    ["courses", data.subjects],
    ["items", data.tasks],
    ["study_logs", data.logs],
  ] as const)
    await assertOwnership(
      client,
      owner,
      table,
      rows.map((row) => id(table, row.id)),
    );
  await assertOwnership(
    client,
    owner,
    "daily_plan_items",
    days.map((row) => row.id),
  );
  const profile = data.profile;
  // 一周配置：文档里的可靠配置 > 数据库里已有的可靠配置 > 旧数据每日上限。
  const storedWeekly = (await client.query<{ weekly_minutes: unknown }>(
    "select weekly_minutes from profiles where user_id=$1",
    [owner],
  )).rows[0]?.weekly_minutes;
  const weekly = isReliableWeek(profile.weekly_minutes)
    ? normalizeWeek(profile.weekly_minutes)
    : isReliableWeek(storedWeekly)
      ? normalizeWeek(storedWeekly)
      : normalizeWeek(Object.fromEntries(
        [0, 1, 2, 3, 4, 5, 6].map((day) => [day, profile.daily_limit_minutes]),
      ));
  // 新字段存在即为准（null/"" 表示用户已清空）；只有完全缺失时才回退旧考试日期。
  const targetDate = Object.prototype.hasOwnProperty.call(profile, "target_date")
    ? profile.target_date ?? null
    : profile.exam_date ?? null;
  await client.query(
    `insert into profiles(user_id,goal_text,goal_type,goal_subtype,target_date,target_date_confirmed,plan_start_date,plan_end_date,target_school,target_program,current_progress,weekly_minutes,exam_type,exam_date)
    values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
    on conflict(user_id) do update set goal_text=excluded.goal_text,goal_type=excluded.goal_type,goal_subtype=excluded.goal_subtype,
      target_date=excluded.target_date,target_date_confirmed=excluded.target_date_confirmed,plan_start_date=excluded.plan_start_date,
      plan_end_date=excluded.plan_end_date,target_school=excluded.target_school,target_program=excluded.target_program,
      current_progress=excluded.current_progress,weekly_minutes=excluded.weekly_minutes,exam_type=excluded.exam_type,
      exam_date=excluded.exam_date,updated_at=now()`,
    [
      owner,
      profile.goal_text ?? "",
      profile.goal_type ?? "other",
      profile.goal_subtype ?? "",
      targetDate,
      profile.target_date_confirmed ?? false,
      profile.plan_start_date ?? null,
      profile.plan_end_date ?? null,
      profile.target_school,
      profile.target_program,
      profile.foundation,
      JSON.stringify(weekly),
      profile.goal_subtype || "其他",
      targetDate,
    ],
  );
  const nativePlanning = data.planning ? { ...data.planning, route: data.planning.route.map(stage => ({ ...stage,
    item_ids: stage.item_ids.map(value => id("items", value)) })) } : null;
  await client.query("update profiles set planning_metadata=$2 where user_id=$1", [owner, nativePlanning ? JSON.stringify(nativePlanning) : null]);
  for (const subject of data.subjects)
    await upsert(
      client,
      `insert into courses(id,user_id,name,priority) values($1,$2,$3,$4) on conflict(id) do update set name=excluded.name,priority=excluded.priority where courses.user_id=excluded.user_id`,
      [id("courses", subject.id), owner, subject.name, subject.priority],
    );
  const priorItems = await client.query<{
    id: string;
    description: string;
    completion_criteria: string;
  }>("select id,description,completion_criteria from items where user_id=$1", [
    owner,
  ]);
  const priorById = new Map(priorItems.rows.map((row) => [row.id, row]));
  for (const task of data.tasks) {
    const old = priorById.get(id("items", task.id));
    let description = task.description ?? "",
      criteria = "";
    if (
      old &&
      description ===
        [
          old.description,
          old.completion_criteria ? `完成标准：${old.completion_criteria}` : "",
        ]
          .filter(Boolean)
          .join("\n")
    ) {
      description = old.description;
      criteria = old.completion_criteria;
    }
    await upsert(
      client,
      `insert into items(id,user_id,course_id,title,description,completion_criteria,estimated_minutes,earliest_date,deadline,deadline_kind,priority,status,confirmed,created_at,updated_at)
      values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,true,$13,$14) on conflict(id) do update set course_id=excluded.course_id,title=excluded.title,description=excluded.description,completion_criteria=excluded.completion_criteria,estimated_minutes=excluded.estimated_minutes,earliest_date=excluded.earliest_date,deadline=excluded.deadline,deadline_kind=excluded.deadline_kind,priority=excluded.priority,status=excluded.status,updated_at=excluded.updated_at where items.user_id=excluded.user_id`,
      [
        id("items", task.id),
        owner,
        id("courses", task.subject_id),
        task.title,
        description,
        criteria,
        task.estimated_minutes,
        task.earliest_date ?? null,
        task.deadline,
        task.deadline_kind ?? "deadline",
        task.priority,
        task.status,
        task.created_at,
        task.updated_at,
      ],
    );
    const nativeItemPlanning = task.planning ? { ...task.planning,
      ...(task.planning.dependencies ? { dependencies: task.planning.dependencies.map(dependency => ({ ...dependency, task_id: id("items", dependency.task_id) })) } : {}) } : null;
    await client.query("update items set planning_metadata=$3 where id=$1 and user_id=$2", [id("items", task.id), owner, nativeItemPlanning ? JSON.stringify(nativeItemPlanning) : null]);
  }
  // Remove vanished children before parents. Foreign keys continue protecting old API rows.
  await client.query(
    "delete from study_logs where user_id=$1 and not(id=any($2::uuid[]))",
    [owner, data.logs.map((row) => id("study_logs", row.id))],
  );
  await client.query(
    "delete from daily_plan_items where user_id=$1 and not(id=any($2::uuid[]))",
    [owner, days.map((row) => row.id)],
  );
  for (const day of days)
    await client.query(
      `insert into daily_plan_items(id,user_id,item_id,date,planned_minutes,actual_minutes,advice_text,advice_topics,completion_status,activity_instance_id) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
    on conflict(user_id,item_id,date) do update set planned_minutes=excluded.planned_minutes,actual_minutes=excluded.actual_minutes,advice_text=excluded.advice_text,advice_topics=excluded.advice_topics,completion_status=excluded.completion_status,activity_instance_id=excluded.activity_instance_id,updated_at=now()`,
      [
        day.id,
        owner,
        day.task_id,
        day.date,
        day.duration_minutes,
        day.actual_minutes,
        day.advice_text ?? "",
        JSON.stringify(day.advice_topics ?? []),
        day.completion_status ??
          (day.status === "completed" ? "completed" : "not_started"),
        day.activity_instance_id ?? null,
      ],
    );
  for (const log of data.logs)
    await upsert(
      client,
      `insert into study_logs(id,user_id,item_id,daily_plan_item_id,date,minutes,created_at) values($1,$2,$3,$4,$5,$6,$7)
    on conflict(id) do update set item_id=excluded.item_id,daily_plan_item_id=excluded.daily_plan_item_id,date=excluded.date,minutes=excluded.minutes where study_logs.user_id=excluded.user_id`,
      [
        id("study_logs", log.id),
        owner,
        id("items", log.task_id),
        log.block_id ? (blockToDay.get(log.block_id) ?? null) : null,
        log.date,
        log.minutes,
        log.started_at,
      ],
    );
  await client.query(
    "delete from items where user_id=$1 and not(id=any($2::uuid[]))",
    [owner, data.tasks.map((row) => id("items", row.id))],
  );
  await client.query(
    "delete from courses where user_id=$1 and not(id=any($2::uuid[]))",
    [owner, data.subjects.map((row) => id("courses", row.id))],
  );
}

const revision = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const PutSchema = z.object({
  data: PlannerDocumentSchema,
  base: PlannerDocumentSchema.nullable(),
  expectedRevision: revision,
  writer_planning_version: z.literal(1).optional(),
});

async function withSnapshot<T>(
  operation: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await transaction(async (client) => {
        await client.query("set transaction isolation level serializable");
        return operation(client);
      });
    } catch (error) {
      if (
        attempt < 2 &&
        ["40001", "40P01"].includes((error as { code: string }).code)
      )
        continue;
      throw error;
    }
  }
}

export async function syncRoutes(app: FastifyInstance) {
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof ProjectionConflict) return reply.code(409).send({ error: error.message });
    throw error;
  });
  app.get("/api/planner/sync", async (request, reply) => {
    const user = await requireUser(request, reply);
    if (!user) return;
    reply.header("Cache-Control", "no-store");
    return withSnapshot(async (client) =>
      currentState(client, user.id, await lockedState(client, user.id)),
    );
  });
  app.put(
    "/api/planner/sync",
    { bodyLimit: 32 * 1024 * 1024 },
    async (request, reply) => {
      const user = await requireUser(request, reply);
      if (!user) return;
      const parsed = PutSchema.safeParse(request.body);
      if (!parsed.success)
        return reply
          .code(400)
          .send({ error: parsed.error.issues[0]?.message ?? "计划格式不正确" });
      const { data, base, expectedRevision, writer_planning_version } = parsed.data;
      if (
        data.profile.user_id !== user.id ||
        (base && base.profile.user_id !== user.id)
      )
        return reply.code(403).send({ error: "计划不属于当前账号" });
      const result = await withSnapshot(async (client) => {
        const state = await lockedState(client, user.id);
        const current = await currentState(client, user.id, state);
        if (writer_planning_version !== 1 && [data, base, current.data].some(hasPlanningMetadata))
          return { upgradeRequired: true as const, error: "当前计划包含新版学习策略，请升级客户端后再同步", code: "planning_writer_upgrade_required" };
        const comparableBase = base ? normalizeEmptyDates(base) : null;
        if (current.revision !== expectedRevision || !same(comparableBase, current.data))
          return { conflict: true as const, ...current };
        const preserved = PlannerDocumentSchema.parse(preservePlanningMetadata(data, current.data));
        await writeProjection(client, user.id, preserved);
        const projection = await snapshot(user.id, client);
        const document = withProjectedProfile(preserved, projection as PlannerDocument | null);
        const updated = await client.query<{ revision: string }>(
          "update planner_sync_state set document=$2,projection=$3,revision=revision+1,updated_at=now() where user_id=$1 returning revision",
          [user.id, JSON.stringify(document), JSON.stringify(projection)],
        );
        return { data: document, revision: Number(updated.rows[0].revision) };
      });
      if ("conflict" in result) reply.code(409);
      if ("upgradeRequired" in result) reply.code(426);
      return result;
    },
  );
}
