-- Upgrade existing payload plans to the daily workload model. Study work is
-- identified by date and duration; fixed events retain their concrete times.
begin;

alter table public.profiles
  add column if not exists planning_mode text generated always as (coalesce(payload ->> 'planning_mode', 'daily')) stored;

create or replace function public.dailyize_block_array(p_blocks jsonb)
returns jsonb language sql immutable as $$
  select coalesce(jsonb_agg(case
    when block ->> 'status' = 'completed' or coalesce((block ->> 'is_fixed')::boolean, false)
      then block
    else jsonb_set(block, '{start_minute}', '0'::jsonb, true)
  end), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_blocks, '[]'::jsonb)) as entries(block);
$$;

create or replace function public.dailyize_planner_data(p_data jsonb)
returns jsonb language plpgsql immutable as $$
declare
  normalized jsonb := jsonb_set(p_data, '{profile,planning_mode}', '"daily"'::jsonb, true);
  block_item jsonb;
  blocks jsonb := '[]'::jsonb;
begin
  for block_item in select value from jsonb_array_elements(coalesce(normalized -> 'blocks', '[]'::jsonb)) loop
    if block_item ->> 'status' <> 'completed'
      and not coalesce((block_item ->> 'is_fixed')::boolean, false)
      and not exists (
      select 1 from jsonb_array_elements(coalesce(p_data -> 'tasks', '[]'::jsonb)) as tasks(task)
        where task ->> 'id' = block_item ->> 'task_id'
          and coalesce((task ->> 'is_fixed')::boolean, false)
      ) then
      block_item := jsonb_set(block_item, '{start_minute}', '0'::jsonb, true);
    end if;
    blocks := blocks || jsonb_build_array(block_item);
  end loop;
  return jsonb_set(normalized, '{blocks}', blocks, true);
end;
$$;

create or replace function public.enforce_daily_profile()
returns trigger language plpgsql as $$
begin
  new.payload := jsonb_set(new.payload, '{planning_mode}', '"daily"'::jsonb, true);
  return new;
end;
$$;

create or replace function public.enforce_daily_block()
returns trigger language plpgsql as $$
begin
  if new.payload ->> 'status' <> 'completed'
    and not coalesce((new.payload ->> 'is_fixed')::boolean, false)
    and not exists (
      select 1 from public.tasks
      where user_id = new.user_id and id = (new.payload ->> 'task_id')::uuid and is_fixed
    ) then
    new.payload := jsonb_set(new.payload, '{start_minute}', '0'::jsonb, true);
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_daily_mode on public.profiles;
create trigger profiles_daily_mode before insert or update of payload on public.profiles
  for each row execute function public.enforce_daily_profile();
drop trigger if exists schedule_blocks_daily_mode on public.schedule_blocks;
create trigger schedule_blocks_daily_mode before insert or update of payload on public.schedule_blocks
  for each row execute function public.enforce_daily_block();

-- Backfill before adding the constraint so existing timed plans remain valid.
update public.profiles
  set payload = jsonb_set(payload, '{planning_mode}', '"daily"'::jsonb, true)
  where payload ->> 'planning_mode' is distinct from 'daily';
update public.schedule_blocks
  set payload = jsonb_set(payload, '{start_minute}', '0'::jsonb, true)
  where payload ->> 'start_minute' is distinct from '0'
    and status <> 'completed' and not is_fixed
    and not exists (
      select 1 from public.tasks t
      where t.user_id = schedule_blocks.user_id and t.id = schedule_blocks.task_id and t.is_fixed
    );
-- Completed blocks, fixed events, replan_runs and replan_changes are immutable
-- historical data. Their original start_minute fields are never backfilled.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass and conname = 'profiles_daily_plan_only'
  ) then
    alter table public.profiles add constraint profiles_daily_plan_only check (planning_mode = 'daily');
  end if;
end $$;

revoke all on function public.dailyize_block_array(jsonb) from public, anon;
revoke all on function public.dailyize_planner_data(jsonb) from public, anon;
revoke all on function public.enforce_daily_profile() from public, anon;
revoke all on function public.enforce_daily_block() from public, anon;
grant execute on function public.dailyize_block_array(jsonb) to authenticated;
grant execute on function public.dailyize_planner_data(jsonb) to authenticated;
commit;
