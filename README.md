# 不白学 · 学习执行台

面向个人学习目标的学习执行工具：把学习目标变成有限周期的每日安排，记录真实用时，并按实际进度调整后续计划。

适用场景包括考试备考（考研、考公、语言考试、职业资格考试等）、课程学习、技能提升、自主学习和用户自定义目标。考研是其中一种具体场景：工作台、初始化和基础模板不再预置考研专用文案、科目、日期或固定考试。

## 维护范围

Flutter 是唯一维护的客户端，覆盖 Web、Windows、Android 和 iOS。原 React 网页版、Tauri 桌面壳及旧测试和部署目录已移除，详情见 [旧版清理记录](REACT_REMOVAL.md)。

- `apps/flutter_client/`：Flutter / Dart 客户端。
- `apps/api/`：Node.js / Fastify API、认证、AI 接口与 PostgreSQL。
- `packages/planner-engine/`：TypeScript 排程参考实现和共享测试 fixture；Flutter 与 API 的回归测试仍使用它。

## 本地启动

要求 Node.js 22+、npm 10+、PostgreSQL，以及 Flutter stable 3.47.3 / Dart 3.13.3。本机 Flutter SDK 为 `D:\tools\flutter`，启动脚本可通过 `-FlutterSdk` 指定其他路径。Flutter 依赖按 `pubspec.lock` 解析。

首次准备 API：从 `apps/api/.env.example` 创建 `apps/api/.env`，设置数据库连接、两个 JWT secret 和来源白名单。数据库须先应用 `apps/api/db/schema.sql`；API 启动时自动执行后续增量迁移。

```dotenv
WEB_ORIGIN=http://127.0.0.1:5180
```

在仓库根目录打开两个终端，分别启动 API 与客户端：

```powershell
Set-Location D:\_projects\sjtu-study-planner
npm install --cache D:\_projects\.npm-cache
npm run api:dev
```

```powershell
Set-Location D:\_projects\sjtu-study-planner
npm run dev
# 仅启动 Web 服务，关闭浏览器不会停止服务
npm run dev -- -Device web-server
# 自定义地址或端口时，同时更新 API 的 WEB_ORIGIN
npm run dev -- -Port 5181 -ApiBaseUrl http://127.0.0.1:8787
```

默认客户端地址为 `http://127.0.0.1:5180`，API 为 `http://127.0.0.1:8787`。端口已占用时使用其他端口。Windows 客户端的运行命令见 [Flutter 客户端说明](apps/flutter_client/README.md)。

账号登录后进入学习工作台；新账号先完成学习目标访谈和分阶段规划。注册需要邮箱验证码，QQ SMTP 配置见 [邮箱注册部署](apps/api/AUTH_DEPLOYMENT.md)。

首次规划从“你接下来想学习什么，或者达成什么目标？”开始。访谈由 AI 根据历史回答继续追问；用户确认规划周期与容量后，直接生成事项，标签是可选建议。事项支持对话修改、手动增删编辑和保存草稿。

目标日期是可选信息。用户可以明确选择“暂不设置目标日期”，系统只推荐并确认一个有限的规划周期：默认一次性排到目标日期前一天；没有目标日期但已知初试年份时，按往年规律（12 月倒数第二个周六）估算初试日并排到考试前一天；两者都没有时才默认从今天开始的 28 个自然日。单次周期最长三年。先确认规划周期与容量，再生成事项，事项确认后试排和检查；条件或计划 revision 改变后必须重新预览。

新计划一次生成覆盖整个有限周期的完整计划：规划响应给出全部事项、可选标签、具体学习范围、时间预算、依赖关系、持续活动、阶段路线与容量假设；程序展开为每日安排。标签仅用于分类和筛选，不参与排程、容量或事项/分钟总量计算。同一事项可关联多个标签，因此各标签统计不可相加。

实际计时与完成时间分别记录：进度只按时间口径（实际用时 / 预计时长，可超过 100%），预计时长用完即自动完成，也可提前确认完成（`completed_at`）。至少三段有效计时才给出速度偏离提示，误计时撤销会减少校准样本；重新访谈能读取这些记录来调整学习方法和范围。自动修订最多两次，冻结已确认的预算、频率、真实日期和固定记录；范围取舍显示为建议，用户明确修改后再预览。

