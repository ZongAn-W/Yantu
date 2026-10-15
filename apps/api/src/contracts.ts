import { z } from "zod";

export const WeeklyMinutesSchema = z.record(z.string(), z.number().int().min(0).max(1440));
export const ProfileSchema = z.object({
  exam_type: z.enum(["考研", "考公", "其他"]),
  exam_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  target_school: z.string().max(200).default(""),
  target_program: z.string().max(200).default(""),
  current_progress: z.string().max(4000).default(""),
  weekly_minutes: WeeklyMinutesSchema.default({ "0": 0, "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, "6": 0 }),
  constraints_text: z.string().max(4000).default(""),
});

export const CourseDraftSchema = z.object({
  id: z.string().min(1).max(80),
  name: z.string().min(1).max(100),
  description: z.string().max(1000).default(""),
  priority: z.number().int().min(1).max(3).default(2),
});

export const ItemDraftSchema = z.object({
  id: z.string().min(1).max(80),
  course_id: z.string().min(1).max(80),
  title: z.string().min(1).max(200),
  description: z.string().max(4000).default(""),
  completion_criteria: z.string().max(1000).default(""),
  estimated_minutes: z.number().int().min(30).max(100000),
  earliest_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  deadline: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  priority: z.number().int().min(1).max(3).default(2),
});

export const PlanDraftSchema = z.object({
  courses: z.array(CourseDraftSchema).min(1).max(100),
  items: z.array(ItemDraftSchema).min(1).max(500),
  analysis_summary: z.string().max(4000),
  assumptions: z.array(z.string().max(500)).max(20).default([]),
  warnings: z.array(z.string().max(500)).max(20).default([]),
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
