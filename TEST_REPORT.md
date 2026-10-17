# Flutter 迁移验证与回归测试报告（第七阶段 + 第八阶段发布验证）

> 当前维护范围（2026-10-17）：Flutter 客户端、Node API 和 TypeScript 排程对照测试。React/Tauri 已移除；下文的 React、Rust 和旧 Playwright 结果仅作历史记录，不能作为当前检查命令。清理记录见 REACT_REMOVAL.md。

停用旧版后的本次验证：TypeScript 类型检查、API 构建通过；API / 排程参考实现 168 项 Vitest 测试通过，含独立 PostgreSQL 的认证和同步集成测试；Flutter 静态分析无问题、291 项单元/widget 测试通过、Web JavaScript 发布构建通过。未在本轮重跑 Windows 集成测试或移动端实机验证。

日期：2026-10-17。SDK：Flutter stable 3.47.3 / Dart 3.13.3（`D:\tools\flutter`，项目内 `.dart_tool/pub-cache`）。

下列第七、八阶段数字保留为当时的执行记录。代码审查后发现回归并重新验证，当前结果及边界以第 11 节为准。

本报告是第七阶段（整体验证与回归）和第八阶段（构建、发布准备与文档）的验收清单和执行结果。结论按“自动化通过 / 人工验证通过 / 未验证 / 环境阻塞”四类标注，编译通过不等于全平台验收完成。

## 0. 前置说明

- 仓库内**不存在 `AGENTS.md`**，也**没有任何 CI 配置**（无 `.github/`、无 CI YAML）。测试与构建此前完全依赖手工命令。这两项是本阶段的既有缺口，未擅自新建。
- 第七、八阶段没有改动 `apps/web`、`apps/desktop`、`supabase/`、`packages/planner-engine` 的任何源码；`apps/api` 只有验证时临时替换、随后还原的 `.env`。`git status` 的已跟踪文件改动与第六阶段结束时完全一致。
- API 集成测试使用隔离测试库 `planner_auth_test`（容器 `planner-auth-phase3-20261016`，`127.0.0.1:55438`）。全过程未接触生产数据库，未输出任何凭据；临时替换的 `apps/api/.env` 已还原，无残留备份文件。
- 未升级任何依赖、未改动 Flutter SDK；依赖按已提交的 `pubspec.lock` 解析。

## 1. 验收清单

