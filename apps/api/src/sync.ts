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
 * 缺失字段、null、空字符串和空数组都表示“没有值”。
 *
 * 客户端与历史文档对这些空值的写法不同：客户端的模型会把空字符串/null
 * 写成显式值，也会为 `@Default([])` 的列表字段（例如 `ad_hoc_learnings`）
 * 写出空数组，而服务端快照在列表为空时直接省略该键。比较时统一忽略，
 * 避免每次同步都因为“同一份内容的两种空值写法”误报 base 变化而永久 409。
 */
const emptyValue = (value: unknown) =>
  value === null ||
  value === undefined ||
  value === "" ||
  (Array.isArray(value) && value.length === 0);

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

/** “缺失”与“显式清空”的判定必须基于键是否存在；旧写入方从不发送新字段键。 */
const hasKey = (value: object, key: string) => Object.prototype.hasOwnProperty.call(value, key);

/** Profile 上的灵活容量字段（文档 blob 权威，关系列是同值投影）。 */
export const LEARNING_PROFILE_KEYS = [
  "capacity_basis",
  "weekly_baseline_minutes",
  "weekly_range_min_minutes",
  "weekly_range_max_minutes",
  "week_capacity_overrides",
  "date_capacity_overrides",
] as const;

/** 每条学习日志上与执行关系/会话/临时学习相关的字段。 */
export const LEARNING_LOG_KEYS = [
  "relation",
  "session_id",
  "ad_hoc_id",
  "quota_minutes",
] as const;

/**
 * 写入方是否具备新能力（能往返 relation/临时学习/容量覆盖）。
 *
 * 新客户端总会发送 `ad_hoc_learnings` 键（即使为空数组）与 `capacity_basis`；
 * 显式的 `writer_learning_version` 优先，键存在检测作为兼容兜底。
 */
export function representsLearningCapabilities(document: PlannerDocument): boolean {
  if (hasKey(document, "ad_hoc_learnings")) return true;
  if (LEARNING_PROFILE_KEYS.some((key) => hasKey(document.profile, key))) return true;
  return document.logs.some(
    (log) =>
      hasKey(log, "relation") ||
      log.session_id !== undefined ||
      log.ad_hoc_id !== undefined ||
      log.quota_minutes !== undefined,
  );
}

/** 旧写入方无法表达、若放行会在投影删除时丢失真实学习事实的记录。 */
export function hasUnrepresentableLearningRecords(
  document: PlannerDocument | null,
): boolean {
  return Boolean(document?.logs.some((log) => log.task_id === null));
}

/**
 * 缺失字段保留云端新数据（旧写入方/旧文档兼容），显式数组或显式值才是权威。
 *
 * 与 `preservePlanningMetadata` 同一原则：旧写入方不理解新字段时，字段缺失
 * 不能解释为“清空”，否则会无声删除临时学习、执行关系或容量覆盖。
 * 只有显式声明具备新能力的写入方（`writer_learning_version: 1`）才把容量字段
 * 缺失解释为“未设置/清空” —— 因为它的模型会把 null 省略出 JSON。
 */
