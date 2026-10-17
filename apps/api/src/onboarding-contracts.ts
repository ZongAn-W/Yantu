import { z } from "zod";
import { CalendarDateSchema, CourseDraftSchema, ItemDraftSchema, NullableDateSchema, ProfileSchema } from "./contracts.js";
import { LearningContextSchema, ResearchSchema, LEARNER_FIELDS } from "./learning-context.js";
import { PlanPlanningSchema } from "./planning-contracts.js";

export const FIRST_QUESTION = "你接下来想学习什么，或者达成什么目标？";
/** 首题只提供具体业务选项；“其他”自定义回答入口由客户端统一提供。 */
export const FIRST_QUESTION_OPTIONS = ["考试备考", "课程学习", "技能提升", "自主学习"];

/**
 * 通用“自填”占位项：只匹配整个选项，不做前缀匹配，
 * 避免把“其他语言课程”这类有具体含义的业务选项误删。
 */
const OTHER_PLACEHOLDER = /^(?:其他|其它|other)\s*(?:[：:]\s*)?(?:[（(]\s*(?:自填|自定义|请填写|请补充|填写|请说明)\s*[）)])?$/i;

/**
 * 归一化题目选项：去除首尾空格与空项、忽略大小写去重，并移除“其他”等自填占位项。
 * 有效选项保持首次出现的顺序，服务端只返回具体业务选项。
 */
export function normalizeQuestionOptions(options: readonly string[]): string[] {
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const raw of options) {
    if (typeof raw !== "string") continue;
    const option = raw.trim();
    if (!option || OTHER_PLACEHOLDER.test(option)) continue;
    const key = option.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    normalized.push(option);
  }
  return normalized;
}

/** 每类目标在访谈里都必须继续追问具体学习内容，因此选项只是起点。 */
export const FIRST_QUESTION_EXAMPLES = [
  "准备计算机专业研究生考试。",
  "三个月内把雅思写作提高到 6.5。",
  "学完这学期的线性代数。",
  "从零学习 Python，能做简单的数据分析。",
  "每天读一点历史，没有固定截止日期。",
];

export { CalendarDateSchema };

export const QuestionOptionsSchema = z
  .array(z.string().trim().max(200))
  .transform(options => normalizeQuestionOptions(options))
  .refine(options => options.length <= 8, "题目选项不能超过8项");

export const QuestionTypeSchema = z.enum(["text", "single_choice", "multiple_choice"]);
export type QuestionType = z.infer<typeof QuestionTypeSchema>;

/** Old drafts infer their type once; explicit AI text answers never retain stale options. */
export function normalizeQuestionPresentation(value: {
  question_type?: QuestionType; question_options?: readonly string[]; question_multiple?: boolean;
}) {
  const options = normalizeQuestionOptions(value.question_options ?? []);
  const type = value.question_type ?? (!options.length ? "text" : value.question_multiple ? "multiple_choice" : "single_choice");
  if (type === "text" || !options.length) return { question_type: "text" as const, question_options: [], question_multiple: false };
  return { question_type: type, question_options: options, question_multiple: type === "multiple_choice" };
}

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
  stage: z.enum(["interview", "checkpoint", "courses", "constraints", "items", "schedule", "complete"]),
  question: z.string().max(1000),
  question_type: QuestionTypeSchema.optional(),
  question_options: QuestionOptionsSchema.default([]),
  question_multiple: z.boolean().default(false),
  question_fields: z.array(z.enum(LEARNER_FIELDS)).default([]),
  learning_context: LearningContextSchema,
  research: ResearchSchema,
  exam_year_override: z.number().int().min(2020).max(2100).nullable().default(null),
  answers: z.array(z.object({ question: z.string().max(1000), answer: z.string().max(4000), fields: z.array(z.enum(LEARNER_FIELDS)).optional() })).max(50),
  profile: ProfileSchema,
  recommendations: RecommendationsSchema.default({}),
  courses: z.array(CourseDraftSchema).max(100),
  items: z.array(ItemDraftSchema).max(500),
  summary: z.string().max(4000),
  assumptions: z.array(z.string().max(500)).max(20),
  warnings: z.array(z.string().max(500)).max(20),
  start_date: z.string(),
  end_date: z.string().default(""),
  constraints_confirmed: z.boolean().default(false),
  planning: PlanPlanningSchema.nullable().default(null),
  preview: z.record(z.unknown()).nullable().default(null),
});
export type OnboardingSession = z.infer<typeof SessionSchema>;