| # | 验收项 | 测试方式 | 结果 |
| --- | --- | --- | --- |
| 1.1 | Dart 单元测试 | `flutter test test/unit` | 通过 |
| 1.2 | 共享排程 golden（TypeScript 与 Dart 同一 fixture） | `npx vitest run packages/planner-engine/src/golden.test.ts` + `test/golden/planner_scheduler_test.dart` | 通过，92 用例两端一致 |
| 2.1 | API client 解析兼容 | `test/unit/api_client_contract_test.dart` | 通过 |
| 2.2 | API client 超时（45s / 240s / 15s / connect 15s） | 同上 | 通过 |
| 2.3 | API client 错误映射（400/401/403/404/409/422/5xx/传输失败/非 JSON 体） | 同上 | 通过 |
| 2.4 | API client 离线与取消 | 同上 | 通过 |
| 2.5 | Cookie 与 Bearer 两套请求行为 | `api_client_contract_test.dart` + `api_client_test.dart` | 通过 |
| 3.1 | Token 自动刷新、并发刷新共用单航班 | `api_client_test.dart` | 通过 |
| 3.2 | 刷新失败清理会话并通知跳转登录 | `api_client_test.dart` | 通过 |
| 3.3 | 网络故障保留会话供重试 | `api_client_test.dart` + `offline_auth_test.dart` | 通过 |
| 3.4 | 凭据持久化只存 refresh token，损坏记录不阻塞启动 | `test/unit/secure_token_store_test.dart`、`token_store_test.dart` | 通过 |
| 4.1 | 持久化、revision/pending/base 同事务 | `test/unit/storage_repository_test.dart` | 通过 |
| 4.2 | 备份语义（仅数据变化才覆盖备份） | 同上 | 通过 |
| 4.3 | 损坏恢复（主→备份、损坏副本保留、双损坏停止写入） | 同上 | 通过 |
| 4.4 | 原子写入与文件数据库恢复（真实文件系统） | 同上 | 通过 |
| 4.5 | JSON 往返（原始 v1 与 envelope、跨账号重映射） | 同上 + `file_transfer_test.dart` | 通过 |
| 5.1 | 离线编辑与恢复同步 | `test/unit/sync_coordinator_test.dart` + integration | 通过 |
| 5.2 | revision/base 三方合并、同日总量修正 | `test/unit/sync_test.dart`、`test/unit/sync_api_http_test.dart` | 通过 |
| 5.3 | 冲突暂停、显式选择合并、删除不静默覆盖 | `sync_test.dart` + integration | 通过 |
| 5.4 | 重试（瞬时失败、单航班、周期重试随 dispose 取消） | `sync_coordinator_test.dart` | 通过 |
| 5.5 | 账户与 API 地址隔离 | `sync_coordinator_test.dart` | 通过 |
| 6.1 | 路由保护与登录跳转 | `test/widget/app_test.dart` | 通过 |
| 6.2 | 表单校验（登录/注册/新建事项/记录用时） | `test/widget/planner_ui_test.dart` | 通过 |
| 6.3 | 异步加载/成功/失败/重试状态 | `planner_ui_test.dart` | 通过 |
| 6.4 | 响应式布局（1400/390/320 宽度） | `planner_ui_test.dart`、`app_test.dart` + integration | 通过 |
| 6.5 | 重要操作（保存实际用时修正当天总量、新增事项上传） | `planner_ui_test.dart` | 通过 |
| 7.1 | 集成：登录加载云端计划并跨页一致 | `integration_test/app_flow_test.dart` | 通过（Windows） |
| 7.2 | 集成：离线修改 → 重启恢复 → 联网上传 | 同上 | 通过（Windows） |
| 7.3 | 集成：revision 冲突 → 暂停 → 显式解决 | 同上 | 通过（Windows） |
| 7.4 | 集成：记录用时在今日/进度与服务端一致 | 同上 | 通过（Windows） |
| 7.5 | 集成：JSON 导出 → 修改 → 导入 → 再同步 | 同上 | 通过（Windows） |
| 7.6 | 集成：侧栏与底部导航切换 | 同上 | 通过（Windows） |
| 8 | 今日/事项/日历/进度对同一数据一致 | `planner_ui_test.dart` + integration + Chrome 人工验收 | 通过 |
| 9 | 原有测试与构建不回归 | Vitest、typecheck、API/React build、Rust、Flutter Web/Windows build | 通过 |
| 10.1 | 发布阻塞项核对与修复 | 逐平台清单比对（Android 主清单、Web 元数据、iOS 配置） | 通过，见第 10 节 |
| 10.2 | 构建脚本可用 | `tool/build-release.cmd -PrepareOnly` 及完整发布构建 | 通过 |
| 10.3 | Web 路由刷新与静态资源 | 无 SPA 回退的静态服务器 + 真实浏览器 | 通过，14/14 |
| 10.4 | Web 发布产物端到端可用 | 发布产物指向隔离测试库，跑完整界面流程 | 通过，22/22 |
| 10.5 | API 地址注入与无密钥泄漏 | 检查 `main.dart.js` 产物内容 | 通过 |
| 10.6 | 使用与发布文档 | `apps/flutter_client/README.md`、根 `README.md` | 完成 |

## 2. 自动化结果（可复核）

