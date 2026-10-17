# Flutter 统一客户端

这是考研执行台唯一维护的客户端，使用 Node/Fastify API，覆盖 Web、Windows、Android 和 iOS。

**状态**：登录、备考向导、AI 草案、今日、事项、日历、进度、设置与数据管理全部可用。React/Tauri 源码和配置已移除，详情见根目录 [清理记录](../../REACT_REMOVAL.md)。

## 1. 环境与版本

| 项 | 版本 | 说明 |
| --- | --- | --- |
| Flutter | `3.47.3` stable | 本机路径 `D:\tools\flutter`，可用 `-FlutterSdk` 覆盖 |
| Dart | `3.13.3` | 随 Flutter SDK 提供，不单独安装 |
| Dart SDK 约束 | `>=3.12.0 <4.0.0` | 见 `pubspec.yaml` |
| 依赖锁定 | `pubspec.lock` 已提交 | 脚本使用 `pub get --enforce-lockfile` 严格按锁文件解析 |

不要无依据升级依赖或改动 Flutter SDK：`pubspec.lock` 已提交，升级会改变所有平台的实际行为，需要重新跑完整回归（见 `TEST_REPORT.md`）。

### 各平台前置工具

| 平台 | 需要 |
| --- | --- |
| 通用 | Flutter stable（含 Dart） |
| Web | Chrome 或 Edge（调试用） |
| Windows | Visual Studio 2022「使用 C++ 的桌面开发」workload + Windows 10/11 SDK；系统「开发者选项」中的 Developer Mode（插件符号链接） |
| Android | Android Studio / Android SDK + JDK 17（Gradle 使用 Java 17 目标） |
| iOS / macOS | macOS + Xcode；Windows 上无法构建或签名 |

用 `flutter doctor` 确认。本机当前状态：Flutter / Windows / Chrome / Visual Studio 可用，**Android 工具链缺失（`[✗] Android toolchain`）**，iOS 需 macOS。

### 本地依赖安装与代码生成

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client

# 项目内独立缓存，避免与全局 Pub 缓存互相污染
$env:PUB_CACHE = 'D:\_projects\sjtu-study-planner\apps\flutter_client\.dart_tool\pub-cache'
$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

flutter pub get                    # 按 pubspec.lock 解析
flutter pub get --enforce-lockfile # 严格模式：锁文件与 pubspec 不一致时直接失败

# 模型代码生成（freezed / json_serializable）
# 仅在修改 lib/shared/models/ 或 api_models.dart 后需要；生成产物已提交
dart run build_runner build --delete-conflicting-outputs
```

生成产物为 `*.freezed.dart` 与 `*.g.dart`，与源码一起提交，因此普通构建和测试不需要执行 `build_runner`。

## 2. 启动与构建

统一脚本位于 `tool/`。所有脚本固定 SDK、使用项目内独立缓存、按锁文件解析依赖、记录完整日志。

| 脚本 | 用途 |
| --- | --- |
| `tool/run-web.ps1` / `.cmd` | 启动 Web 调试（默认端口 5180） |
| `tool/build-release.ps1` / `.cmd` | 分析 + 测试 + 各平台构建，并输出产物绝对路径 |

### Web

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client

# 调试启动（Chrome），默认 http://127.0.0.1:5180
.\tool\run-web.cmd
.\tool\run-web.cmd -Port 5181 -ApiBaseUrl http://127.0.0.1:8787

# 发布构建
.\tool\build-release.cmd -ApiBaseUrl https://api.example.com -Target Web

# 等价的手工命令
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
flutter build web --release --base-href /planner/ --dart-define=API_BASE_URL=https://api.example.com
```

`-Mode Release` 的 `run-web.ps1` 只用于验证发布编译路径，不支持热重载，不能代替调试模式验收。

