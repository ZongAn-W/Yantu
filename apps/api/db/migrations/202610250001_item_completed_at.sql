-- 事项进度改为纯时间口径（阶段 2）。
--
-- 1) items 增加 completed_at timestamptz：非空即完成；old status 只作为同步兼容投影。
-- 2) 旧 status=completed 且没有完成时间的数据，按迁移契约补 completed_at = updated_at。
-- 3) delayed/conflict 不再作为事项状态：所有非归档事项按时间规则重新派生
--    （completed_at 非空或已用分钟>=estimated_minutes → completed；有实际用时 → in_progress；
--    否则 not_started）。archived 继续保留为「不再安排、保留历史」的独立标记。
-- 4) planning_metadata 投影以新结构为准：丢弃 workload / content_progress / feedback；
--    清空后没有任何策略字段的投影置为 NULL，避免旧客户端误判为包含新版学习策略。
-- 5) 缓存文档（planner_sync_state.document/projection）由读取路径按关系表投影重建，
--    items 的更新会触发 planner_sync_revision 让客户端重新拉取。
--
-- 所有语句可重复执行；迁移只新增/收敛数据，不删除学习日志或固定记录。

alter table items add column if not exists completed_at timestamptz;

-- 旧完成状态迁移为完成时间（迁移契约 §3.1）。
update items
   set completed_at = updated_at
 where status = 'completed'
   and completed_at is null;

-- 按时间口径重新派生非归档事项的兼容 status（覆盖 delayed/conflict 与旧 completed 的边界数据）。
with actual as (
  select item.id,
         coalesce(sum(log.minutes), 0)::int as minutes
    from items item
    left join study_logs log
      on log.item_id = item.id and log.user_id = item.user_id
   group by item.id
), derived as (
  select actual.id,
         actual.minutes,
         (item.completed_at is not null or actual.minutes >= item.estimated_minutes) as completed
    from actual
    join items item on item.id = actual.id
   where item.status <> 'archived'
)
update items target
   set completed_at = case
         when derived.completed and target.completed_at is null then target.updated_at
         else target.completed_at
       end,
       status = case
         when derived.completed then 'completed'
         when derived.minutes > 0 then 'in_progress'
         else 'not_started'
       end
  from derived
 where derived.id = target.id
   and (
     target.status is distinct from case
       when derived.completed then 'completed'
       when derived.minutes > 0 then 'in_progress'
       else 'not_started'
     end
     or (derived.completed and target.completed_at is null)
   );

-- planning 投影丢弃内容量/内容反馈字段；空对象不再保留。
update items
   set planning_metadata = planning_metadata - 'workload' - 'content_progress' - 'feedback'
 where planning_metadata is not null
   and (planning_metadata ? 'workload' or planning_metadata ? 'content_progress' or planning_metadata ? 'feedback');

update items
   set planning_metadata = null
 where planning_metadata = '{}'::jsonb;
