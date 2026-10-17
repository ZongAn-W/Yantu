# Flutter 统一客户端迁移设计

> 当前状态（2026-10-17）：已决定停用 React/Tauri，Flutter 为唯一维护的客户端。下文是迁移各阶段的历史记录，其中“保留旧客户端”“并行运行”“停用另行决定”等描述不再代表当前维护范围。运行与清理方式见根目录 README.md 和 REACT_REMOVAL.md。TypeScript 排程参考实现及共享 fixture 仍保留。

本文是第一阶段的审计结果和迁移设计。第一阶段只记录现有行为、目标接口、目录规划和验收标准；不删除 `apps/web`、`apps/desktop` 或 `packages/planner-engine`，也不改变现有运行时行为。

## 1. 审计结论

### 现有运行时边界

| 区域 | 当前实现 | 迁移约束 |
| --- | --- | --- |
| Web | `apps/web` 使用 React 19、TypeScript、Vite、React Router 7、CSS 和 Lucide | 继续作为可运行客户端，Flutter 与它并行 |
| Windows | Tauri 2 WebView 加载 Web 页面，Rust 提供文件存储和文件对话框 | 保留现有桌面版；Flutter Windows 使用独立入口 |
| API | `apps/api` 使用 Fastify、Zod、PostgreSQL、JWT、Argon2、Nodemailer | 保留现有路由和数据库；认证与同步只做向后兼容的增量接口 |
| 排程 | `packages/planner-engine` 是 TypeScript 独立包，Web 直接调用 | TypeScript 作为旧客户端和 golden oracle；Dart 迁移必须通过同一输入输出测试 |
| Supabase | Web `store.tsx` 使用 Supabase Auth、Realtime 和 RPC 的 `revision` | Flutter 第一阶段走 Node API；Supabase 数据结构继续保留，不迁移数据库 |

### Web 入口和页面行为

`apps/web/src/App.tsx` 的路由和导航如下：

| 当前路径 | 页面 | 主要行为 |
| --- | --- | --- |
| `/` | `Dashboard` | 今日事项、计划/实际分钟、完成状态、记录用时、每日复盘、重排预览和撤销 |
| `/calendar` | `Calendar` | 日/周计划、固定事件、拖动或编辑事项日期 |
| `/tasks` | `Tasks` | 事项筛选、新建/编辑/删除、事项完成状态、未来事项显示切换 |
| `/progress` | `Progress` | 完成环、周比较、月热力图、剩余量和课程累计实际用时 |
| `/settings` | `SettingsPage` | 备考信息、排程边界、课程优先级、导入导出、同步和账号 |
| 前置流程 | `AuthPage`、`Onboarding` | 邮箱登录/注册验证码；六步备考资料；AI 草案编辑和确认 |

主导航是“今日、日历、事项、进度、设置”。桌面使用侧边栏，窄屏使用菜单和底部导航等价物。重要交互均有加载、错误和成功状态；表单使用浏览器校验并支持键盘操作。

### 数据模型

`packages/planner-engine/src/types.ts` 定义当前 `PlannerData` v1：

- `Profile`：考试日期、目标院校/方向、每日上限、粒度、机动时间、单科上限、学习时间窗口和 `planning_mode`。
- `Subject`：课程 id、名称、颜色、优先级。
- `Task`：课程事项、描述、预计/已完成分钟、起始日期、截止日期、优先级和状态。
- `ScheduleBlock`：事项某天的计划分钟、实际分钟、完成状态、建议文本/主题和历史时间字段。
- `TimeLog`：事项/时间块/日期/分钟/来源；同一事项同一天的手动输入代表该天总量。
- `FixedEvent`：课程、考试、休息和正式考试，支持不重复/每天/每周重复。
- `ReplanRun`、`ReplanChange`、`Conflict`、`DayChange`：重排前后快照、变更、冲突和日容量变化。
- `Phase`：备考阶段日期和说明。

数据空间键为 `sjtu-study-planner:items-v2`；登录用户的云端缓存使用 `:cloud:<userId>`。存储元数据为 `{ version, revision, pending, base, updatedAt }`。导出文件目前是原始 `PlannerData` JSON，主存储还会单独保存元数据。

### 本地存储和恢复行为

`apps/web/src/storage.ts` 已提供 `PlannerStorage` 接口：

```text
load(key) -> data, metadata, recovered, error
save(key, data, metadata, recovery?)
importJson()
exportJson(data)
```

浏览器使用 `localStorage` 主键和备份键；保存前保留上一份有效值，读取失败时尝试备份。Tauri Rust 在应用数据目录保存主文件和 `.bak`，写入采用临时文件加原子替换，主文件损坏时保留 `.corrupt-*` 并恢复备份；主备份都损坏时停止覆盖，要求显式导入。导入会先做 `normalizePlannerData` 校验，导出/恢复保留事项、时间块、日志和重排快照。

Flutter 必须保留这些语义：离线编辑先落本地；`pending` 可见；冲突时不静默覆盖；损坏数据不能覆盖原文件；导入恢复必须是显式操作。

### API 和认证现状

现有 API 主要路由如下：

```text
POST /api/auth/registration-code
POST /api/auth/register
POST /api/auth/login
POST /api/auth/refresh
POST /api/auth/logout
GET  /api/me
GET/POST /api/onboarding/profile
POST /api/ai/plan-drafts
GET  /api/ai/plan-drafts/:id
POST /api/ai/plan-drafts/:id/confirm
GET  /api/courses                 GET/POST /api/items
PATCH/DELETE /api/items/:id
GET  /api/planner/snapshot
GET  /api/plans                   POST /api/plans/generate
POST /api/daily-reviews/:date/settle
POST /api/study-logs             PATCH /api/study-logs/:id
GET  /api/progress
GET  /api/replan-runs             POST /api/replan-runs/:id/undo
```

当前 Fastify `requireUser` 只读取 `planner_access` httpOnly Cookie；`/api/auth/refresh` 只读取 `planner_refresh` Cookie。访问令牌有效期 15 分钟，刷新令牌有效期 30 天。Web `api.ts` 使用 `credentials: include`，401 后调用 Cookie refresh；刷新失败会发出 `planner:session-expired` 事件。AI 密钥只在 API 环境变量中，客户端不接触。

