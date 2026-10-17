create table if not exists auth_refresh_tokens (
  user_id uuid not null references users(id) on delete cascade,
  jti uuid primary key,
  token_hash text not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists auth_refresh_tokens_user_active
  on auth_refresh_tokens(user_id, expires_at)
  where revoked_at is null;