| 套件 | 命令 | 结果 |
| --- | --- | --- |
| Flutter 分析 | `flutter analyze --no-pub` | No issues found |
| Flutter 单元 + widget | `flutter test --no-pub` | **281 通过 / 0 失败** |
| Flutter 集成（Windows 真机进程） | `flutter test integration_test/app_flow_test.dart -d windows` | **6 通过 / 0 失败** |
| 共享 golden（TypeScript oracle） | `npx vitest run packages/planner-engine/src/golden.test.ts` | 93 通过（92 用例 + 1 汇总） |
| Vitest 全量（含隔离 PostgreSQL） | `npm test`（`AUTH_TEST_DATABASE_URL=…planner_auth_test`） | **185 通过 / 0 跳过**，含 11 认证 + 6 同步集成 |
| 根 TypeScript | `npm run typecheck` | 通过 |
| React 构建 | `npm run build` | 通过 |
| API 构建 | `npm run api:build` | 通过 |
| Rust 桌面存储 | `npm run desktop:test` | 6 通过 |
| Flutter Web 发布构建 | `flutter build web --dart-define=API_BASE_URL=…` | `✓ Built build\web` |
| Flutter Windows 发布构建 | `flutter build windows --dart-define=API_BASE_URL=…` | `✓ Built …\Release\sjtu_study_planner_client.exe` |

第七阶段新增 81 项自动化测试，全部针对真实风险，无跳过断言、无空壳 mock：

| 新增文件 | 用例 | 覆盖 |
| --- | --- | --- |
| `test/unit/api_client_contract_test.dart` | 32 | 超时、状态码映射、非 JSON 体、取消、Cookie/Bearer、UTF-8 与大数据体、会话处理 |
| `test/unit/secure_token_store_test.dart` | 8 | 凭据持久化与损坏记录 |
| `test/unit/sync_api_http_test.dart` | 19 | 真实 Dio 上的 `/api/planner/sync` 拉取/推送/409 冲突/字段校验 |
| `test/unit/sync_coordinator_test.dart` | 14 | 离线、重试、单航班、删除暂停、账户与地址隔离、在飞行期间编辑不丢失 |
| `test/widget/planner_ui_test.dart` | 8 | 表单、异步失败与重试、破坏性阻断态、响应式、保存后跨端一致 |
| `integration_test/app_flow_test.dart` + `support/` | 6 | 真实 socket + 真实文件数据库的端到端闭环 |

## 3. 本阶段修复的缺陷

修复均先由失败测试复现，再改实现，再重跑受影响套件。

1. **凭据损坏会中断会话恢复**（`lib/core/auth/token_store.dart`）：`SecureTokenStore.read()` 对无法解析、缺少 `refreshToken`、或 `refreshToken` 为空的记录直接抛 `FormatException`，导致启动检查会话时崩溃；空令牌还会让刷新请求带着无效值发出。现改为清除该损坏记录并返回“无会话”。复现用例：`secure_token_store_test.dart` 三项。
2. **服务端计划缺少引用校验**（`lib/core/sync/sync_api.dart`）：`HttpSyncApi` 只做 JSON 解析，服务端返回悬空 `task_id`/`subject_id`/`block_id` 时会被接受并落盘，与本地存储的校验强度不一致。现调用 `validatePlanner`，与 `SembastStorageRepository` 同规则，失败映射为 `ResponseFailure`。复现用例：`sync_api_http_test.dart` 的“document that fails domain validation is rejected”。
3. **新建事项默认日期用设备时钟**（`lib/features/planner/presentation/planner_dialogs.dart`）：与全项目 Asia/Shanghai 的日期约定不一致，跨时区设备会得到不同的起止日期。改用 `shanghaiToday()`。复现用例：`planner_ui_test.dart` 的“new-task form”用例。

## 4. 人工验证

**Chrome（Web）**：使用隔离测试库启动真实 Flutter Web 客户端，Playwright 驱动完整流程，22 项界面断言全部通过，除登录前的正常 401 探测外无控制台错误。覆盖：登录 → 今日页显示服务端课程分组与事项 → 记录 75 分钟后显示“1小时15分”且服务端收到 `PUT /api/planner/sync` → 重排预览打开并取消 → 事项页新建事项写入云端 → 日历显示固定事件与当天可用容量 → 进度页累计一致 → 设置页显示备考信息与云端版本 → 414px 宽度切换底部导航且无横向溢出。验收用的截图与驱动脚本属于临时产物，已清理，不入库。

**Windows（桌面）**：集成测试以真实进程运行（`-d windows`），使用真实 `Dio` socket 与真实文件数据库（Sembast 文件 + `.recovery.json` 备份）。

## 5. 未验证项

