# 不白学 · 考研执行台

面向上海理工大学计算机专业大三学生的单用户统考计划工具。首页直接进入今日学习任务。每日学习计划只列任务与时长，学习顺序由你决定；固定课程、考试和休息可保留具体时刻。

## 本地运行

要求 Node.js 22+ 与 npm 10+。项目路径：`D:\_projects\sjtu-study-planner`。

```powershell
Set-Location D:\_projects\sjtu-study-planner
npm install --cache D:\_projects\.npm-cache
npm run dev
```

浏览器打开 `http://127.0.0.1:5173`。未配置 Supabase 时会自动使用完整 localStorage Demo，无需登录。刷新页面保留任务、每日安排、实际学习日志、固定事件和重排历史。Demo 数据仅在当前浏览器中保存，可在设置中导出 JSON 并在其他浏览器恢复。

```powershell
npm run typecheck
npm test
npm run build
npm run desktop:test
$env:PLAYWRIGHT_BROWSERS_PATH = 'D:\_projects\sjtu-study-planner\.playwright-browsers'
npx playwright install chromium
npm run test:e2e
```

## Windows 桌面版（Tauri 2）

桌面版复用 `apps/web` 的 React 页面、CSS 和 `packages/planner-engine`，不会改变网页版入口。首次准备 Windows 构建环境：

1. 安装 Node.js 22+、npm 10+。
2. 安装 Rust stable（`rustup`，选择 `stable-x86_64-pc-windows-msvc`）并重启终端，使 `cargo` 可用。
3. 在 Visual Studio Build Tools 2022 中安装“使用 C++ 的桌面开发”、MSVC v143、Windows 10/11 SDK。
4. 安装并启用 WebView2 Runtime。Windows 10 通常需要单独安装 Evergreen WebView2。
5. 在项目根目录执行 `npm install`；Tauri CLI 已作为开发依赖安装。

启动桌面开发版：

```powershell
Set-Location D:\_projects\sjtu-study-planner
npm run desktop:dev
```

构建 Windows 安装包（NSIS `.exe` 和 MSI）：

```powershell
npm run desktop:build
```

构建产物位于 `apps/desktop/src-tauri/target/release/bundle/`。桌面版启动后直接打开今日任务页，使用 Hash 路由保证离线加载稳定；网页版仍使用 BrowserRouter。

## 桌面数据、备份与迁移

桌面版把本地 Demo 保存到 Tauri 应用数据目录：`%APPDATA%\cn.sjtu.studyplanner\planner-data.json`；登录账号的离线缓存保存为同目录下的 `planner-account-<用户ID>.json`，与 Demo 分离。每次写入先验证并保存最近备份，再通过临时文件替换主文件；启动发现主文件损坏时会自动读取最近备份、把损坏文件另存为 `.corrupt-*`，并在界面显示恢复结果。主文件和备份都不可读取时会停止编辑和同步，不会覆盖原数据；可以重试读取、导出当前可读数据或从 JSON 恢复。

在网页版“设置 → 数据管理”点击“导出本地数据”，然后在桌面版点击同一处的“恢复数据”并选择 JSON 文件，即可迁移浏览器计划。桌面版导出使用 Windows 系统保存对话框；网页版继续使用浏览器下载。建议定期把导出的 JSON 保存到 OneDrive、U 盘或其他独立位置，恢复时选择该文件即可。

未配置 Supabase 时，网页版和桌面版都提供完整本地 Demo，离线修改会持续保存，不需要登录。配置 `VITE_SUPABASE_URL` 与 `VITE_SUPABASE_ANON_KEY`（或 publishable key）并重启后，桌面版仍先写本地账号文件，再在网络可用时自动同步；待同步标记、revision 和同步基线都随本地数据保存。退出应用前会等待最后一次写入完成，重新打开会继续同步；恢复网络后自动重试。云端写入失败或版本冲突不会覆盖本地修改，现有合并逻辑会保留双方独立编辑并在设置页显示同步状态。

`npm test` 运行独立排程算法测试；Playwright 覆盖桌面与 Pixel 7 手机视口。`npm run build` 先做 TypeScript 检查，再生成 `apps/web/dist`。所有源码、依赖缓存和测试产物可保留在 D 盘。

## 功能与数据

- `/`：今日任务列表、计划和实际时长、手动记录学习用时、重排预览与撤销。
- `/calendar`：按天/周查看每日任务和时长、跨日期移动任务、固定事件。
- `/tasks`：任务创建、编辑、删除、筛选、拆分到每日计划。
- `/progress`：实际完成环、周对比、月度热力图、剩余任务燃尽和各科累计真实用时。
- `/settings`：目标学校和方向、考试日期、每日容量、科目优先级、数据导出恢复、登录与同步状态。

默认计划包含 2026 年 10 月至 2027 年 12 月的六个备考阶段，数学一、英语一、408 和 2027 年 7 月开始的政治。初试暂定 2027-12-25（政治、英语一）与 2027-12-26（数学一、408），可在设置中按官方通知修改。

学习结构仅有“课程 → 事项”两层。高数、线代、概率论、数据结构等课程下面是基础一轮、强化、真题训练、考前回顾；英语按首轮记忆、滚动复习、真题精读、限时训练等实际学习方式组织。政治各课程下面是知识学习与选择题训练，分析题背诵归政治综合。数学、英语和408的整卷练习及复盘独立记时。

`packages/planner-engine/src/categories.ts` 提供预设课程和事项名称建议；`apps/web/src/item-seeds.ts` 提供阶段事项、日期、起始时间预算及说明。课程与事项均可自定义。章节内容、材料与完成标准写进事项的 `description`，不新增章节层级。事项管理默认隐藏未来事项，可以勾选“显示后续事项”。

