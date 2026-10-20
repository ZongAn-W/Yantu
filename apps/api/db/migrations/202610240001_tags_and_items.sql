-- Replace the legacy course/item ownership model with optional many-to-many tags.
-- Preserve items and all execution facts; invalid or cross-owner legacy references become untagged.

create table if not exists tags (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tags_user_name_unique unique (user_id, name)
);

create unique index if not exists tags_user_normalized_name_unique
  on tags (user_id, lower(btrim(name)));
create unique index if not exists tags_id_user_unique on tags(id, user_id);
create unique index if not exists items_id_user_unique on items(id, user_id);

-- Keep the earliest legacy course with each normalized name as the stable tag identity.
do $$ begin
  if to_regclass('courses') is not null then
    execute $sql$
      insert into tags(id, user_id, name, created_at, updated_at)
      select distinct on (course.user_id, lower(btrim(course.name)))
        course.id, course.user_id, btrim(course.name), course.created_at, course.created_at
      from courses course
      where btrim(course.name) <> ''
      order by course.user_id, lower(btrim(course.name)), course.created_at, course.id
      on conflict (user_id, lower(btrim(name))) do nothing
    $sql$;
  end if;
end $$;

create table if not exists task_tags (
  user_id uuid not null references users(id) on delete cascade,
  task_id uuid not null,
  tag_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (task_id, tag_id),
  constraint task_tags_task_owner_fk foreign key (task_id, user_id)
    references items(id, user_id) on delete cascade,
  constraint task_tags_tag_owner_fk foreign key (tag_id, user_id)
    references tags(id, user_id) on delete cascade
);

do $$ begin
  if to_regclass('courses') is not null then
    execute $sql$
      insert into task_tags(user_id, task_id, tag_id)
      select distinct item.user_id, item.id, tag.id
      from items item
      join courses course on course.id = item.course_id and course.user_id = item.user_id
      join tags tag on tag.user_id = course.user_id
        and lower(btrim(tag.name)) = lower(btrim(course.name))
      on conflict do nothing
    $sql$;
  end if;
end $$;

-- New relationship tables participate in the same revision/CAS contract.
drop trigger if exists planner_sync_revision on tags;
create trigger planner_sync_revision after insert or update or delete on tags
  for each row execute function planner_touch_revision();
drop trigger if exists planner_sync_revision on task_tags;
create trigger planner_sync_revision after insert or update or delete on task_tags
  for each row execute function planner_touch_revision();

-- Rewrite only the renamed ownership fields in cached JSON. Keep planning metadata,
-- timing positions, execution relations and all other richer blob-only data intact.
create or replace function planner_migrate_course_document(source jsonb, owner uuid) returns jsonb
language plpgsql as $$
declare
  result jsonb;
  rows jsonb;
begin
  if jsonb_typeof(source) <> 'object' then return source; end if;
  if to_regclass('courses') is null then return source; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', tag.id::text, 'user_id', owner::text, 'name', tag.name,
    'color', tag.color, 'created_at', tag.created_at, 'updated_at', tag.updated_at
  ) order by tag.created_at, tag.id), '[]'::jsonb)
  into rows from tags tag where tag.user_id = owner;
  result := jsonb_set(source - 'subjects' - 'courses', '{tags}', rows, true);
  if jsonb_typeof(source -> 'tasks') = 'array' then
    select coalesce(jsonb_agg(
      (task - 'subject_id' - 'course_id') || jsonb_build_object('tag_ids',
        case when tag.id is null then '[]'::jsonb else jsonb_build_array(tag.id::text) end)
      order by ordinal
    ), '[]'::jsonb)
    into rows
    from jsonb_array_elements(source -> 'tasks') with ordinality as entries(task, ordinal)
    left join lateral (
      select candidate.id
      from tags candidate
      join courses course on course.user_id = candidate.user_id
        and lower(btrim(course.name)) = lower(btrim(candidate.name))
      left join lateral (
        select old_subject ->> 'name' as name
        from jsonb_array_elements(coalesce(source -> 'subjects', source -> 'courses', '[]'::jsonb)) old_subject
        where old_subject ->> 'id' = coalesce(entries.task ->> 'subject_id', entries.task ->> 'course_id')
        limit 1
      ) legacy on true
      where candidate.user_id = owner
        and (candidate.id::text = coalesce(entries.task ->> 'subject_id', entries.task ->> 'course_id')
          or (legacy.name is not null and lower(btrim(candidate.name)) = lower(btrim(legacy.name)))
          or exists (select 1 from items item join courses linked on linked.id=item.course_id
            where item.user_id=owner and item.id::text=(entries.task ->> 'id')
              and lower(btrim(linked.name))=lower(btrim(candidate.name))))
      order by candidate.created_at, candidate.id
      limit 1
    ) tag on true
    where jsonb_typeof(entries.task) = 'object';
    result := jsonb_set(result, '{tasks}', rows, true);
  end if;
  if jsonb_typeof(result -> 'profile') = 'object' then
    result := jsonb_set(result, '{profile}', (result -> 'profile') - 'subject_limit_minutes', true);
  end if;
  return result;
end $$;

update planner_sync_state state
set document = planner_migrate_course_document(state.document, state.user_id),
    projection = planner_migrate_course_document(state.projection, state.user_id),
    revision = revision + 1,
    updated_at = now()
where state.document is not null or state.projection is not null;

drop function planner_migrate_course_document(jsonb, uuid);

alter table items drop constraint if exists items_course_id_fkey;
alter table items drop column if exists course_id;
drop table if exists courses;