- **Android**：未编译、未实机验证。`flutter doctor` 报告 `[✗] Android toolchain`。待执行：安装 Android SDK/命令行工具 → `flutter doctor --android-licenses` → `flutter build apk --debug` → 在设备或模拟器上跑 `integration_test/app_flow_test.dart`（需把 `FakePlannerServer` 的地址换成可达地址，移动端用 `10.0.2.2`）。
- **iOS / macOS**：未编译、未实机验证，需 macOS 与 Xcode；本机为 Windows，属硬阻塞。
- **Windows 安装包（NSIS/MSI）**：本阶段只做 `flutter build windows` 发布编译，未打包、未在干净机器上安装验证。
- **真实 AI 输出**：备考向导在未配置 AI 密钥时走服务端确定性回退；本阶段未对真实模型输出验收。
- **服务端结算与正式生成**：`结束今天` 与客户端重排仍只写本机并经 `/api/planner/sync` 提交，未接 `/api/daily-reviews/:date/settle` 与 `/api/plans/generate`（第六阶段记录的既有边界）。
- **触屏拖拽**：日历拖动在桌面为长按拖动；触屏手势与无障碍替代路径未单独验收。
- **Web Wasm**：`flutter_secure_storage_web`、`share_plus` 的 Wasm dry-run 提示仍在，不承诺 Wasm 发布。
- **多设备真实并发**：冲突路径由双服务器桩与集成桩覆盖，未用两台真实设备同时写入验收。

## 6. 环境阻塞与前置条件

| 项 | 状态 |
| --- | --- |
| Flutter / Dart | 可用（3.47.3 / 3.13.3） |
| Chrome | 可用（155） |
| Visual Studio 2022 C++ | 可用（17.14） |
| Windows 11 | 可用（25H2） |
| Android SDK | **缺失**，阻塞 Android 编译与实机验证 |
| Xcode / macOS | **不可用**，阻塞 iOS 与 macOS 编译 |
| PostgreSQL 测试库 | 可用（隔离容器） |
| CI 配置 | **不存在**，所有检查需手工执行 |
| 仓库 `AGENTS.md` | **不存在** |

## 7. 剩余缺陷与风险

- 服务端 `planner.ts` 的生成/结算算法与 Dart domain 规则仍不等价（容量、缓冲、固定事件、14/7 天窗口）。客户端本机排程不作为服务端等价确认接口；两者差异表见 `FLUTTER_MIGRATION_DESIGN.md` 第 9 节。
- 排序契约：`engine.ts` 末级 ID 比较用宿主 `localeCompare`，Dart 用字符比较。人为导入混合大小写/非 ASCII ID 且截止日期、优先级、创建时间完全相同的任务，跨平台顺序无统一契约。
- 新账号在首次联网失败时仍无本机计划（`data == null`），页面显示失败态并提示重试。这是第六阶段记录的有意差异（与 Web 一致，不自动导入预设计划）。
- 同步 `rebase` 以关系表投影为准：直接改写 `planner_sync_state.document` 而不写入关系表会被服务端纠正。验证脚本因此改为经 `PUT /api/planner/sync` 播种。
- 取消的请求当前与离线同归 `OfflineFailure`，页面按“稍后重试”处理。若将来需要区分用户主动取消，需扩展错误模型。

## 8. 复现命令