export function preserveLearningData(
  data: PlannerDocument,
  current: PlannerDocument | null,
  options: { preserveCapacity?: boolean } = {},
): PlannerDocument {
  if (!current) return data;
  const result = clone(data);
  // 临时学习实体集合：键整体缺失时保留云端集合；显式数组（含 []）才代表写入方意图。
  if (!hasKey(data, "ad_hoc_learnings") && current.ad_hoc_learnings !== undefined)
    result.ad_hoc_learnings = clone(current.ad_hoc_learnings);
  // Profile 容量字段：旧写入方缺失保留已有值；显式 null/空对象会由投影写入清空。
  if (options.preserveCapacity !== false) {
    const targetProfile = result.profile as Record<string, unknown>;
    const currentProfile = current.profile as Record<string, unknown>;
    for (const key of LEARNING_PROFILE_KEYS)
      if (!hasKey(data.profile, key) && hasKey(current.profile, key))
        targetProfile[key] = clone(currentProfile[key]);
  }
  // 每条日志的执行关系是计时事实：旧写入方缺字段时按 id 保留，不能被重置成 legacy。
  const currentLogs = new Map(current.logs.map((log) => [log.id, log]));
  for (const log of result.logs) {
    const previous = currentLogs.get(log.id);
    if (!previous) continue;
    const target = log as Record<string, unknown>;
    const source = previous as Record<string, unknown>;
    for (const key of LEARNING_LOG_KEYS)
      if (!hasKey(target, key) && hasKey(source, key) && source[key] !== undefined)
        target[key] = clone(source[key]);
  }
  // 保留下来的临时学习实体若引用的课程/事项已被本写入方删除，只清除失效引用，
  // 不伪造新的归属（关系表外键也会做同样处理）。
  const subjectIds = new Set(result.subjects.map((row) => row.id));
  const taskIds = new Set(result.tasks.map((row) => row.id));
  for (const adHoc of result.ad_hoc_learnings ?? []) {
    if (adHoc.subject_id && !subjectIds.has(adHoc.subject_id)) adHoc.subject_id = null;
    if (adHoc.converted_task_id && !taskIds.has(adHoc.converted_task_id)) adHoc.converted_task_id = null;
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
    logs = ids("study_logs", document.logs),
    adHoc = ids("ad_hoc_learnings", document.ad_hoc_learnings ?? []);
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
    ...(native.ad_hoc_learnings !== undefined || document.ad_hoc_learnings !== undefined
      ? {
          ad_hoc_learnings: (native.ad_hoc_learnings ?? []).map((row) => ({
            ...row,
            id: adHoc.get(row.id) ?? row.id,
            subject_id: row.subject_id
              ? (subjects.get(row.subject_id) ?? row.subject_id)
              : null,
            converted_task_id: row.converted_task_id
              ? (tasks.get(row.converted_task_id) ?? row.converted_task_id)
              : null,
          })),
        }
      : {}),
    blocks: native.blocks.map((row) => ({
      ...row,
      id: nativeBlocks.get(row.id)!,
      task_id: tasks.get(row.task_id) ?? row.task_id,
    })),
    logs: native.logs.map((row) => ({
      ...row,
      id: logs.get(row.id) ?? row.id,
      task_id: row.task_id === null ? null : tasks.get(row.task_id) ?? row.task_id,
      block_id: row.block_id
        ? (nativeBlocks.get(row.block_id) ?? row.block_id)
        : null,
      ad_hoc_id: row.ad_hoc_id
        ? (adHoc.get(row.ad_hoc_id) ?? row.ad_hoc_id)
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
  // 临时学习实体同样是关系投影的权威子集：关系表删除/修改优先，本机未同步的新行保留。
  const baseAdHoc = base.ad_hoc_learnings ?? [],
    remoteAdHoc = remote.ad_hoc_learnings ?? [],
    localAdHoc = result.ad_hoc_learnings ?? [];
  if (baseAdHoc.length || remoteAdHoc.length || localAdHoc.length)
    result.ad_hoc_learnings = applyRemoteRows(
      baseAdHoc,
      localAdHoc,
      remoteAdHoc,
    ) as PlannerDocument["ad_hoc_learnings"];
  const tasks = new Set(result.tasks.map((row) => row.id));
  const adHoc = new Set((result.ad_hoc_learnings ?? []).map((row) => row.id));
  result.blocks = result.blocks.filter((row) => tasks.has(row.task_id));
  const blocks = new Set(result.blocks.map((row) => row.id));
  result.logs = result.logs
    .filter((row) =>
      row.task_id === null
        ? Boolean(row.ad_hoc_id && adHoc.has(row.ad_hoc_id))
        : tasks.has(row.task_id),
    )
    .map((row) => ({
      ...row,
      // 临时学习日志没有日程归属；失效的 block 引用不能把旧额度继续算到新日期。
      block_id: row.task_id === null
        ? null
        : row.block_id && blocks.has(row.block_id)
          ? row.block_id
          : null,
    }));
  // 关系投影是权威来源：文档里缺失的执行关系/临时学习引用补回（remote 已映射回客户端 id 空间）。
  // 否则新客户端读不到计时归属，旧写入方回写时又会把“缺失”当默认值。
  const projectedLogs = new Map(remote.logs.map((log) => [log.id, log]));
  for (const log of result.logs) {
    const source = projectedLogs.get(log.id) as Record<string, unknown> | undefined;
    if (!source) continue;
    const target = log as Record<string, unknown>;
    for (const key of LEARNING_LOG_KEYS) {
      // null 与缺失同义（都没有值），不把 null 回填成显式键，避免每次读取改写文档。
      const value = source[key];
      if (!hasKey(target, key) && hasKey(source, key) && value !== undefined && value !== null)
        target[key] = clone(value);
    }
  }
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
  return normalizeProfilePlaceholders(result);
}

/**
 * Profile 里“没有值”的统一字面量。
 *
 * 空目标日期和空学习限制在文档中都统一用空字符串表达：客户端模型写出空字符串，
 * 服务端快照可能省略或用 null；读写比较前都要归一化，否则每次同步都会因为
 * null 与 '' 的表示差异而误报冲突。
 */
function normalizeProfilePlaceholders(document: PlannerDocument): PlannerDocument {
  const result = clone(document);
  const profile = result.profile as Record<string, unknown>;
  const target = profile.target_date;
  if (target === null || target === undefined) profile.target_date = "";
  const constraints = profile.constraints;
  if (constraints === null || constraints === undefined) profile.constraints = "";
  return result;
}

/**
 * `profile.constraints`（同步文档）与 `profiles.constraints_text`（关系表）的映射。
 *
 * 字段缺失表示旧客户端或旧文档不理解该字段，此时保留关系表已有值；
 * `null` 或空字符串才是用户明确清空。非法类型同样保留旧值，避免写入无效资料。
 */
function projectedConstraints(
  profile: PlannerDocument["profile"],
  stored: string | null | undefined,
): string {
  if (!Object.prototype.hasOwnProperty.call(profile, "constraints"))
    return stored ?? "";
  const value = (profile as Record<string, unknown>).constraints;
  if (typeof value === "string") return value;
  if (value === null || value === undefined) return "";
  return stored ?? "";
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
  options: { persist?: boolean } = {},
) {
  const raw = (await snapshot(owner, client)) as PlannerDocument | null;
  const rebased =
    row.document && raw && row.projection
      ? rebase(row.document, row.projection, raw)
      : (row.document ?? raw);
  // 关系表是权威来源：文档里没有的字段（例如旧客户端的 weekly_minutes）必须补回。
  // 执行关系/临时学习引用在 rebase 内按投影权威补回，避免丢失计时事实。
  const data = rebased ? withProjectedProfile(rebased, raw) : rebased;
  // 只读调用方（PUT/规划提交）随后会整体写入新状态，无需先重写一次缓存文档。
  if (data && options.persist !== false)
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
  const current = await currentState(client, owner, row, { persist: false });
  // 规划提交路径同样遵守“缺失=保留”：生成的文档不会清掉临时学习/容量覆盖。
  const validated = PlannerDocumentSchema.parse(
    preserveLearningData(preservePlanningMetadata(data, current.data), current.data),
  );
  await writeProjection(client, owner, validated);
  const projection = await snapshot(owner, client);
  const document = withProjectedProfile(validated, projection as PlannerDocument | null);
  const result = await client.query<{ revision: string }>(
    "update planner_sync_state set document=$2,projection=$3,revision=revision+1,updated_at=now() where user_id=$1 returning revision",
    [owner, JSON.stringify(document), JSON.stringify(projection)],
  );
  return Number(result.rows[0].revision);
}

/** 目标 id 若已被其他账号占用，整批导入必须拒绝（保持旧错误语义）。 */
async function assertOwnership(
  client: pg.PoolClient,
  owner: string,
  rows: Array<{ table: string; ids: string[] }>,
) {
  const clauses = rows
    .map(
      (row, index) =>
        `select id from ${row.table} where id=any($${index + 1}::uuid[]) and user_id<>$${rows.length + 1}`,
    )
    .join(" union all ");
  const found = await client.query(
    `select 1 from (${clauses}) foreign_rows limit 1`,
    [...rows.map((row) => row.ids), owner],
  );
  if (found.rowCount) throw new ProjectionConflict("导入包含其他账号的标识");
}

const WRITE_CHUNK = 500;

/** 用一条 unnest 批量语句写入若干行；每块都必须恰好影响 chunk.length 行。 */
async function insertBatch(
  client: pg.PoolClient,
  table: string,
  columns: string[],
  types: string[],
  conflict: string,
  rows: unknown[][],
) {
  for (let offset = 0; offset < rows.length; offset += WRITE_CHUNK) {
    const chunk = rows.slice(offset, offset + WRITE_CHUNK);
    const values = columns.map((_, column) => chunk.map((row) => row[column]));
    const result = await client.query(
      `insert into ${table}(${columns.join(",")}) select * from unnest(${types
        .map((type, index) => `$${index + 1}::${type}[]`)
        .join(",")}) ${conflict}`,
      values,
    );
    if (result.rowCount !== chunk.length)
      throw new ProjectionConflict("导入包含其他账号的标识");
  }
}

/** 只删除确实消失的行；空列表不发语句。 */
async function deleteBatch(
  client: pg.PoolClient,
  table: string,
  owner: string,
  ids: string[],
) {
  if (!ids.length) return;
  await client.query(
    `delete from ${table} where user_id=$1 and id=any($2::uuid[])`,
    [owner, ids],
  );
}

/** jsonb 的键顺序不稳定，比较投影元数据前先做稳定序列化。 */
function canonicalJson(value: unknown): string {
  const sort = (input: unknown): unknown => {
    if (Array.isArray(input)) return input.map(sort);
    if (input && typeof input === "object")
      return Object.fromEntries(
        Object.entries(input as Record<string, unknown>)
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([key, child]) => [key, sort(child)]),
      );
    return input;
  };
  return JSON.stringify(sort(value)) ?? "null";
}

/** 旧写入方缺失新字段时保留数据库已有值；写入方显式给出的 null 才表示清空。 */
function projectedOptional(
  row: Record<string, unknown>,
  existing: Row | undefined,
  key: string,
): unknown {
  if (hasKey(row, key)) return row[key] ?? null;
  return existing ? (existing[key] ?? null) : null;
}

/**
 * relation 描述已经发生的计时事实：
 * - 旧写入方缺失该字段 → 保留数据库已有关系；
 * - legacy_unknown 只是旧数据兜底，不能覆盖数据库里已知的 scheduled/extra/ad_hoc；
 * - 显式给出的新关系（用户修正归属）为准。
 */
function projectedRelation(row: Record<string, unknown>, existing: Row | undefined): string {
  const stored = typeof existing?.relation === "string" ? existing.relation : null;
  if (!hasKey(row, "relation") || row.relation === undefined)
    return stored ?? "legacy_unknown";
  const value = row.relation;
  if (value === "legacy_unknown" && stored && stored !== "legacy_unknown") return stored;
  return typeof value === "string" ? value : stored ?? "legacy_unknown";
}

async function writeProjection(
  client: pg.PoolClient,
  owner: string,
  data: PlannerDocument,
  options: { clearMissingCapacity?: boolean } = {},
) {
  const id = (table: string, value: string) => dbId(owner, table, value);
  // 先批量读取当前投影行：写入阶段只处理新增或确实变化的行，删除仍走显式 DELETE。
  const existingCourses = (
    await client.query<Row>(
      "select id,name,priority from courses where user_id=$1",
      [owner],
    )
  ).rows;
  const existingItems = (
    await client.query<Row>(
      `select id,course_id,title,description,completion_criteria,estimated_minutes,
        earliest_date::text,deadline::text,deadline_kind,priority,status,planning_metadata
       from items where user_id=$1`,
      [owner],
    )
  ).rows;
  const existingDays = (
    await client.query<Row>(
      `select id,item_id,date::text,planned_minutes,actual_minutes,advice_text,advice_topics,
        completion_status,activity_instance_id
       from daily_plan_items where user_id=$1`,
      [owner],
    )
  ).rows;
  const existingLogs = (
    await client.query<Row>(
      `select id,item_id,ad_hoc_id,daily_plan_item_id,date::text,minutes,relation,
        session_id,quota_minutes from study_logs where user_id=$1`,
      [owner],
    )
  ).rows;
  const existingAdHoc = (
    await client.query<Row>(
      `select id,title,subject_id,archived,converted_task_id,created_at,updated_at
       from ad_hoc_learnings where user_id=$1`,
      [owner],
    )
  ).rows;
  const byId = (rows: Row[]) => new Map(rows.map((row) => [String(row.id), row]));
  const coursesById = byId(existingCourses);
  const itemsById = byId(existingItems);
  const daysById = byId(existingDays);
  const logsById = byId(existingLogs);
  const adHocById = byId(existingAdHoc);
  const daysByKey = new Map(
    existingDays.map((row) => [`${row.item_id}:${row.date}`, row.id]),
  );
  const groups = new Map<string, Row>();
  const blockToDay = new Map<string, string>();
  for (const block of data.blocks) {
    const key = `${block.task_id}:${block.date}`;
    let day = groups.get(key);
    if (!day) {
      const itemId = id("items", block.task_id);
      const dayKey = `${itemId}:${block.date}`;
      const existingId = daysByKey.get(dayKey);
      const blockId = id("daily_plan_items", block.id);
      day = {
        ...block,
        // 移动日程（同一个 block id 换日期）会算出旧日期行的 id；当它已被其他
        // (item,date) 行占用时改用 (item,date) 派生的确定性备用 id，旧行随后被删除，
        // 既不会主键冲突，也保证重复同步/移动回原日期时 id 选择稳定。
        id:
          existingId ??
          (daysById.has(blockId) ? id("daily_plan_items", dayKey) : blockId),
        task_id: itemId,
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
  const courseTargets = data.subjects.map((subject) => ({
    id: id("courses", subject.id),
    name: subject.name,
    priority: subject.priority,
  }));
  const itemTargets = data.tasks.map((task) => {
    const itemId = id("items", task.id);
    const previous = itemsById.get(itemId);
    // 旧数据把“完成标准”并进 description；文档等价时保留原拆分，不能每次同步都改写。
    let description = task.description ?? "",
      criteria = "";
    if (
      previous &&
      description ===
        [
          previous.description,
          previous.completion_criteria ? `完成标准：${previous.completion_criteria}` : "",
        ]
          .filter(Boolean)
          .join("\n")
    ) {
      description = previous.description;
      criteria = previous.completion_criteria;
    }
    return {
      id: itemId,
      course_id: id("courses", task.subject_id),
      title: task.title,
      description,
      criteria,
      estimated_minutes: task.estimated_minutes,
      earliest_date: task.earliest_date ?? null,
      deadline: task.deadline,
      deadline_kind: task.deadline_kind ?? "deadline",
      priority: task.priority,
      status: task.status,
      created_at: task.created_at,
      updated_at: task.updated_at,
      planning: task.planning
        ? {
            ...task.planning,
            ...(task.planning.dependencies
              ? {
                  dependencies: task.planning.dependencies.map((dependency) => ({
                    ...dependency,
                    task_id: id("items", dependency.task_id),
                  })),
                }
              : {}),
          }
        : null,
    };
  });
  const adHocPresent = hasKey(data, "ad_hoc_learnings");
  const adHocTargets = (data.ad_hoc_learnings ?? []).map((row) => ({
    id: id("ad_hoc_learnings", row.id),
    title: row.title,
    subject_id: row.subject_id ? id("courses", row.subject_id) : null,
    archived: row.archived ?? false,
    converted_task_id: row.converted_task_id ? id("items", row.converted_task_id) : null,
    created_at: row.created_at,
    updated_at: row.updated_at,
  }));
  // 每条日志都可归属正式事项或临时学习；缺失新字段时保留数据库已有值（显式 null 才清空）。
  const logTargets = data.logs.map((log) => {
    const logId = id("study_logs", log.id);
    const previous = logsById.get(logId);
    const row = log as Record<string, unknown>;
    const adHocValue = projectedOptional(row, previous, "ad_hoc_id");
    return {
      id: logId,
      item_id: log.task_id === null ? null : id("items", log.task_id),
      ad_hoc_id:
        typeof adHocValue === "string"
          ? id("ad_hoc_learnings", adHocValue)
          : null,
      daily_plan_item_id: log.block_id
        ? (blockToDay.get(log.block_id) ?? null)
        : null,
      date: log.date,
      minutes: log.minutes,
      relation: projectedRelation(row, previous),
      session_id: projectedOptional(row, previous, "session_id"),
      quota_minutes: projectedOptional(row, previous, "quota_minutes"),
      created_at: log.started_at,
    };
  });
  await assertOwnership(client, owner, [
    { table: "courses", ids: courseTargets.map((row) => row.id) },
    { table: "items", ids: itemTargets.map((row) => row.id) },
    { table: "study_logs", ids: logTargets.map((row) => row.id) },
    { table: "daily_plan_items", ids: days.map((row) => row.id) },
    { table: "ad_hoc_learnings", ids: adHocTargets.map((row) => row.id) },
  ]);
  const profile = data.profile;
  // 一周配置：文档里的可靠配置 > 数据库里已有的可靠配置 > 旧数据每日上限。
  // 学习限制：字段缺失表示旧客户端/旧文档，保留关系表已有的值。
  const storedProfile = (await client.query<{
    weekly_minutes: unknown;
    constraints_text: string | null;
    capacity_basis: string | null;
    weekly_baseline_minutes: number | null;
    weekly_range_min_minutes: number | null;
    weekly_range_max_minutes: number | null;
    week_capacity_overrides: unknown;
    date_capacity_overrides: unknown;
  }>(
    `select weekly_minutes,constraints_text,capacity_basis,weekly_baseline_minutes,
      weekly_range_min_minutes,weekly_range_max_minutes,week_capacity_overrides,
      date_capacity_overrides from profiles where user_id=$1`,
    [owner],
  )).rows[0];
  const storedWeekly = storedProfile?.weekly_minutes;
  const weekly = isReliableWeek(profile.weekly_minutes)
    ? normalizeWeek(profile.weekly_minutes)
    : isReliableWeek(storedWeekly)
      ? normalizeWeek(storedWeekly)
      : normalizeWeek(Object.fromEntries(
        [0, 1, 2, 3, 4, 5, 6].map((day) => [day, profile.daily_limit_minutes]),
      ));
  const constraints = projectedConstraints(
    profile,
    storedProfile?.constraints_text,
  );
  // 新字段存在即为准（null/"" 表示用户已清空）；只有完全缺失时才回退旧考试日期。
  const targetDate = Object.prototype.hasOwnProperty.call(profile, "target_date")
    ? profile.target_date ?? null
    : profile.exam_date ?? null;
  // 容量投影：键缺失=保留关系表已有值（旧写入方）；显式 null/空对象=清空覆盖。
  // 只有声明新能力的写入方才把容量字段缺失解释为“未设置”（其模型会省略 null）。
  const clearMissing = options.clearMissingCapacity === true;
  const profileRow = profile as Record<string, unknown>;
  const capacityBasis = hasKey(profile, "capacity_basis")
    ? profileRow.capacity_basis ?? null
    : clearMissing
      ? null
      : storedProfile?.capacity_basis ?? null;
  const capacityMinutes = (key: (typeof LEARNING_PROFILE_KEYS)[number]) => {
    if (hasKey(profile, key)) return profileRow[key] ?? null;
    if (clearMissing) return null;
    return (storedProfile as Record<string, unknown> | undefined)?.[key] ?? null;
  };
  const capacityOverrides = (key: "week_capacity_overrides" | "date_capacity_overrides") => {
    if (hasKey(profile, key)) {
      const value = profileRow[key];
      return value === null || value === undefined ? null : JSON.stringify(value);
    }
    if (clearMissing) return null;
    const stored = storedProfile?.[key];
    return stored === null || stored === undefined ? null : JSON.stringify(stored);
  };
  await client.query(
    `insert into profiles(user_id,goal_text,goal_type,goal_subtype,target_date,target_date_confirmed,plan_start_date,plan_end_date,target_school,target_program,current_progress,weekly_minutes,constraints_text,exam_type,exam_date,capacity_basis,weekly_baseline_minutes,weekly_range_min_minutes,weekly_range_max_minutes,week_capacity_overrides,date_capacity_overrides)
    values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)
    on conflict(user_id) do update set goal_text=excluded.goal_text,goal_type=excluded.goal_type,goal_subtype=excluded.goal_subtype,
      target_date=excluded.target_date,target_date_confirmed=excluded.target_date_confirmed,plan_start_date=excluded.plan_start_date,
      plan_end_date=excluded.plan_end_date,target_school=excluded.target_school,target_program=excluded.target_program,
      current_progress=excluded.current_progress,weekly_minutes=excluded.weekly_minutes,constraints_text=excluded.constraints_text,
      exam_type=excluded.exam_type,exam_date=excluded.exam_date,capacity_basis=excluded.capacity_basis,
      weekly_baseline_minutes=excluded.weekly_baseline_minutes,weekly_range_min_minutes=excluded.weekly_range_min_minutes,
      weekly_range_max_minutes=excluded.weekly_range_max_minutes,week_capacity_overrides=excluded.week_capacity_overrides,
      date_capacity_overrides=excluded.date_capacity_overrides,updated_at=now()`,
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
      constraints,
      profile.goal_subtype || "其他",
      targetDate,
      capacityBasis,
      capacityMinutes("weekly_baseline_minutes"),
      capacityMinutes("weekly_range_min_minutes"),
      capacityMinutes("weekly_range_max_minutes"),
      capacityOverrides("week_capacity_overrides"),
      capacityOverrides("date_capacity_overrides"),
    ],
  );
  const nativePlanning = data.planning ? { ...data.planning, route: data.planning.route.map(stage => ({ ...stage,
    item_ids: stage.item_ids.map(value => id("items", value)) })) } : null;
  await client.query("update profiles set planning_metadata=$2 where user_id=$1", [owner, nativePlanning ? JSON.stringify(nativePlanning) : null]);
  // 差异写入：只有新增或旧 upsert 确实会改写的行才落库；每行写入仍触发既有 revision 触发器。
  const changedCourses = courseTargets.filter((target) => {
    const previous = coursesById.get(target.id);
    return (
      !previous ||
      previous.name !== target.name ||
      previous.priority !== target.priority
    );
  });
  await insertBatch(
    client,
    "courses",
    ["id", "user_id", "name", "priority"],
    ["uuid", "uuid", "text", "int"],
    "on conflict(id) do update set name=excluded.name,priority=excluded.priority where courses.user_id=excluded.user_id",
    changedCourses.map((row) => [row.id, owner, row.name, row.priority]),
  );
  const changedItems = itemTargets.filter((target) => {
    const previous = itemsById.get(target.id);
    if (!previous) return true;
    return (
      previous.course_id !== target.course_id ||
      previous.title !== target.title ||
      previous.description !== target.description ||
      previous.completion_criteria !== target.criteria ||
      previous.estimated_minutes !== target.estimated_minutes ||
      (previous.earliest_date ?? null) !== target.earliest_date ||
      previous.deadline !== target.deadline ||
      (previous.deadline_kind ?? "deadline") !== target.deadline_kind ||
      previous.priority !== target.priority ||
      previous.status !== target.status ||
      canonicalJson(previous.planning_metadata) !== canonicalJson(target.planning)
    );
  });
  await insertBatch(
    client,
    "items",
    [
      "id", "user_id", "course_id", "title", "description", "completion_criteria",
      "estimated_minutes", "earliest_date", "deadline", "deadline_kind", "priority",
      "status", "confirmed", "created_at", "updated_at", "planning_metadata",
    ],
    [
      "uuid", "uuid", "uuid", "text", "text", "text", "int", "date", "date", "text",
      "int", "text", "boolean", "timestamptz", "timestamptz", "jsonb",
    ],
    `on conflict(id) do update set course_id=excluded.course_id,title=excluded.title,
      description=excluded.description,completion_criteria=excluded.completion_criteria,
      estimated_minutes=excluded.estimated_minutes,earliest_date=excluded.earliest_date,
      deadline=excluded.deadline,deadline_kind=excluded.deadline_kind,priority=excluded.priority,
      status=excluded.status,updated_at=excluded.updated_at,
      planning_metadata=excluded.planning_metadata where items.user_id=excluded.user_id`,
    changedItems.map((row) => [
      row.id,
      owner,
      row.course_id,
      row.title,
      row.description,
      row.criteria,
      row.estimated_minutes,
      row.earliest_date,
      row.deadline,
      row.deadline_kind,
      row.priority,
      row.status,
      true,
      row.created_at,
      row.updated_at,
      row.planning ? JSON.stringify(row.planning) : null,
    ]),
  );
  // 临时学习实体：只有文档显式携带集合时才增删改，缺失时保留关系表已有行。
  const changedAdHoc = adHocTargets.filter((target) => {
    const previous = adHocById.get(target.id);
    if (!previous) return true;
    return (
      previous.title !== target.title ||
      (previous.subject_id ?? null) !== target.subject_id ||
      previous.archived !== target.archived ||
      (previous.converted_task_id ?? null) !== target.converted_task_id
    );
  });
  await insertBatch(
    client,
    "ad_hoc_learnings",
    [
      "id", "user_id", "title", "subject_id", "archived", "converted_task_id",
      "created_at", "updated_at",
    ],
    ["uuid", "uuid", "text", "uuid", "boolean", "uuid", "timestamptz", "timestamptz"],
    `on conflict(id) do update set title=excluded.title,subject_id=excluded.subject_id,
      archived=excluded.archived,converted_task_id=excluded.converted_task_id,
      updated_at=excluded.updated_at where ad_hoc_learnings.user_id=excluded.user_id`,
    changedAdHoc.map((row) => [
      row.id,
      owner,
      row.title,
      row.subject_id,
      row.archived,
      row.converted_task_id,
      row.created_at,
      row.updated_at,
    ]),
  );
  // Remove vanished children before parents. Foreign keys continue protecting old API rows.
  const logTargetIds = new Set(logTargets.map((row) => row.id));
  await deleteBatch(
    client,
    "study_logs",
    owner,
    existingLogs
      .map((row) => String(row.id))
      .filter((rowId) => !logTargetIds.has(rowId)),
  );
  // 旧写入方缺失集合键时绝不删除临时学习实体；显式集合为准。
  if (adHocPresent) {
    const adHocTargetIds = new Set(adHocTargets.map((row) => row.id));
    await deleteBatch(
      client,
      "ad_hoc_learnings",
      owner,
      existingAdHoc
        .map((row) => String(row.id))
        .filter((rowId) => !adHocTargetIds.has(rowId)),
    );
  }
  const dayTargetIds = new Set(days.map((row) => row.id));
  await deleteBatch(
    client,
    "daily_plan_items",
    owner,
    existingDays
      .map((row) => String(row.id))
      .filter((rowId) => !dayTargetIds.has(rowId)),
  );
  const changedDays = days.filter((day) => {
    const previous = daysById.get(String(day.id));
    if (!previous) return true;
    const completion =
      day.completion_status ??
      (day.status === "completed" ? "completed" : "not_started");
    return (
      previous.item_id !== day.task_id ||
      previous.date !== day.date ||
      previous.planned_minutes !== day.duration_minutes ||
      previous.actual_minutes !== day.actual_minutes ||
      previous.advice_text !== (day.advice_text ?? "") ||
      canonicalJson(previous.advice_topics) !== canonicalJson(day.advice_topics ?? []) ||
      previous.completion_status !== completion ||
      (previous.activity_instance_id ?? null) !== (day.activity_instance_id ?? null)
    );
  });
  await insertBatch(
    client,
    "daily_plan_items",
    [
      "id", "user_id", "item_id", "date", "planned_minutes", "actual_minutes",
      "advice_text", "advice_topics", "completion_status", "activity_instance_id",
    ],
    ["uuid", "uuid", "uuid", "date", "int", "int", "text", "jsonb", "text", "text"],
    `on conflict(user_id,item_id,date) do update set planned_minutes=excluded.planned_minutes,
      actual_minutes=excluded.actual_minutes,advice_text=excluded.advice_text,
      advice_topics=excluded.advice_topics,completion_status=excluded.completion_status,
      activity_instance_id=excluded.activity_instance_id,updated_at=now()`,
    changedDays.map((day) => [
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
    ]),
  );
  const changedLogs = logTargets.filter((target) => {
    const previous = logsById.get(target.id);
    return (
      !previous ||
      (previous.item_id ?? null) !== target.item_id ||
      (previous.ad_hoc_id ?? null) !== target.ad_hoc_id ||
      (previous.daily_plan_item_id ?? null) !== target.daily_plan_item_id ||
      previous.date !== target.date ||
      previous.minutes !== target.minutes ||
      // 执行关系/会话/额度是计时事实：只有确实变化才重写，避免每条日志都触发 revision。
      (previous.relation ?? "legacy_unknown") !== target.relation ||
      (previous.session_id ?? null) !== target.session_id ||
      (previous.quota_minutes ?? null) !== target.quota_minutes
    );
  });
  await insertBatch(
    client,
    "study_logs",
    [
      "id", "user_id", "item_id", "ad_hoc_id", "daily_plan_item_id", "date",
      "minutes", "relation", "session_id", "quota_minutes", "created_at",
    ],
    [
      "uuid", "uuid", "uuid", "uuid", "uuid", "date", "int", "text", "text",
      "int", "timestamptz",
    ],
    `on conflict(id) do update set item_id=excluded.item_id,ad_hoc_id=excluded.ad_hoc_id,
      daily_plan_item_id=excluded.daily_plan_item_id,date=excluded.date,minutes=excluded.minutes,
      relation=excluded.relation,session_id=excluded.session_id,quota_minutes=excluded.quota_minutes
      where study_logs.user_id=excluded.user_id`,
    changedLogs.map((row) => [
      row.id,
      owner,
      row.item_id,
      row.ad_hoc_id,
      row.daily_plan_item_id,
      row.date,
      row.minutes,
      row.relation,
      row.session_id,
      row.quota_minutes,
      row.created_at,
    ]),
  );
  const itemTargetIds = new Set(itemTargets.map((row) => row.id));
  await deleteBatch(
    client,
    "items",
    owner,
    existingItems
      .map((row) => String(row.id))
      .filter((rowId) => !itemTargetIds.has(rowId)),
  );
  const courseTargetIds = new Set(courseTargets.map((row) => row.id));
  await deleteBatch(
    client,
    "courses",
    owner,
    existingCourses
      .map((row) => String(row.id))
      .filter((rowId) => !courseTargetIds.has(rowId)),
  );
}

const revision = z.number().int().min(0).max(Number.MAX_SAFE_INTEGER);
const PutSchema = z.object({
  data: PlannerDocumentSchema,
  base: PlannerDocumentSchema.nullable(),
  expectedRevision: revision,
  writer_planning_version: z.literal(1).optional(),
  /**
   * 新数据能力声明：能往返临时学习/执行关系/容量覆盖的写入方固定发送 1。
   * 缺失时按文档内容检测兜底；旧写入方不发送该字段。
   */
  writer_learning_version: z.literal(1).optional(),
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
    // 可选 ?revision=N：只用于无变化轮询的快速路径；老客户端不带参数时行为完全不变。
    const rawRevision = (request.query as { revision?: unknown }).revision;
    const knownRevision =
      typeof rawRevision === "string" &&
      /^\d+$/.test(rawRevision) &&
      Number.isSafeInteger(Number(rawRevision))
        ? Number(rawRevision)
        : null;
    return withSnapshot(async (client) => {
      if (knownRevision !== null) {
        // 只读判定：不插入状态行、不拿 for update 锁、不生成 snapshot，也不重写缓存文档。
        const row = (
          await client.query<{ revision: string }>(
            "select revision from planner_sync_state where user_id=$1",
            [user.id],
          )
        ).rows[0];
        if (row && Number(row.revision) === knownRevision)
          return { revision: knownRevision, unchanged: true as const };
      }
      return currentState(client, user.id, await lockedState(client, user.id));
    });
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
      const { data, base, expectedRevision, writer_planning_version, writer_learning_version } = parsed.data;
      if (
        data.profile.user_id !== user.id ||
        (base && base.profile.user_id !== user.id)
      )
        return reply.code(403).send({ error: "计划不属于当前账号" });
      const result = await withSnapshot(async (client) => {
        const state = await lockedState(client, user.id);
        const current = await currentState(client, user.id, state, { persist: false });
        if (writer_planning_version !== 1 && [data, base, current.data].some(hasPlanningMetadata))
          return { upgradeRequired: true as const, error: "当前计划包含新版学习策略，请升级客户端后再同步", code: "planning_writer_upgrade_required" };
        // 旧写入方无法表达临时学习日志（task_id 为 null）：放行会在投影里无声删除真实计时记录，
        // 因此先给出明确升级提示；不写任何数据、revision 不变，升级后可用同一 revision/base 重试。
        const capable = writer_learning_version === 1 || representsLearningCapabilities(data);
        if (!capable && hasUnrepresentableLearningRecords(current.data))
          return { upgradeRequired: true as const, error: "当前计划包含临时学习或加学计时记录，请升级客户端后再同步", code: "learning_writer_upgrade_required" };
        const comparableBase = base ? normalizeProfilePlaceholders(base) : null;
        if (current.revision !== expectedRevision || !same(comparableBase, current.data))
          return { conflict: true as const, ...current };
        // 缺失 ≠ 清空：旧写入方/旧文档缺少新字段时保留云端临时学习、执行关系与容量覆盖。
        // 显式声明新能力的写入方（writer_learning_version=1）才把容量字段缺失当作“未设置”。
        const declaredCapable = writer_learning_version === 1;
        const preserved = PlannerDocumentSchema.parse(
          preserveLearningData(
            preservePlanningMetadata(data, current.data),
            current.data,
            { preserveCapacity: !declaredCapable },
          ),
        );
        await writeProjection(client, user.id, preserved, {
          clearMissingCapacity: declaredCapable,
        });
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
