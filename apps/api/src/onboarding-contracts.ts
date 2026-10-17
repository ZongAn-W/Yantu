import { z } from "zod";
import { CalendarDateSchema, CourseDraftSchema, ItemDraftSchema, NullableDateSchema, ProfileSchema } from "./contracts.js";

export const FIRST_QUESTION = "你接下来想学习什么，或者达成什么目标？";
export const FIRST_QUESTION_OPTIONS = ["考试备考", "课程学习", "技能提升", "自主学习", "其他"];

/** 每类目标在访谈里都必须继续追问具体学习内容，因此选项只是起点。 */
export const FIRST_QUESTION_EXAMPLES = [
  "准备计算机专业研究生考试。",
  "三个月内把雅思写作提高到 6.5。",
  "学完这学期的线性代数。",
  "从零学习 Python，能做简单的数据分析。",
  "每天读一点历史，没有固定截止日期。",
];

export { CalendarDateSchema };

export const QuestionOptionsSchema = z.array(z.string().trim().min(1).max(200)).max(8);

export const RecommendedWeeklyMinutesSchema = z
  .record(z.enum(["0", "1", "2", "3", "4", "5", "6"]), z.number().int().min(0).max(480))
  .refine(value => Object.keys(value).length === 0 || Object.keys(value).length === 7, "推荐时间必须包含完整一周");

const legacyRecommendations = z.preprocess(value => {
  if (!value || typeof value !== "object") return value;
  const row = { ...(value as Record<string, unknown>) };
  // 旧访谈会话只用 exam_date 表达一个日期；读入后按目标日期解释。
  if (row.target_date === undefined && row.exam_date !== undefined) row.target_date = row.exam_date;
  if (row.target_date_reason === undefined && row.exam_date_reason !== undefined) row.target_date_reason = row.exam_date_reason;
  if (row.target_date_estimated === undefined && row.exam_date_estimated !== undefined) row.target_date_estimated = row.exam_date_estimated;
  delete row.exam_date;
  delete row.exam_date_reason;
  delete row.exam_date_estimated;
  return row;
}, z.object({
  /** 用户希望达成目标的可选日期；空表示没有目标日期。 */
  target_date: z.preprocess(value => (value === "" || value === undefined ? "" : value), CalendarDateSchema.or(z.literal(""))).default(""),
  target_date_reason: z.string().max(1000).default(""),
  target_date_estimated: z.boolean().default(true),
  /** 本次规划周期的结束日期，必须是有限区间。 */
  plan_end_date: z.preprocess(value => (value === "" || value === undefined ? "" : value), CalendarDateSchema.or(z.literal(""))).default(""),
  plan_end_date_reason: z.string().max(1000).default(""),
  weekly_minutes: RecommendedWeeklyMinutesSchema.default({}),
  weekly_minutes_reason: z.string().max(1000).default(""),
}));

export const RecommendationsSchema = legacyRecommendations;
export type OnboardingRecommendations = z.infer<typeof RecommendationsSchema>;

export const CoursesSchema = z.array(CourseDraftSchema).min(1).max(100);
export const ItemsSchema = z.array(ItemDraftSchema.extend({
  earliest_date: CalendarDateSchema.optional(),
  deadline: CalendarDateSchema,
})).min(1).max(500);

export const SessionSchema = z.object({
  revision: z.number().int().nonnegative(),
  has_plan: z.boolean().default(false),
  replanning: z.boolean().default(false),
  plan_revision: z.number().int().nonnegative().nullable().default(null),
  current_plan: z.record(z.unknown()).nullable().default(null),
  stage: z.enum(["interview", "checkpoint", "courses", "items", "schedule", "complete"]),
  question: z.string().max(1000),
  question_options: QuestionOptionsSchema.default([]),
  question_multiple: z.boolean().default(false),
  answers: z.array(z.object({ question: z.string().max(1000), answer: z.string().max(4000) })).max(50),
  profile: ProfileSchema,
  recommendations: RecommendationsSchema.default({}),
  courses: z.array(CourseDraftSchema).max(100),
  items: z.array(ItemDraftSchema).max(500),
  summary: z.string().max(4000),
  assumptions: z.array(z.string().max(500)).max(20),
  warnings: z.array(z.string().max(500)).max(20),
  start_date: z.string(),
  end_date: z.string().default(""),
});
export type OnboardingSession = z.infer<typeof SessionSchema>;

export const ActionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("resume_interview") }),
  z.object({ type: z.literal("restart_interview") }),
  z.object({ type: z.literal("refresh_plan") }),
  z.object({ type: z.literal("answer"), answer: z.string().trim().min(1, "请先填写回答").max(4000) }),
  z.object({ type: z.literal("continue") }),
  z.object({ type: z.literal("generate_courses") }),
  z.object({ type: z.literal("save_courses"), courses: CoursesSchema }),
  z.object({ type: z.literal("confirm_courses"), courses: CoursesSchema }),
  z.object({ type: z.literal("revise_courses"), courses: CoursesSchema, instruction: z.string().trim().min(1).max(2000) }),
  z.object({ type: z.literal("save_items"), items: ItemsSchema }),
  z.object({ type: z.literal("confirm_items"), items: ItemsSchema }),
  z.object({ type: z.literal("revise_items"), items: ItemsSchema, instruction: z.string().trim().min(1).max(2000) }),
  z.object({ type: z.literal("back"), target: z.enum(["interview", "courses", "items"]) }),
  z.object({
    type: z.literal("finish"),
    start_date: CalendarDateSchema,
    /** 本次规划周期结束日期；目标日期可以没有，规划周期必须有。 */
    end_date: CalendarDateSchema,
    /** 可选目标日期，null、"" 或省略都表示暂不设置。 */
    target_date: NullableDateSchema.optional(),
    weekly_minutes: z.record(z.enum(["0", "1", "2", "3", "4", "5", "6"]), z.number().int().min(0).max(480)),
  }),
]);
export type OnboardingAction = z.infer<typeof ActionSchema>;

export function newSession(): OnboardingSession {
  return {
    revision: 0, has_plan: false, replanning: false, plan_revision: null, current_plan: null,
    stage: "interview", question: FIRST_QUESTION, answers: [],
    question_options: FIRST_QUESTION_OPTIONS, question_multiple: false,
    profile: ProfileSchema.parse({}), recommendations: RecommendationsSchema.parse({}),
    courses: [], items: [], summary: "", assumptions: [], warnings: [], start_date: "", end_date: "",
  };
}

export function validateReferences(courses: OnboardingSession["courses"], items: OnboardingSession["items"]) {
  if (new Set(courses.map(c => c.id)).size !== courses.length) throw new Error("课程编号重复，请修改后重试");
  if (new Set(items.map(i => i.id)).size !== items.length) throw new Error("事项编号重复，请修改后重试");
  const ids = new Set(courses.map(c => c.id));
  if (items.some(i => !ids.has(i.course_id))) throw new Error("事项必须属于已确认的课程");
}
