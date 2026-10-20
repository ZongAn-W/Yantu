-- 二期：在服务端与数据库层彻底删除临时学习（ad-hoc learning）。
--
-- 一期已在产品层下线临时学习，客户端不再创建/展示/统计；本迁移按用户确认的规则
-- 直接删除历史数据，不再保留临时学习表、列或同步字段：
--   1) 纯临时学习计时（study_logs.item_id 为空）直接删除；
--   2) 已转为正式事项/关联到事项的临时学习计时（item_id 非空且 ad_hoc_id 非空）
--      保留真实用时：关系改写为 extra 并清空 ad_hoc_id；
--   3) 删除 ad_hoc_learnings 表的全部行与表本身、study_logs.ad_hoc_id 列、
--      相关索引与旧归属约束；
--   4) relation 约束收窄为 scheduled / extra / legacy_unknown；
--   5) study_logs.item_id 收窄为必填（清理后已无空行），日志必须归属正式事项。
--
-- 同步文档 blob（planner_sync_state.document/projection）是权威数据来源，同样清理：
-- 删除 ad_hoc_learnings 键与日志的 ad_hoc_id，把 ad_hoc 关系改写为 extra，
-- 删除没有正式事项归属的日志；内容确实变化的用户 revision+1，让客户端重新拉取。
--
-- 执行顺序：先迁/删日志，再删列与表（外键依赖）；所有语句可重复执行。

-- 1) 迁移学习日志。列可能已在上一次执行时删除，因此用信息模式做条件判断。
do $$
begin
  -- 纯临时学习计时没有正式事项，按确认规则直接删除。
  delete from study_logs where item_id is null;

  if exists (
    select 1 from information_schema.columns
    where table_schema = current_schema()
      and table_name = 'study_logs'
      and column_name = 'ad_hoc_id'
  ) then
    -- 已转为正式事项的临时学习计时：真实分钟数不变，归属关系改为加学并清空引用。
    update study_logs
       set relation = case when relation = 'ad_hoc' then 'extra' else relation end,
           ad_hoc_id = null
     where ad_hoc_id is not null;
  end if;

  -- 防御：极少数历史行可能标记了 ad_hoc 关系却没有 ad_hoc_id（例如转换后的半迁移数据）。
  update study_logs set relation = 'extra' where relation = 'ad_hoc';
end $$;

-- 2) 删除 ad_hoc 相关的索引、旧归属约束与列。
drop index if exists logs_user_ad_hoc;
alter table study_logs drop constraint if exists study_logs_owner_check;
alter table study_logs drop column if exists ad_hoc_id;
-- 清理后每条日志都有正式事项；保留 NOT NULL 屏障，避免再次出现无主日志。
alter table study_logs alter column item_id set not null;

-- 3) relation 只保留真实存在的执行关系；ad_hoc 不再是合法值。
alter table study_logs drop constraint if exists study_logs_relation_check;
alter table study_logs add constraint study_logs_relation_check
  check (relation in ('scheduled', 'extra', 'legacy_unknown'));

-- 4) 删除临时学习实体表（依赖它的 ad_hoc_id 列已先删除，触发器随表删除）。
drop table if exists ad_hoc_learnings;

-- 5) 清理权威同步文档 blob。JSON 形态与 PlannerDocument 一致：logs 为数组，
--    每个元素用 task_id 表达事项归属；无 task_id 的日志属于已删除的临时学习。
with cleaned as (
  select
    state.user_id,
    case
      when jsonb_typeof(state.document) = 'object' then
        case
          when jsonb_typeof(state.document -> 'logs') = 'array' then
            jsonb_set(
              state.document - 'ad_hoc_learnings',
              '{logs}',
              coalesce((
                select jsonb_agg(
                  case
                    when entry ->> 'relation' = 'ad_hoc'
                      then jsonb_set(entry - 'ad_hoc_id', '{relation}', '"extra"')
                    else entry - 'ad_hoc_id'
                  end
                  order by ordinality
                )
                from jsonb_array_elements(state.document -> 'logs') with ordinality as entries(entry, ordinality)
                where jsonb_typeof(entry) = 'object'
                  and coalesce(entry ->> 'task_id', '') <> ''
              ), '[]'::jsonb),
              false
            )
          else state.document - 'ad_hoc_learnings'
        end
      else state.document
    end as document,
    case
      when jsonb_typeof(state.projection) = 'object' then
        case
          when jsonb_typeof(state.projection -> 'logs') = 'array' then
            jsonb_set(
              state.projection - 'ad_hoc_learnings',
              '{logs}',
              coalesce((
                select jsonb_agg(
                  case
                    when entry ->> 'relation' = 'ad_hoc'
                      then jsonb_set(entry - 'ad_hoc_id', '{relation}', '"extra"')
                    else entry - 'ad_hoc_id'
                  end
                  order by ordinality
                )
                from jsonb_array_elements(state.projection -> 'logs') with ordinality as entries(entry, ordinality)
                where jsonb_typeof(entry) = 'object'
                  and coalesce(entry ->> 'task_id', '') <> ''
              ), '[]'::jsonb),
              false
            )
          else state.projection - 'ad_hoc_learnings'
        end
      else state.projection
    end as projection
  from planner_sync_state state
)
update planner_sync_state target
   set document = cleaned.document,
       projection = cleaned.projection,
       revision = target.revision + 1,
       updated_at = now()
  from cleaned
 where cleaned.user_id = target.user_id
   and (cleaned.document is distinct from target.document
        or cleaned.projection is distinct from target.projection);
