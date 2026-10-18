-- 学习执行关系、临时学习与灵活容量投影。
--
-- 权威数据仍是 planner_sync_state.document（JSON blob）；这里的表/列是关系投影：
-- 用于跨设备读取、条件查询与旧接口兼容。缺失字段按旧语义处理，null/显式空表示清空。
-- 迁移只新增，不修改已应用的历史迁移；所有语句可重复执行。

-- 1) 临时学习实体：名称即可开始计时，不伪造预算/截止日期，也不进入正式排程队列。
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

create index if not exists ad_hoc_learnings_user
  on ad_hoc_learnings(user_id, archived, created_at);

-- 2) 学习日志：执行关系（scheduled/extra/ad_hoc/legacy_unknown）与记录方式（source）正交。
--    临时学习没有正式事项，item_id 必须可为空；每条记录仍必须能归属到正式事项或临时学习之一。
alter table study_logs alter column item_id drop not null;
-- 旧数据缺失执行关系时保留 legacy_unknown，不擅自推断成原定学习或临时学习。
alter table study_logs add column if not exists relation text not null default 'legacy_unknown';
alter table study_logs add column if not exists session_id text;
-- restrict：删除临时学习实体本身不能无声带走真实学习分钟；
-- 正常归档用 archived=true。文档合法删除时必须先删日志再删实体（sync 已按此顺序）。
alter table study_logs add column if not exists ad_hoc_id uuid references ad_hoc_learnings(id) on delete restrict;
alter table study_logs add column if not exists quota_minutes integer;

alter table study_logs drop constraint if exists study_logs_relation_check;
alter table study_logs add constraint study_logs_relation_check
  check (relation in ('scheduled', 'extra', 'ad_hoc', 'legacy_unknown'));

alter table study_logs drop constraint if exists study_logs_quota_minutes_check;
alter table study_logs add constraint study_logs_quota_minutes_check
  check (quota_minutes is null or quota_minutes >= 0);

-- 两类归属至少要有一个；转为正式事项后 ad_hoc_id 仍保留，用于解释历史关系。
alter table study_logs drop constraint if exists study_logs_owner_check;
alter table study_logs add constraint study_logs_owner_check
  check (num_nonnulls(item_id, ad_hoc_id) >= 1);

create index if not exists logs_user_ad_hoc
  on study_logs(user_id, date) where ad_hoc_id is not null;

-- 3) Profile 容量投影：文档 blob 权威，这些列是投影镜像。
--    缺失（null）= 旧数据/未设置；显式空对象 = 用户清空覆盖；显式 0 是有效容量（休息日）。
alter table profiles add column if not exists capacity_basis text;
alter table profiles add column if not exists weekly_baseline_minutes integer;
alter table profiles add column if not exists weekly_range_min_minutes integer;
alter table profiles add column if not exists weekly_range_max_minutes integer;
alter table profiles add column if not exists week_capacity_overrides jsonb;
alter table profiles add column if not exists date_capacity_overrides jsonb;

alter table profiles drop constraint if exists profiles_capacity_basis_check;
alter table profiles add constraint profiles_capacity_basis_check
  check (capacity_basis is null or capacity_basis in ('gross_buffer', 'net'));

alter table profiles drop constraint if exists profiles_capacity_minutes_check;
alter table profiles add constraint profiles_capacity_minutes_check check (
  (weekly_baseline_minutes is null or weekly_baseline_minutes between 0 and 10080)
  and (weekly_range_min_minutes is null or weekly_range_min_minutes between 0 and 10080)
  and (weekly_range_max_minutes is null or weekly_range_max_minutes between 0 and 10080)
);

alter table profiles drop constraint if exists profiles_capacity_overrides_shape_check;
alter table profiles add constraint profiles_capacity_overrides_shape_check check (
  (week_capacity_overrides is null or jsonb_typeof(week_capacity_overrides) = 'object')
  and (date_capacity_overrides is null or jsonb_typeof(date_capacity_overrides) = 'object')
);

-- 4) 新表的 revision 触发器。
--    旧迁移 202610160003 的触发器表数组已冻结（不能改已应用迁移），因此这里单独创建。
--    planner_touch_revision() 由 202610160003 定义；本迁移按文件名顺序总是后执行。
drop trigger if exists planner_sync_revision on ad_hoc_learnings;
create trigger planner_sync_revision
  after insert or update or delete on ad_hoc_learnings
  for each row execute function planner_touch_revision();
