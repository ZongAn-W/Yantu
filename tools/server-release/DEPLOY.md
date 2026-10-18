# 现有服务器升级发布包

> 日常发布推荐使用仓库根目录的一键部署：`npm run deploy`（见根 README「一键部署」）。它会自动完成本文件的构建、上传、`--check` 与 `--apply`；本文件保留作为手动流程与回滚参考。

- 发布 ID：`__RELEASE_ID__`
- 目标站点：`__API_ORIGIN__`（现有服务器，保留服务器 `.env` 与数据库卷）
- 基础 commit：`__BASE_COMMIT__`（发布内容基于当前工作区；该提交包含本次全部实现）
- 构建时间：`__BUILT_AT__`
- 本包内容：`source/`（API 源码与迁移）、`web/`（Flutter Web 构建，已注入 `API_BASE_URL=__API_ORIGIN__`）、`upgrade-server.sh`、`release.json`
- 需要上传到服务器的文件：
  1. `study-planner-__RELEASE_ID__.tar.gz`（必需）
  2. `study-planner-__RELEASE_ID__.tar.gz.sha256`（可选校验）
  3. `study-planner-api-__RELEASE_ID__-image.tar.gz`（**可选但强烈建议**：服务器无法访问 Docker Hub/npm 时用它，见第 2 节）
  4. `study-planner-api-__RELEASE_ID__-image.tar.gz.sha256`（可选校验）

> 密钥/`.env`/数据库凭据**不在本包内**。服务器已有 `apps/api/.env` 原样保留；本次升级没有新增环境变量。

## 0. 本次升级做了什么

- API：新容量/执行关系/临时学习实现 + 新迁移 `202610200001_learning_relations_capacity.sql`（只新增表与可空列，旧数据不动；API 启动时自动执行）。
- Web：全周期计划、灵活周/日期容量、三类学习入口等新客户端。
- 顺序：**先 API（含迁移），再 Web/客户端**。旧客户端在云端出现临时学习/加学日志后会收到 426 升级提示（数据保留），请尽快更新桌面端。

## 1. 上传并做只读检查

用阿里云 Workbench 文件管理器或 `scp` 把 tar.gz 上传到 `/tmp`：

```bash
scp study-planner-__RELEASE_ID__.tar.gz root@__API_ORIGIN_HOST__:/tmp/
```

在服务器执行：

```bash
sha256sum -c /tmp/study-planner-__RELEASE_ID__.tar.gz.sha256 2>/dev/null || sha256sum /tmp/study-planner-__RELEASE_ID__.tar.gz
mkdir -p /opt/sjtu-study-planner/releases/__RELEASE_ID__
tar -xzf /tmp/study-planner-__RELEASE_ID__.tar.gz -C /opt/sjtu-study-planner/releases/__RELEASE_ID__
sudo bash /opt/sjtu-study-planner/releases/__RELEASE_ID__/upgrade-server.sh --check
```

`--check` 只读：校验现有 Compose/容器、`.env` 完整性、Nginx 配置与静态根、Web 构建的 API 地址、API 健康与数据库可用性，并报告磁盘、Web 根目录和**该服务器是否具备构建 API 镜像的网络条件**。若报错，把错误信息发出来（不要发 `.env` 内容）。

## 2. 服务器网络不确定时的镜像策略

`--check` 会报告：

- `API image ... is already loaded`：已 `docker load` 过，直接进入第 3 节；
- “服务器可能无法构建…”：说明服务器可能无法访问 Docker Hub/npm。此时把本机预构建的镜像 tar 上传并加载：

```bash
scp study-planner-api-__RELEASE_ID__-image.tar.gz root@__API_ORIGIN_HOST__:/tmp/
ssh root@__API_ORIGIN_HOST__
docker load < /tmp/study-planner-api-__RELEASE_ID__-image.tar.gz
docker image inspect study-planner-api:__RELEASE_ID__ >/dev/null && echo "image ready"
```

也可以把镜像 tar 放到发布目录（`/opt/sjtu-study-planner/releases/__RELEASE_ID__/api-image.tar.gz`），脚本会在 `--apply` 时自动 `docker load`。

> 本机镜像为 Linux/amd64；服务器架构必须是 amd64（`uname -m` 应为 `x86_64`）。

## 3. 发布（自动备份 + 自动回滚）

```bash
sudo bash /opt/sjtu-study-planner/releases/__RELEASE_ID__/upgrade-server.sh --apply
```

脚本会：