```powershell
# 仓库根目录
npm run typecheck
npm run build
npm run api:build
npm run desktop:test
npx vitest run packages/planner-engine/src/golden.test.ts

# 需要隔离测试库的完整 Vitest
docker start planner-auth-phase3-20261016
$env:AUTH_TEST_DATABASE_URL = 'postgres://planner_test:phase3-test-only@127.0.0.1:55438/planner_auth_test'
npm test

# Flutter 目录（使用独立 PUB_CACHE，见 apps/flutter_client/README.md）
& D:\tools\flutter\bin\flutter.bat analyze --no-pub
& D:\tools\flutter\bin\flutter.bat test --no-pub
& D:\tools\flutter\bin\flutter.bat test integration_test/app_flow_test.dart -d windows --no-pub
& D:\tools\flutter\bin\flutter.bat build web --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:8787
& D:\tools\flutter\bin\flutter.bat build windows --no-pub --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

## 9. 回滚

第七阶段新增内容：`test/unit/api_client_contract_test.dart`、`test/unit/secure_token_store_test.dart`、`test/unit/sync_api_http_test.dart`、`test/unit/sync_coordinator_test.dart`、`test/widget/planner_ui_test.dart`、`integration_test/`（含 `support/`）、`pubspec.yaml` 的 `integration_test` 开发依赖，以及第 3 节列出的三处实现修复。删除新增测试并回退三处实现即可回到第六阶段状态；不涉及数据库、API、旧客户端或业务数据。

第八阶段新增内容：`tool/build-release.ps1` / `.cmd`，以及 Android 主清单、`web/index.html`、`web/manifest.json`、`ios/Runner/Info.plist` 的平台配置修复；文档改动在 `apps/flutter_client/README.md`、根 `README.md`、`FLUTTER_MIGRATION_DESIGN.md` 第 12 节和本报告。回退这些文件即可回到第七阶段状态，同样不涉及数据库、API 或业务数据。

## 10. 第八阶段：发布准备验证

### 10.1 修复的发布阻塞项

| 项 | 问题 | 处理 | 验证程度 |
| --- | --- | --- | --- |
| Android | 主清单缺 `INTERNET`，release 构建完全没有网络权限 | 在 `src/main/AndroidManifest.xml` 声明 `INTERNET`、`ACCESS_NETWORK_STATE` 与 file_picker 需要的查询；应用名改为「不白学」 | **仅静态核对**（本机无 Android SDK） |
| Web | 发布会话标题、描述、PWA 名称是模板值，主题色是模板蓝 | `index.html` 与 `manifest.json` 改为产品名称/描述与设计令牌色，补 `lang="zh-CN"` 与 viewport | 已在发布产物上验证 |
| iOS | 应用名为模板英文、未声明中文本地化、开发用明文 HTTP 无豁免 | 设中文名与 `CFBundleLocalizations`；ATS 明文豁免严格限制在 `127.0.0.1` / `localhost` | **仅静态核对**（需 macOS/Xcode） |
| 文档 | README 曾称 Web 需要 SPA 回退规则 | 实测为 hash URL 策略，已更正 | 已在发布产物上验证 |

Android 的 `applicationId`（仍是 `com.example.sjtu_study_planner_client`）与 release 签名（仍是 debug 签名）作为**发布前必改项**记录在文档中，本阶段未擅自更改，因为改动应用身份会影响既有安装。

### 10.2 真实产物验证

| 检查 | 方式 | 结果 |
| --- | --- | --- |
| 发布构建产物 | `tool/build-release.cmd -ApiBaseUrl https://47.116.63.161 -Target All -Mode Release` | Web 与 Windows 产出并打印绝对路径；Android 因无 SDK 跳过并告警 |
| Web 静态资源与 PWA 元数据 | 无 SPA 回退的静态服务器 + 真实浏览器，14 项断言 | 全过 |
| Web 路由与刷新 | 深链接 `/#/tasks` 未登录重定向 `/#/login`；刷新 HTTP 200 且视图重新挂载 | 全过 |
| Web 发布产物端到端 | 发布产物 + 隔离测试库，22 项界面断言 | 全过（含真实登录、Cookie/CORS、记录用时上传、新建事项、响应式） |
| API 地址注入 | 产物 `main.dart.js` 含生产地址 | 通过 |
| 无密钥泄漏 | 产物不含 `JWT_*_SECRET`、`AI_API_KEY`、`SMTP_PASS`、`service_role` | 通过 |
| 静态服务器来源白名单 | 从非白名单来源打开发布产物 | 被 CORS 拒绝（符合预期），证明白名单生效 |

产物绝对路径（本机）：

