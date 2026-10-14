-- Static subject > category taxonomy. No category table is required.
-- Actual durations and replan history are retained; logs snapshot the category.
begin;

create or replace function public.planner_category_subject(p_category text)
returns text language sql immutable set search_path = public, pg_temp as $$
  select case
    when p_category = any(array['math-calculus','math-linear','math-probability','math-comprehensive']) then 'math'
    when p_category = any(array['english-vocabulary','english-grammar','english-reading','english-writing','english-translation','english-listening','english-comprehensive']) then 'english'
    when p_category = any(array['cs-data-structures','cs-operating-systems','cs-organization','cs-networks','cs-coding','cs-comprehensive']) then 'cs'
    when p_category = any(array['politics-marxism','politics-mao','politics-xi','politics-history','politics-ethics','politics-current-affairs','politics-comprehensive']) then 'politics'
    else null
  end;
$$;

create or replace function public.infer_task_category(p_subject text, p_title text)
returns text language plpgsql immutable set search_path = public, pg_temp as $$
declare
  title text := coalesce(p_title, '');
  matches text[] := array[]::text[];
begin
  if p_subject = 'math' then
    if title ~* '高数|高等数学|微积分|极限|导数|积分|微分|级数|calculus' then matches := array_append(matches, 'math-calculus'); end if;
    if title ~* '线代|线性代数|矩阵|行列式|向量|方程组|特征值|二次型|linear\s*algebra' then matches := array_append(matches, 'math-linear'); end if;
    if title ~* '概率|数理统计|随机变量|分布|参数估计|假设检验|probability|statistics' then matches := array_append(matches, 'math-probability'); end if;
  elsif p_subject = 'english' then
    if title ~* '词汇|单词|词根|词缀|vocab|word\s*list' then matches := array_append(matches, 'english-vocabulary'); end if;
    if title ~* '语法|长难句|句法|grammar|sentence' then matches := array_append(matches, 'english-grammar'); end if;
    if title ~* '阅读|reading' then matches := array_append(matches, 'english-reading'); end if;
    if title ~* '写作|作文|writing|essay' then matches := array_append(matches, 'english-writing'); end if;
    if title ~* '翻译|translation' then matches := array_append(matches, 'english-translation'); end if;
    if title ~* '听力|listening' then matches := array_append(matches, 'english-listening'); end if;
  elsif p_subject = 'cs' then
    if title ~* 'c\+\+|c/c|机试|编程|代码|coding|programming' then return 'cs-coding'; end if;
    if title ~* '数据结构|链表|栈|队列|二叉树|图论|排序|查找|data\s*structures?' then matches := array_append(matches, 'cs-data-structures'); end if;
    if title ~* '操作系统|进程|线程|虚拟内存|文件系统|operating\s*systems?|\mos\M' then matches := array_append(matches, 'cs-operating-systems'); end if;
    if title ~* '组成原理|计算机组成|计组|指令|总线|cpu|cache|微程序|computer\s*organization' then matches := array_append(matches, 'cs-organization'); end if;
    if title ~* '计算机网络|计网|网络层|传输层|链路层|\m(tcp|ip|http)\M|computer\s*networks?' then matches := array_append(matches, 'cs-networks'); end if;
  elsif p_subject = 'politics' then
    if title ~* '马原|马克思主义基本原理|哲学|政治经济学|科学社会主义' then matches := array_append(matches, 'politics-marxism'); end if;
    if title ~* '毛中特|毛泽东|中国特色社会主义理论体系' then matches := array_append(matches, 'politics-mao'); end if;
    if title ~* '习思想|习近平|新时代中国特色社会主义思想' then matches := array_append(matches, 'politics-xi'); end if;
    if title ~* '史纲|近现代史|历史纲要' then matches := array_append(matches, 'politics-history'); end if;
    if title ~* '思修|法基|思想道德|道德与法治|法律基础' then matches := array_append(matches, 'politics-ethics'); end if;
    if title ~* '时政|形势与政策|当代世界|时事' then matches := array_append(matches, 'politics-current-affairs'); end if;
  end if;
  return case when cardinality(matches) = 1 then matches[1] else p_subject || '-comprehensive' end;
end;
$$;

alter table public.tasks add column if not exists category_id text generated always as (payload ->> 'category_id') stored;
alter table public.time_logs add column if not exists category_id text generated always as (payload ->> 'category_id') stored;
create index if not exists tasks_user_category_deadline on public.tasks(user_id, category_id, deadline);
create index if not exists logs_user_category_date on public.time_logs(user_id, category_id, date);

create or replace function public.enforce_task_category()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  subject text := new.payload ->> 'subject_id';
  category text := new.payload ->> 'category_id';
begin
  if public.planner_category_subject(category) is distinct from subject then
    category := public.infer_task_category(subject, new.payload ->> 'title');
    new.payload := jsonb_set(new.payload, '{category_id}', to_jsonb(category), true);
  end if;
  return new;
end;
$$;

create or replace function public.snapshot_log_category()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare
  category text := new.payload ->> 'category_id';
  task_payload jsonb;
begin
  -- Valid snapshots remain stable when a task changes subject/category later.
  if public.planner_category_subject(category) is not null then return new; end if;
  select payload into task_payload from public.tasks
    where user_id = new.user_id and id = (new.payload ->> 'task_id')::uuid;
  if task_payload is not null then
    category := task_payload ->> 'category_id';
    if public.planner_category_subject(category) is null then
      category := public.infer_task_category(task_payload ->> 'subject_id', task_payload ->> 'title');
    end if;
    new.payload := jsonb_set(new.payload, '{category_id}', to_jsonb(category), true);
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_category on public.tasks;
create trigger tasks_category before insert or update of payload on public.tasks
  for each row execute function public.enforce_task_category();
drop trigger if exists logs_category on public.time_logs;
create trigger logs_category before insert or update of payload on public.time_logs
  for each row execute function public.snapshot_log_category();

update public.tasks set payload = jsonb_set(payload, '{category_id}', to_jsonb(public.infer_task_category(subject_id, title)), true)
  where public.planner_category_subject(category_id) is distinct from subject_id;
update public.time_logs as logs set payload = jsonb_set(logs.payload, '{category_id}', to_jsonb(tasks.category_id), true)
  from public.tasks as tasks
  where tasks.user_id = logs.user_id and tasks.id = logs.task_id
    and public.planner_category_subject(logs.category_id) is null;

alter table public.tasks add constraint tasks_valid_category check (public.planner_category_subject(category_id) is not null and public.planner_category_subject(category_id) is not distinct from subject_id);
alter table public.time_logs add constraint logs_valid_category check (category_id is null or public.planner_category_subject(category_id) is not null);

revoke all on function public.planner_category_subject(text) from public, anon;
revoke all on function public.infer_task_category(text, text) from public, anon;
revoke all on function public.enforce_task_category() from public, anon;
revoke all on function public.snapshot_log_category() from public, anon;
grant execute on function public.planner_category_subject(text) to authenticated;
grant execute on function public.infer_task_category(text, text) to authenticated;
commit;
