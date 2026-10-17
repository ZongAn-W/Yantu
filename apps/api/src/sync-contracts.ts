import { z } from "zod";

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
  })
  .passthrough();
export const PlannerDocumentSchema = z
  .object({
    version: z.literal(1),
    profile: z
      .object({
        user_id: id,
        planning_mode: z.enum(["daily", "timed"]).optional(),
        target_school: z.string().max(200),
        target_program: z.string().max(200),
        exam_date: date,
        exam_end_date: date,
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
            earliest_date: date.optional(),
            is_fixed: z.boolean(),
            status,
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
            task_id: id,
            block_id: id.nullable(),
            date,
            minutes,
            started_at: stamp,
            ended_at: stamp,
            source: z.enum(["timer", "manual"]),
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
      const ids = new Set<string>();
      for (const row of data[key]) {
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
    for (const task of data.tasks) {
      if (
        !subjects.has(task.subject_id) ||
        (task.earliest_date && task.earliest_date > task.deadline)
      )
        ctx.addIssue({
          code: "custom",
          path: ["tasks"],
          message: "事项引用或起止日期无效",
        });
    }
    for (const block of data.blocks)
      if (!tasks.has(block.task_id))
        ctx.addIssue({
          code: "custom",
          path: ["blocks"],
          message: "日程引用不存在的事项",
        });
    for (const log of data.logs)
      if (
        !tasks.has(log.task_id) ||
        (log.block_id &&
          (!blocks.has(log.block_id) ||
            blocks.get(log.block_id)!.task_id !== log.task_id))
      )
        ctx.addIssue({
          code: "custom",
          path: ["logs"],
          message: "学习记录引用无效",
        });
  });
export type PlannerDocument = z.infer<typeof PlannerDocumentSchema>;
