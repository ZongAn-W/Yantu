import { z } from "zod";
import { ItemPlanningSchema, PlanPlanningSchema } from "./planning-contracts.js";

const id = z.string().min(1).max(200);
const date = z
  .string()
  .regex(/^\d{4}-\d{2}-\d{2}$/)
  .refine((value) => {
    const parsed = new Date(value + "T00:00:00Z");
    return (
      Number.isFinite(+parsed) && parsed.toISOString().slice(0, 10) === value
    );
  }, "日期格式无效");
const minutes = z.number().int().min(0).max(10000000);
const priority = z.union([z.literal(1), z.literal(2), z.literal(3)]);
const stamp = z.string().datetime({ offset: true });
const owned = { id, user_id: id };
const timestamped = { created_at: stamp, updated_at: stamp };
const status = z.enum([
  "not_started",
  "in_progress",
  "completed",
  "delayed",
  "conflict",
  "archived",
]);
const block = z
  .object({
    ...owned,
    ...timestamped,
    task_id: id,
    date,
    start_minute: minutes,
    duration_minutes: minutes.positive(),
    actual_minutes: minutes,
    is_fixed: z.boolean(),
    status: z.enum(["planned", "completed"]),
    advice_text: z.string().max(20000).optional(),
    advice_topics: z.array(z.string()).optional(),
    completion_status: z
      .enum(["not_started", "partial", "completed", "skipped"])
      .optional(),
    feedback: z.string().max(4000).optional(),
    activity_instance_id: id.nullable().optional(),
  })
  .passthrough();
/**
 * 旧格式的空字符串、null 和字段缺失都表示“没有这个日期”。
 * 不使用占位日期充当真实日期。
 */
const optionalDate = z.preprocess(
  (value) => (value === "" || value === null || value === undefined ? undefined : value),
  date.optional(),
);

const nullableDate = z.preprocess(
  (value) => (value === "" || value === undefined ? null : value),
  date.nullable(),
);

/** 特定自然周的容量覆盖；只给周总量时由程序生成逐日建议。 */
const WeekCapacityOverrideSchema = z
  .object({
    total_minutes: minutes.max(10080).optional(),
    days: z
      .record(z.enum(["0", "1", "2", "3", "4", "5", "6"]), minutes.max(1440))
      .optional(),
  })
  .passthrough();

const MondayKey = z.string().refine((value) => {
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(+parsed) && parsed.toISOString().slice(0, 10) === value
    && parsed.getUTCDay() === 1;
}, "容量覆盖的周标识必须是周一日期");

