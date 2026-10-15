create extension if not exists pgcrypto;

create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  password_hash text not null,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  user_id uuid primary key references users(id) on delete cascade,
  exam_type text not null default '考研',
  exam_date date not null,
  target_school text not null default '',
  target_program text not null default '',
  current_progress text not null default '',
  weekly_minutes jsonb not null default '{"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"0":0}',
  constraints_text text not null default '',
  updated_at timestamptz not null default now()
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
  priority smallint not null default 2 check (priority between 1 and 3),
  confirmed boolean not null default false,
  status text not null default 'not_started',
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
  completion_status text not null default 'not_started' check (completion_status in ('not_started','partial','completed','skipped')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, item_id, date)
);

create table if not exists study_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  item_id uuid not null references items(id) on delete cascade,
  daily_plan_item_id uuid references daily_plan_items(id) on delete set null,
  date date not null,
  minutes integer not null check (minutes >= 0),
  feedback text not null default '',
  created_at timestamptz not null default now()
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
create index if not exists items_user_deadline on items(user_id, deadline);
