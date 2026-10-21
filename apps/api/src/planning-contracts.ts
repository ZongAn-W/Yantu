import { z } from "zod";

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(+parsed) && parsed.toISOString().slice(0, 10) === value;
}, "日期格式无效");
const identifier = z.string().min(1).max(200);

/**
 * 事项的策略元数据：只有时间口径。
 *
 * 进度事实只有 `estimated_minutes`（预算）与学习日志实际用时；数量×单价的工作量、
 * 内容进度与难度反馈已移除。旧数据里的 `workload` / `content_progress` / `feedback`
 * 在解析时被宽容忽略，写回时不再生成（见 output/time-only-migration-spec.md）。
 */
export const ItemPlanningSchema = z.object({
  activity: z.object({
    kind: z.enum(["finite", "recurring"]),
    starts_on: date.optional(),
    ends_on: date.optional(),
    sessions_per_week: z.number().int().min(1).max(7).optional(),
    session_minutes: z.number().int().positive().max(240).optional(),
    state: z.enum(["active", "paused", "ended"]).optional(),
  }).optional(),
  dependencies: z.array(z.object({ task_id: identifier, mode: z.enum(["planned", "confirmed"]) })).max(500).optional(),
});

export const PlanPlanningSchema = z.object({
  version: z.literal(1),
  prompt_version: z.string().min(1).max(100),
  rules_version: z.string().min(1).max(100),
  /** 规划范围：full 一次覆盖整个有限周期；rolling 为旧版默认近期细化窗口。 */
  mode: z.enum(["rolling", "full"]).optional(),
  detail_days: z.number().int().min(1).max(1095).default(14),
  rolling: z.boolean(),
  route: z.array(z.object({
    id: identifier,
    title: z.string().min(1).max(500),
    start_date: date.optional(),
    end_date: date.optional(),
    item_ids: z.array(identifier).max(500),
    outcome: z.string().max(2000),
    check: z.string().max(2000),
  })).max(100),
  milestones: z.array(z.record(z.unknown())).max(100),
  assumptions: z.array(z.string().max(2000)).max(100),
  risks: z.array(z.string().max(2000)).max(100),
  uncovered: z.array(z.string().max(2000)).max(100),
  frozen_inputs: z.record(z.unknown()).optional(),
  quality: z.record(z.unknown()).nullable().optional(),
  detailed_until: date.optional(),
  forecast: z.record(z.unknown()).nullable().optional(),
  needs_review: z.boolean().optional(),
  /** 用户确认的容量采用值、来源与说明；完整计划基线的一部分。 */
  capacity: z.record(z.unknown()).nullable().optional(),
});

export type ItemPlanning = z.infer<typeof ItemPlanningSchema>;
export type PlanPlanning = z.infer<typeof PlanPlanningSchema>;
