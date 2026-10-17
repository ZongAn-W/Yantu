create table if not exists planner_sync_state (
  user_id uuid primary key references users(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0),
  document jsonb,
  projection jsonb,
  updated_at timestamptz not null default now()
);

create or replace function planner_touch_revision() returns trigger language plpgsql as $$
declare owner_id uuid;
begin
  if TG_OP = 'DELETE' then owner_id := OLD.user_id; else owner_id := NEW.user_id; end if;
  insert into planner_sync_state(user_id, revision) values(owner_id, 1)
    on conflict(user_id) do update set revision=planner_sync_state.revision+1,updated_at=now();
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end $$;

do $$ declare table_name text;
begin
  foreach table_name in array array['profiles','courses','items','daily_plan_items','study_logs','daily_reviews','replan_runs','plan_versions'] loop
    execute format('create trigger planner_sync_revision after insert or update or delete on %I for each row execute function planner_touch_revision()', table_name);
  end loop;
end $$;