当前 API 的 `snapshot` 是关系表的组合结果，`settle` 在事务内写学习日志、每日计划和未来重排；Node API 目前没有通用的带 revision 条件写入接口。Web 的 Supabase 路径另有 `load_planner_state`/`save_planner_state` RPC 和 revision 冲突合并逻辑。

## 2. Flutter 目标架构

### 目录规划

第二阶段创建以下目录，第一阶段不创建工程文件：

```text
apps/flutter_client/
  lib/
    main.dart
    app.dart
    bootstrap.dart
    router/
      app_router.dart
      route_guards.dart
    core/
      config/
      errors/
      http/
      auth/
      storage/
      sync/
      platform/
      widgets/
    features/
      auth/
        data/ domain/ presentation/
      onboarding/
      planner/
        data/ domain/ presentation/
      dashboard/
      calendar/
      tasks/
      progress/
      settings/
    shared/
      models/
      serialization/
      validation/
  test/
    fixtures/
    golden/
    unit/
    widget/
  integration_test/
  web/
  windows/
  android/
  ios/
  pubspec.yaml
  analysis_options.yaml
  README.md
```

每个 feature 遵循 `data -> domain -> presentation`：Widget 只订阅 Riverpod provider 和发送意图；API、存储、同步和排程规则放在 domain/data 模块。外部调用者只依赖小接口，具体 HTTP、数据库和平台适配器通过 provider 注入。

### 状态管理和路由

- 使用 Riverpod `Provider`/`Notifier`/`AsyncNotifier`。
- `SessionController` 管理 `unknown/authenticated/unauthenticated/expired`。
- `PlannerController` 管理当前 `PlannerData`、`StorageMetadata` 和修改意图。
- `SyncController` 管理 `connected/syncing/offline/conflict/error`、重试和待同步计数。
- 使用 `go_router`，认证守卫只允许登录用户进入工作台；未完成备考资料时重定向 `/onboarding`。
- 桌面/Web 路由保留 `/`、`/calendar`、`/tasks`、`/progress`、`/settings`；移动端使用同一命名路由和底部导航。

### 网络层和错误模型

`Dio` 通过 `ApiClient` 提供统一超时、JSON 解码、状态码映射和取消请求。错误统一为 `NetworkFailure`、`UnauthorizedFailure`、`ValidationFailure`、`ConflictFailure`、`ServerFailure`、`OfflineFailure`，页面只处理这些领域错误。

请求拦截器按平台选择认证方式：Web 保留 `withCredentials` Cookie；Windows/Android/iOS 发送 `Authorization: Bearer <accessToken>`。401 只允许单航班 refresh 请求，刷新成功重放原请求，失败清理会话并跳转登录。AI 请求超时沿用 240 秒，其余请求默认 45 秒，refresh 15 秒。

### 认证兼容方案

保留现有 Cookie 登录响应和 Web 行为。为 Flutter 增加显式 Bearer 模式：

1. `/api/auth/login` 和 `/api/auth/register` 接受 `X-Client-Auth: bearer`，返回 `{ user, accessToken, refreshToken, expiresIn }`；没有该请求头时仍只设置现有 Cookie。
2. 增加 `POST /api/auth/token/refresh`，请求体携带 refresh token，返回轮换后的 access/refresh token。现有 `/api/auth/refresh` 继续只处理 Cookie。
3. `userFromRequest` 先解析 `Authorization: Bearer`，没有 Bearer 时回退到 Cookie；所有业务路由仍通过 `requireUser`，因此旧客户端不变。
4. 增加 refresh token 哈希表和轮换/撤销字段的数据库迁移，服务端只保存哈希，不保存原 token。Flutter refresh token 只进入 `flutter_secure_storage`，access token 只保存在内存和受保护的短期缓存中。
5. JWT secret、AI key、数据库连接信息永远留在 API 环境变量，不进入 Flutter 构建产物。

第三阶段必须为 Cookie 登录、Bearer 登录、过期自动刷新、refresh 失败清理和未授权业务请求补充 API 集成测试；现有 7 个数据库依赖认证测试需要在测试数据库可用时启用。

### 存储接口和平台适配

对外只暴露一个 `StorageRepository`：

```text
load(userKey) -> StorageSnapshot
save(userKey, PlannerData, StorageMetadata, recovery: bool)
exportJson(PlannerData) -> ExportResult
importJson() -> PlannerData
restore(PlannerData)
markPending(bool)
recoverFromBackup() -> RecoveryResult
```

第一版选用 Sembast 文档数据库作为跨平台本地数据库：IO 平台使用文件数据库，Web 使用 `sembast_web` 的 IndexedDB。若 Flutter stable 验证发现 Web 适配不稳定，保留同一接口并切换为 `DriftStorageRepository`（IO SQLite）加 IndexedDB adapter，不让 Widget 或同步层感知实现变化。凭据仍由 `flutter_secure_storage` 管理，不与 PlannerData 混存。

文件能力由 `FileTransferRepository` 隔离：

- Windows：`file_picker`/保存对话框，临时文件加原子替换，保留备份和损坏副本。
- Android/iOS：`file_picker` 导入；导出使用 `share_plus` 系统分享或保存面板。
- Web：文件选择器导入，浏览器下载导出，IndexedDB 持久化。

导入格式先接受当前原始 `PlannerData`，同时接受带 `version/data/metadata` 的 envelope；校验失败不覆盖当前数据。`version`、`revision`、`pending`、`base`、`updatedAt` 字段保持原名和含义。

### 同步设计

`SyncRepository` 维护三份值：`local`、`base`、`remote`，以及 `revision` 和 `pending`。修改流程为：先更新本地并保存；在线时提交条件 revision；成功后把服务端响应设为新的 `base`；revision 不匹配时取得远端版本，按实体 id 和字段修改合并，再让用户确认冲突结果。

为支持 Node API 的离线恢复，在不改变现有业务路由的前提下新增：

```text
GET  /api/planner/sync
  -> { data: PlannerData|null, revision: number }

PUT  /api/planner/sync
  body: { data: PlannerData, base: PlannerData|null, expectedRevision: number }
  -> 200 { data: PlannerData, revision: number }
  -> 409 { conflict: true, data: PlannerData, revision: number }
```

