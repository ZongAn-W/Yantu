-- SJTU study planner: single-user plans isolated by Supabase Auth user.
-- The JSON payload is the versioned TypeScript record, while important fields
-- are exposed as generated relational columns for indexing and reporting.
begin;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  phases jsonb not null default '[]'::jsonb check (jsonb_typeof(phases) = 'array'),
  revision bigint not null default 0,
  target_school text generated always as (payload ->> 'target_school') stored,
  target_program text generated always as (payload ->> 'target_program') stored,
  exam_date text generated always as (payload ->> 'exam_date') stored,
  exam_end_date text generated always as (payload ->> 'exam_end_date') stored,
  planning_mode text generated always as (coalesce(payload ->> 'planning_mode', 'daily')) stored,
  daily_limit_minutes integer generated always as ((payload ->> 'daily_limit_minutes')::integer) stored,
  granularity_minutes integer generated always as ((payload ->> 'granularity_minutes')::integer) stored,
  updated_at timestamptz not null default now(),
  check (payload ->> 'user_id' = user_id::text),
  check (daily_limit_minutes between 30 and 480),
  check (granularity_minutes = 30),
  check (planning_mode = 'daily')
);

create table public.subjects (
  user_id uuid not null references auth.users(id) on delete cascade,
  id text not null check (id in ('math', 'english', 'cs', 'politics')),
  payload jsonb not null,
  name text generated always as (payload ->> 'name') stored,
  priority integer generated always as ((payload ->> 'priority')::integer) stored,
  color text generated always as (payload ->> 'color') stored,
  primary key (user_id, id),
  check (payload ->> 'id' = id and payload ->> 'user_id' = user_id::text),
  check (priority between 1 and 3)
);

create table public.tasks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  subject_id text generated always as (payload ->> 'subject_id') stored,
  title text generated always as (payload ->> 'title') stored,
  estimated_minutes integer generated always as ((payload ->> 'estimated_minutes')::integer) stored,
  completed_minutes integer generated always as ((payload ->> 'completed_minutes')::integer) stored,
  priority integer generated always as ((payload ->> 'priority')::integer) stored,
  deadline text generated always as (payload ->> 'deadline') stored,
  earliest_date text generated always as (payload ->> 'earliest_date') stored,
  is_fixed boolean generated always as ((payload ->> 'is_fixed')::boolean) stored,
  status text generated always as (payload ->> 'status') stored,
  created_at text generated always as (payload ->> 'created_at') stored,
  updated_at text generated always as (payload ->> 'updated_at') stored,
  unique (user_id, id),
  foreign key (user_id, subject_id) references public.subjects(user_id, id) on delete cascade,
  check (payload ->> 'id' = id::text and payload ->> 'user_id' = user_id::text),
  check (estimated_minutes > 0 and completed_minutes between 0 and estimated_minutes),
  check (priority between 1 and 3),
  check (status in ('not_started', 'in_progress', 'completed', 'delayed', 'conflict'))
);

create table public.schedule_blocks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  task_id uuid generated always as ((payload ->> 'task_id')::uuid) stored,
  date text generated always as (payload ->> 'date') stored,
  start_minute integer generated always as ((payload ->> 'start_minute')::integer) stored,
  duration_minutes integer generated always as ((payload ->> 'duration_minutes')::integer) stored,
  actual_minutes integer generated always as ((payload ->> 'actual_minutes')::integer) stored,
  is_fixed boolean generated always as ((payload ->> 'is_fixed')::boolean) stored,
  status text generated always as (payload ->> 'status') stored,
  created_at text generated always as (payload ->> 'created_at') stored,
  updated_at text generated always as (payload ->> 'updated_at') stored,
  unique (user_id, id),
  foreign key (user_id, task_id) references public.tasks(user_id, id) on delete cascade,
  check (payload ->> 'id' = id::text and payload ->> 'user_id' = user_id::text),
  check (start_minute between 0 and 1439 and duration_minutes > 0 and start_minute + duration_minutes <= 1440),
  check (actual_minutes >= 0),
  check (status in ('planned', 'completed'))
);

create table public.time_logs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  task_id uuid generated always as ((payload ->> 'task_id')::uuid) stored,
  block_id uuid generated always as ((payload ->> 'block_id')::uuid) stored,
  date text generated always as (payload ->> 'date') stored,
  minutes integer generated always as ((payload ->> 'minutes')::integer) stored,
  started_at text generated always as (payload ->> 'started_at') stored,
  ended_at text generated always as (payload ->> 'ended_at') stored,
  source text generated always as (payload ->> 'source') stored,
  foreign key (user_id, task_id) references public.tasks(user_id, id) on delete cascade,
  foreign key (user_id, block_id) references public.schedule_blocks(user_id, id),
  check (payload ->> 'id' = id::text and payload ->> 'user_id' = user_id::text),
  check (minutes >= 0),
  check (source in ('timer', 'manual'))
);

