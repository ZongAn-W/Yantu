import { z } from "zod";

const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(+parsed) && parsed.toISOString().slice(0, 10) === value;
}, "日期格式无效");
const identifier = z.string().min(1).max(200);

export const WorkloadSchema = z.object({
  components: z.array(z.object({
    id: identifier,
    label: z.string().min(1).max(500),
    quantity: z.number().finite().positive().max(1000000),
    unit: z.string().min(1).max(100),
    minutes_per_unit: z.number().finite().positive().max(1000000),
    selected: z.boolean().optional(),
    range_min: z.number().finite().positive().optional(),
    range_max: z.number().finite().positive().optional(),
  })).min(1).max(100),
  source: z.string().max(2000),
  confidence: z.enum(["low", "medium", "high"]),
  calibration: z.string().max(2000),
  evidence_refs: z.array(z.string().max(2000)).max(100).optional(),
});

export const ItemPlanningSchema = z.object({
  workload: WorkloadSchema.optional(),
  activity: z.object({
    kind: z.enum(["finite", "recurring"]),
    starts_on: date.optional(),
    ends_on: date.optional(),
    sessions_per_week: z.number().int().min(1).max(7).optional(),
    session_minutes: z.number().int().positive().max(240).optional(),
    state: z.enum(["active", "paused", "ended"]).optional(),
  }).optional(),
  dependencies: z.array(z.object({ task_id: identifier, mode: z.enum(["planned", "confirmed"]) })).max(500).optional(),
  content_progress: z.object({
    completed_units: z.number().finite().nonnegative().optional(),
    feedback: z.string().max(4000).optional(),
    confirmed: z.boolean().optional(),
  }).optional(),
  feedback: z.object({
    content_units: z.number().finite().nonnegative(),
    content_completed: z.boolean(),
    difficulty: z.enum(["easy", "manageable", "hard"]),
    sampled_at: z.string().datetime({ offset: true }),
  }).optional(),
});

export const PlanPlanningSchema = z.object({
  version: z.literal(1),
  prompt_version: z.string().min(1).max(100),
  rules_version: z.string().min(1).max(100),
  detail_days: z.number().int().min(1).max(90).default(14),
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
});

export type ItemPlanning = z.infer<typeof ItemPlanningSchema>;
export type PlanPlanning = z.infer<typeof PlanPlanningSchema>;