当前 Flutter 3.47.3 的 Web 热重载编译器在 IndexedDB 跨标签通知后热重启可能报类型异常；启动脚本暂时关闭该编译器选项，保留调试和热重启。该参数在 SDK 内已标 deprecated，升级 SDK 后应重新验证再移除。

### Windows

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client

# 调试运行
flutter run -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8787

# 发布构建
.\tool\build-release.cmd -ApiBaseUrl https://api.example.com -Target Windows
```

Windows 构建前必须在「设置 → 系统 → 开发者选项」打开 Developer Mode，否则插件符号链接会失败。

### Android

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client

# 模拟器访问宿主机 API 使用 10.0.2.2（见第 3 节）
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8787

# 发布 APK（release 默认用 debug 签名，上架前必须换正式签名，见第 6 节）
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.example.com

# 按 ABI 拆分，减小体积
flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=https://api.example.com
```

**Android 工具链未安装时脚本会跳过并明确告警**，不会伪装成功。

### iOS

```powershell
# 只能在 macOS + Xcode 上执行
flutter build ios --release --dart-define=API_BASE_URL=https://api.example.com
flutter build ipa --release --dart-define=API_BASE_URL=https://api.example.com
```

Windows 上无法构建或签名 iOS；`flutter doctor` 会显示 Xcode 缺失。

## 3. API 地址与环境配置

API 地址在**编译期**通过 `--dart-define=API_BASE_URL=...` 注入，默认值 `http://127.0.0.1:8787`（见 `lib/core/config/app_config.dart`）。它是公开地址，**绝不放 JWT secret、AI key、数据库凭据或签名私钥**。

### 各平台访问开发 API 的差异

| 运行位置 | `API_BASE_URL` | 原因 |
| --- | --- | --- |
| Web（`run-web.ps1`，端口 5180） | `http://127.0.0.1:8787` | 同一主机，Cookie 可用 |
| Windows 桌面 | `http://127.0.0.1:8787` | 同一主机 |
| Android 模拟器 | `http://10.0.2.2:8787` | `10.0.2.2` 是模拟器指向宿主机的别名；`127.0.0.1` 会指向模拟器自身 |
| Android 真机 | `http://<开发机局域网 IP>:8787` | 真机与开发机需在同一网络，且 API 要监听可被访问的地址 |
| iOS 模拟器 | `http://127.0.0.1:8787` | 模拟器与宿主机共享网络栈 |
| iOS 真机 | `http://<开发机局域网 IP>:8787` | 同 Android 真机 |
| 生产 | `https://<域名>` | 必须 HTTPS；见第 6 节 |

### 浏览器 Cookie 与 CORS

Flutter Web 使用 **httpOnly Cookie** 会话，Dio 开启 `withCredentials`（`lib/core/http/browser_credentials_web.dart`），不向浏览器存储写入 token。服务端 `WEB_ORIGIN` 是**逗号分隔**的白名单；CORS 以该白名单注册并开启 `credentials: true`，且带 `Origin` 的非 GET 请求必须在白名单内：

```dotenv
# apps/api/.env
WEB_ORIGIN=http://127.0.0.1:5180
```

- 开发模式下 API 会自动额外放行 `http://127.0.0.1:5180` 与 `http://localhost:5180`（`NODE_ENV !== 'production'`）；**生产环境不会**，必须显式列入 `WEB_ORIGIN`。
- Windows 和移动端使用 Bearer 会话，无需额外的浏览器来源白名单。
- 只改了 Flutter 的 `-Port` 而没同步 `WEB_ORIGIN`，会出现登录后立刻 401 或写入被 403 拒绝。
- 跨主机（真机访问开发机）时 Cookie 需要 `SameSite=None; Secure`，因此开发环境走 HTTP 时真机登录可能失败；此时用 Bearer 模式或给开发 API 配 HTTPS 反代。

## 4. Token、账户隔离、本地数据与同步

### Token 保存与刷新