create table public.fixed_events (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  title text generated always as (payload ->> 'title') stored,
  date text generated always as (payload ->> 'date') stored,
  start_minute integer generated always as ((payload ->> 'start_minute')::integer) stored,
  duration_minutes integer generated always as ((payload ->> 'duration_minutes')::integer) stored,
  kind text generated always as (payload ->> 'kind') stored,
  repeat text generated always as (payload ->> 'repeat') stored,
  created_at text generated always as (payload ->> 'created_at') stored,
  updated_at text generated always as (payload ->> 'updated_at') stored,
  check (payload ->> 'id' = id::text and payload ->> 'user_id' = user_id::text),
  check (start_minute between 0 and 1439 and duration_minutes > 0 and start_minute + duration_minutes <= 1440),
  check (kind in ('course', 'exam', 'rest', 'official_exam')),
  check (repeat in ('none', 'daily', 'weekly'))
);

create table public.replan_runs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  status text generated always as (payload ->> 'status') stored,
  created_at text generated always as (payload ->> 'created_at') stored,
  unique (user_id, id),
  check (payload ->> 'id' = id::text and payload ->> 'user_id' = user_id::text),
  check (status in ('confirmed', 'undone')),
  check (jsonb_typeof(payload -> 'before') = 'array' and jsonb_typeof(payload -> 'after') = 'array' and jsonb_typeof(payload -> 'changes') = 'array')
);

create table public.replan_changes (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  payload jsonb not null,
  run_id uuid generated always as ((payload ->> 'run_id')::uuid) stored,
  block_id uuid generated always as ((payload ->> 'block_id')::uuid) stored,
  type text generated always as (payload ->> 'type') stored,
  foreign key (user_id, run_id) references public.replan_runs(user_id, id) on delete cascade,
  check (payload ->> 'id' = id::text and payload ->> 'user_id' = user_id::text),
  check (type in ('added', 'deleted', 'moved'))
);

-- A change record may refer to a block that was deleted as part of a replan,
-- so its before/after snapshots remain JSON. Reject snapshots that carry a
-- different account owner before they can enter the history tables.
create or replace function public.validate_replan_owner(p_payload jsonb, p_user uuid)
returns boolean language sql immutable as $$
  select not jsonb_path_exists(
    p_payload,
    '$.**.user_id ? (@ != $owner)',
    jsonb_build_object('owner', to_jsonb(p_user::text))
  );
$$;
revoke all on function public.validate_replan_owner(jsonb, uuid) from public, anon;
grant execute on function public.validate_replan_owner(jsonb, uuid) to authenticated;

-- Daily workload entries carry a date and duration, never a reserved clock slot.
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
  -- Fixed events and every replan before/after snapshot are deliberately kept.
  return jsonb_set(normalized, '{blocks}', blocks, true);
end;
$$;
revoke all on function public.dailyize_block_array(jsonb) from public, anon;
revoke all on function public.dailyize_planner_data(jsonb) from public, anon;
grant execute on function public.dailyize_block_array(jsonb) to authenticated;
grant execute on function public.dailyize_planner_data(jsonb) to authenticated;

create index tasks_user_deadline on public.tasks(user_id, deadline, priority desc);
create index blocks_user_date on public.schedule_blocks(user_id, date, start_minute);
create index logs_user_date on public.time_logs(user_id, date);
create index events_user_date on public.fixed_events(user_id, date);
create index changes_user_run on public.replan_changes(user_id, run_id);

