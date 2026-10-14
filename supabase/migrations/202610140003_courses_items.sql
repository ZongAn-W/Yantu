-- Course IDs are user-defined; time belongs to individual items (tasks).
begin;
alter table public.subjects drop constraint if exists subjects_id_check;
alter table public.tasks drop constraint if exists tasks_valid_category;
alter table public.time_logs drop constraint if exists logs_valid_category;
drop trigger if exists tasks_category on public.tasks;
drop trigger if exists logs_category on public.time_logs;
commit;