- **Web**：httpOnly Cookie，浏览器不保存 token，Dio 带 `withCredentials`。
- **Windows / Android / iOS**：Bearer access token 只在内存，refresh token 由 `flutter_secure_storage` 保存（Windows 凭据管理器 / Keychain / Keystore），**只存 refresh token 哈希对应的原值，access token 从不落盘**。
- access token 有效 15 分钟，refresh token 30 天；服务端只存 refresh token 哈希，并在事务中轮换、撤销旧 token。
- 过期请求先自动刷新再重放；并发 401 只发起**一次**刷新（单航班），其余请求等待同一结果。
- 刷新返回鉴权失败或数据异常 → 清理会话并跳登录页；断网/超时/服务端暂不可用 → **保留凭据**供重试。已成功登录过的账号在 API 离线时仍可恢复本机计划；显式退出或服务端确认失效后不能用缓存绕过登录。
- 凭据记录损坏（无法解析、缺字段、空 refresh token）会被清除并按“无会话”处理，不会阻断启动。

### 账户与 API 地址隔离

本地数据库按 **API 地址 + 账号 ID** 分槽（`sjtu-study-planner:items-v2:<scope>:cloud:<userId>`）。同一台机器上不同账号、不同 API 环境的数据互不可见、互不覆盖。跨账号导入会重设所属账号并重映射实体 ID。

### 本地数据库位置

| 平台 | 位置 |
| --- | --- |
| Windows | `%APPDATA%\com.example\sjtu_study_planner_client\sjtu-study-planner.db`（`path_provider` 应用支持目录） |
| Android / iOS | 应用沙盒支持目录下的 `sjtu-study-planner.db` |
| Web | IndexedDB（`sembast_web`），**不使用 localStorage**，也不覆盖旧 React/Tauri 的数据目录 |

### 备份与恢复

- 主计划与 `{version, revision, pending, base, updatedAt}` 同事务保存。
- 数据内容变化前保留上一份有效快照（`<key>:backup`）；只有同步元数据变化时不会反复覆盖备份。
- IO 平台额外保留 `<db>.recovery.json`；启动前校验数据库文件，损坏时保留 `<db>.corrupt-*` 并尝试从备份恢复。
- 主数据与备份都无效时**停止编辑和同步**，允许显式 JSON 恢复；损坏文件不会被自动删除。
- 导入接受旧客户端原始 `PlannerData` v1 与 `{version,data,metadata}` envelope；字段/日期/引用校验失败不会覆盖主数据。导出始终是旧客户端可读的原始 v1 JSON。
- Windows 导出使用系统保存框并通过 `MoveFileEx` 原子替换；移动端经系统文件选择器；Web 触发浏览器下载。取消选择不改变数据。

### 离线修改与同步冲突

- 离线重启时，只要本机有当前账号的有效计划，备考资料请求失败不会把用户送回首次填写向导。没有缓存时显示读取失败和重试；只有服务端明确返回资料不存在才进入向导。
- 修改先落本机，再同步。每 15 秒及应用回到前台自动重试，也可在设置页手动重试。
- 使用共同 `base` 合并独立字段；同一事项同一天的累计日志按**总量修正**而非相加。
- 同一字段或同一天总量的并发修改会暂停上传，设置页提供「冲突项保留本机 / 使用云端」的显式选择；未选择时保留本机修改与原基线，重启后重新识别冲突，不静默丢弃任何一侧。
- 本机排程预览不落盘；确认与撤销经同一串行保存路径。客户端本机重排**不等价于**服务端 `/api/plans/generate`，`结束今天` 目前也只写本机并经 `/api/planner/sync` 提交。
- 关系表中的日计划汇总只更新原时间块发生变化的字段，保留分块 ID、开始时间、固定标记、创建时间、反馈和未变化的日志关联。无法安全映射到分块/固定块/分时模式的汇总时长变化返回 409，保留原快照；需先核对并纠正云端汇总，再重试同步。
- 重新打开「结束今天」会读取已有完成程度和反馈。保存只更新用户改过的字段，并在一次本机保存中提交整份记录；未修改的混合时间块状态和反馈不会被统一覆盖。整体反馈保存为可选 `PlannerData.daily_feedback`（日期到文字的映射），支持 JSON 导入导出和按日期三方合并；旧 v1 JSON 无需增加该字段。