服务端在事务中校验所有子表、按 expected revision 写入并递增 revision；已有 `/api/planner/snapshot`、`/api/study-logs`、`/api/daily-reviews` 等路由继续可用，Web 不必切换。若正式排程只能通过服务端执行，客户端只把离线排程作为预览，确认时仍调用服务端 `/api/plans/generate` 或 `/api/daily-reviews/:date/settle`。

## 3. 排程引擎迁移

### TypeScript 行为基线

`packages/planner-engine/src/engine.ts` 当前公开接口为：

```text
addDays, dateToday, eventOccursOn
taskCompletedMinutes, remainingTaskMinutes
fixedEventMinutesForDate, availableDailyMinutes
validateBlockPlacement
generateReplanPreview
confirmReplan, undoLastReplan
```

约束和行为必须保留：

- 每日有效上限不超过 480 分钟，并至少扣除 30 分钟机动时间。
- 默认学习粒度 30 分钟；单科每天最多 240 分钟。
- 固定事件按时间并集扣除容量，重复事件支持 daily/weekly。
- daily 模式不强制学习开始时间；timed 模式检查时间窗、粒度、时间块和固定事件重叠。
- 未完成重排处理未来 14 天；超额完成最多提前 7 天。
- 重排先返回 preview，包含 `before/after/changes/postponed/advanced/conflicts/daily_changes`，确认后才改变状态。
- 已完成事项不再安排；截止日期、起始日期、每日容量、单科容量不足会形成冲突。
- `undoLastReplan` 保留重排历史并恢复最近一次确认前快照。
- `recordTaskDayMinutes` 将同一事项同一天视为总量修正，不把重复提交相加；独立设备的日志按日期和事项合并。

### Dart 迁移方式

先为 TypeScript 和 Dart 定义相同 JSON fixture，覆盖日期、固定事件并集、容量边界、重叠、冲突、14/7 天窗口、确认/撤销和日志合并。Dart 版本放在 `features/planner/domain/scheduler/`，不在 Widget 中复制规则。每个 fixture 先由 TypeScript 生成期望 JSON，再由 Dart 测试逐字段比较；迁移期间 TypeScript 仍是 Web/Tauri 的实现和回归 oracle。

客户端离线排程只负责可解释的本地预览和恢复网络前的编辑反馈；服务端排程负责正式计划、每日结算和 AI 建议。两者必须共享 `PlannerData` 和约束字段，服务端确认结果优先，客户端发现差异时显示同步状态而不是静默覆盖。

## 4. 页面迁移顺序和验收

### 阶段 1：审计和设计（本阶段）

产物是本文档。验收：现有路由、模型、认证、存储、同步和排程约束有来源；风险和兼容点有记录；现有 TypeScript、Web、Rust 检查通过；没有删除旧代码。

### 阶段 2：Flutter 壳和平台工程

创建 `apps/flutter_client`、Riverpod/go_router/Dio 基础设施、平台入口和 `StorageRepository` 空实现。验收：`flutter analyze`、`flutter test` 通过；Web `flutter build web` 和 Windows `flutter build windows` 在开发机可编译；移动平台至少完成 debug 编译配置。

### 阶段 3：模型、API 和认证

迁移 freezed/json_serializable 模型，完成 Cookie/Bearer 兼容、refresh、统一错误和 API client。验收：未登录守卫、登录/注册/验证码、过期刷新、refresh 失败退出、草案和 snapshot 解析测试通过；旧 Web API 测试不回归。

### 阶段 4：本地存储、导入导出和同步

完成主数据、备份、恢复、JSON、离线队列、revision/base 合并和冲突界面。验收：断网可读写；恢复网络自动同步；冲突保留两端修改并要求确认；损坏主数据可从备份恢复；Web/Windows/移动导入导出各有测试。

### 阶段 5：Dart 排程引擎

完成 golden fixtures、离线预览、确认/撤销和日志合并。验收：所有 TypeScript golden case 与 Dart 输出一致；每日容量、机动、单科上限、固定事件、14/7 天窗口和冲突测试通过；Widget 不包含排程规则。

### 阶段 6：页面迁移

顺序为登录/注册 -> 备考资料 -> AI 草案 -> 今日 -> 事项 -> 日历 -> 进度 -> 设置/数据管理。验收：页面行为和中文文案与 Web 对齐；桌面/Web 侧栏、移动底部导航、响应式布局、键盘和无障碍、异步状态均可用。

### 阶段 7：测试和跨平台验收

新增 Dart 单元、widget、integration、API client、存储、同步冲突和 token 测试；保留现有 Vitest/Playwright/Rust 测试。验收矩阵覆盖 Web、Windows、Android、iOS 的登录、云端加载、离线编辑、恢复同步、冲突、JSON 往返、今日/事项/日历/进度一致性。

### 阶段 8：构建和文档

新增 `apps/flutter_client/README.md`，记录 Flutter stable/Dart 版本、开发和测试命令、四平台构建、API 地址、环境变量、token 和本地存储、发布流程。根 `README.md` 只追加仍然有效的 Flutter 入口说明，不删除旧客户端文档。

## 5. 风险、兼容逻辑和回滚

| 风险 | 影响 | 保留/缓解方案 |
| --- | --- | --- |
| Node API 当前只有 Cookie 会话 | Flutter 无法安全持久化 Web Cookie | 增加显式 Bearer 模式，Cookie 默认分支完全保留；新增认证集成测试 |
| Node API 当前 snapshot 没有 revision 写入 | 离线 Flutter 无法进行条件同步 | 增加 `/api/planner/sync` 和服务端 revision 事务；旧 snapshot 路由保留 |
| Web、Node、Supabase 的数据字段来源不同 | 字段缺失或状态不一致 | Dart 模型使用可选字段和兼容解析；服务端响应先归一化为 `PlannerData` |
| Sembast/IndexedDB 或 Flutter Web 数据库适配变化 | Web 持久化不可用 | 所有调用经过 `StorageRepository`；保留 Drift + IndexedDB adapter 备选实现 |
| Dart 浮点/日期实现与 TypeScript 不同 | 排程结果漂移 | 日期统一 UTC date-only；分钟使用整数；golden tests 阻止漂移 |
| AI 草案生成慢或失败 | 向导无法完成 | Dio 长超时、取消、重试和错误状态；服务端确定性回退继续保留 |
| 多设备同时修改 | 本地数据被覆盖 | `base + revision + entity merge`；冲突进入设置页并允许重试，不自动丢弃本地修改 |
| 旧格式不可自动迁移 | 用户导入失败 | 保持现有 `items-v2` 语义；明确拒绝旧结构，提供 JSON 导入恢复；不删除旧代码 |
| Flutter 平台工具链未安装 | 无法编译验证 | 第二阶段开始前安装 Flutter stable、Dart、Windows SDK、Android SDK、Xcode；当前仅记录为环境前置条件 |

