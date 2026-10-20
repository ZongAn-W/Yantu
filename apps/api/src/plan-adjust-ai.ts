import { z } from "zod";
import { AI_REQUEST_TIMEOUT_MS, requestStructuredAI } from "./ai-json.js";
import { adoptedWeeklyCapacity, plusDays } from "./capacity.js";
import { config } from "./config.js";
import type { PlannerDocument } from "./sync-contracts.js";

const date = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((value) => {
    const parsed = new Date(`${value}T00:00:00Z`);
    return (
      Number.isFinite(+parsed) && parsed.toISOString().slice(0, 10) === value
    );
  }, "日期格式无效");

const weekdayKey = z.enum(["0", "1", "2", "3", "4", "5", "6"]);

/**
 * AI 输出的调整方案（设计文档 §5）。
 *
 * 字段名是服务端、Flutter 客户端与验收测试的共同契约，不得改名；服务端解析后由
 * `applyPlanAdjustment` 按硬性规则应用到当前文档，非法方案整体拒绝，不做部分应用。
 */
export const PlanAdjustmentSchema = z.object({
  assessment: z.string().min(1).max(4000),
  verdict: z.enum(["reasonable", "too_light", "too_heavy"]),
  required_minutes: z.object({
    min: z.number().int().min(0).max(1_000_000),
    max: z.number().int().min(0).max(1_000_000),
  }),
  cycle: z.object({ end_date: date, reason: z.string().max(2000) }),
  intensity: z
    .object({
      weekly_minutes: z.record(
        weekdayKey,
        z.number().int().min(0).max(1440),
      ),
      reason: z.string().max(2000),
    })
    .nullable()
    .optional(),
  task_updates: z
    .array(
      z.object({
        task_id: z.string().min(1).max(80),
        estimated_minutes: z.number().int().min(30).max(1_000_000),
        reason: z.string().max(1000),
      }),
    )
    .max(1000)
    .default([]),
  new_subjects: z
    .array(
      z.object({
        key: z.string().min(1).max(80),
        name: z.string().min(1).max(100),
        priority: z.number().int().min(1).max(3),
      }),
    )
    .max(20)
    .default([]),
  new_tasks: z
    .array(
      z.object({
        key: z.string().min(1).max(80),
        // 已存在的 subject id，或 new_subjects 的 key。
        subject: z.string().min(1).max(100),
        title: z.string().min(1).max(200),
        description: z.string().max(4000).default(""),
        estimated_minutes: z.number().int().min(30).max(200_000),
        earliest_date: date.optional(),
        deadline_kind: z.enum(["deadline", "plan_end"]),
        deadline: date.optional(),
        priority: z.number().int().min(1).max(3),
        reason: z.string().max(1000),
      }),
    )
    .max(200)
    .default([]),
  warnings: z.array(z.string().max(1000)).max(20).default([]),
});
export type PlanAdjustment = z.infer<typeof PlanAdjustmentSchema>;

const RULES = {
  verdict:
    "依据目标估算所需总学习时长；当前计划明显低于下限判 too_light，明显高于上限判 too_heavy，否则 reasonable",
  goal_examples:
    "考研交大计算机：数学+408+英语+政治+真题复盘通常需要约 1500–3000 小时（视基础和脱产程度）；400 小时属于明显不合理",
  intensity:
    "新的每周分钟模板必须可排程（每日 0–1440，考虑近期实际执行，避免一次提高超过 2 倍）；周期结束日不得晚于 target_date（若有），且不得早于今天",
  real_hours:
    "required_minutes/required_max_minutes 必须为整数分钟，表示达成目标的现实总学习时长区间",
} as const;

type Row = Record<string, unknown>;
const rows = (value: unknown): Row[] =>
  Array.isArray(value) ? value.filter((item): item is Row => Boolean(item) && typeof item === "object") : [];
const text = (value: unknown) => (typeof value === "string" ? value : "");
const finite = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? value : 0);

/** Inclusive calendar day count; 0 when the interval is inverted. */
function daySpan(start: string, end: string): number {
  if (end < start) return 0;
  return Math.round((Date.parse(`${end}T00:00:00Z`) - Date.parse(`${start}T00:00:00Z`)) / 86_400_000) + 1;
}