-- Every table is owner-only, including history snapshots. No anonymous policies.
do $$
declare table_name text;
begin
  foreach table_name in array array['profiles','subjects','tasks','schedule_blocks','time_logs','fixed_events','replan_runs','replan_changes'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('create policy owner_only on public.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
    execute format('alter table public.%I replica identity full', table_name);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = table_name) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
  end loop;
end $$;

-- One statement gives a consistent snapshot of the complete graph.
create or replace function public.load_planner_state()
returns jsonb language sql stable security invoker set search_path = public, pg_temp as $$
  select coalesce((select jsonb_build_object(
    'revision', p.revision,
    'data', jsonb_build_object(
      'version', 1, 'profile', p.payload, 'phases', p.phases,
      'subjects', coalesce((select jsonb_agg(s.payload order by s.id) from subjects s where s.user_id = auth.uid()), '[]'::jsonb),
      'tasks', coalesce((select jsonb_agg(t.payload order by t.id) from tasks t where t.user_id = auth.uid()), '[]'::jsonb),
      'blocks', coalesce((select jsonb_agg(b.payload order by b.date, b.start_minute, b.id) from schedule_blocks b where b.user_id = auth.uid()), '[]'::jsonb),
      'logs', coalesce((select jsonb_agg(l.payload order by l.ended_at, l.id) from time_logs l where l.user_id = auth.uid()), '[]'::jsonb),
      'fixed_events', coalesce((select jsonb_agg(e.payload order by e.date, e.start_minute, e.id) from fixed_events e where e.user_id = auth.uid()), '[]'::jsonb),
      'replan_runs', coalesce((select jsonb_agg(r.payload order by r.created_at, r.id) from replan_runs r where r.user_id = auth.uid()), '[]'::jsonb)
    )) from profiles p where p.user_id = auth.uid()), jsonb_build_object('revision', 0, 'data', null));
$$;

-- Compare-and-swap plus a per-user row lock makes confirmed replans and undo
-- atomic across all eight tables. The client rebases independent device edits.
create or replace function public.save_planner_state(p_data jsonb, p_expected_revision bigint)
returns jsonb language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  actor uuid := auth.uid();
  current_revision bigint;
  item jsonb;
  run_item jsonb;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if p_data ->> 'version' <> '1' or jsonb_typeof(p_data -> 'profile') <> 'object' then
    raise exception 'Invalid planner data';
  end if;
  if p_data -> 'profile' ->> 'user_id' is distinct from actor::text then
    raise exception 'Planner owner mismatch';
  end if;
  p_data := public.dailyize_planner_data(p_data);
  foreach item in array array[p_data -> 'subjects', p_data -> 'tasks', p_data -> 'blocks', p_data -> 'logs', p_data -> 'fixed_events', p_data -> 'replan_runs', p_data -> 'phases'] loop
    if jsonb_typeof(item) is distinct from 'array' then raise exception 'Invalid planner collection'; end if;
  end loop;

  insert into profiles(user_id, payload, phases, revision) values(actor, p_data -> 'profile', p_data -> 'phases', 0)
    on conflict (user_id) do nothing;
  select revision into current_revision from profiles where user_id = actor for update;
  if current_revision is distinct from p_expected_revision then
    raise exception 'PLANNER_REVISION_CONFLICT';
  end if;

  -- These are the account's database rows, not filesystem files. Transactional
  -- replacement keeps deleted tasks and undo snapshots consistent and bounded.
  delete from time_logs where user_id = actor;
  delete from schedule_blocks where user_id = actor;
  delete from replan_changes where user_id = actor;
  delete from replan_runs where user_id = actor;
  delete from tasks where user_id = actor;
  delete from subjects where user_id = actor;
  delete from fixed_events where user_id = actor;

  for item in select value from jsonb_array_elements(p_data -> 'subjects') loop
    insert into subjects(user_id, id, payload) values(actor, item ->> 'id', jsonb_set(item, '{user_id}', to_jsonb(actor::text)));
  end loop;
  for item in select value from jsonb_array_elements(p_data -> 'tasks') loop
    insert into tasks(user_id, id, payload) values(actor, (item ->> 'id')::uuid, jsonb_set(item, '{user_id}', to_jsonb(actor::text)));
  end loop;
  for item in select value from jsonb_array_elements(p_data -> 'blocks') loop
    insert into schedule_blocks(user_id, id, payload) values(actor, (item ->> 'id')::uuid, jsonb_set(item, '{user_id}', to_jsonb(actor::text)));
  end loop;
  for item in select value from jsonb_array_elements(p_data -> 'logs') loop
    insert into time_logs(user_id, id, payload) values(actor, (item ->> 'id')::uuid, jsonb_set(item, '{user_id}', to_jsonb(actor::text)));
  end loop;
  for item in select value from jsonb_array_elements(p_data -> 'fixed_events') loop
    insert into fixed_events(user_id, id, payload) values(actor, (item ->> 'id')::uuid, jsonb_set(item, '{user_id}', to_jsonb(actor::text)));
  end loop;
  for run_item in select value from jsonb_array_elements(p_data -> 'replan_runs') loop
    if not public.validate_replan_owner(run_item, actor) then raise exception 'Replan snapshot owner mismatch'; end if;
    if jsonb_typeof(run_item -> 'changes') is distinct from 'array' then raise exception 'Invalid replan changes'; end if;
    insert into replan_runs(user_id, id, payload) values(actor, (run_item ->> 'id')::uuid, jsonb_set(run_item, '{user_id}', to_jsonb(actor::text)));
    for item in select value from jsonb_array_elements(run_item -> 'changes') loop
      if not public.validate_replan_owner(item, actor) then raise exception 'Replan change owner mismatch'; end if;
      if item ->> 'run_id' is distinct from run_item ->> 'id' then raise exception 'Replan change run mismatch'; end if;
      insert into replan_changes(user_id, id, payload) values(actor, (item ->> 'id')::uuid, jsonb_set(item, '{user_id}', to_jsonb(actor::text)));
    end loop;
  end loop;
  update profiles set payload = p_data -> 'profile', phases = p_data -> 'phases', revision = current_revision + 1, updated_at = now() where user_id = actor;
  return jsonb_build_object('revision', current_revision + 1);
end;
$$;

revoke all on function public.load_planner_state() from public, anon;
revoke all on function public.save_planner_state(jsonb, bigint) from public, anon;
grant execute on function public.load_planner_state() to authenticated;
grant execute on function public.save_planner_state(jsonb, bigint) to authenticated;
commit;