每一阶段都在独立提交中完成，Flutter 客户端通过 feature flag、独立 API client 和独立本地数据键接入。出现回归时可以停用 Flutter 入口、回滚新增 API migration/路由，并继续使用 Web/Tauri；在 Flutter 达到阶段 7 验收前不讨论停用旧客户端。

## 6. 当前验证记录

在 2026-10-16 的现有工作区执行：

- `npm run typecheck`：通过。
- `npm test`：75 个测试通过，7 个需要数据库的认证集成测试跳过。
- `npm run build`：通过，Vite 仅报告 bundle 大小提示。
- `cargo test --manifest-path apps/desktop/src-tauri/Cargo.toml`：6 个存储测试通过。
- `flutter`/`dart`：当前机器未安装，因此没有执行 Flutter 分析或构建。

工作区在审计开始前已有未提交修改，本文档按这些修改后的认证/API/Web 行为审计，没有覆盖或撤销它们。

## 7. 实施进度（2026-10-16）

第二阶段已创建 Flutter 四平台宿主、Riverpod/go_router/Dio、存储接口和 IO/IndexedDB 适配；Flutter 3.47.3 / Dart 3.13.3 已安装，Web 编译及调试启动可用。Windows 仍待 Developer Mode/Visual Studio 修复，Android 待 SDK，iOS 需要 macOS。

第三阶段已增加完整 Dart 模型与生成序列化、类型化计划/备考/AI 草案客户端、Cookie/Bearer 双认证、refresh 哈希存储和事务轮换/撤销、登录注册 UI、路由守卫，以及今日计划只读加载。客户端数据保持 `PlannerData.version=1` 与现有 snake_case 字段，metadata 保持 `updatedAt`，日期保留 date-only 字符串。服务端业务表及旧 Cookie 响应保留。

第四阶段尚未验收：本地持久化编辑、网络恢复自动同步、revision/base 冲突处理、文件导入导出和恢复仍需继续实现。第六阶段的备考向导、草案确认页面和完整事项/日历/进度/设置交互尚未迁移；新账号登录后显示无计划状态。第三阶段新增认证与模型测试不代表这些后续功能已经可用。

本次验证：Flutter 分析无问题，19 个 Dart/widget 测试通过，Flutter Web 发布构建及 Chrome 调试启动通过；现有 Vitest 86 个测试通过（含独立 PostgreSQL 上的 11 个认证集成测试，无跳过），根 TypeScript 检查、API/React 构建和 6 个 Rust 测试通过。浏览器使用隔离测试库完成 Cookie 登录、刷新恢复、退出，并正确显示云端计划 90 分钟/真实日志 35 分钟。SMTP 在 API 集成测试中使用替身，没有发送真实验证码邮件；Windows/Android/iOS 本次没有完成平台二进制验收。

Flutter Web 普通 JavaScript 构建通过，但 `flutter_secure_storage_web`/`share_plus` 的 Wasm dry-run 仍有兼容提示，当前不承诺 Wasm 发布。Web 不使用插件保存 token；后续可通过升级或平台依赖隔离解决该提示。

## 8. 第四阶段实施记录（2026-10-16）

已实现 Sembast IO/IndexedDB 存储、事务快照及同步 metadata、有效快照备份、Windows 原子 JSON 写入、损坏文件保留/数据库恢复、跨平台文件选择与保存、账号/API 数据隔离、离线账号恢复、今日累计用时编辑、15 秒/前台自动同步、冲突暂停与显式选择、设置页状态和恢复入口。

Node API 新增 `/api/planner/sync` 和 `planner_sync_state`，保留导出字段并投影到现有关系表；revision 触发器跟踪旧路由写入。同步事务同时校验基线和 revision，SERIALIZABLE 冲突重试；非 UUID 导出 ID 做稳定映射，旧 API 继续读取原有表。没有停用旧客户端，也没有更改 Supabase RPC。回滚新增客户端/路由可保留附加表和触发器，不需要回滚业务数据。

验证：Flutter 分析无问题、35 个 Dart/widget 测试通过；Vitest 91 项全部通过，含独立 PostgreSQL 的 11 个认证与 5 个同步集成测试；根 TypeScript、API/React、Flutter Web/Windows 构建通过。浏览器实际关闭 API 后把用时 35 修正为 65 分钟，刷新后从 IndexedDB 恢复，API 重启后自动同步，数据库实查为 65 分钟。Windows 文件原子替换/损坏恢复用主机测试验证。

限制：Android 缺 SDK、iOS 缺 macOS，未完成移动端二进制和文件对话框实机验收。Web API 离线使用已验证，首次完全断网加载静态资源和 PWA 安装尚未实现；Wasm 不在当前构建承诺中。下一阶段为 TypeScript/Dart 排程 golden tests 和引擎迁移，备考向导及完整事项/日历/进度页面仍待迁移。

补充验证：Web 导出 JSON 已实际下载并核对 v1 数据及 65 分钟累计值；设置页检查了桌面和 390px 手机宽度。中文字体已随包保存并保留 OFL 许可证。当前 SDK 的 Web 热重载编译器与 IndexedDB 跨标签通知在热重启后出现过类型异常，启动脚本暂时关闭该编译器选项，调试启动/热重启验证通过；该兼容参数在 SDK 内已标 deprecated，后续 SDK 升级需复测移除。

## 9. 第五阶段实施记录（2026-10-17）

### 实现和兼容

