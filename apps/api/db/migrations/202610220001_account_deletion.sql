-- Wrong-password limits are shared across API instances and cleared with the account.
create table if not exists account_deletion_attempts (
  user_id uuid primary key references users(id) on delete cascade,
  attempts integer not null default 0 check (attempts >= 0),
  window_started_at timestamptz not null default now()
);

-- Cascaded child deletes run after the parent users row has disappeared. They
-- must not recreate planner_sync_state and violate its user foreign key.
create or replace function planner_touch_revision() returns trigger language plpgsql as $$
declare owner_id uuid;
begin
  if TG_OP = 'DELETE' then owner_id := OLD.user_id; else owner_id := NEW.user_id; end if;
  if exists(select 1 from users where id=owner_id) then
    insert into planner_sync_state(user_id, revision) values(owner_id, 1)
      on conflict(user_id) do update set revision=planner_sync_state.revision+1,updated_at=now();
  end if;
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end $$;