引导会话保存到 PostgreSQL，刷新和重新登录可继续，账号间隔离，并发修改会提示重新读取。资料、标签、事项和首次每日安排在同一事务内提交。新增数据库迁移把旧课程转换为同名标签，事项、安排和学习记录继续保留。配置服务器 `AI_API_KEY` 才会启用动态访谈与对话修改。

访谈和时间建议默认使用 `AI_SIMPLE_REASONING_EFFORT=low`；事项生成、事项修订和自动质量修复使用 `AI_PLANNING_REASONING_EFFORT=high`，两项均可在服务器环境中独立调整。其它 AI 请求继续使用 `AI_REASONING_EFFORT`。

所有 AI 请求共用同一段逐字节一致的 system 前缀（`apps/api/src/ai-json.ts` 的 `SHARED_SYSTEM_PROMPT`），任务指令追加在该 system 消息之后，个人数据和每轮变化的内容放在 user JSON 末尾，以便 DeepSeek 等提供方复用上下文缓存。每次调用会输出一行 `ai_usage` JSON 日志，包含调用类型与 `cache_hit_tokens` / `cache_miss_tokens`，可按日志核对缓存命中率；官方资料抽取只发送页面 `url`、`title` 和裁剪后的正文（最多 16000 字，不含导航链接），避免把唯一 URL 全部塞进 prompt。

可用时间默认表示净学习预算，支持周模板、周覆盖、日期覆盖和明确休息日。旧数据继续按总预算扣机动时间计算。每日最多 8 小时；所有事项共享全局每日容量，不按标签限制。

设置中修改周期或容量只保存设置，不再自动重排未来安排；需要按新容量或周期重排时，到「调整学习计划」页使用“一键调整后续计划”。该操作由 AI 根据目标、人物画像、学习进度和近期实际执行重新规划，先预览调整前后的周期、学习强度、总学习时长、预算变化与未安排量，确认后由服务端原子提交。历史日期、已完成安排、固定时间块与固定事项、有实际用时或日志引用的安排不会被改动；排不完的时间预算保留为未安排量并说明原因，不会为了通过校验而改写事项预算或真实截止日期。

本期结束或即将结束时，今日页提供“继续安排下一周期”入口：确认新的规划区间后，一次生成覆盖新周期的完整安排；本期安排边界类事项跟随新周期延展，真实截止日期保持不变，已完成状态、实际用时、固定安排和已有每日安排都不被覆盖，重复确认不会重复生成安排。

工作台导航新增“调整”页（`/adjust`）：集中展示人物画像（目标、目标日期、院校专业、约束）、已布置事项的完成情况、近期可用学习时间与当前规划区间。可继续访谈完善画像、修改目标与规划，或打开容量编辑器调整近期可用时间；页面底部的“一键调整后续计划”改为 AI 调整：AI 先审查“目标需要多少学习量、当前计划是否合理”，再按人物画像、时间进度、近期实际执行调整规划周期结束日期、学习强度（每周可用时间）、事项时间预算与新增事项，并在预览中展示所需/当前/调整后总时长、周期与强度变化、预算变化、日程影响和截止风险，确认后由服务端原子写入。历史日期、已完成安排、有实际用时的记录、事项真实截止日期与已有学习事实不被改写。

访谈归入“调整学习计划”页。未确认的规划作为独立草稿保存，当前计划保持生效；最终确认后复用已有事项标识、标签和完成进度，保留历史日程与实际用时。云端计划并发变化时必须重新读取并确认。

## 学情访谈与官方资料

访谈会把一段回答中的年级/在职情况、院校/学院/专业/学位、各科进度、薄弱项、目标及时间约束分别记录在会话 `learning_context` 中，并保留原回答依据。下一问优先补充会影响课程或安排的信息；已知信息、同义考试名称和用户暂缓的内容不会逐层重复确认。公开考试要求由后台求证，不要求用户解释 408 的组成或自己查招生目录。

四年制/五年制本科的年级用于推算常规应届考研年份，初试年份与入学年份分别显示，支持手动修改。推算结果不写成精确官方考试日；已毕业、二战等情况会询问报考年份。非考研目标不套用初试/入学年份。