export const ActionSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("resume_interview") }),
  z.object({ type: z.literal("restart_interview") }),
  z.object({ type: z.literal("refresh_plan") }),
  z.object({ type: z.literal("set_exam_year"), year: z.number().int().min(2020).max(2100) }),
  z.object({ type: z.literal("retry_research") }),
  z.object({ type: z.literal("answer"), answer: z.string().trim().min(1, "请先填写回答").max(4000) }),
  z.object({ type: z.literal("continue") }),
  z.object({ type: z.literal("generate_courses") }),
  z.object({ type: z.literal("save_courses"), courses: CoursesSchema }),
  z.object({ type: z.literal("confirm_courses"), courses: CoursesSchema }),
  z.object({ type: z.literal("set_constraints"), start_date: CalendarDateSchema, end_date: CalendarDateSchema,
    target_date: NullableDateSchema.optional(), weekly_minutes: RecommendedWeeklyMinutesSchema.refine(value => Object.keys(value).length === 7, "请填写完整一周时间"),
    detail_days: z.number().int().min(1).max(90).default(14) }),
  z.object({ type: z.literal("preview_schedule"), start_date: CalendarDateSchema, end_date: CalendarDateSchema,
    target_date: NullableDateSchema.optional(), weekly_minutes: RecommendedWeeklyMinutesSchema.refine(value => Object.keys(value).length === 7, "请填写完整一周时间"),
    detail_days: z.number().int().min(1).max(90).default(14) }),
  z.object({ type: z.literal("revise_courses"), courses: CoursesSchema, instruction: z.string().trim().min(1).max(2000) }),
  z.object({ type: z.literal("save_items"), items: ItemsSchema }),
  z.object({ type: z.literal("confirm_items"), items: ItemsSchema }),
  z.object({ type: z.literal("revise_items"), items: ItemsSchema, instruction: z.string().trim().min(1).max(2000) }),
  z.object({ type: z.literal("back"), target: z.enum(["interview", "courses", "constraints", "items"]) }),
  z.object({
    type: z.literal("finish"),
    start_date: CalendarDateSchema,
    /** 本次规划周期结束日期；目标日期可以没有，规划周期必须有。 */
    end_date: CalendarDateSchema,
    /** 可选目标日期，null、"" 或省略都表示暂不设置。 */
    target_date: NullableDateSchema.optional(),
    weekly_minutes: z.record(z.enum(["0", "1", "2", "3", "4", "5", "6"]), z.number().int().min(0).max(480)),
    preview_token: z.string().optional(),
  }),
]);
export type OnboardingAction = z.infer<typeof ActionSchema>;

export function newSession(): OnboardingSession {
  return {
    revision: 0, has_plan: false, replanning: false, plan_revision: null, current_plan: null,
    stage: "interview", question: FIRST_QUESTION, answers: [],
    question_options: FIRST_QUESTION_OPTIONS, question_multiple: false,
    question_fields: [], learning_context: LearningContextSchema.parse({}), research: ResearchSchema.parse({}), exam_year_override: null,
    profile: ProfileSchema.parse({}), recommendations: RecommendationsSchema.parse({}),
    courses: [], items: [], summary: "", assumptions: [], warnings: [], start_date: "", end_date: "",
    constraints_confirmed: false, planning: null, preview: null,
  };
}

export function validateReferences(courses: OnboardingSession["courses"], items: OnboardingSession["items"]) {
  if (new Set(courses.map(c => c.id)).size !== courses.length) throw new Error("课程编号重复，请修改后重试");
  if (new Set(items.map(i => i.id)).size !== items.length) throw new Error("事项编号重复，请修改后重试");
  const ids = new Set(courses.map(c => c.id));
  if (items.some(i => !ids.has(i.course_id))) throw new Error("事项必须属于已确认的课程");
}
