create extension if not exists pgcrypto;

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  username text,
  password_hash text not null,
  email_verified_at timestamptz,
  created_at timestamptz not null default now()
);

-- 通用学习目标与规划设置。exam_type / exam_date 只作为历史镜像保留。
create table if not exists profiles (
  user_id uuid primary key references users(id) on delete cascade,
  goal_text text not null default '',
  goal_type text not null default 'other' check (goal_type in ('exam','course','skill','self_study','other')),
  goal_subtype text not null default '',
  target_date date,
  target_date_confirmed boolean not null default false,
  plan_start_date date,
  plan_end_date date,
  exam_type text,
  exam_date date,
  target_school text not null default '',
  target_program text not null default '',
  current_progress text not null default '',
  weekly_minutes jsonb not null default '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"0":0}',
  constraints_text text not null default '',
  -- 灵活容量投影：文档 blob 权威，这些列只是镜像。缺失为旧数据，显式空对象表示清空覆盖。
  capacity_basis text,
  weekly_baseline_minutes integer,
  weekly_range_min_minutes integer,
  weekly_range_max_minutes integer,
  week_capacity_overrides jsonb,
  date_capacity_overrides jsonb,
  planning_metadata jsonb,
  updated_at timestamptz not null default now(),
  constraint profiles_capacity_basis_check
    check (capacity_basis is null or capacity_basis in ('gross_buffer','net')),
  constraint profiles_capacity_minutes_check check (
    (weekly_baseline_minutes is null or weekly_baseline_minutes between 0 and 10080)
    and (weekly_range_min_minutes is null or weekly_range_min_minutes between 0 and 10080)
    and (weekly_range_max_minutes is null or weekly_range_max_minutes between 0 and 10080)
  ),
  constraint profiles_capacity_overrides_shape_check check (
    (week_capacity_overrides is null or jsonb_typeof(week_capacity_overrides) = 'object')
    and (date_capacity_overrides is null or jsonb_typeof(date_capacity_overrides) = 'object')
  )
);

create table if not exists courses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name text not null,
  description text not null default '',
  priority smallint not null default 2 check (priority between 1 and 3),
  created_at timestamptz not null default now()
);

create table if not exists items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  course_id uuid not null references courses(id) on delete cascade,
  title text not null,
  description text not null default '',
  completion_criteria text not null default '',
  estimated_minutes integer not null check (estimated_minutes > 0),
  earliest_date date,
  deadline date not null,
  -- deadline 为真实截止日期，plan_end 为本期安排边界。
  deadline_kind text not null default 'deadline' check (deadline_kind in ('deadline','plan_end')),
  priority smallint not null default 2 check (priority between 1 and 3),
  confirmed boolean not null default false,
  status text not null default 'not_started',
  planning_metadata jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 临时学习实体：名称即可开始计时，不伪造预算/截止日期，也不进入正式排程队列。
create table if not exists ad_hoc_learnings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  title text not null check (title <> ''),
  -- 可选分类/课程归属；课程删除后保留实体本身，只清除失效引用。
  subject_id uuid references courses(id) on delete set null,
  archived boolean not null default false,
  -- 转为正式事项或关联已有事项后归档并记录目标事项；历史日志仍保留原引用。
  converted_task_id uuid references items(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists plan_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  kind text not null check (kind in ('draft','confirmed','replan')),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists daily_plan_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  item_id uuid not null references items(id) on delete cascade,
  date date not null,
  planned_minutes integer not null check (planned_minutes > 0),
  actual_minutes integer not null default 0 check (actual_minutes >= 0),
  advice_text text not null default '',
  advice_topics jsonb not null default '[]',
  activity_instance_id text,
  completion_status text not null default 'not_started' check (completion_status in ('not_started','partial','completed','skipped')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, item_id, date)
);

create table if not exists study_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  -- 临时学习没有正式事项：item_id 可空，ad_hoc_id 指向临时学习实体。
  item_id uuid references items(id) on delete cascade,
  -- restrict：删除临时学习实体不能无声带走真实学习分钟；归档用 archived=true。
  ad_hoc_id uuid references ad_hoc_learnings(id) on delete restrict,
  daily_plan_item_id uuid references daily_plan_items(id) on delete set null,
  date date not null,
  minutes integer not null check (minutes >= 0),
  -- 计时发生时的执行关系，与记录方式 source 正交；旧数据保留 legacy_unknown。
  relation text not null default 'legacy_unknown'
    constraint study_logs_relation_check check (relation in ('scheduled','extra','ad_hoc','legacy_unknown')),
  -- 同一次开始到暂停（含跨零点拆分）的稳定会话标识。
  session_id text,
  -- 原定学习开始时可计入该事项当日达成的额度（分钟）。
  quota_minutes integer
    constraint study_logs_quota_minutes_check check (quota_minutes is null or quota_minutes >= 0),
  feedback text not null default '',
  created_at timestamptz not null default now(),
  -- 每条记录必须能归属到正式事项或临时学习之一；转为正式事项后仍保留 ad_hoc_id。
  constraint study_logs_owner_check check (num_nonnulls(item_id, ad_hoc_id) >= 1)
);

create table if not exists daily_reviews (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  date date not null,
  feedback text not null default '',
  result jsonb not null default '{}',
  settled_at timestamptz not null default now(),
  unique (user_id, date)
);

create table if not exists replan_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  date date not null,
  before_payload jsonb not null,
  after_payload jsonb not null,
  explanation text not null default '',
  undone_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists ai_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  kind text not null,
  status text not null default 'running',
  request_id text,
  input_payload jsonb not null,
  output_payload jsonb,
  error_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists daily_plan_user_date on daily_plan_items(user_id, date);
create index if not exists logs_user_date on study_logs(user_id, date);
-- 旧库的 study_logs 可能还没有 ad_hoc_id 列（迁移会补），因此该部分索引只在
-- 迁移 202610200001 中创建，避免建库脚本在“迁移前”的数据库上失败。
create index if not exists ad_hoc_learnings_user
  on ad_hoc_learnings(user_id, archived, created_at);
create index if not exists items_user_deadline on items(user_id, deadline);
create index if not exists daily_plan_activity_instance
  on daily_plan_items(user_id, item_id, activity_instance_id)
  where activity_instance_id is not null;
