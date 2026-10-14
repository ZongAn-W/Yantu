# Supabase 配置

没有环境变量时应用以完整本地 Demo 运行。云端为第一版的单用户计划提供账号隔离与多设备同步，不需要 service role 密钥。

1. 在 Supabase 新建项目。用 Supabase CLI `supabase db push` 应用 `migrations` 目录；其中 `001_initial.sql` 是旧版空占位。按顺序执行 `202610130001_planner.sql`、`202610140001_daily_plan_compat.sql`、`202610140002_study_categories.sql`、`202610140003_courses_items.sql`，最后一份取消旧分类约束和触发器，启用课程与事项两层结构。
2. 将 `apps/web/.env.example` 复制为 `apps/web/.env.local`，填写项目 URL 和公开 anon / publishable key。
3. 重启 Vite。设置页显示“云端已配置 · 请登录”，支持邮箱密码注册、登录和退出。
4. 在 Supabase Auth 配置本站 Site URL 和允许的 Redirect URL。开发默认 `http://localhost:5173`。启用邮件确认时先点确认邮件再登录；生产请配置实际域名和邮件发送服务。

## 存储与同步

八张表均包含 `user_id` 并启用 RLS，所有读写限制为 `auth.uid()`。subjects 存储可自定义的课程，tasks 存储事项；课程 ID 是字符串，其他实体采用 UUID。业务字段保存为 JSON payload，事项的 `description` 保存学习范围与完成标准。六个总体备考阶段保存在 profiles.phases，不属于课程事项层级。计划模式固定为 `daily`，普通学习块只表达日期和分钟数。

`load_planner_state()` 在单个数据库快照中读取计划。`save_planner_state(p_data, p_expected_revision)` 以用户行锁和乐观版本号在事务中保存八表，确认重排和撤销均包含前后快照及完整变更记录；容量冲突由独立排程引擎处理。

time_logs 使用 task_id 归属到具体事项，同课程下的多个事项分别计时。再次记录同一事项当天累计时长会替换该组日志。历史 migration 中的 category_id 列不再参与新版读写，课程汇总按事项的 subject_id 计算。

首次登录先读取云端。只有账号没有云端 profile 时才导入当前 Demo；已存在云端的账号以云端数据为准，不被默认种子覆盖。每个账号的本机缓存与 Demo 分离。tasks、schedule_blocks、time_logs 和其余表均已加入 Realtime publication，收到更改后读取一致的快照。并发版本冲突保留独立实体更改并合并计时日志；同一记录的并发编辑采用本机最近操作。失败的网络写入保存在本机，恢复网络或重试时继续同步。

本仓库不包含 Supabase 项目凭据。云端注册、RLS 和真实多设备同步需要用户自己的 Supabase 项目才能做端到端验证；Demo 的核心执行、计时、排程、导出和恢复均无需云端。当前开发机未安装 Supabase CLI、PostgreSQL 客户端，也没有可用项目 URL，因此本次完成的是 migration 静态核对和客户端 build/typecheck；真实云端端到端测试仍需用户自己的项目。

如果某个 Supabase 项目已经执行过旧版 `001_initial.sql`（其中创建了非 payload 表结构），请先在该项目做一次人工备份和迁移，再执行 canonical migration；全新项目直接 `supabase db push` 不会遇到重复建表。已有 canonical schema 的项目应用新增的 daily compatibility migration 即可完成字段和旧学习时间块转换。

本地使用 `sjtu-study-planner:items-v2`；新版不读取或转换旧三级数据。已有云端旧计划需单独准备为新版课程事项结构，前端不会自动重置或覆盖。