/** 紧凑的近期执行统计：按日、按课程分别汇总计划与实际，避免把全部 blocks 塞进提示词。 */
function recentExecution(document: PlannerDocument, today: string) {
  const plannedByDate = new Map<string, number>();
  for (const block of document.blocks)
    plannedByDate.set(block.date, (plannedByDate.get(block.date) ?? 0) + block.duration_minutes);
  type DayActual = { actual: number; scheduled: number; extra: number };
  const actualByDate = new Map<string, DayActual>();
  for (const log of document.logs) {
    const day = actualByDate.get(log.date) ?? { actual: 0, scheduled: 0, extra: 0 };
    day.actual += log.minutes;
    if (log.relation === "scheduled") day.scheduled += log.minutes;
    else if (log.relation === "extra") day.extra += log.minutes;
    actualByDate.set(log.date, day);
  }
  const day = (value: string) => {
    const actual = actualByDate.get(value) ?? { actual: 0, scheduled: 0, extra: 0 };
    return {
      date: value,
      planned_minutes: plannedByDate.get(value) ?? 0,
      actual_minutes: actual.actual,
      scheduled_minutes: actual.scheduled,
      extra_minutes: actual.extra,
    };
  };
  const dates = (days: number) =>
    Array.from({ length: days }, (_, index) => plusDays(today, -index));
  const last7 = dates(7);
  const last14 = dates(14);
  const plannedIn = (window: string[]) => window.reduce((sum, value) => sum + (plannedByDate.get(value) ?? 0), 0);
  const actualIn = (window: string[]) => window.reduce((sum, value) => sum + (actualByDate.get(value)?.actual ?? 0), 0);
  // 按课程统计近 14 天：计划来自 blocks，实际来自 logs；所有日志都归属正式事项。
  const taskById = new Map(document.tasks.map((task) => [task.id, task]));
  const subjectActual = new Map<string, number>();
  const subjectPlanned = new Map<string, number>();
  for (const log of document.logs) {
    if (!log.task_id || !last14.includes(log.date)) continue;
    const subject = taskById.get(log.task_id)?.subject_id;
    if (subject) subjectActual.set(subject, (subjectActual.get(subject) ?? 0) + log.minutes);
  }
  for (const block of document.blocks) {
    if (!last14.includes(block.date)) continue;
    const subject = taskById.get(block.task_id)?.subject_id;
    if (subject) subjectPlanned.set(subject, (subjectPlanned.get(subject) ?? 0) + block.duration_minutes);
  }
  const perSubjectLast14 = document.subjects
    .filter((subject) => (subjectActual.get(subject.id) ?? 0) > 0 || (subjectPlanned.get(subject.id) ?? 0) > 0)
    .map((subject) => ({
      subject: subject.name,
      actual_minutes: subjectActual.get(subject.id) ?? 0,
      planned_minutes: subjectPlanned.get(subject.id) ?? 0,
    }));
  return {
    days: last7.map(day).reverse(),
    last7_actual_minutes: actualIn(last7),
    last7_planned_minutes: plannedIn(last7),
    last14_actual_minutes: actualIn(last14),
    last14_planned_minutes: plannedIn(last14),
    per_subject_last14: perSubjectLast14,
  };
}

function futureLoad(document: PlannerDocument, today: string) {
  const plannedByDate = new Map<string, number>();
  for (const block of document.blocks)
    plannedByDate.set(block.date, (plannedByDate.get(block.date) ?? 0) + block.duration_minutes);
  const next14 = Array.from({ length: 14 }, (_, index) => {
    const value = plusDays(today, index);
    return { date: value, planned_minutes: plannedByDate.get(value) ?? 0 };
  });
  const scheduledRemaining = document.tasks
    .filter((task) => task.status !== "archived")
    .reduce((sum, task) => sum + Math.max(0, task.estimated_minutes - task.completed_minutes), 0);
  return { next14_days: next14, scheduled_remaining_minutes: scheduledRemaining };
}

export type AdjustmentContext = ReturnType<typeof buildAdjustmentContext>;

/**
 * 给模型的 user JSON（设计文档 §4）。
 *
 * 明确不包含全量 blocks：只给逐日/逐课程聚合和未来 14 天负荷摘要，既控制上下文长度，
 * 也避免模型逐块改写受保护的历史记录。
 */
