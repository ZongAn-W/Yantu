export type SubjectId = string;
export type TaskStatus =
  "not_started" | "in_progress" | "completed" | "delayed" | "conflict";
export type Priority = 1 | 2 | 3;
export interface Subject {
  id: SubjectId;
  user_id: string;
  name: string;
  color: string;
  priority: Priority;
}
export interface Task {
  id: string;
  user_id: string;
  subject_id: SubjectId;
  title: string;
  /** Scope and completion criteria for this course item. */
  description?: string;
  estimated_minutes: number;
  completed_minutes: number;
  priority: Priority;
  deadline: string;
  earliest_date?: string;
  is_fixed: boolean;
  status: TaskStatus;
  created_at: string;
  updated_at: string;
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
  exam_date: string;
  exam_end_date: string;
  daily_limit_minutes: number;
  granularity_minutes: number;
  buffer_minutes: number;
  subject_limit_minutes: number;
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
  subjects: Subject[];
  tasks: Task[];
  blocks: ScheduleBlock[];
  logs: TimeLog[];
  fixed_events: FixedEvent[];
  replan_runs: ReplanRun[];
  phases: Phase[];
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
