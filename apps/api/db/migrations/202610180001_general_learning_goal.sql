-- 通用学习目标：把“考研专用”的资料结构改为通用学习目标与有限规划周期。
-- 保留历史院校、专业和考试日期列；不使用占位日期冒充真实目标日期。

alter table profiles add column if not exists goal_text text not null default '';
alter table profiles add column if not exists goal_type text not null default 'other';
alter table profiles add column if not exists goal_subtype text not null default '';
alter table profiles add column if not exists target_date date;
alter table profiles add column if not exists target_date_confirmed boolean not null default false;
alter table profiles add column if not exists plan_start_date date;
alter table profiles add column if not exists plan_end_date date;

-- exam_type / exam_date 变成历史镜像：不再必填，也不再默认“考研”。
alter table profiles alter column exam_date drop not null;
alter table profiles alter column exam_type drop not null;
alter table profiles alter column exam_type drop default;

-- 旧考试日期原样迁入目标日期，并标记为未经用户确认的历史值。
update profiles
   set target_date = exam_date
 where target_date is null
   and exam_date is not null;

-- 无法可靠推断的目标类型保持“其他”，只把明确的考试类型映射过去。
update profiles set goal_type = 'exam' where exam_type in ('考研', '考公');
update profiles set goal_subtype = exam_type where goal_subtype = '' and exam_type in ('考研', '考公');

-- 旧访谈曾把学习目标拼进 constraints_text，取出第一行作为目标描述。
update profiles
   set goal_text = substring(constraints_text from '^(?:长期目标|学习目标)：([^\n]+)')
 where goal_text = ''
   and constraints_text ~ '^(长期目标|学习目标)：';

-- 事项日期语义：真实截止日期，或本期安排边界。
alter table items add column if not exists deadline_kind text not null default 'deadline';
alter table items drop constraint if exists items_deadline_kind_check;
alter table items add constraint items_deadline_kind_check check (deadline_kind in ('deadline', 'plan_end'));