API 默认用 Bing RSS 搜索及官方栏目导航获取公开资料，只读取官方域名的 HTML/PDF，并核对原文引文、院校专业范围及适用年度。搜索结果本身不是事实依据；模型提出的网址只作为待验证导航线索。目标年度资料未公布、学位范围不明确或要求冲突时标为参考/待核实。客户端可展开查看原文、适用年份和来源链接；查询失败可重试，后台更新不清空正在输入的回答。公共查询缓存按目标范围隔离在 `exam_research_cache`（已核对/参考/未找到分别保留 30 天/7 天/1 天，过期才重新核实）；抓取过的官方页面原文与搜索命中会写入本地资料库 `exam_research_documents` / `exam_research_searches`，默认分别复用 30 天/7 天，访谈目标逐渐补充或缓存过期时优先复用本地资料、只补抓缺失部分，避免每次访谈都整轮联网。点「重新核实官方资料」会强制联网刷新。资料库不保存个人基础、薄弱项或完整访谈内容。

无密钥搜索及官方站点可能限制自动访问。部署时可在 `apps/api/.env` 配置搜索接口，密钥只留在后端：

```dotenv
# bing（默认，无需搜索密钥）、brave、tavily 或 disabled
RESEARCH_SEARCH_PROVIDER=bing
RESEARCH_SEARCH_API_KEY=
# 本地官方资料库复用时长（天），点「重新核实官方资料」不受此限制
RESEARCH_LIBRARY_DOCUMENT_DAYS=30
RESEARCH_LIBRARY_SEARCH_DAYS=7
```

Brave/Tavily 需填写各自的搜索 API 密钥。未取得可核实原文时，系统保留待核实状态并继续访谈，不把模型记忆冒充已求证的事实。查询在数据库事务之外执行，结果按目标缓存；修改院校、专业、学位或年份后，旧任务结果不会覆盖新目标。

## 验证与构建

仓库根目录的检查覆盖 API 和 TypeScript 排程参考实现：

```powershell
npm run typecheck
npm test
npm run api:build
```

API 数据库集成测试需配置独立测试库的 `AUTH_TEST_DATABASE_URL`；未配置时会跳过这部分测试，不要指向生产数据库。