- `packages/planner-engine/fixtures/planner-goldens.json` 为两端直接读取的同一份输入/预期，目前 92 个用例；`golden-cases.ts` 记录输入，显式更新命令生成 TypeScript oracle。普通测试不重写 golden。比较保留全部字段、可选键、null、ID、毫秒 UTC 时间戳、历史快照和数组顺序，只忽略 JSON 对象属性的书写顺序。
- TypeScript 仅增加可选的每次调用时钟和 ID 依赖，原生产调用方式和排程规则保留。Dart 在 `features/planner/domain/scheduler/planner_scheduler.dart` 实现同一组纯函数，不导入 Flutter、HTTP 或本地数据库。
- 已迁移日期/周期、事件并集、daily/timed 容量与冲突、至少 30 分钟缓冲、每日 480 分钟预算和单科 240 分钟硬上限、14 天未完成重排、7 天有限提前、部分执行记录、不可变块、预览/确认/撤销、任务日累计用时和按任务日期合并日志。
- Dart 显式实现稳定排序，保留相同键的输入顺序；40 个同键来源用例防止依赖 Dart `List.sort` 的非稳定行为。默认新 ID 为 UUID v4，失败 slot 尝试也消耗注入 ID，旧块 ID/创建时间的复用与 TypeScript 一致。新时间戳截断至毫秒，不重写历史时间戳；date-only 运算用 UTC，`dateToday` 与 TypeScript 一样使用传入时钟自身的日历日期。
- 模型增加 `ReplanPreview`、`TaskStatusSnapshot`、可选 `task_status_before/after`。旧 JSON 缺省 `planning_mode` 在读取时仍按 daily 运行，导出仍省略该键；其余已定义的可选建议/反馈字段保持省略或存在，日志 `block_id:null` 保留。
- `study_edits.dart` 只转发 domain 操作，今日记录经 `PlannerCoordinator.recordDayMinutes` 调用同一算法。Widget 没有排程规则，也没有在本阶段重写整套页面。

### 离线应用边界

`LocalReplanning` 返回内存 proposal；`PlannerCoordinator.previewReplan/cancelReplan` 不改变本机数据、pending、revision 或云端。`confirmReplan/undoReplan` 使用现有串行编辑、校验、先落盘再同步的流程。应用层确认校验完整当前数据基线，任务、日志、设置、固定事件和建议字段变化都会使预览过期，包括等待存储队列时发生的修改。

domain 保留 TypeScript 的块快照检查；应用层额外在本机确认的 run 中保存可选 `local_undo_guard`（不含历史，避免递归嵌套），撤销前核对完整当前数据。该扩展字段在 JSON、Sembast 和现有 API passthrough 文档中保留，重启后也能阻止覆盖后续学习记录。旧 TypeScript run 没有该字段，仍按原块快照及可选任务状态快照撤销，不能追溯保护旧 run 生成时未保存的日志/设置基线。撤销保留 run，标记 undone，任务 `updated_at` 按原 TypeScript 行为保留确认后的值。

本机确认是对客户端快照的显式编辑，通过现有 revision/base 同步；不调用正式生成或每日结算接口，也不把本机结果声明为 API 排程的等价结果。后续页面应明确区分本机预览和服务端生成/结算，不连续调用两套算法来确认同一个操作。服务端生成后的数据通过现有 revision 同步进入客户端；并发本机修改仍走三方合并和冲突处理。

### 服务端差异审计（保持现状）

| 行为 | TypeScript/Dart domain | `apps/api/src/planner.ts` 现有行为 |
| --- | --- | --- |
| 容量 | 全局每日上限封顶 480，扣至少 30 缓冲、固定事件并集 | `dayMinutes` 直接使用星期容量，无对应缓冲/480 硬限制和固定事件输入 |
| 分配 | 对现有块的待完成部分按粒度尝试，保留有效未来位置 | `generateRows` 每天只遍历每任务一次，每任务最多分配 30 分钟，按截止日期/优先级排 |
| 范围 | 未完成至 today+14（包含第 14 天），提前至 today+7（包含第 7 天），遵守任务起止日期 | 从 from 至 profile.exam_date，遵守任务起止日期，没有客户端的 14/7 窗口 |
| 实际量 | 任务计数与日志取较大值再封顶；放置容量计算实际块/孤立日志 | 剩余量使用数据库日志合计，生成阶段不从每日容量扣除既有实际记录 |
| 不可变块 | 固定任务、固定块、已完成块、窗口外块保留 | generatePlan 先删除 from 之后日程；settleDay 删除未来零实际未完成行，之后 upsert，没有相同的固定块模型 |
| 确认/撤销 | 显式 preview、重复/过期检查、历史状态，客户端额外完整基线保护 | settleDay 事务直接结算并记录 before/after；undoRun 没有客户端的 after 匹配保护 |
| 身份/历史 | 多个块可属于同一任务同一天，完整导出保留每个块 | 关系表按任务/日期合并；`planner_sync_state.document` 保留拆块和扩展字段，snapshot 是聚合投影 |

本阶段没有替换上述服务端实现，没有修改数据库 schema/迁移或部署。新增同步集成用例在隔离测试库验证：同任务同一天的两个 30 分钟块在正式关系表投影为 60 分钟，但连续 GET sync 仍返回原两个 ID、状态快照、建议和本地撤销保护字段。

### 已知歧义和后续问题

- `engine.ts` 的任务最后一级 ID 比较用宿主语言环境的 `localeCompare`；当前 Node 为 `zh-CN`。Dart 使用字符比较，现有小写 UUID 和本阶段 legacy ID 用例一致；人为导入混合大小写/非 ASCII ID、且截止日期/优先级/创建时间完全相同的任务，排序尚无跨平台统一契约。未擅自改动旧引擎的排序规则；需后续独立确定此输入的比较规范。
- TypeScript `addDays` 使用 `Date.parse`，允许 2 月 30 日归一化但拒绝月份 0/13、日期 0/32；Dart 函数按此基线兼容并有 golden。应用存储入口仍使用既有严格真实日期校验，不导入这种日期。
- domain 的快照键故意只含原 TypeScript 列出的核心块字段，不包含建议字段和任务/日志输入；本阶段用应用层完整基线补足本机操作保护，未改变旧 TypeScript/API 的公开行为。
- 完整重排对话框、日历拖动、服务端结算页面仍属第六阶段。Android SDK 未安装，iOS 需 macOS/Xcode；移动二进制/实机没有验证。普通 Web JavaScript 构建可用，插件 Wasm dry-run 提示仍存在。

### 验证

