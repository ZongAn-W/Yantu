create table if not exists onboarding_sessions (
  user_id uuid primary key references users(id) on delete cascade,
  revision integer not null default 0,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);
