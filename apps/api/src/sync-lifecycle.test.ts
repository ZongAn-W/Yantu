import { describe, expect, it } from "vitest";
import { PlannerDocumentSchema, type PlannerDocument } from "./sync-contracts.js";
import { normalizeBaseTaskLifecycle, preserveTaskArchived, resolvedItemLifecycle, withProjectedTaskLifecycle } from "./sync.js";

const STAMP = "2026-10-12T00:00:00.000Z";

/** 最小合法同步文档；tasks 用宽松对象构造以覆盖旧/新两种 JSON 形态。 */
function document(tasks: Array<Record<string, unknown>>): PlannerDocument {
  return PlannerDocumentSchema.parse({
    version: 1,
    profile: {
      user_id: "owner", planning_mode: "daily", target_date: null,
      plan_start_date: "2026-10-01", plan_end_date: "2026-10-31",
      target_school: "", target_program: "", daily_limit_minutes: 480,
      granularity_minutes: 30, buffer_minutes: 30, study_start_minute: 480,
      study_end_minute: 1320, foundation: "",
    },
    tags: [],
    tasks,
    blocks: [],
    logs: [],
    fixed_events: [],
    replan_runs: [],
    phases: [],
  });
}

function task(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: "task", user_id: "owner", tag_ids: [], title: "任务",
    estimated_minutes: 120, completed_minutes: 0, priority: 2,
    deadline: "2026-10-31", is_fixed: false,
    created_at: STAMP, updated_at: STAMP,
    ...extra,
  };
}

describe("archived dual-form lifecycle (阶段 3b-A)", () => {
  it("resolves the storage truth with the new field taking priority", () => {
    // 新写入方：archived=true、status 缺失 → 归档，兼容投影 status=archived。
    expect(resolvedItemLifecycle(task({ archived: true }), undefined, 0))
      .toEqual({ archived: true, status: "archived", completed_at: null });
    // 旧写入方：只有 status='archived'、archived 缺失 → 归档。
    expect(resolvedItemLifecycle(task({ status: "archived" }), undefined, 0))
      .toEqual({ archived: true, status: "archived", completed_at: null });
    // archived 缺失且云端已归档 → 保留云端值。
    expect(resolvedItemLifecycle(task(), { archived: true, status: "archived" }, 0).archived).toBe(true);
    // 显式 false = 取消归档；旧 status 的归档投影不再生效，status 按时间口径重新派生。
    expect(resolvedItemLifecycle(task({ archived: false, status: "archived" }),
      { archived: true, status: "archived" }, 30)).toMatchObject({ archived: false, status: "in_progress" });
    // 未归档事项按时间事实派生兼容 status。
    expect(resolvedItemLifecycle(task({ completed_at: STAMP }), undefined, 0)).toMatchObject({ archived: false, status: "completed" });
    expect(resolvedItemLifecycle(task(), undefined, 120)).toMatchObject({ status: "completed" });
    expect(resolvedItemLifecycle(task(), undefined, 0)).toMatchObject({ status: "not_started" });
  });

  it("keeps completed_at missing=preserve and explicit null=clear", () => {
    const previous = { completed_at: "2026-10-10T00:00:00.000Z", status: "completed", archived: false };
    expect(resolvedItemLifecycle(task(), previous, 0).completed_at).toBe(previous.completed_at);
    expect(resolvedItemLifecycle(task({ completed_at: null }), previous, 0).completed_at).toBeNull();
    expect(resolvedItemLifecycle(task({ completed_at: "2026-10-11T08:00:00.000Z" }), previous, 0).completed_at)
      .toBe("2026-10-11T08:00:00.000Z");
  });

  it("preserves cloud archived when the field is missing and honors explicit false", () => {
    const archivedDoc = document([task({ archived: true })]);
    // 新写入方省略 archived：保留云端 true。
    expect(preserveTaskArchived(document([task()]), archivedDoc).tasks[0].archived).toBe(true);
    // 旧写入方用 status='archived' 表达归档意图。
    expect(preserveTaskArchived(document([task({ status: "archived" })]), document([task()])).tasks[0].archived).toBe(true);
    // 显式 false 取消归档。
    expect(preserveTaskArchived(document([task({ archived: false })]), archivedDoc).tasks[0].archived).toBe(false);
    // 无云端值、无旧 status → 未归档。
    expect(preserveTaskArchived(document([task()]), null).tasks[0].archived).toBe(false);
  });

  it("fills archived and derived status back from the relational projection", () => {
    // 旧缓存文档：既没有 archived 也没有 status；投影（快照）权威为已归档。
    const legacyDocument = document([task()]);
    expect(legacyDocument.tasks[0].archived).toBeUndefined();
    expect(legacyDocument.tasks[0].status).toBeUndefined();
    const projection = document([task({ archived: true, status: "archived" })]);
    const merged = withProjectedTaskLifecycle(legacyDocument, projection);
    expect(merged.tasks[0]).toMatchObject({ archived: true, status: "archived" });

    // 新客户端文档只发 archived（不回传 status）：读响应仍补派生 status 供旧客户端。
    const newClient = document([task({ archived: true })]);
    const filled = withProjectedTaskLifecycle(newClient, projection);
    expect(filled.tasks[0].archived).toBe(true);
    expect(filled.tasks[0].status).toBe("archived");

    // 没有投影时按新字段/旧 status 兼容推导。
    const fallback = withProjectedTaskLifecycle(document([task({ status: "archived" })]), null);
    expect(fallback.tasks[0]).toMatchObject({ archived: true, status: "archived" });
  });

  it("fills model-unrepresentable lifecycle fields on the sync base to avoid false conflicts", () => {
    // 阶段 3b 前的客户端：base 里没有 archived（模型不认识），status 保留。
    const current = document([task({ archived: true, status: "archived", completed_at: STAMP })]);
    const legacyBase = document([task({ status: "archived" })]);
    expect(legacyBase.tasks[0].archived).toBeUndefined();
    expect(normalizeBaseTaskLifecycle(legacyBase, current).tasks[0].archived).toBe(true);

    // 阶段 B 之后的新客户端：base 里没有 status/archived 也无妨。
    const newBase = document([task()]);
    const normalized = normalizeBaseTaskLifecycle(newBase, current);
    expect(normalized.tasks[0]).toMatchObject({
      archived: true, status: "archived", completed_at: STAMP,
    });

    // 客户端明确写下的值不被覆盖；新任务/已删除任务保持原样。
    const explicit = document([task({ archived: false, status: "not_started", completed_at: null })]);
    expect(normalizeBaseTaskLifecycle(explicit, current).tasks[0]).toMatchObject({
      archived: false, status: "not_started", completed_at: null,
    });
    const extraBase = document([task(), task({ id: "local-only", title: "local" })]);
    expect(normalizeBaseTaskLifecycle(extraBase, current).tasks[1].archived).toBeUndefined();
  });
});