Flutter 的分析和单元测试在客户端目录运行：

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client
$env:PUB_CACHE = 'D:\_projects\sjtu-study-planner\apps\flutter_client\.dart_tool\pub-cache'
& D:\tools\flutter\bin\flutter.bat analyze --no-pub
& D:\tools\flutter\bin\flutter.bat test --no-pub
```

从仓库根目录构建 Flutter Web，脚本默认执行分析和测试：

```powershell
npm run build -- -ApiBaseUrl https://api.example.com
```

Web 产物为 `apps/flutter_client/build/web/`。Windows、Android 构建与签名要求见 [Flutter 客户端说明](apps/flutter_client/README.md)。Android、iOS 尚未完成实机验收；Windows 安装包尚未打包。Web 未实现 Service Worker 离线资源缓存。

## 数据表示与兼容

学习目标、目标类型、可选目标日期、规划周期、可用时间和场景信息（院校、专业等）统一使用一组字段：`goal_text`、`goal_type`（`exam`/`course`/`skill`/`self_study`/`other`）、`goal_subtype`、`target_date`、`target_date_confirmed`、`plan_start_date`、`plan_end_date`、`weekly_minutes`（默认七天模板）、`current_progress`、`constraints_text`、`target_school`、`target_program`。灵活容量使用 `capacity_basis`（`gross_buffer`/`net`）、`weekly_baseline_minutes`、`weekly_range_min_minutes`、`weekly_range_max_minutes`、`week_capacity_overrides`（键为周一日期）、`date_capacity_overrides`（键为日期，显式 0 表示休息）。数据库 `profiles` 表、访谈会话、API 资料、本机 `PlannerData.profile` 和同步文档共用这组名称，没有第二份需要人工对账的数据源。

学习日志统一包含 `task_id`、`relation`、`session_id`、`quota_minutes`、`block_id`、`date`、`minutes`、`source` 与真实起止时间；每条日志必须归属一个正式事项。执行关系为 `scheduled`（今日原定学习）、`extra`（已有事项加学），旧数据缺少该字段时保留为 `legacy_unknown`，只在有可靠日程关联时有限推断为原定学习并标明依据。

> **临时学习已在二期从服务端与数据库删除（迁移 `202610230001_remove_ad_hoc_learning.sql`）**：产品层已于 2026-10-20 下线该功能；二期按确认规则直接清理历史数据——纯临时学习计时（`item_id` 为空）删除，已关联正式事项的计时保留真实分钟并改写为 `extra`，`ad_hoc_learnings` 表、`study_logs.ad_hoc_id` 列、相关索引与旧约束全部删除，权威同步文档 blob 一并清理。历史 migration 文件保留原样，只作为历史记录。

空值语义统一：`null`、缺失字段和旧格式空字符串都表示“没有这个日期”，不会用占位日期冒充。资料更新接口区分“不修改这个字段”（`PATCH` 中省略）和“清空这个字段”（显式传 `null`）。

新旧字段兼容只在反序列化边界做一次归一化：

- **新字段缺失**（通用改造之前的历史文档）→ 用 `exam_date` / `exam_end_date` 作为目标日期和规划结束日期的来源；
- **新字段存在**（包括空字符串和 `null`）→ 以新字段为准，用户主动清空后不会再被旧考试日期填回；清空时同时清除“已确认”状态；
- 计划文档统一用空字符串表示“没有目标日期”，服务端快照、同步比较和数据库 `NULL` 之间按同一规则映射，避免每次同步都因为 `null` 与 `''` 不一致而误报冲突。

事项日期带一个来源标记：`deadline_kind` 为 `deadline` 表示真实截止日期，为 `plan_end` 表示本期安排边界。进入下一周期时只延展后者，真实截止日期即使恰好等于旧周期末也不改写。真实截止日期可以早于、等于或晚于本期结束日期：排程只生成与本期区间相交的部分，截止日期与未安排量原样保留；开始日期晚于本期结束日的事项保留为后续事项。旧数据没有该字段时按真实截止日期解释（保守策略，不做“日期相等即本期边界”的推断）。

旧账号兼容：升级迁移把历史 `exam_type`/`exam_date` 原值保留在 `profiles`，同时写入目标类型、目标日期和规划周期；旧“其他”类型不会被一律改成考研，院校与专业信息原样保留。旧客户端导出的 JSON 和旧同步基线可以直接读取，缺少的字段使用默认值，不使用占位日期。

## 数据库迁移

新增迁移 `apps/api/db/migrations/202610180001_general_learning_goal.sql`，API 启动时自动执行；`apps/api/db/schema.sql` 供全新安装使用。

- `profiles.exam_date` 取消非空约束，`exam_type` 取消默认值，两者保留为历史镜像列。
- 新增 `goal_text`、`goal_type`、`goal_subtype`、`target_date`、`target_date_confirmed`、`plan_start_date`、`plan_end_date`。
- `items` 新增 `deadline_kind`（`deadline`/`plan_end`）。
- 该迁移不删除账号、事项、日志、计划版本或固定事件，也不修改已应用的历史迁移；旧课程关系由后续标签迁移转换。

新增迁移 `apps/api/db/migrations/202610200001_learning_relations_capacity.sql`（一期，临时学习结构已被二期迁移 `202610230001` 删除）：

- `study_logs.item_id` 允许为空，新增执行关系 `relation`（`scheduled`/`extra`/`ad_hoc`/`legacy_unknown`，旧数据默认 `legacy_unknown`）、`session_id`、`ad_hoc_id`、`quota_minutes`，并约束每条记录至少归属正式事项或临时学习之一。
- 新增 `ad_hoc_learnings` 表（名称即可开始的临时学习实体，可归档、可记录转换后的正式事项引用），带同步 revision 触发器。
- `profiles` 新增容量投影列：`capacity_basis`、`weekly_baseline_minutes`、`weekly_range_min_minutes`、`weekly_range_max_minutes`、`week_capacity_overrides`、`date_capacity_overrides`。文档 JSON 仍是权威数据，这些列是同步投影；列为空表示旧数据。
- 迁移只新增，可重复执行，不删除真实学习记录；`ad_hoc_id` 使用 restrict 约束，避免删除实体时静默丢失真实计时。

新增迁移 `apps/api/db/migrations/202610230001_remove_ad_hoc_learning.sql`（二期，彻底删除临时学习）：

- 纯临时学习日志（`item_id` 为空）直接删除；已关联/转为正式事项的临时学习计时保留真实用时，`relation` 改写为 `extra` 并清空 `ad_hoc_id`。
- `study_logs.item_id` 收窄为必填（先删除无主历史行），`relation` 约束收窄为 `scheduled`/`extra`/`legacy_unknown`（不再允许 `ad_hoc`）。
- 删除 `study_logs.ad_hoc_id` 列、`logs_user_ad_hoc` 索引、旧归属约束与 `ad_hoc_learnings` 表。执行顺序为先迁/删日志、再删列与表，外键依赖不会阻断迁移。
- 权威同步文档 blob（`planner_sync_state.document` / `projection`）同步清理：删除 `ad_hoc_learnings` 键与日志的 `ad_hoc_id`，把 `ad_hoc` 关系改为 `extra`，删除没有正式事项归属的日志；内容有变化的账号 `revision` 前进，客户端会重新拉取清理后的文档。
- 迁移可重复执行（列/表/索引均按存在性判断），不删除真实学习记录，也不修改任何已应用的历史迁移文件。

## 同步与旧写入方

执行关系与容量覆盖贯通本机存储、JSON 导入导出、备份恢复、数据库投影和同步文档。同步仍以完整文档 + revision/base 三方合并提交：缺失字段表示旧写入方/旧数据（保留云端权威值），显式 null 或空表示用户主动清空。服务端已删除临时学习，每条学习日志都必须归属正式事项，`task_id` 为空的日志与 `ad_hoc` 关系不再被接受。

新客户端同步时声明 `writer_learning_version: 1`，使容量字段缺失被解释为“未设置”；旧写入方缺少该字段时保留云端容量覆盖与执行关系，不会被静默清除。临时学习的 426 升级路径已随功能删除，服务端只在规划策略能力不足时返回 `planning_writer_upgrade_required`。

## 学习规则与数据

学习结构以事项为中心。标签是可选的多对多分类，筛选按任一标签匹配；事项、分钟、进度和容量始终按事项计算，不能按标签重复累计。每日安排只列事项与时长。

每日最多 8 小时；所有事项共用每日容量，不再设置课程或标签每日上限。旧数据继续保留“先扣机动时间”的口径，新计划按净学习预算计算。旧 fixed_events 字段只用于历史兼容。一键调整先预览后确认；历史、固定、已完成或已有实际记录的安排受保护。

学习发生时与计划的关系分为两类，与「计时/手动」记录方式相互独立：**今日原定学习**（在今日学习区计时，按该安排的额度封顶）、**已有事项加学**（从「全部事项」行内闹钟为任意现有事项计时，今天没有安排也能开始，不自动抵消其他今日安排）。原定 60 分钟实际学到 90 分钟时全部 90 分钟都保留，原定达成最多 60 分钟，多出的 30 分钟单独记为加学；同一事项同一天可以既有原定学习也有加学，加学中的事项会显示在「今日加学」。

当天容量只计算一次：实际投入、尚未执行的有效预留、新增可安排量与超出预算量分别表达。例如当天净容量 120 分钟、数学原定 60 分钟其中已学 30 分钟、另有 20 分钟加学时：实际投入 50 分钟、数学尚需预留 30 分钟、新增可安排 40 分钟（不是 `120-60-30-20`）。今日页本身不再展示这行净容量拆分；容量设置仍在设置/调整页维护。今日原定达成按各原定事项分别封顶，其他事项加学不能抵消未完成的原定事项；时间进度、实际用时与事项完成按同一时间口径表达。

实际用时由开始、暂停和继续计时累计，不提供手动修改用时或每日完成勾选；暂停后可确认并撤销最近一整段误计时。当天用时达标、事项完成与目标达成分别表达：事项进度 = 实际用时 / 预计时长（可超过 100%），预计时长用完即自动完成，也可提前确认完成（`completed_at`）；完成后仍可复习计时，超额实际用时继续保留。规划周期结束不自动判定长期目标完成、失败或逾期。

Flutter Web 在 IndexedDB 保存本机计划；Windows 和移动端使用应用数据目录中的 Sembast 数据库。本机数据按 API 地址和账号隔离，修改先落本机，再通过 revision/base 协议同步到 PostgreSQL；冲突需要显式选择。本机缓存和备份不因停用旧版而删除。

JSON 导出与恢复保留计划、事项说明、实际日志、执行关系、固定事件、容量覆盖和重排记录；历史导出里的临时学习字段只用于历史数据兼容读取，不再进入服务端同步文档（服务端已删除该结构）。格式与历史 v1 导出兼容（旧导出缺少的新字段按旧语义读取，用户显式清空的字段不会被旧值填回）；历史浏览器缓存或桌面文件需要显式导入。

实际用时只由开始、暂停和继续计时累计，并随快照同步提交；调整页“一键调整后续计划”调用服务端 AI 接口生成预览，确认后由服务端校验并原子提交计划版本。详细规则、存储位置和已知限制见 [Flutter 客户端说明](apps/flutter_client/README.md)。

## 部署与记录

- [邮箱注册与 API 升级](apps/api/AUTH_DEPLOYMENT.md)
- `apps/api/docker-compose.yml`：本地 PostgreSQL 与 API。
- `apps/api/docker-compose.server.yml`：服务器部署，保留已有数据库卷和环境变量。
- `apps/api/setup-ip-web.sh`：Nginx 静态根目录使用 Flutter Web 产物。
- [测试报告](TEST_REPORT.md) 与 [迁移设计](FLUTTER_MIGRATION_DESIGN.md)：包含历史阶段记录；当前维护范围以本文为准。

### 一键部署（推荐）

日常发布不再手动打包、上传和敲服务器命令，一条命令完成：

```powershell
# 首次：生成部署密钥，并按打印的提示在服务器（阿里云 Workbench）执行一次公钥安装命令
npm run deploy:key

