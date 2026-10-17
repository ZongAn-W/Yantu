import { z } from "zod";
import { ItemPlanningSchema, PlanPlanningSchema } from "./planning-contracts.js";

/** 自然日 YYYY-MM-DD；用于目标日期、规划周期和事项日期。 */
export const CalendarDateSchema = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/, "请选择有效日期")
  .refine(value => {
    const date = new Date(`${value}T00:00:00Z`);
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }, "请选择有效日期");

/**
 * 可选日期。`null`、`""` 和字段缺失都表示“没有这个日期”，
 * 旧客户端导出的空字符串因此可以继续读取；不会用占位日期冒充。
 */
export const NullableDateSchema = z.preprocess(
  value => (value === "" || value === undefined ? null : value),
  CalendarDateSchema.nullable(),
);

/** 通用目标类型：考试备考、课程学习、技能提升、自主学习、其他。 */
export const GoalTypeSchema = z.enum(["exam", "course", "skill", "self_study", "other"]);
export type GoalType = z.infer<typeof GoalTypeSchema>;

export const GOAL_TYPE_LABELS: Record<GoalType, string> = {
  exam: "考试备考",
  course: "课程学习",
  skill: "技能提升",
  self_study: "自主学习",
  other: "其他",
};

export const EMPTY_WEEK = { "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 };

export const WeeklyMinutesSchema = z.record(z.string(), z.number().int().min(0).max(1440));

/**
 * 规范的学习目标与规划设置。
 *
 * 唯一的规范来源：数据库 profiles 表、访谈会话、PlannerData.profile 与同步文档
 * 都使用这组字段名，避免同一信息在多处维护后互相覆盖。
 */
export const ProfileSchema = z.object({
  goal_text: z.string().max(2000).default(""),
  goal_type: GoalTypeSchema.default("other"),
  goal_subtype: z.string().max(200).default(""),
  target_date: NullableDateSchema.default(null),
  target_date_confirmed: z.boolean().default(false),
  plan_start_date: NullableDateSchema.default(null),
  plan_end_date: NullableDateSchema.default(null),
  target_school: z.string().max(200).default(""),
  target_program: z.string().max(200).default(""),
  current_progress: z.string().max(4000).default(""),
  weekly_minutes: WeeklyMinutesSchema.default({ ...EMPTY_WEEK }),
  constraints_text: z.string().max(4000).default(""),
});

/** 部分更新：字段缺失表示“不修改”，target_date 传 null 表示“清空”。 */
export const ProfileUpdateSchema = ProfileSchema.partial();
export type ProfileUpdate = z.infer<typeof ProfileUpdateSchema>;

/** 兼容旧名称，访谈会话复用同一份资料结构。 */
export const InterviewProfileSchema = ProfileSchema;

export const CourseDraftSchema = z.object({
  id: z.string().min(1).max(80),
  name: z.string().min(1).max(100),
  description: z.string().max(1000).default(""),
  priority: z.number().int().min(1).max(3).default(2),
});

/** 事项日期语义：真实截止日期，或本期安排边界。 */
export const ItemDateKindSchema = z.enum(["deadline", "plan_end"]);

export const ItemDraftSchema = z.object({
  id: z.string().min(1).max(80),
  course_id: z.string().min(1).max(80),
  title: z.string().min(1).max(200),
  description: z.string().max(4000).default(""),
  completion_criteria: z.string().max(1000).default(""),
  estimated_minutes: z.number().int().min(30).max(100000),
  earliest_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  deadline: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  deadline_kind: ItemDateKindSchema.default("deadline"),
  priority: z.number().int().min(1).max(3).default(2),
  planning: ItemPlanningSchema.nullable().optional(),
});

export const PlanDraftSchema = z.object({
  courses: z.array(CourseDraftSchema).min(1).max(100),
  items: z.array(ItemDraftSchema).min(1).max(500),
  analysis_summary: z.string().max(4000),
  assumptions: z.array(z.string().max(500)).max(20).default([]),
  warnings: z.array(z.string().max(500)).max(20).default([]),
  planning: PlanPlanningSchema.nullable().optional(),
});

export const DailyEntrySchema = z.object({
  item_id: z.string().uuid(),
  actual_minutes: z.number().int().min(0).max(1440),
  completion_status: z.enum(["not_started", "partial", "completed", "skipped"]),
  feedback: z.string().max(2000).default(""),
});

export const SettleSchema = z.object({
  feedback: z.string().max(4000).default(""),
  entries: z.array(DailyEntrySchema).default([]),
});

export type ProfileInput = z.infer<typeof ProfileSchema>;
export type PlanDraft = z.infer<typeof PlanDraftSchema>;
