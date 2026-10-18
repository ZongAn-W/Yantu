-- AI 一键调整后续计划（PLAN_ADJUST_AI_DESIGN §2.4）。
--
-- 1) ai_jobs 保存在线预览：kind='plan_adjustment'、status='previewed'，
--    output_payload={base_revision, document, preview, ai}，确认后 status='confirmed'。
--    某些旧库还没有该表：这里按 db/schema.sql 的定义幂等建表（不修改 schema.sql）。
-- 2) plan_versions 需要记录 kind='adjust' 的调整历史；旧库的 check 约束只允许
--    draft/confirmed/replan，必须替换后才能写入。
-- 迁移只新增，不修改已应用的历史迁移；所有语句可重复执行。

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

create index if not exists ai_jobs_user_kind on ai_jobs(user_id, kind, created_at desc);

-- 新库可能只跑迁移而没有执行 db/schema.sql：同样幂等建表，避免 confirm 写入失败。
create table if not exists plan_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  kind text not null check (kind in ('draft','confirmed','replan')),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

alter table plan_versions drop constraint if exists plan_versions_kind_check;
alter table plan_versions add constraint plan_versions_kind_check
  check (kind in ('draft', 'confirmed', 'replan', 'adjust'));
