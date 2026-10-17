# 不白学 · 考研执行台

面向考研备考的学习执行工具：今日任务、课程与事项、日历、真实学习用时、进度、备考资料与 AI 草案。

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
# 自定义地址或端口时，同时更新 API 的 WEB_ORIGIN
npm run dev -- -Port 5181 -ApiBaseUrl http://127.0.0.1:8787
```

默认客户端地址为 `http://127.0.0.1:5180`，API 为 `http://127.0.0.1:8787`。端口已占用时使用其他端口。Windows 客户端的运行命令见 [Flutter 客户端说明](apps/flutter_client/README.md)。

账号登录后进入学习工作台；新账号经备考向导生成课程和事项。注册需要邮箱验证码，QQ SMTP 配置见 [邮箱注册部署](apps/api/AUTH_DEPLOYMENT.md)。未配置 AI 密钥时，API 提供确定性草案和建议回退。

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

## 学习规则与数据

学习结构为“课程 → 事项”两层。事项可设置总时间预算、起止日期和优先级，学习内容与完成标准写在事项说明中。每日安排只列事项与时长；固定课程、考试和休息保留具体时刻。

默认每日最多 8 小时，保留至少 30 分钟机动，每课程每天最多 4 小时。固定事件重叠时按时间并集扣除容量。客户端自动重排最多处理未来 14 天，超额完成最多提前 7 天内任务，先预览后确认。

实际用时按“事项 + 日期”累计记录；再次填写是修正当天总量。每日完成勾选只表示当天安排完成，整项完成需单独确认；用完时间预算不会自动完成事项，超额实际用时仍保留。

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
