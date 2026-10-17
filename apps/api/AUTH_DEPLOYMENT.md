# 邮箱注册部署

新注册需要用户名、已验证邮箱和密码。用户名为 2 至 24 个中文、英文字母、数字或下划线字符，不区分大小写判重；登录仅使用邮箱。密码至少 9 位，包含英文字母和数字，最多 128 位。验证码只保留 HMAC 摘要，有效 10 分钟、每个邮箱每 60 秒可发一次、每小时最多 5 次，5 次校验错误后必须重新获取。接口还按客户端 IP 限流。

## QQ 邮箱

1. 在 QQ 邮箱网页版的“设置 → 账号”中开启 SMTP 服务（新版界面可能在“账号与安全”或“安全设置”中）。按 QQ 邮箱的验证流程生成授权码。
2. 在服务器上编辑 `/opt/sjtu-study-planner/apps/api/.env`，只在服务器中填写真实邮箱和授权码，不要发送到聊天中或写入前端配置。

```dotenv
SMTP_HOST=smtp.qq.com
SMTP_PORT=465
SMTP_USER=你的QQ邮箱@qq.com
SMTP_PASS=QQ邮箱生成的SMTP授权码
SMTP_FROM=你的QQ邮箱@qq.com
```

`SMTP_FROM` 留空时使用 `SMTP_USER`。保留 `.env` 的 `600` 权限。未配置 SMTP 时发送接口返回 `503`，不会返回假成功或把验证码打印到日志。

## 升级已有服务器

先备份数据库，并同步本次修改的源码、依赖清单、`package-lock.json`、Compose 配置和 `db/migrations/`。保留服务器已有 `.env` 和数据库卷，不重新运行 `init-server-env.mjs`，不重新初始化数据库。

在服务器项目根目录构建新 API 镜像（如服务器无法访问镜像仓库，可沿用之前本机构建、上传镜像的流程）：

```bash
cd /opt/sjtu-study-planner
docker build -f apps/api/Dockerfile -t study-planner-api:latest .
docker compose --env-file apps/api/.env -f apps/api/docker-compose.server.yml up -d --no-deps --force-recreate --wait --wait-timeout 120 api
```

API 启动时在事务和数据库锁保护下自动应用 `db/migrations/202610160001_email_registration.sql`，重复启动不会重复迁移。已有用户保留账号和学习数据，自动补上 `user_<用户ID>` 用户名；已有密码仍可登录。旧会话需要重新登录，新注册必须完成邮箱校验。

在安装 Flutter SDK 的构建机上构建 Web 客户端，再将 `apps/flutter_client/build/web/` 上传到服务器的同名目录：

```bash
cd apps/flutter_client
flutter build web --release --dart-define=API_BASE_URL=https://47.116.63.161
```

Nginx 的静态根目录应为 `/opt/sjtu-study-planner/apps/flutter_client/build/web`；仓库内 `setup-ip-web.sh` 使用该路径。API 端口继续仅绑定主机 `127.0.0.1`，外部请求由 Nginx 转发。API 信任紧邻的一层代理以读取真实客户端 IP；Nginx 应覆盖设置 `X-Forwarded-For`，不能让客户端直接访问容器 API。`WEB_ORIGIN` 包含 `https://47.116.63.161`，本地调试使用 `http://127.0.0.1:5180`，多个来源以逗号分隔。带 Origin 的写入请求必须来自配置白名单；Windows 和移动端使用 Bearer 会话。

## 验收

- 未登录直接访问今日、事项、日历或设置，均停留在登录页。
- 填写用户名与邮箱，发送验证码，真实邮箱收到邮件。60 秒内不能重复发送。
- 错误、过期或已使用的验证码不能注册；密码不足 9 位或缺少英文字母、数字不能注册。
- 注册成功进入学习目标访谈，退出后不能继续操作工作台；再次用邮箱和密码登录成功。
- 已有账号重新登录后仍可读取原有计划。
- Windows 客户端需要更新到本次 Flutter 源码构建的版本，再验证注册、登录、刷新会话和退出；安装包尚未打包验收。

## 本地检查

常规 API 验证：`npm test`、`npm run typecheck`、`npm run api:build`。Flutter Web 使用 `npm run build -- -ApiBaseUrl https://api.example.com` 构建。真实 PostgreSQL 集成测试只应连接独立测试数据库：

```powershell
$env:AUTH_TEST_DATABASE_URL = "postgres://planner:TEST_PASSWORD@127.0.0.1:55432/planner"
npx vitest run apps/api/src/auth.integration.test.ts
```

测试会创建表、执行迁移并生成测试账号，不要使用生产数据库。集成测试使用模拟邮件出口以验证验证码业务逻辑；QQ 实际投递必须在配置 SMTP 后另行验收。