1. 备份 `apps/api/.env`、Compose 文件、旧 API 镜像、旧前端目录；
2. `pg_dump -Fc` 备份数据库并用 `pg_restore --list` 校验非空；
3. 使用已加载镜像或现场构建 `study-planner-api:__RELEASE_ID__`，只重建 `api` 容器（数据库容器与卷不动）；
4. 等待健康检查并确认新迁移已写入 `schema_migrations`；
5. 把新前端替换到**现有 Nginx 静态根**（自动探测；多个候选时用 `WEB_ROOT=/path ...` 指定）；
6. 校验 WASM MIME、HTTPS API 健康与 JS gzip；失败自动恢复旧镜像/Compose/前端（数据库迁移保留）。

## 4. 发布后验收

```bash
curl -fsS __API_ORIGIN__/api/health
curl -fsSI __API_ORIGIN__/canvaskit/chromium/canvaskit.wasm | grep -i content-type   # application/wasm
curl -fsSI -H 'Accept-Encoding: gzip' __API_ORIGIN__/main.dart.js | grep -i content-encoding  # gzip
sudo docker compose --env-file /opt/sjtu-study-planner/apps/api/.env \
  -f /opt/sjtu-study-planner/apps/api/docker-compose.server.yml \
  exec -T db psql -U planner -d planner -c "select name from schema_migrations order by name" | grep 202610200001
```

浏览器（桌面 + 手机宽度，强制刷新 Ctrl+F5，**不要清站点存储**）：

- 登录成功，已有账号能看到原计划，学习数据不丢；
- 新计划覆盖完整周期；日历可“跳到周期末”，不再显示“待细化/未来 14 天”；
- 设置 → “管理特定周与日期容量”：可增删改、显式 0、清除恢复上层、周/日期冲突提示与影响预览；
- 今日页“开始学习”三入口：今日安排 / 已有事项加学 / 临时学习；各计时 1 分钟后同步文档含正确 relation/session；
- 容量分解显示 `净容量 / 实际投入 / 有效预留 / 新增可安排`；
- 事项、进度、日历页正常，手机 390 宽度无横向溢出；
- 旧客户端（未升级的 Windows 客户端）：在云端已有临时学习/加学日志后同步会收到明确 426 升级提示，升级后同 revision/base 重试即可。

## 5. 回滚

```bash
sudo bash -c '
set -euo pipefail
cd /opt/sjtu-study-planner
backup=$(ls -dt backups/__RELEASE_ID__-* | head -1)
compose=(docker compose --env-file apps/api/.env -f apps/api/docker-compose.server.yml)
old_image=$(cat "$backup/previous-image-id.txt")
docker tag "$old_image" study-planner-api:latest
cp -p "$backup/docker-compose.server.yml" apps/api/docker-compose.server.yml
"${compose[@]}" up -d --no-deps --force-recreate --wait --wait-timeout 180 api
web_root=$(cat "$backup/web-root.txt")
if [ -d "$backup/web" ]; then
  mv "$web_root" "$backup/failed-web"; mv "$backup/web" "$web_root"
  nginx -t && nginx -s reload
fi
echo "Rolled back application; database migrations are retained."
'
```

数据库迁移不会回滚（只新增，旧代码可忽略）。如确需恢复数据库，使用 `$backup/planner.dump`（会丢失备份后的新写入，优先只回滚应用）。

## 6. 常见问题

- **服务器构建镜像失败（网络/registry）**：按第 2 节上传并 `docker load` 预构建镜像，再 `--apply`。
- **Nginx 静态根探测失败**：`--check` 会列出候选；用 `sudo WEB_ROOT=/实际/root bash ... --apply` 指定。
- **白屏 / WASM MIME 错误**：先按本仓库 `apps/api/AUTH_DEPLOYMENT.md` 的修复章节处理 Nginx（`application/wasm`、gzip、禁止旧 React 版长缓存），或在仓库 `output/fix-flutter-nginx.sh` 存在时使用它，然后再发布前端。
- **浏览器仍加载旧资源**：强制刷新；`index.html`/`main.dart.js`/`flutter_bootstrap.js` 应返回 `Cache-Control: no-cache`。
- **数据库容器 ID 变化**：脚本会直接失败并回滚，不要手动重建 `planner-db` 卷。

## 7. 安全与清理

- 发布包与镜像 tar 可含源码与前端构建，**不含** `.env`、JWT/SMTP/AI/数据库密钥；
- 服务器 `.env` 保持 `600`，不要贴到聊天或提交到 git；
- API 仅监听 `127.0.0.1:8787`，外部经 Nginx；`WEB_ORIGIN` 必须与站点 origin 完全一致；
- 验证完成后可删除 `/tmp` 下的上传文件；`/opt/sjtu-study-planner/backups/` 保留最近几次发布备份（权限 700）。
