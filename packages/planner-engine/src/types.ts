export type TaskStatus =
  "not_started" | "in_progress" | "completed" | "delayed" | "conflict" | "archived";
export type Priority = 1 | 2 | 3;
export interface Tag {
  id: string;
  user_id: string;
  name: string;
  color?: string;
}
export interface Task {
  id: string;
  user_id: string;
  tag_ids: string[];
  title: string;
  /** Learning scope and completion criteria. */
  description?: string;
  estimated_minutes: number;
  completed_minutes: number;
  priority: Priority;
  deadline: string;
  /** deadline 为真实截止日期，plan_end 为本期安排边界。 */
  deadline_kind?: "deadline" | "plan_end";
  earliest_date?: string;
  is_fixed: boolean;
  status: TaskStatus;
  created_at: string;
  updated_at: string;
  planning?: import("../../../apps/api/src/planning-scheduler").StrategyTask["planning"];
}
export interface ScheduleBlock {
  id: string;
  user_id: string;
  task_id: string;
  date: string;
  /** Legacy timed-plan position; ignored as a placement constraint in daily mode. */
  start_minute: number;
  duration_minutes: number;
  actual_minutes: number;
  is_fixed: boolean;
  status: "planned" | "completed";
  created_at: string;
  updated_at: string;
  /** Optional server-generated daily learning guidance. */
  advice_text?: string;
  advice_topics?: string[];
  completion_status?: "not_started" | "partial" | "completed" | "skipped";
  feedback?: string;
  activity_instance_id?: string | null;
}
export interface TimeLog {
  id: string;
  user_id: string;
  task_id: string;
  block_id: string | null;
  date: string;
  minutes: number;
  started_at: string;
  ended_at: string;
  source: "timer" | "manual";
}
export interface FixedEvent {
  id: string;
  user_id: string;
  title: string;
  date: string;
  start_minute: number;
  duration_minutes: number;
  kind: "course" | "exam" | "rest" | "official_exam";
  repeat: "none" | "daily" | "weekly";
  created_at: string;
  updated_at: string;
}
export interface Profile {
  user_id: string;
  /** Missing values use daily plans; timed is retained for legacy plans. */
  planning_mode?: "daily" | "timed";
  target_school: string;
  target_program: string;
  /** 通用学习目标；旧数据可能没有这些字段。 */
  goal_text?: string;
  goal_type?: "exam" | "course" | "skill" | "self_study" | "other";
  goal_subtype?: string;
  target_date?: string;
  target_date_confirmed?: boolean;
  plan_start_date?: string;
  plan_end_date?: string;
  weekly_minutes?: Record<string, number>;
  constraints?: string;
  /** 旧字段：目标日期的历史镜像。 */
  exam_date?: string;
  exam_end_date?: string;
  daily_limit_minutes: number;
  granularity_minutes: number;
  buffer_minutes: number;
  study_start_minute: number;
  study_end_minute: number;
  foundation: string;
}
export interface Phase {
  id: string;
  title: string;
  start: string;
  end: string;
  description: string;
}
export interface ReplanChange {
  id: string;
  user_id: string;
  run_id: string;
  type: "added" | "deleted" | "moved";
  block_id: string;
  before: ScheduleBlock | null;
  after: ScheduleBlock | null;
}
export interface Conflict {
  task_id: string;
  title: string;
  minutes: number;
  reason: string;
}
export interface DayChange {
  date: string;
  before_minutes: number;
  after_minutes: number;
}
export interface ReplanPreview {
  id: string;
  user_id: string;
  created_at: string;
  before: ScheduleBlock[];
  after: ScheduleBlock[];
  changes: ReplanChange[];
  postponed: string[];
  advanced: string[];
  conflicts: Conflict[];
  daily_changes: DayChange[];
}
export interface ReplanRun extends ReplanPreview {
  status: "confirmed" | "undone";
}
export interface PlannerData {
  version: 1;
  profile: Profile;
  tags: Tag[];
  tasks: Task[];
  blocks: ScheduleBlock[];
  logs: TimeLog[];
  fixed_events: FixedEvent[];
  replan_runs: ReplanRun[];
  phases: Phase[];
  planning?: Record<string, unknown> | null;
}
export interface ReplanInput {
  tasks: Task[];
  blocks: ScheduleBlock[];
  logs: TimeLog[];
  fixed_events: FixedEvent[];
  profile: Profile;
  today: string;
  mode: "unfinished" | "overcompleted";
  excess_minutes?: number;
}
