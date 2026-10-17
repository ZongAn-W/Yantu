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

首次规划从“你接下来想学习什么，或者达成什么目标？”开始，后台 AI 每次根据全部历史回答生成下一问，尽可能提供单选或多选答案，并保留“其他”文字输入。包含第一问共回答五题后，可以继续补充，也可以生成课程。课程先经用户确认，再生成各课程的学习事项；两阶段都支持对话修改、手动增删编辑和保存草稿。

目标日期是可选信息。用户可以明确选择“暂不设置目标日期”，系统只推荐并确认一个有限的规划周期：默认从今天开始的 28 个自然日，首尾均计入，可手动调整。只有用户明确提供的日期才会进入资料；AI 推荐值标记为“预计”，以正式通知为准，绝不写成官方已公布日期。规划结束日期是本次排程的边界，不等于用户目标日期。事项确认后，默认采用这些建议，开始日期默认今天；确认后生成覆盖该周期的每日安排，再进入工作台。

引导会话保存到 PostgreSQL，刷新和重新登录可继续，账号间隔离，并发修改会提示重新读取。资料、课程、事项和首次每日安排在同一事务内提交；失败可重试，重复最终确认不会生成第二套课程。增量表由 API 启动时自动迁移。配置服务器 `AI_API_KEY` 才会启用真正的动态访谈和对话修改；未配置时使用明确标注的基础模板，可手动编辑，对话修改会提示尚未配置 AI。

一周七天的可用时间分别保存（`0` 为明确的休息日），排程按每天的实际预算计算并扣除至少 30 分钟机动时间；某天为 0 时该天不生成学习安排。这组配置是排程的唯一来源：首次确认、重新访谈、同步写入、本机快照和设置表单读取的都是逐日值，不会用全周最大值或每日上限替代。只有真正缺少周配置的旧数据才按每日上限兜底。

本期结束或即将结束时，今日页提供“继续安排下一周期”入口：确认新的规划区间后，本期安排边界类事项跟随新周期延展，真实截止日期保持不变，已完成状态、实际用时、固定安排和已有每日安排都不被覆盖，重复确认不会重复生成安排。

在设置中缩短周期、把某天改为休息日或降低可用时间时，先显示调整预览（每日调整前后时长、释放/重新排入/未安排量、被保护的记录），确认后才写入。历史日期、已完成安排、固定时间块与固定事项、有实际用时或日志引用的安排不会被改动；无法排完的工作量保留为未安排量并说明原因，不会为了通过校验而改写事项预算或真实截止日期。

工作台导航中的“访谈”支持继续已有访谈或重新访谈。未确认的规划作为独立草稿保存，当前计划保持生效；最终确认后更新未来可调整日程，复用已有课程和事项的标识及完成进度，并保留历史日程、实际用时和固定安排。被替换的未完成事项归档，可在事项管理的“已归档”筛选中查看。确认前同步本机计划；云端计划在访谈期间发生变化时，需要显式更新计划进度后再确认，草稿保留。

## 学情访谈与官方资料

访谈会把一段回答中的年级/在职情况、院校/学院/专业/学位、各科进度、薄弱项、目标及时间约束分别记录在会话 `learning_context` 中，并保留原回答依据。下一问优先补充会影响课程或安排的信息；已知信息、同义考试名称和用户暂缓的内容不会逐层重复确认。公开考试要求由后台求证，不要求用户解释 408 的组成或自己查招生目录。

四年制/五年制本科的年级用于推算常规应届考研年份，初试年份与入学年份分别显示，支持手动修改。推算结果不写成精确官方考试日；已毕业、二战等情况会询问报考年份。非考研目标不套用初试/入学年份。

API 默认用 Bing RSS 搜索及官方栏目导航获取公开资料，只读取官方域名的 HTML/PDF，并核对原文引文、院校专业范围及适用年度。搜索结果本身不是事实依据；模型提出的网址只作为待验证导航线索。目标年度资料未公布、学位范围不明确或要求冲突时标为参考/待核实。客户端可展开查看原文、适用年份和来源链接；查询失败可重试，后台更新不清空正在输入的回答。公共查询缓存按目标范围隔离在 `exam_research_cache`，不保存个人基础、薄弱项或完整访谈内容。

无密钥搜索及官方站点可能限制自动访问。部署时可在 `apps/api/.env` 配置搜索接口，密钥只留在后端：

```dotenv
# bing（默认，无需搜索密钥）、brave、tavily 或 disabled
RESEARCH_SEARCH_PROVIDER=bing
RESEARCH_SEARCH_API_KEY=
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

学习目标、目标类型、可选目标日期、规划周期、一周七天可用时间和场景信息（院校、专业等）统一使用一组字段：`goal_text`、`goal_type`（`exam`/`course`/`skill`/`self_study`/`other`）、`goal_subtype`、`target_date`、`target_date_confirmed`、`plan_start_date`、`plan_end_date`、`weekly_minutes`、`current_progress`、`constraints_text`、`target_school`、`target_program`。数据库 `profiles` 表、访谈会话、API 资料、本机 `PlannerData.profile` 和同步文档共用这组名称，没有第二份需要人工对账的数据源。

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
- 迁移不删除账号、课程、事项、日志、计划版本或固定事件，也不修改已应用的历史迁移。

## 学习规则与数据

学习结构为“课程 → 事项”两层。事项可设置总时间预算、起止日期和优先级，学习内容与完成标准写在事项说明中。每日安排只列事项与时长；固定课程、考试和休息保留具体时刻。

默认每日最多 8 小时，保留至少 30 分钟机动，每课程每天最多 4 小时。固定事件重叠时按时间并集扣除容量。客户端自动重排最多处理未来 14 天，超额完成最多提前 7 天内任务，先预览后确认。

实际用时按“事项 + 日期”累计记录；再次填写是修正当天总量。每日完成勾选只表示当天安排完成，整项完成需单独确认；用完时间预算不会自动完成事项，超额实际用时仍保留。规划周期结束不自动判定长期目标完成、失败或逾期。

Flutter Web 在 IndexedDB 保存本机计划；Windows 和移动端使用应用数据目录中的 Sembast 数据库。本机数据按 API 地址和账号隔离，修改先落本机，再通过 revision/base 协议同步到 PostgreSQL；冲突需要显式选择。本机缓存和备份不因停用旧版而删除。

JSON 导出与恢复保留计划、事项说明、实际日志、固定事件和重排记录。格式与历史 v1 导出兼容；历史浏览器缓存或桌面文件需要显式导入。

客户端“结束今天”和重排经快照同步提交，尚未接入服务端正式结算与生成接口。详细规则、存储位置和已知限制见 [Flutter 客户端说明](apps/flutter_client/README.md)。

## 部署与记录

- [邮箱注册与 API 升级](apps/api/AUTH_DEPLOYMENT.md)
- `apps/api/docker-compose.yml`：本地 PostgreSQL 与 API。
- `apps/api/docker-compose.server.yml`：服务器部署，保留已有数据库卷和环境变量。
- `apps/api/setup-ip-web.sh`：Nginx 静态根目录使用 Flutter Web 产物。
- [测试报告](TEST_REPORT.md) 与 [迁移设计](FLUTTER_MIGRATION_DESIGN.md)：包含历史阶段记录；当前维护范围以本文为准。

客户端仅注入公开的 `API_BASE_URL`。数据库凭据、JWT secret、AI key、SMTP 授权码和签名材料只留在服务器或构建机。