export function buildAdjustmentContext(document: PlannerDocument, today: string) {
  const profile = document.profile as unknown as Row;
  const planStart = document.profile.plan_start_date ?? today;
  const planEnd = document.profile.plan_end_date ?? document.profile.target_date ?? plusDays(today, 27);
  const template = (() => {
    const week = document.profile.weekly_minutes;
    if (!week || typeof week !== "object" || Object.keys(week).length !== 7) return null;
    return Object.fromEntries(
      [0, 1, 2, 3, 4, 5, 6].map((value) => [String(value), finite((week as Row)[String(value)])]),
    );
  })();
  const adopted = adoptedWeeklyCapacity(document.profile);
  const baseline = document.profile.weekly_baseline_minutes ?? null;
  const rangeMin = document.profile.weekly_range_min_minutes ?? null;
  const rangeMax = document.profile.weekly_range_max_minutes ?? null;
  const activeTasks = document.tasks.filter((task) => task.status !== "archived");
  const subjectName = new Map(document.subjects.map((subject) => [subject.id, subject.name]));
  const subjectTotals = document.subjects
    .map((subject) => {
      const tasks = activeTasks.filter((task) => task.subject_id === subject.id);
      const planned = tasks.reduce((sum, task) => sum + task.estimated_minutes, 0);
      const completed = tasks.reduce((sum, task) => sum + task.completed_minutes, 0);
      return {
        subject: subject.name,
        planned_minutes: planned,
        completed_minutes: completed,
        remaining_minutes: tasks.reduce((sum, task) => sum + Math.max(0, task.estimated_minutes - task.completed_minutes), 0),
      };
    })
    .filter((row) => row.planned_minutes > 0 || row.completed_minutes > 0);
  const tasks = activeTasks.slice(0, 500).map((task) => {
    const planning = task.planning ?? null;
    const activity = planning?.activity ?? null;
    const workload = planning?.workload ?? null;
    const contentProgress = planning?.content_progress ?? null;
    const feedback = planning?.feedback ?? null;
    return {
      task_id: task.id,
      subject: subjectName.get(task.subject_id) ?? task.subject_id,
      title: task.title,
      status: task.status,
      estimated_minutes: task.estimated_minutes,
      completed_minutes: task.completed_minutes,
      remaining_minutes: Math.max(0, task.estimated_minutes - task.completed_minutes),
      deadline: task.deadline,
      deadline_kind: task.deadline_kind ?? "deadline",
      earliest_date: task.earliest_date ?? null,
      priority: task.priority,
      is_fixed: task.is_fixed,
      activity: activity
        ? {
            kind: activity.kind,
            ...(activity.starts_on ? { starts_on: activity.starts_on } : {}),
            ...(activity.ends_on ? { ends_on: activity.ends_on } : {}),
            ...(activity.sessions_per_week ? { sessions_per_week: activity.sessions_per_week } : {}),
            ...(activity.session_minutes ? { session_minutes: activity.session_minutes } : {}),
            ...(activity.state ? { state: activity.state } : {}),
          }
        : null,
      workload_components: rows(workload?.components)
        .filter((component) => component.selected !== false)
        .slice(0, 20)
        .map((component) => ({
          label: text(component.label),
          quantity: finite(component.quantity),
          minutes_per_unit: finite(component.minutes_per_unit),
        })),
      content_progress: contentProgress ?? null,
      feedback: feedback ?? null,
    };
  });
  return {
    today,
    goal: {
      type: text(profile.goal_type) || "other",
      text: text(profile.goal_text),
      subtype: text(profile.goal_subtype),
      target_school: text(profile.target_school),
      target_program: text(profile.target_program),
      target_date: text(profile.target_date),
      foundation: text(profile.foundation),
      constraints: text(profile.constraints),
    },
    plan_cycle: {
      start: planStart,
      end: planEnd,
      remaining_days: daySpan(today, planEnd),
    },
    capacity: {
      basis: document.profile.capacity_basis ?? "gross_buffer",
      weekly_minutes_template: template,
      weekly_baseline_minutes: baseline,
      weekly_range: rangeMin !== null || rangeMax !== null
        ? { min: rangeMin ?? 0, max: rangeMax ?? rangeMin ?? 0 }
        : null,
      adopted_weekly_minutes: adopted.minutes,
      date_override_count: Object.keys(document.profile.date_capacity_overrides ?? {}).length,
      week_override_count: Object.keys(document.profile.week_capacity_overrides ?? {}).length,
    },
    totals: {
      planned_minutes: activeTasks.reduce((sum, task) => sum + task.estimated_minutes, 0),
      completed_minutes: activeTasks.reduce((sum, task) => sum + task.completed_minutes, 0),
      remaining_minutes: activeTasks.reduce(
        (sum, task) => sum + Math.max(0, task.estimated_minutes - task.completed_minutes),
        0,
      ),
      subject_totals: subjectTotals,
    },
    tasks,
    ...(activeTasks.length > tasks.length ? { tasks_omitted: activeTasks.length - tasks.length } : {}),
    recent_execution: recentExecution(document, today),
    future_load: futureLoad(document, today),
    rules: RULES,
  };
}

