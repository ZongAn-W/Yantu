# React / Tauri 停用清理

2026-10-17 起只维护 Flutter 客户端。默认启动和构建已切换为 Flutter，npm workspace、依赖声明、TypeScript 与 Vitest 范围已排除旧客户端；API 和部署配置使用 Flutter Web 来源与产物目录。

## 已移除的旧版内容

用户提供的 AGENTS.md 禁止批量删除，要求批量清理由用户手动完成。配置调整后由用户移除以下路径；已逐项核对，它们均已不存在。路径相对于仓库根目录 `D:\_projects\sjtu-study-planner`。

| 路径 | 内容 |
| --- | --- |
| `apps/web/` | React / Vite 网页版源码、测试、环境文件及构建产物 |
| `apps/desktop/` | 加载 React 的 Tauri 桌面壳、Rust 代码及构建产物 |
| `tests/` | 只针对 React 页面编写的 Playwright 测试 |
| `playwright.config.ts` | 启动 React 的旧端到端测试配置 |
| `supabase/` | 仅旧客户端使用的 Supabase 部署说明与迁移文件 |

旧端到端测试生成的 `.playwright-browsers/`、`.playwright-cli/`、`playwright-report/`、`test-results/` 可按需手动清理；它们不属于当前客户端的测试流程。

现有 node_modules 可能仍留有之前安装的 React/Tauri 包。本次只更新依赖声明与锁文件，未运行会批量删除本机依赖文件的清理命令。需要清理磁盘时，可手动删除根目录 `node_modules/` 后执行 `npm ci`。

## 必须保留

- `apps/flutter_client/`：唯一维护的客户端及其 Dart 测试。
- `apps/api/`：账号、PostgreSQL、AI 与同步接口。
- `packages/planner-engine/`：Flutter 和 API 测试消费的共享 fixture、TypeScript 排程参考实现。
- PostgreSQL 数据库及数据卷、浏览器本机数据、应用数据目录和导出的备份：停用旧源码不需要删除这些业务数据。

迁移设计与测试报告保留历史记录，当前运行命令以根目录 README.md 为准。

## 验证

- npm 清单和锁文件的 workspace 一致，不再包含 React、Tauri 和 Supabase 客户端包。
- TypeScript 类型检查与 API 构建通过，API / 排程参考实现的 168 项 Vitest 测试通过，含独立 PostgreSQL 认证和同步集成测试。
- Flutter 静态分析无问题，291 项单元/widget 测试通过，Web JavaScript 发布构建通过。
- React 的 5174 服务已停止，Flutter 5180 与 API 8787 继续运行；已有测试账号登录返回 200。
- API 允许 Flutter Web 来源；未配置白名单时不再放行旧 5174 和 Tauri 来源。
