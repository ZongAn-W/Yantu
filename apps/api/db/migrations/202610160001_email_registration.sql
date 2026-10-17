alter table users add column if not exists username text;
alter table users add column if not exists email_verified_at timestamptz;

update users set username = 'user_' || replace(id::text, '-', '') where username is null;
alter table users alter column username set not null;
create unique index if not exists users_username_lower on users(lower(username));
create unique index if not exists users_email_lower on users(lower(email));

create table if not exists registration_codes (
  email text primary key,
  code_hash text not null,
  expires_at timestamptz not null,
  sent_at timestamptz not null,
  window_started_at timestamptz not null,
  sends_in_window integer not null default 1,
  attempts integer not null default 0,
  consumed boolean not null default false
);