```text
D:\_projects\sjtu-study-planner\apps\flutter_client\build\web\index.html             Web 入口
D:\_projects\sjtu-study-planner\apps\flutter_client\build\web\main.dart.js           Web bundle (3.36 MB)
D:\_projects\sjtu-study-planner\apps\flutter_client\build\web\manifest.json          PWA manifest
D:\_projects\sjtu-study-planner\apps\flutter_client\build\windows\x64\runner\Release\sjtu_study_planner_client.exe
D:\_projects\sjtu-study-planner\apps\flutter_client\build\windows\x64\runner\Release\data   (27.1 MB)
```

### 10.3 第八阶段未验证项

- **Android**：未编译、未实机。清单修复只做静态核对；`applicationId` 与 release 签名仍是模板状态。
- **iOS**：未编译、未签名，需 macOS/Xcode。
- **Windows 安装包**：未打包 NSIS/MSI，未在干净机器安装。
- **Web 离线资源缓存**：未实现 Service Worker；`manifest.json` 只提供安装元数据，不代表可离线运行。
- **商店上传、线上部署、生产迁移**：按要求未执行。
- **旧客户端停用**：未执行，须另行决定。

### 10.4 与旧客户端的功能对等

Flutter 客户端与旧 Web 客户端功能对等：六个业务页面、邮箱验证码注册与登录、备考资料向导与 AI 草案、JSON 导入导出与备份恢复、离线修改与同步冲突处理均已迁移并有测试覆盖（281 项单元/widget + 6 项集成 + 22 项发布产物界面断言）。

已知差异（有意保留，非缺陷）：`结束今天` 的服务端结算与用服务端生成替代本机重排未接入页面；客户端不自动导入 Web 的整套预设课程与事项，新账号的课程与事项由备考向导生成。

## 11. 审查问题 1、3、4 修复（2026-10-17）

用户确认旧 React 客户端兼容性不再作为本轮验收目标，本轮只修复同步、离线路由和今日记录，未删除或调整旧客户端代码。

- **问题 1：汇总投影覆盖时间块**。保留原时间块的 ID、开始时间、固定标记、创建时间和反馈，只合并真正发生变化的共享字段；实际时长按时间块顺序分配，超额记到最后一块。日志按 ID 合并变动字段，保留未变化的分块引用。无法安全映射的汇总时长变化、删除固定或已完成块返回 409，事务回滚保留原快照，不自动丢弃详细安排。此类结构冲突需先核对并纠正云端汇总，再重试。
- **问题 3：离线重启误入向导**。备考资料读取失败与明确不存在分别处理；同一账号的本机计划可直接进入工作台。没有缓存时显示错误及重试。资料请求加入账号与请求代次校验，避免迟到响应覆盖新状态；未登录时不初始化文件选择器和计划存储。
- **问题 4：重复保存清空记录**。从原数据初始化完成程度和反馈，保存只修改用户实际编辑的字段；domain 层统一处理校验及记录，应用层一次保存。整体反馈新增可选 `daily_feedback`，通过现有 v1 JSON/存储/同步往返并按日期合并，不改数据库结构。
- **既有失败测试**：账号隔离测试原先两个账号共用同一个远端桩，导致错误地向 B 返回 A 的计划；现使用各自账号的独立远端，保留共享本机数据库及重启断言。

已完成：Flutter 单元/widget **291 通过 / 0 失败**；Vitest **188 通过**（隔离 PostgreSQL），其中同步集成 **9 项**；`flutter analyze`、根 TypeScript 检查、API 编译、Flutter Web/Windows 发布构建通过。原有 Wasm dry-run 提示仍在，普通 JavaScript Web 构建成功。

Windows 关键离线集成 **1 项通过**：`flutter test integration_test/app_flow_test.dart -d windows --no-pub --plain-name 'an offline edit survives a restart and uploads when back online'`，新增了离线重启后今日页、事项页可见的断言。此项使用真实 Windows 进程、socket 和文件数据库，覆盖断网编辑、关闭、重启读取、页面访问、网络恢复与上传；没有将前阶段全部 6 项集成记为本轮重跑。路由新增只读缓存探测，另有 widget 测试确保新账号在资料查询完成前不启动云端同步，避免默认计划抢先创建备考资料。

Android/iOS 本轮未验证，环境限制与第 5 节一致。没有生产迁移、发布或远端部署。