学习块按 30 分钟拆分，但只表示哪一天学习多少分钟。默认每天上限 8 小时、至少留 30 分钟机动、每科每天最多 4 小时；固定课程、考试和休息先占用每日容量，重叠固定事件按时间并集扣除。自动重排最多处理未来 14 天，超额完成最多提前 7 天内任务，先预览再确认；容量不足会显示冲突。

总时长和当天分配分钟数直接设置在事项上。每天按事项记录累计实际用时，例如“高数 / 基础一轮 120 分钟”。再次填写修正该事项当天总时长；没有当天计划的事项也可补记。每天的完成勾选只表示当天安排完成，整项学习完成在事项管理里确认。进度页汇总课程并显示事项明细。

时间投入来自实际学习记录；用于计算剩余预算的分钟数最多计入预计总时长，超额实际记录仍全部保留。用完时间预算不会自动完成事项。同一事项、同一天的并发修正使用本机本次累计值；不同事项或不同日期的修改可以合并。

新版本地数据使用 `sjtu-study-planner:items-v2`，不读取旧格式、不自动迁移章节事项。导出与恢复保留事项说明、时间预算、学习日志和每日安排。已有云端计划需按新版结构准备；应用不会自动重置云端数据。

## Supabase Auth / PostgreSQL / Realtime

将 `apps/web/.env.example` 复制为 `apps/web/.env.local`，填写公开环境变量后重启开发服务器：

```dotenv
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_PUBLIC_ANON_KEY
# 也可使用 VITE_SUPABASE_PUBLISHABLE_KEY 代替 ANON_KEY
```

浏览器环境只允许公开 anon/publishable key。新建 Supabase 项目后，按顺序应用：

1. `supabase/migrations/202610130001_planner.sql`：八张表、RLS、Realtime 与原子快照 RPC。
2. `supabase/migrations/202610140001_daily_plan_compat.sql`：已有 payload schema 的每日任务兼容迁移和触发器。
3. `supabase/migrations/202610140002_study_categories.sql`：任务与实际日志的二级分类、旧数据回填和分类索引。
4. `supabase/migrations/202610140003_courses_items.sql`：取消旧分类约束与触发器，允许自定义课程；事项说明使用原有 JSON payload，无需新增列。

`001_initial.sql` 已保留为空占位。CLI 首次使用时先运行 `npx supabase login` 和 `npx supabase link --project-ref YOUR_PROJECT_REF`，之后运行 `npx supabase db push`；也可在 SQL Editor 按顺序执行上述文件。Auth Site URL / Redirect URL 应包含实际应用域名，开发可填写 `http://127.0.0.1:5173` 和 `http://localhost:5173`。启用邮箱确认时需要先确认注册邮件。

首次登录先读取账号云端数据，仅当云端没有 profile 时才导入当前 Demo。账号缓存与 Demo 分离；任务、学习块和日志等通过 Realtime 同步，写入使用版本号避免异步覆盖。完整计划、重排变更及撤销均由事务 RPC 保存。

本项目不含真实 Supabase 凭据，云端注册、RLS 与多设备同步需配置你自己的项目后验收。当前云端 migration 已静态核对，尚未连接真实 Supabase 项目执行。若你的项目曾使用旧版非 payload `001_initial.sql` schema，需先备份并做人工 schema 迁移，不能直接套用新建项目 migration。更多说明见 `supabase/README.md`。

## 目录

```text
apps/api/                  Node.js / Fastify API、AI 接口与 PostgreSQL schema
apps/web/                 React / TypeScript / Vite 应用与本地/云端存储
packages/planner-engine/  独立排程引擎、共享类型、Vitest 测试
supabase/migrations/      PostgreSQL schema、RLS、Realtime、兼容迁移
tests/                    Playwright 页面与移动端交互测试
```

## Node API、AI 与 Docker

新流程可以使用自有服务器上的 Node API。API 负责注册登录、备考资料、AI 课程与事项草案、每日建议和每日结算；浏览器不会接触 AI 密钥。复制 `apps/api/.env.example` 为 `apps/api/.env`，填写 `JWT_ACCESS_SECRET`、`JWT_REFRESH_SECRET`、`WEB_ORIGIN`，以及兼容 OpenAI Chat Completions 的 `AI_BASE_URL`、`AI_API_KEY`、`AI_MODEL` 和 `AI_REASONING_EFFORT`。DeepSeek V4.1 Flash 使用 `AI_BASE_URL=https://api.deepseek.com`、`AI_MODEL=deepseek-flash`；`AI_REASONING_EFFORT=max` 启用最大推理强度。不填写 AI 密钥时，服务器使用确定性草案和建议回退，便于本地验证完整流程。

本地启动 API（需要 PostgreSQL）：

```powershell
npm run api:dev
```

Linux 服务器使用 Docker：

```bash
cd apps/api
cp .env.example .env
# 编辑 .env，至少修改两个 JWT secret、WEB_ORIGIN 和 AI 配置
docker compose up --build -d
```

然后在 `apps/web/.env.local` 设置：

```dotenv
VITE_API_URL=http://127.0.0.1:8787
```

重启 Vite 后，注册入口会进入分步备考向导。用户确认 AI 草案后，服务器生成直到考试日的每日安排；“结束今天”会提交实际用时、完成程度和反馈，并自动调整后续安排。服务器不可用时，原有 localStorage Demo 仍可运行；API 模式下正式账号数据保存在 PostgreSQL。