## 5. 测试

| 层次 | 命令 | 说明 |
| --- | --- | --- |
| 静态检查 | `flutter analyze --no-pub` | 必须无问题 |
| 单元 + widget | `flutter test --no-pub` | 291 项（含 92 个共享 golden 用例） |
| 排程 golden（共享 fixture） | 见下 | TypeScript 为 oracle，Dart 逐字段比对 |
| API / 存储 / 同步单元 | `flutter test --no-pub test/unit` | 含真实文件系统与真实 Dio |
| Flutter integration | 见下 | 真实 socket + 真实文件数据库 |
| 仓库其它回归 | 见下 | API / 排程参考实现的 Vitest、typecheck、API 构建 |

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client
$env:PUB_CACHE = 'D:\_projects\sjtu-study-planner\apps\flutter_client\.dart_tool\pub-cache'

flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub test/unit
flutter test --no-pub test/golden/planner_scheduler_test.dart

# 集成测试在 Windows 上以真实进程运行（约 4 分钟）
flutter test integration_test/app_flow_test.dart -d windows --no-pub
```

共享 golden 使用仓库根同一份 `packages/planner-engine/fixtures/planner-goldens.json`，TypeScript 侧是 oracle：

```powershell
Set-Location D:\_projects\sjtu-study-planner
npm test -- packages/planner-engine            # TypeScript golden
npx vitest run packages/planner-engine/src/golden.test.ts
npm run typecheck
npm run api:build