Flutter 3.47.3 / Dart 3.13.3，沿用 `D:\tools\flutter` 和项目 `.dart_tool/pub-cache`。本阶段 147 项 Flutter 测试（含 92 个共享 golden、20 个应用/协调器用例）与全量 185 项 Vitest 通过，无跳过；包括隔离 PostgreSQL 的 11 个认证和 6 个同步测试。Flutter analyze、根 TypeScript typecheck、API/React build、Flutter Web/Windows 发布构建，以及 `tool/run-web.cmd -PrepareOnly` 锁文件/缓存检查通过。复现命令见 `apps/flutter_client/README.md`。首次基线执行曾遇到 `offline_auth_test.dart` 的固定 20ms 等待时序失败，未改认证实现，后续全量运行通过；该时序测试仍可能在负载下波动。

回滚范围为新增 domain/application、协调器几个操作入口、模型增量和 golden oracle 的运行时注入。保留已有 React/Tauri/API/数据库与旧 TypeScript 引擎；没有提交或撤销既有工作区修改。本机 run 的新增可选保护字段可由旧客户端忽略，历史和业务数据无需删除。

## 10. 第六阶段实施记录（2026-10-17）

### 分层与新增模块

Widget 只订阅 provider 并发送意图，规则全部位于 domain/application：

| 层 | 文件 | 内容 |
| --- | --- | --- |
| domain | `planner_format.dart` | 时长/日期/时间文本；`duration` 先四舍五入总值再拆分，避免出现“1小时60分”；`shanghaiToday` 固定用 Asia/Shanghai，复用 Web 的日历语义 |
| domain | `study_day.dart` | 每日统计、按事项分组、事项日/累计用时、进度刷新、事项日完成勾选、事项完成、删除、待安排时长、整日移动、日历容量与固定事件 |
| domain | `task_editing.dart` | `TaskDraft` 与校验、新增/更新事项、新建课程名自动建科目、安排时间块、固定事件冲突检查 |
| domain | `progress_metrics.dart` | 累计实际、剩余量、周计划/实际、燃尽、热力图分档、中断天数、预计完成与落后判断 |
| domain | `initial_plan.dart` | 新账号的最小计划：空课程/事项加不可覆盖的正式初试固定事件 |
| application | `planner_session.dart` | `PlannerSnapshot` 值对象与 `PlannerSession` 命令面（事项、排程、用时、重排、导入导出、冲突、同步） |
| application | `onboarding_controller.dart` | 备考资料六步校验、AI 草案生成/编辑/确认、设置草稿校验与应用 |
| presentation | `planner_dialogs.dart` | 记录用时、调整日期、事项编辑、安排时间块、标记完成、固定事件、结束今天、重排预览 |
| presentation | `planner_page_state.dart` | 统一的加载/失败/阻断/重试外壳 |
| presentation | `shell/app_shell.dart` | 侧栏（≥900px）与底部导航、同步状态条、账号与同步对话框 |
| core | `theme.dart`、`widgets.dart` | 设计令牌、面板/提示/进度条/异步按钮 |

页面路由沿用 `/`、`/calendar`、`/tasks`、`/progress`、`/settings`，新增 `/onboarding` 和内部 `/loading`（等待备考资料查询，避免已完成账号闪现代理向导）。应用层 `plannerSyncProvider` 不再使用 `autoDispose`：路由在等待资料时没有页面订阅计划，autoDispose 会丢弃协调器并在每次切换路由时重新初始化。

### 与 Web 行为的对齐

- 今日：计划/已学/剩余、完成环、按课程分组的事项行、记录用时、今日完成勾选、改日期、结束今天、重排预览+确认、撤销最近调整；文案与 Web 一致。
- 事项：搜索/课程/状态/优先级/截止日期筛选、默认隐藏后续事项、新建/编辑/安排时间块/标记完成/删除（删除前确认）、时间投入与预算。
- 日历：日/周视图、日期步进与今天、每列计划与容量、固定事件（含重复）与删除、超出容量提示、长按拖动或“调整日期”移动、事项行记录用时。
- 进度：课程进度、近 7 天计划/实际柱状图、月度热力图与中断天数、总体燃尽与预计完成、累计实际学习。
- 设置：备考信息、排程边界（上限/粒度/机动/单科/时间窗口）、课程优先级、导出/导入/备份恢复、同步状态与冲突二选一、账号信息。
- 备考向导：六步表单校验 + AI 草案编辑（名称/预算/说明/增删）+ 确认；确认后刷新本机计划并跳转今日。

### 本阶段修复的问题

- `ReplanDialog.dispose` 在卸载后调用 `ref.read`，改为在 `initState` 捕获会话。
- 取消预览时同步 `notifyListeners` 会在组件树 finalize 期间触发 Riverpod provider 重建；改为 microtask 延迟通知。
- `duration` 对小数分钟的进位会产出“1小时60分”，改为先对总值取整再拆分。
- 新账号既无本机也无云端计划时，协调器在“云端为空”分支写入最小计划（含正式初试），使各页面有可编辑数据；不改变已有计划账号的行为。
- `offline_auth_test.dart` 的固定 20ms 等待改为条件轮询，消除负载下的时序抖动。

### 与 Web 有意保留的差异

- 客户端不自动导入 Web 的整套预设课程/事项；新账号的课程与事项由备考向导生成，本机只预置正式初试与休息固定事件。
- 结束今天只写本机（累计用时、完成程度、反馈），不调用 `/api/daily-reviews/:date/settle`。本机重排同样是客户端快照编辑，经 `/api/planner/sync` 的 revision/base 协议提交，不调用 `/api/plans/generate`。两个正式接口仍由服务端实现，未在本阶段接入页面。

### 验证

`flutter analyze` 无问题，201 项 Flutter 测试通过（含本阶段新增 41 项 domain/application/会话测试）。Flutter Web 与 Windows 发布构建、根 typecheck、API/React build 通过；Vitest 185 项全部通过（含隔离 PostgreSQL 的 11 个认证与 6 个同步测试，无跳过）。