# 之后每次发布（本机执行）
npm run deploy
```

`npm run deploy` 会依次：TypeScript 类型检查 → 构建 Flutter Web（Release，编译进 `API_BASE_URL`）→ 打包（只含 API 源码 + Web，约 26MB，不含 `.env`/数据库/镜像）→ `scp` 上传 → 服务器运行 `upgrade-server.sh --check` 和 `--apply` → 从本机验证线上 `/api/health`。服务器自己构建 API 镜像；服务器 `.env`、数据库容器和 `planner-db` 卷保持不动；失败自动回滚，备份在 `/opt/sjtu-study-planner/backups/<发布ID>-*`。

常用选项：

```powershell
npm run deploy -- -CheckOnly   # 只做服务器只读检查，不改任何东西
npm run deploy -- -SkipBuild   # 复用现有 apps/flutter_client/build/web
npm run deploy -- -FullCheck   # 额外运行 npm test（Flutter 测试默认跳过）
npm run deploy -- -ReleaseId 20261018-1600
```

运行脚本见 [tools/deploy-server.ps1](tools/deploy-server.ps1)、[tools/prepare-release.mjs](tools/prepare-release.mjs)、[tools/setup-deploy-key.ps1](tools/setup-deploy-key.ps1)；服务器侧脚本模板在 [tools/server-release/](tools/server-release/)。`upgrade-server.sh --check` 现在会额外校验：`DATABASE_URL` 不能指向 `localhost`（容器内必须是 `db`），以及服务器 `.env` 的 `SMTP_USER`/`SMTP_PASS` 未配置时给出警告。

客户端仅注入公开的 `API_BASE_URL`。数据库凭据、JWT secret、AI key、SMTP 授权码和签名材料只留在服务器或构建机。

## AI 规划升级

字段和五条调用链见 [实现设计](PLANNING_UPGRADE_DESIGN.md)，证据见 [升级验收](AI_PLANNING_ACCEPTANCE.md)。增量迁移 `202610190001_ai_planning_metadata.sql` 仅增加可空元数据列，不改历史迁移或学习记录。新策略要求同步写入方声明 `writer_planning_version: 1`，旧写入方收到 426 升级提示。旧生成/结算兼容接口不能改写新版策略。

新计划默认全周期生成：一次规划响应返回整个有限周期的完整学习范围与结构化策略，程序按该策略展开每日安排；`planning.mode = "full"`、`rolling = false`、`detailed_until = plan_end_date`，不再存在“其后待细化”的空预测区间。旧滚动计划（`rolling = true`）继续按原数据读取，客户端提供一次“补全本周期安排”的预览与确认后才转换为全周期模式，服务端不会自动升级或覆盖旧计划。同步文档新增 `writer_learning_version: 1` 用于执行关系与容量覆盖能力声明。

去标识化 AI 案例覆盖长期/短期考试、大学课程、项目技能、自主学习、材料未知、容量不足和进度偏离。真实评测使用现有后端配置，并显式限制样本数：

```powershell
npm run planning:eval -w @planner/api -- --limit=8
npm run planning:eval -w @planner/api -- --live --limit=3 --cases=long-exam,project-skill,self-study
# 可选修订，每例最多额外两次；输出不含密钥
npm run planning:eval -w @planner/api -- --live --variant=upgrade --repair --limit=1 --cases=project-skill
```