# 需要隔离测试库的 API 集成测试（不要指向生产库）
docker start planner-auth-phase3-20261016
$env:AUTH_TEST_DATABASE_URL = 'postgres://planner_test:phase3-test-only@127.0.0.1:55438/planner_auth_test'
npm test
```

集成测试的桩服务器只在 `127.0.0.1` 监听随机端口，关闭监听以模拟离线（得到真实连接拒绝）；数据库写在系统临时目录，凭据用内存实现，不污染操作系统钥匙串。文件选择器被替换（真实选择器需要人工操作），JSON 仍由生产序列化代码处理。

## 6. 发布

### 产物位置

| 平台 | 路径（相对 `apps/flutter_client/`） |
| --- | --- |
| Web | `build/web/`（入口 `index.html`，bundle `main.dart.js`，PWA `manifest.json`） |
| Windows | `build/windows/x64/runner/Release/sjtu_study_planner_client.exe` 与同目录 `data/` |
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Android AAB | `build/app/outputs/bundle/release/app-release.aab` |
| iOS | `build/ios/iphoneos/Runner.app`、`build/ios/ipa/*.ipa` |

`tool/build-release.ps1` 在构建结束后会打印每个产物的**绝对路径与大小**，缺失项标记为 `MISSING`，跳过的平台标记为 `SKIPPED`。

### 部署路径与发布步骤

**Web**（静态站点）

1. `.\tool\build-release.cmd -ApiBaseUrl https://<域名> -Target Web`
2. 把 `build/web/` 整个目录上传到静态服务器或对象存储。
3. 子路径部署时用 `--base-href /planner/`（脚本透传 `flutter build web` 的参数）。
4. **不需要 SPA 回退规则**：客户端使用 Flutter Web 默认的 hash URL 策略，运行时地址形如 `https://<域名>/#/tasks`，服务器只需把 `/` 返回 `index.html`。已在真实发布产物上用无回退的静态服务器验证：深链接 `/#/tasks` 未登录时重定向到 `/#/login`，刷新返回 200 且视图正常挂载；而路径式的 `/tasks` 会得到 404，所以**不要把 `/tasks` 这类无 `#` 的地址当作入口或分享链接**。
5. 在 API 的 `WEB_ORIGIN` 中加入该站点的准确来源（含协议与端口），否则浏览器会被 CORS 拦截、登录后立刻失败。用发布产物指向生产 API、却从其他来源打开时，出现 `blocked by CORS policy` 属于预期，说明白名单生效。
6. **未实现离线资源缓存**：没有 Service Worker，首次打开需要联网获取静态资源；已加载过的资源依赖浏览器 HTTP 缓存（`Cache-Control` 由托管方决定）。PWA 的 `manifest.json` 只提供安装元数据，不代表可离线运行。完整 PWA 离线属于后续工作。

**Windows**

1. `.\tool\build-release.cmd -ApiBaseUrl https://<域名> -Target Windows`
2. 分发整个 `Release/` 目录（`.exe` + `data/`），不能只复制 `.exe`。
3. 未签名时 Windows SmartScreen 会告警；正式分发应做代码签名（`signtool`），签名私钥与口令**不进入仓库**。
4. 本阶段只做 `flutter build windows` 发布编译，**没有生成 NSIS/MSI 安装包**，也没有在干净机器上做过安装验证。

**Android**

1. 先创建上传密钥（**不要提交到仓库**）：

   ```powershell
   keytool -genkeypair -v -keystore $env:USERPROFILE\planner-upload.jks `
     -keyalg RSA -keysize 2048 -validity 10000 -alias planner
   ```

2. 在 `android/key.properties`（已在 `.gitignore` 范围外，需自行确认不提交）中引用密钥库，并在 `android/app/build.gradle.kts` 的 `release` 中加入 `signingConfig`。**当前仓库仍是模板状态**：`release` 使用 debug 签名，不能上架。
3. `flutter build appbundle --release --dart-define=API_BASE_URL=https://<域名>`
4. 上传 `.aab` 到 Google Play，或对国内渠道用 `--split-per-abi` 生成 APK。
5. `applicationId` 目前是模板值 `com.example.sjtu_study_planner_client`，正式发布前必须改成自己的唯一 ID（改 ID 会改变应用身份，老用户无法平滑升级）。
6. `versionCode` / `versionName` 来自 `pubspec.yaml` 的 `version: 0.1.0+1`。

**iOS**

1. 在 macOS 上打开 `ios/Runner.xcworkspace`。
2. 设置 Team、Bundle Identifier 与签名方式（自动或手动 Provisioning Profile）。
3. `flutter build ipa --release --dart-define=API_BASE_URL=https://<域名>`
4. 用 Xcode Organizer 或 `xcrun altool` 上传 App Store Connect。
5. `ios/Runner/Info.plist` 只为 `127.0.0.1` / `localhost` 放行明文 HTTP（开发 API）。**发布版本必须使用 HTTPS**，不要扩大该豁免范围。

### 环境配置清单（不含任何密钥）

| 位置 | 变量 | 说明 |
| --- | --- | --- |
| 客户端构建 | `API_BASE_URL` | 公开 API 地址，编译期注入 |
| `apps/api/.env` | `JWT_ACCESS_SECRET`、`JWT_REFRESH_SECRET` | 仅服务端；用长随机值 |
| `apps/api/.env` | `DATABASE_URL` | 仅服务端 |
| `apps/api/.env` | `WEB_ORIGIN` | 逗号分隔的来源白名单 |
| `apps/api/.env` | `AI_BASE_URL`、`AI_API_KEY`、`AI_MODEL` | 仅服务端；缺失时用确定性回退 |
| `apps/api/.env` | `SMTP_*` | 仅服务端，注册验证码用 |
| 构建机（不入库） | Android keystore、iOS 证书/描述文件 | 签名材料 |

### 回滚

| 目标 | 做法 |
| --- | --- |
| 客户端 | 重新部署上一版 `build/web/` 产物，或分发上一版 `Release/` 目录；客户端与 API 之间只有公开接口，无需回滚数据库 |
| 数据 | 本机 `json` 导出可直接回灌；服务端不提供自动降级，业务数据不要回滚 |

API 的同步与 refresh token 表属于当前客户端的运行依赖，客户端版本回滚时保留数据库与业务数据。

### 已知限制

- **Android 未验证**：本机缺 Android SDK，未编译、未实机；`tool/build-release.ps1` 会跳过并告警。
- **iOS 未验证**：需 macOS/Xcode。
- **Windows 安装包未验证**：未打包、未在干净机器安装。
- **无离线资源缓存**：见上文 Web 步骤 6。
- **真实 AI 输出未验收**：未配置密钥时走服务端确定性回退。
- **服务端结算与正式生成未接入页面**：`结束今天` 与客户端重排只写本机。
- **Wasm 不在承诺范围**：`flutter_secure_storage_web` 与 `share_plus` 的 Wasm dry-run 提示仍存在；普通 JavaScript 构建可用。
- **Android 签名与 applicationId 仍是模板状态**：上架前必须替换。

## 7. 认证和 API（现状）

第三阶段接入真实登录、注册验证码、自动恢复会话、退出、认证路由守卫，以及类型化 `PlannerData`、备考资料和 AI 草案客户端。第四阶段接入本机计划、今日累计用时编辑、JSON 导入导出、备份恢复和 revision/base 同步。第五阶段实现 Dart 排程 domain 与离线操作接口。第六阶段完成全部页面迁移（今日、事项、日历、进度、设置、备考资料与 AI 草案），手机使用底部导航、Web/Windows 使用侧栏。第七阶段补齐 81 项测试与 6 项 Windows 集成测试并修复三个缺陷。第八阶段完成发布准备。

默认开发入口 `http://127.0.0.1:5180`，API `http://127.0.0.1:8787`，保持同一主机以便开发 Cookie 生效。先按仓库原有说明配置 PostgreSQL 和 `apps/api/.env`，然后：

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\api
npm run dev
```

注册发邮件需要服务器 SMTP 配置；现有账号登录不依赖邮件发送。API 启动时会执行 `202610160002_bearer_refresh_tokens.sql` 与 `202610160003_planner_sync.sql`，不改动旧业务表。

真实数据库认证测试使用独立测试库，**不能填生产数据库**：

```powershell
Set-Location D:\_projects\sjtu-study-planner
$env:AUTH_TEST_DATABASE_URL = 'postgres://planner_test:phase3-test-only@127.0.0.1:55438/planner_auth_test'
npm test -- apps/api/src/auth.integration.test.ts
```

## 8. 本机排程（第五阶段）

纯 Dart 引擎位于 `lib/features/planner/domain/scheduler/planner_scheduler.dart`，与 TypeScript 共用 `packages/planner-engine/fixtures/planner-goldens.json` 的 92 个输入和完整预期（含生成后的 ID、UTC 毫秒时间、建议字段、任务状态快照和数组顺序）。旧 JSON 缺省 `planning_mode` 时读取为 daily、导出仍省略。

应用入口由 `PlannerCoordinator` 提供，Widget 只展示返回的 preview 并调用这些命令：

```dart
final preview = await coordinator.previewReplan(
  today: '2026-10-17',
  mode: ReplanMode.unfinished,
);
coordinator.cancelReplan(); // No persistence or network request.
await coordinator.previewReplan(today: '2026-10-17');
await coordinator.confirmReplan();
await coordinator.undoReplan();
await coordinator.recordDayMinutes(taskId, '2026-10-17', 90);
```

`ReplanMode.overcompleted` 可带 `excessMinutes`，只从未来 7 天提前。未完成只重排现有块在未来 14 天内的待完成部分，不自动补齐整项预计需求。每日最多 480 分钟预算扣至少 30 分钟缓冲，同科最多 240；daily 模式固定事件含休息按并集扣容量，timed 模式休息只占时间窗口、不扣同一预算。已执行记录留在原日，固定/已完成/窗口外块保护。

预览/取消不落盘。确认和撤销先经协调器串行校验、持久化再同步；期间任务、日志、设置、固定事件或建议变化使确认过期。新本机 run 的可选 `local_undo_guard` 随 JSON/存储/API 保存，重启后修改数据仍阻止撤销覆盖。旧 TypeScript run 沿用其块快照保护和可选 `task_status_before/after`；没有完整旧输入时无法追溯增强保护。`study_edits.dart` 仅为兼容转发，今日学习记录已使用 domain。

本机确认是客户端快照编辑，经 `/api/planner/sync` 的 revision/base 协议提交；不会调用 `/api/plans/generate` 或每日 settle。服务端仍负责正式生成/结算及 AI 建议。服务端现有算法使用星期容量、每天每任务一次最多 30 分钟、从开始日至考试日，尚没有客户端的缓冲、固定事件和 14/7 天规则；不可将两者作为等价确认接口。差异表见根 `FLUTTER_MIGRATION_DESIGN.md` 第 9 节。正式 API 算法、数据库和旧客户端未被替换。

## 9. 页面模块（第六阶段）

```text
lib/features/
  shell/app_shell.dart                 侧栏（≥900px）/ 底部导航、同步条、账号对话框
  dashboard/presentation/              今日：计划/已学/剩余、完成环、逐事项行、重排、撤销
  tasks/presentation/                  事项：筛选、增删改、安排时间块、标记完成
  calendar/presentation/               日历：日/周视图、固定事件、容量、拖动/改日期
  progress/presentation/               进度：课程进度、周对比、热力图、燃尽
  onboarding/presentation/             备考资料六步 + AI 草案编辑与确认
  settings/presentation/               设置：备考信息、排程边界、优先级、数据、同步
  planner/domain/                      格式化、每日统计、事项编辑、进度指标、最小计划
  planner/application/                 会话命令面、快照、备考向导控制器
  planner/presentation/                共用对话框与页面状态外壳
```

路由沿用 `/`、`/calendar`、`/tasks`、`/progress`、`/settings`，新增 `/onboarding`；认证与备考资料守卫在 `app/router/app_router.dart`。

有意的行为差异：本机不自动导入 Web 的整套预设课程与事项，新账号的课程/事项由备考向导生成，本机只预置正式初试与休息固定事件。

## 10. 测试与验收记录

审查修复后 `flutter analyze` 无问题，**291** 项 Flutter 单元/widget 测试通过；TypeScript 与 Dart 共享 golden 92 用例两端一致；Vitest 188 项全部通过（含隔离 PostgreSQL 的 11 个认证与 9 个同步测试）。本轮根 typecheck、API 构建、Flutter Web 与 Windows 发布编译通过；Windows 集成复测状态见 `TEST_REPORT.md` 第 11 节。前阶段的 React/Rust、6 项 Windows 集成与 22 项 Chrome 界面断言保留为历史验证记录，不代表本轮全部重新执行。

完整清单、未验证项与复现命令见根 [`TEST_REPORT.md`](../../TEST_REPORT.md)、[`FLUTTER_MIGRATION_DESIGN.md`](../../FLUTTER_MIGRATION_DESIGN.md) 第 11 节。

本阶段修复：Android 主清单缺少 `INTERNET` 权限（release 构建完全没有网络）、Web 发布会话缺少标题与描述、iOS 应用名与本地化未配置、iOS 开发 API 缺少受限的明文 HTTP 豁免。

未验证（不得视为通过）：Android、iOS/macOS、Windows 安装包、真实 AI 输出、触屏拖拽替代路径、Web Wasm 发布、双真实设备并发冲突。