真实浏览器验收（Chrome，1440×1000 与 414×896，隔离测试库，未连接生产）：登录后进入今日页，服务端事项与课程分组正确显示；记录 75 分钟后今日页显示“1小时15分”，进度页累计与课程进度同步更新，服务端收到 PUT `/api/planner/sync`；重排预览可打开并取消；事项页新建事项后写入云端并出现在列表；日历显示固定事件、当天容量与新建时间块；设置页显示备考信息、排程边界、同步状态与云端版本；手机宽度切换为底部导航且无横向溢出。22 项界面断言全部通过，除首次会话探测的正常 401 外无控制台错误。截图与脚本保留在 `.dsh-verify/`。

### 剩余问题

- `结束今天` 的服务端结算、以及用服务端生成替代本机重排，仍待后续阶段；当前页面不提供这两个入口。
- 备战向导的 AI 草案依赖服务端 AI 配置；未配置密钥时使用服务端确定性回退，本阶段未对真实 AI 输出验收。
- Android SDK 未安装、iOS 需 macOS/Xcode：移动二进制的编译与实机验收未执行，只有 Web 与 Windows 完成编译验证。
- 日历拖动在桌面端为长按/拖动；触屏手势与无障碍拖拽替代路径尚未单独验收。
- 普通 Web JavaScript 构建可用；`flutter_secure_storage_web` 与 `share_plus` 的 Wasm dry-run 提示仍在，不承诺 Wasm 发布。

回滚范围为新增 domain/application/presentation 文件、`app_router.dart`、`app.dart`、`planner_sync.dart`、`planner_coordinator.dart` 的空云端分支，以及 `planner_page_state`/`app_shell`。保留 React/Tauri/API/数据库与旧 TypeScript 引擎；未提交、未部署，也未撤销既有工作区修改。

## 11. 第七阶段实施记录（2026-10-17）

完整的验收清单、逐项结果、未验证项、环境阻塞和复现命令见根 `TEST_REPORT.md`。本节只记录结论与修复。

### 核对前六阶段

前六阶段的实现与测试均在位，未发现阻断整体验证的问题。仓库内不存在 `AGENTS.md`，也没有任何 CI 配置，因此全部检查为手工执行；这两项按缺口记录，未擅自新建。

### 新增测试（81 项，全部针对真实风险）

| 文件 | 用例 | 覆盖 |
| --- | --- | --- |
| `test/unit/api_client_contract_test.dart` | 32 | 超时分层（45s/240s/15s/connect）、状态码与传输失败映射、非 JSON 体、取消、Cookie 与 Bearer 两套行为、UTF-8 与整份计划体、会话过期回调 |
| `test/unit/secure_token_store_test.dart` | 8 | 凭据只持久化 refresh token、损坏/不完整记录、跨进程重启 |
| `test/unit/sync_api_http_test.dart` | 19 | 真实 Dio 上的 `/api/planner/sync`：拉取解析、revision 校验、领域校验、推送体、409 触发重新拉取、离线与 5xx |
| `test/unit/sync_coordinator_test.dart` | 14 | 离线启动、瞬时失败重试、单航班、删除暂停、账户与 API 地址隔离、周期重试随 dispose 取消、在飞行期间编辑不丢失 |
| `test/widget/planner_ui_test.dart` | 8 | 登录/注册/事项/用时表单校验、加载失败与重试、阻断态、响应式（1400/390/320）、保存后本机与服务端一致 |
| `integration_test/app_flow_test.dart` | 6 | 真实 socket + 真实文件数据库：登录加载云端计划且跨页一致、离线修改经重启恢复并联网上传、revision 冲突与显式解决、记录用时跨页与服务端一致、JSON 导出导入再同步、侧栏与底部导航切换 |

集成测试使用一个本地 `HttpServer` 桩（真实监听端口，永不在线为关闭监听以产生真实连接拒绝）与真实 Sembast 文件数据库（临时目录），仅文件选择器被替换（真实选择器需要人工操作）；凭据存用内存实现，避免污染操作系统钥匙串。公开接口 `integration_test` 由 SDK 提供，已加入 `pubspec.yaml` 开发依赖。

### 本阶段修复

1. `SecureTokenStore.read()` 对无法解析、缺字段或空 `refreshToken` 的记录抛异常/返回不可用令牌，导致启动会话恢复失败并可能发出无效刷新请求。改为清除损坏记录并返回“无会话”。
2. `HttpSyncApi` 缺少与本地存储同强度的引用校验，服务端返回悬空 `task_id`/`subject_id`/`block_id` 时会被接受。改为调用 `validatePlanner`。
3. 新建事项的默认起止日期使用设备时钟而非 Asia/Shanghai，跨时区会得到不同日期。改用 `shanghaiToday()`。

### 验证结论

`flutter analyze` 无问题；Flutter 单元与 widget 测试 **281 通过**；Windows 集成测试 **6 通过**；TypeScript/Dart 共享 golden 92 用例两端一致（Vitest 93 通过）；Vitest 全量 **185 通过、0 跳过**（含隔离 PostgreSQL 的 11 认证与 6 同步）；根 typecheck、React 构建、API 构建、Rust 6 项测试、Flutter Web 与 Windows 发布编译全部通过。Chrome 上以隔离测试库重跑真实界面流程，22 项断言通过且无回归。

### 未验证与阻塞（不得视为通过）

- Android：`flutter doctor` 报告工具链缺失，未编译、未实机验证。
- iOS/macOS：需 macOS 与 Xcode，本机为 Windows，属硬阻塞。
- Windows 安装包未打包、未在干净机器安装验证。
- 真实 AI 输出未验收（未配置密钥时走确定性回退）。
- 服务端 `/api/daily-reviews/:date/settle` 与 `/api/plans/generate` 仍未接入页面。
- 触屏拖拽替代路径、Web Wasm 发布、双真实设备并发冲突未验收。

回滚范围为新增测试目录、`pubspec.yaml` 的 `integration_test` 开发依赖，以及上述三处实现修复；不涉及数据库、API、旧客户端或业务数据。未提交、未部署。

## 12. 第八阶段实施记录（2026-10-17）

本阶段只做发布准备：修发布阻塞项、补构建脚本与使用文档、在真实产物上验证。**不执行商店上传、线上部署或生产迁移**，也未停用旧客户端。

### 工具链核对