const ADJUSTMENT_INSTRUCTIONS = [
  "你是学习计划调整顾问。根据用户的目标、画像、当前计划总量、事项摘要、近期实际执行和未来负荷，输出一次调整方案；只返回一个 JSON 对象，不要 Markdown、注释或额外字段。",
  "一、目标审查（硬性要求）：先依据 goal 与 foundation 估算达成目标所需的现实总学习时长区间 required_minutes（整数分钟，单位是分钟，min 不得大于 max）。交大计算机考研（数学+408+英语+政治+真题复盘）通常需要约 1500–3000 小时；当前计划只有 400 小时属于明显不合理，应判 too_light 并真正增加总学习量。verdict 只能是 reasonable（合理）/ too_light（偏轻）/ too_heavy（偏重）。assessment 用中文说明判断依据、当前计划与目标的差距，以及本次调整如何修正。",
  "二、周期：cycle.end_date 是新的规划周期结束日期（YYYY-MM-DD），必须不早于 today；若 goal.target_date 存在且不早于 today，则不得晚于 target_date；从当前周期开始日算起总跨度不得超过 1095 天。开始日期不可修改。cycle.reason 用中文说明理由。",
  '三、学习强度：intensity.weekly_minutes 是一周七天可用分钟模板，键为 "0"(周日) 到 "6"(周六)，每天 0–1440 的整数，0 表示休息；提高强度时必须参考 recent_execution 的实际执行，避免一次提高超过 2 倍；确实不需要调整时 intensity 填 null。intensity.reason 用中文说明理由。',
  "四、事项预算：task_updates 只能修改现有未归档事项的 estimated_minutes（整数 30–1000000，包含已完成用时的总预算），不得低于该事项的 completed_minutes；不得修改真实截止日期、最早开始日期、固定事项、已完成事项或归档事项；task_id 必须来自 tasks。reason 用中文说明理由。",
  '五、新增事项：当现有事项不足以达成目标时，用 new_subjects 新增课程（key 为自定义短标识）、用 new_tasks 新增事项。new_tasks.subject 填现有 subjects 的 id 或 new_subjects 中的 key；deadline_kind="plan_end" 表示截止日期跟随新周期结束日（deadline 可省略）；deadline_kind="deadline" 表示真实截止日期，此时必须给出 deadline 且不早于 today；earliest_date 可选且不得晚于 deadline；estimated_minutes 为整数分钟；reason 用中文说明理由。',
  "六、禁止事项：不得删除或归档既有事项；不得改动固定事项和已完成记录；不得编造用户没有提供的事实、资料或已完成进度；目标所需时长和新增事项都要有依据。warnings 只写用户需要知道的取舍、风险或无法满足的目标。",
  "七、一致性：调整后总时长 = 所有未归档事项预算之和（含新增事项）。verdict=too_light 时必须在周期、强度、事项预算或新增事项上真正增加学习量；too_heavy 时适当下调强度或预算。建议量力而行，不要把每天排满到 1440 分钟。",
  "八、只返回严格符合以下结构的 JSON（字段名固定）：",
  '{"assessment":"中文审查结论","verdict":"reasonable|too_light|too_heavy","required_minutes":{"min":整数分钟,"max":整数分钟},"cycle":{"end_date":"YYYY-MM-DD","reason":"中文理由"},"intensity":{"weekly_minutes":{"0":0,"1":0,"2":0,"3":0,"4":0,"5":0,"6":0},"reason":"中文理由"}或null,"task_updates":[{"task_id":"现有事项id","estimated_minutes":整数,"reason":"中文理由"}],"new_subjects":[{"key":"短标识","name":"课程名","priority":1}],"new_tasks":[{"key":"短标识","subject":"课程id或新课程key","title":"事项标题","description":"范围","estimated_minutes":整数,"earliest_date":"可选","deadline_kind":"deadline|plan_end","deadline":"可选","priority":1,"reason":"中文理由"}],"warnings":["中文提示"]}',
].join("\n");

/**
 * 调用 AI 生成调整方案。
 *
 * 未配置 AI 时直接抛错（路由映射 502），绝不回退到本地确定性算法；超时/网络/结构化
 * 输出校验失败由 `requestStructuredAI` 抛出，路由同样映射 502 并保留原计划。
 */
export async function generatePlanAdjustment(context: AdjustmentContext): Promise<PlanAdjustment> {
  if (!config.aiApiKey) throw new Error("服务器尚未配置 AI，暂时无法调整计划；请稍后重试或联系管理员");
  return requestStructuredAI(PlanAdjustmentSchema, ADJUSTMENT_INSTRUCTIONS, context, {
    timeoutMs: AI_REQUEST_TIMEOUT_MS,
    reasoningEffort: config.aiPlanningReasoningEffort,
    label: "plan-adjust",
  });
}
