-- 阶段 3b-A：事项归档改为独立布尔事实 `archived`，与完成正交。
--
-- 1) items 增加 archived boolean not null default false（幂等）。
-- 2) 幂等回填：旧 status='archived' → archived=true。
-- 3) 反向兼容：archived=true 但旧 status 投影不是 archived 时补齐 status='archived'，
--    保证仍读 status 的旧客户端能识别归档事项（阶段 C 才会删除 status 列）。
-- 4) 不删除任何数据/列：items.status 继续作为旧客户端读投影保留。
--
-- 说明：迁移在 API 启动前执行；重复执行无副作用。

alter table items add column if not exists archived boolean not null default false;

-- 旧数据回填：只有旧 status 表达归档的行才需要改为 archived=true。
update items
   set archived = true
 where status = 'archived'
   and archived = false;

-- 反向补齐旧客户端读投影：archived 权威为 true 时 status 也必须是 archived。
update items
   set status = 'archived'
 where archived = true
   and status is distinct from 'archived';