Flutter `3.47.3` / Dart `3.13.3`，Dart SDK 约束 `>=3.12.0 <4.0.0`，`pubspec.lock` 已提交且构建脚本使用 `pub get --enforce-lockfile`。本阶段**未升级任何依赖、未改动 Flutter SDK**。`flutter doctor`：Flutter / Windows / Chrome / Visual Studio 可用，**Android 工具链缺失**，iOS 需 macOS。

仓库内仍不存在 `AGENTS.md`，也没有 CI 配置；沿用第七阶段的记录，未擅自新建。

### 修复的发布阻塞项

1. **Android 主清单缺少 `INTERNET` 权限**：模板只在 `src/debug/AndroidManifest.xml` 声明，release 构建完全没有网络权限，装到真机后所有 API 调用都会失败。已在 `src/main/AndroidManifest.xml` 声明 `INTERNET` 与 `ACCESS_NETWORK_STATE`，并补上 file_picker 需要的 `GET_CONTENT`/`CREATE_DOCUMENT` 查询；应用名从模板包名改为「不白学」。**修复已静态核对，但本机无 Android SDK，未做 release 构建或实机验证。**
2. **Web 发布会话缺少标识**：`web/index.html` 的标题、描述、apple 标题与 `web/manifest.json` 的名称都是模板值 `sjtu_study_planner_client` / `A new Flutter project.`，PWA 主题色是模板蓝 `#0175C2`。已改为「不白学 · 考研执行台」、产品描述与设计令牌色 `#275e91` / `#f5f7fa`，并补 `lang="zh-CN"` 与 viewport。
3. **iOS 应用名与本地化未配置**：`CFBundleDisplayName` 为模板英文名，未声明中文本地化，且开发用的明文 HTTP API 缺少受限豁免。已设中文名、`CFBundleLocalizations`（zh_CN / zh-Hans / en），并把 ATS 明文豁免**严格限制在 `127.0.0.1` 与 `localhost`**；Android 的 `applicationId` 与 release 签名仍是模板状态，已在文档中标为发布前必改项。

修正前，`apps/flutter_client/README.md` 曾声称 Web 需要 SPA 回退规则；实测该客户端使用 Flutter Web 默认的 **hash URL 策略**，该说法不成立，已更正。

### 新增脚本

| 脚本 | 用途 |
| --- | --- |
| `tool/build-release.ps1` / `.cmd` | 按锁文件解析依赖 → `flutter analyze` → `flutter test` → 按平台构建 → 打印产物绝对路径与大小 |

支持 `-Target Web|Windows|Android|All`、`-Mode Debug|Release|Both`、`-ApiBaseUrl`、`-SkipTests`、`-SkipAnalyze`、`-PrepareOnly`。缺少 Android SDK 时**跳过并明确告警**，产物缺失标记 `MISSING`，不会把跳过伪装成成功。沿用 `run-web.ps1` 的约定：固定 SDK、项目内独立缓存、镜像环境变量、完整日志。延续既有命名，未引入新的构建系统。

### 真实产物验证

- 发布构建（`-ApiBaseUrl https://47.116.63.161 -Target All -Mode Release`）产出 Web 与 Windows 发布件，脚本打印绝对路径；Android 因缺 SDK 跳过并告警。
- 用**无 SPA 回退**的静态服务器托管 `build/web/`，以真实浏览器验证 14 项：静态资源与 PWA manifest 可访问且内容为中文名称与设计色、页面标题正确、运行时地址为 `/#/login`（hash 策略）、未登录访问 `/#/tasks` 重定向到 `/#/login`、刷新返回 200 且视图重新挂载。控制台仅有指向生产 API 的白名单外 CORS 拒绝——这同时证明服务端来源白名单生效。
- 重新以隔离测试库地址构建 Web 发布件，在同一来源上跑完整界面流程：**22/22 断言通过**，含真实登录（Cookie + CORS）、云端计划加载、记录 75 分钟后 `PUT /api/planner/sync`、新建事项、四个页面与 414px 响应式；除登录前的正常 401 探测外无控制台错误。这证明发布产物本身可用，不只是调试构建。
- `tool/build-release.cmd -PrepareOnly` 按锁文件解析依赖并通过 analyze 与 281 项测试。
- 已核对 `main.dart.js` 不含 `JWT_ACCESS_SECRET`、`JWT_REFRESH_SECRET`、`AI_API_KEY`、`SMTP_PASS`、`service_role` 等任何密钥标识；`API_BASE_URL` 作为公开地址按预期出现在产物中。

### 文档

`apps/flutter_client/README.md` 重写为发布级文档，覆盖：SDK 与各平台前置工具、依赖安装与代码生成、四个平台的启动与构建、API 地址与各运行位置差异、Cookie/CORS、token 与账户隔离、数据库位置与备份恢复、离线与冲突处理、五个层次的测试运行方式、产物位置与部署/签名/发布步骤、回滚与已知限制。根 `README.md` 增加 Flutter 客户端入口并保留原有内容。

### 对等结论与边界

Flutter 客户端与旧 Web 客户端**功能对等**：六个业务页面、认证与验证码注册、备考向导与 AI 草案、JSON 导入导出、离线修改与冲突处理均已迁移并有测试覆盖。仍有差异且已记录：`结束今天` 的服务端结算与用服务端生成替代本机重排未接入页面；客户端不自动导入 Web 的整套预设课程与事项。

**旧客户端停用须另行决定**，本阶段保留 React/Tauri 入口不变。Web 未实现 Service Worker 离线缓存。Android 与 iOS 的构建、签名与实机验收仍未执行。

## 13. 审查后修复（2026-10-17）

用户已确认本轮无需保留旧客户端兼容性，修复范围为审查问题 1、3、4；此次未删除旧代码。

- 同步从关系表的日汇总按字段更新原时间块，保留分块身份、时间和固定标记；日志也按字段更新并保留分块关联。无法安全映射的结构变化返回 409 并保留原计划，需先核对云端汇总后重试。
- 备考资料获取错误不再等同资料缺失；有当前账号的本机计划即可离线进入工作台，无缓存时显示错误和重试。
- 今日记录由 domain/application 层整体保存，只更新用户编辑的字段。可选 `daily_feedback` 保存按日整体反馈，旧 v1 数据不要求该字段，现有侧表 JSON 文档保留它，无数据库迁移；三方合并按日期处理。

本轮完整验证与剩余边界见 `TEST_REPORT.md` 第 11 节。