export const PlannerDocumentSchema = z
  .object({
    version: z.literal(1),
    planning: PlanPlanningSchema.nullable().optional(),
    profile: z
      .object({
        user_id: id,
        planning_mode: z.enum(["daily", "timed"]).optional(),
        goal_text: z.string().max(2000).optional(),
        goal_type: z.enum(["exam", "course", "skill", "self_study", "other"]).optional(),
        goal_subtype: z.string().max(200).optional(),
        /** 用户目标日期，可空；与本次规划周期分别表达。 */
        target_date: nullableDate.optional(),
        target_date_confirmed: z.boolean().optional(),
        /** 本次规划周期的有限区间；排程只在这个区间内生成安排。 */
        plan_start_date: optionalDate,
        plan_end_date: optionalDate,
        /** 一周七天的可用学习分钟数；缺少时退回每日上限。 */
        weekly_minutes: z.record(z.string(), z.number().int().min(0).max(1440)).optional(),
        /** 容量口径：旧数据为扣除机动的总预算，新数据为净学习预算。 */
        capacity_basis: z.enum(["gross_buffer", "net"]).nullable().optional(),
        weekly_baseline_minutes: minutes.max(10080).nullable().optional(),
        weekly_range_min_minutes: minutes.max(10080).nullable().optional(),
        weekly_range_max_minutes: minutes.max(10080).nullable().optional(),
        /** 特定周容量覆盖，键为上海时区周一日期；null/{} = 显式清空覆盖。 */
        week_capacity_overrides: z
          .record(MondayKey, WeekCapacityOverrideSchema)
          .nullable()
          .optional(),
        /** 特定日期净容量覆盖；显式 0 表示休息，删除键表示恢复上层规则；null/{} = 清空。 */
        date_capacity_overrides: z
          .record(z.string(), minutes.max(1440))
          .nullable()
          .optional(),
        target_school: z.string().max(200),
        target_program: z.string().max(200),
        /** 旧字段：目标日期存在时作为镜像写入，新数据不再依赖它们排程。 */
        exam_date: optionalDate,
        exam_end_date: optionalDate,
        daily_limit_minutes: minutes.max(1440),
        granularity_minutes: minutes.positive(),
        buffer_minutes: minutes,
        subject_limit_minutes: minutes,
        study_start_minute: minutes.max(1440),
        study_end_minute: minutes.max(1440),
        foundation: z.string().max(20000),
      })
      .passthrough(),
    subjects: z
      .array(
        z
          .object({
            ...owned,
            name: z.string().min(1).max(200),
            color: z.string().max(40),
            priority,
          })
          .passthrough(),
      )
      .max(1000),
    tasks: z
      .array(
        z
          .object({
            ...owned,
            ...timestamped,
            subject_id: id,
            title: z.string().min(1).max(200),
            description: z.string().max(20000).optional(),
            estimated_minutes: minutes.positive(),
            completed_minutes: minutes,
            priority,
            deadline: date,
            /** deadline 为真实截止日期，plan_end 为本期安排边界。 */
            deadline_kind: z.enum(["deadline", "plan_end"]).optional(),
            earliest_date: date.optional(),
            is_fixed: z.boolean(),
            status,
            planning: ItemPlanningSchema.nullable().optional(),
          })
          .passthrough(),
      )
      .max(10000),
    blocks: z.array(block).max(100000),
    logs: z
      .array(
        z
          .object({
            ...owned,
            /** 归属事项；学习记录必须归属正式事项（临时学习已删除）。 */
            task_id: id,
            block_id: id.nullable(),
            date,
            minutes,
            started_at: stamp,
            ended_at: stamp,
            source: z.enum(["timer", "manual"]),
            /** 计时发生时的执行关系；旧数据缺少时保留未知语义。 */
            relation: z.enum(["scheduled", "extra", "legacy_unknown"]).optional(),
            session_id: id.nullable().optional(),
            quota_minutes: minutes.optional(),
          })
          .passthrough(),
      )
      .max(100000),
    fixed_events: z
      .array(
        z
          .object({
            ...owned,
            ...timestamped,
            title: z.string().min(1).max(200),
            date,
            start_minute: minutes.max(1440),
            duration_minutes: minutes.positive(),
            kind: z.enum(["course", "exam", "rest", "official_exam"]),
            repeat: z.enum(["none", "daily", "weekly"]),
          })
          .passthrough(),
      )
      .max(10000),
    replan_runs: z
      .array(
        z
          .object({
            ...owned,
            created_at: stamp,
            before: z.array(block),
            after: z.array(block),
            changes: z.array(
              z
                .object({
                  ...owned,
                  run_id: id,
                  type: z.enum(["added", "deleted", "moved"]),
                  block_id: id,
                  before: block.nullable(),
                  after: block.nullable(),
                })
                .passthrough(),
            ),
            postponed: z.array(id),
            advanced: z.array(id),
            conflicts: z.array(
              z
                .object({
                  task_id: id,
                  title: z.string(),
                  minutes,
                  reason: z.string(),
                })
                .passthrough(),
            ),
            daily_changes: z.array(
              z
                .object({
                  date,
                  before_minutes: minutes,
                  after_minutes: minutes,
                })
                .passthrough(),
            ),
            status: z.enum(["confirmed", "undone"]),
          })
          .passthrough(),
      )
      .max(1000),
    phases: z
      .array(
        z
          .object({
            id,
            title: z.string(),
            start: date,
            end: date,
            description: z.string(),
          })
          .passthrough(),
      )
      .max(1000),
  })
  .passthrough()
  .superRefine((data, ctx) => {
    const owner = data.profile.user_id;
    const collections = [
      "subjects",
      "tasks",
      "blocks",
      "logs",
      "fixed_events",
      "replan_runs",
    ] as const;
    for (const key of collections) {
      const rows = data[key];
      const ids = new Set<string>();
      for (const row of rows) {
        if (ids.has(row.id) || row.user_id !== owner)
          ctx.addIssue({
            code: "custom",
            path: [key],
            message: "数据含重复标识或其他账号的数据",
          });
        ids.add(row.id);
      }
    }
    const subjects = new Set(data.subjects.map((row) => row.id));
    const tasks = new Set(data.tasks.map((row) => row.id));
    const blocks = new Map(data.blocks.map((row) => [row.id, row]));
    // 容量覆盖使用稳定落点：周覆盖键必须是周一日期，日期覆盖必须是有效日期。
    for (const monday of Object.keys(data.profile.week_capacity_overrides ?? {})) MondayKey.parse(monday);
    for (const day of Object.keys(data.profile.date_capacity_overrides ?? {})) date.parse(day);
    for (const task of data.tasks) {
      const workload = task.planning?.workload;
      if (data.planning && workload) {
        const calculated = Math.ceil(workload.components.filter(component => component.selected !== false)
          .reduce((sum, component) => sum + component.quantity * component.minutes_per_unit, 0));
        const expected = task.planning?.activity?.kind === "recurring" ? task.planning.activity.session_minutes : task.estimated_minutes;
        if (calculated !== expected)
          ctx.addIssue({ code: "custom", path: ["tasks", task.id, "planning", "workload"], message: "事项预算与结构化工作量不一致，请先修改工作量或重新评估" });
      }
      if (
        !subjects.has(task.subject_id) ||
        (task.earliest_date && task.earliest_date > task.deadline)
      )
        ctx.addIssue({
          code: "custom",
          path: ["tasks"],
          message: "事项引用或起止日期无效",
        });
      if (task.planning?.dependencies?.some(dependency => !tasks.has(dependency.task_id) || dependency.task_id === task.id))
        ctx.addIssue({ code: "custom", path: ["tasks", task.id, "planning", "dependencies"], message: "前置事项引用无效" });
    }
    const tasksById = new Map(data.tasks.map(task => [task.id, task]));
    const visiting = new Set<string>(), visited = new Set<string>();
    function hasCycle(id: string): boolean {
      if (visiting.has(id)) return true;
      if (visited.has(id)) return false;
      visiting.add(id);
      if (tasksById.get(id)?.planning?.dependencies?.some(dependency => hasCycle(dependency.task_id))) return true;
      visiting.delete(id);
      visited.add(id);
      return false;
    }
    if (data.tasks.some(task => hasCycle(task.id)))
      ctx.addIssue({ code: "custom", path: ["tasks"], message: "前置事项存在循环依赖" });
    for (const stage of data.planning?.route ?? []) {
      if (stage.item_ids.some(id => !tasks.has(id)) || (stage.start_date && stage.end_date && stage.start_date > stage.end_date))
        ctx.addIssue({ code: "custom", path: ["planning", "route", stage.id], message: "学习路线引用或日期无效" });
    }
    const instances = new Map<string, string>();
    for (const block of data.blocks) {
      if (!block.activity_instance_id) continue;
      const identity = `${block.task_id}:${block.activity_instance_id}`;
      if (instances.has(identity) && instances.get(identity) !== block.date)
        ctx.addIssue({ code: "custom", path: ["blocks", block.id], message: "同一活动实例不能重复安排到不同日期" });
      instances.set(identity, block.date);
    }
    for (const block of data.blocks)
      if (!tasks.has(block.task_id))
        ctx.addIssue({
          code: "custom",
          path: ["blocks"],
          message: "日程引用不存在的事项",
        });
    for (const log of data.logs) {
      const invalid =
        // 每条学习记录必须归属一个已存在的事项（临时学习已从服务端删除）。
        !tasks.has(log.task_id) ||
        (log.block_id !== null &&
          (!blocks.has(log.block_id) || blocks.get(log.block_id)!.task_id !== log.task_id)) ||
        (log.session_id !== undefined && log.session_id !== null && log.session_id.length === 0);
      if (invalid)
        ctx.addIssue({
          code: "custom",
          path: ["logs", log.id],
          message: "学习记录引用无效",
        });
    }
  });
export type PlannerDocument = z.infer<typeof PlannerDocumentSchema>;
