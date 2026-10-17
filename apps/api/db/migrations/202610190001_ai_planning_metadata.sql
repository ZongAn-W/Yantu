-- Missing metadata retains legacy finite-budget semantics; no historical inference.
alter table profiles add column if not exists planning_metadata jsonb;
alter table items add column if not exists planning_metadata jsonb;
alter table daily_plan_items add column if not exists activity_instance_id text;

create index if not exists daily_plan_activity_instance
  on daily_plan_items(user_id, item_id, activity_instance_id)
  where activity_instance_id is not null;
