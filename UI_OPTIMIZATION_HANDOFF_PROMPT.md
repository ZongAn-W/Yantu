# 交接 Prompt：让另一个对话继续做「借鉴开源实现」的 UI 深度优化

> 把下面整段（从「你是本项目的 Flutter UI 工程师」到结尾）复制给另一个对话即可。工作目录相同的会话可以直接读取仓库文件；不同会话请确认路径 `D:\_projects\sjtu-study-planner` 可访问。

---

你是本项目的 Flutter UI 工程师，接手一个已完成的视觉改版，继续做「大规模借鉴开源实现」的 UI 深度优化。

## 0. 工作区与现状（先确认，别重做已完成的视觉方向）

- 仓库：`D:\_projects\sjtu-study-planner`（Monorepo：`apps/flutter_client` Flutter 客户端 + `apps/api` Fastify API + `packages/planner-engine`）。
- 客户端是唯一维护的 UI：Flutter 3.47.3 / Dart 3.13.3，覆盖 Web、Windows、Android、iOS。
- 2026-10-20 已完成「雾蓝墨水 / Mist Ink」视觉改版：令牌在 `apps/flutter_client/lib/core/theme.dart`，共享组件在 `apps/flutter_client/lib/core/widgets.dart`，今日/日历/调整/设置/登录/侧栏均已重构。
- 当前验证基线：`flutter analyze --no-pub` 0 error（仅 6 条既有 lint info）；`flutter test --no-pub` **704 条全部通过**；桌面 1366 与移动 390/320 宽截图无 overflow。
- 本轮不改视觉方向、不改业务功能：**只把自研 UI 实现替换/增强为成熟开源实现（大规模借鉴）**，并补齐桌面键盘/焦点、暗色主题、动效纪律、图标一致性、性能细节。

## 1. 开工前必读（按顺序，全部读完再动手）

1. `UI_OSS_BORROW_PROMPT.md` —— 本轮完整规格（v2）：许可证矩阵、依赖兼容性实测、W0–W7 工作包、验收标准。**这是主规格，严格按它执行。**
2. `THIRD_PARTY_NOTICES.md` —— 第三方代码/素材登记规则与模板。
3. `DESIGN.md` —— 视觉规范、令牌、设计禁忌与借鉴出处。
4. `apps/flutter_client/lib/core/theme.dart`、`lib/core/widgets.dart` —— 当前令牌与共享组件实现。
5. 参考研究（存在则读，不存在跳过）：`.dsh-verify/ui-redesign/research/domain-apps.md`、`flutter-ui.md`。
6. 改版前/后截图：`.dsh-verify/ui-redesign/before/`、`.dsh-verify/ui-redesign/final2/`。

读完后先给我一个 5–10 行的执行计划（本轮做哪些工作包、预计改哪些文件、风险点），再开始写代码。

## 2. 本轮任务：先完成 W0 + W1，验证通过再继续 W2–W7

完整细节在 `UI_OSS_BORROW_PROMPT.md`；这里给出本会话的硬性范围：

### W0 — 第三方代码引入机制（先做，无视觉变化）

- 新建 `packages/ui_vendor/` 内部包目录（若本轮确定不需要 vendor，可先只建空目录与 README 说明，但目录与规则要就位）。
- 按 `THIRD_PARTY_NOTICES.md` 的规则建立登记；同步更新 `DESIGN.md` 的「借鉴与版权」表。
- 提交前自检：`git grep -n -i "AGPL-3.0\|GNU AFFERO\|GNU GENERAL PUBLIC LICENSE" -- apps/flutter_client/lib packages/` 必须为空（AGPL/GPL 不允许进入源码）。

### W1 — 用 MIT 实现替换自研日历/图表/图标（本轮主战场）

1. **引入 `table_calendar 3.3.0`（MIT）**：替换月视图自研网格（`lib/features/calendar/presentation/calendar_month_chart.dart`）。用 `calendarBuilders`/`eventLoader` 保留：今日蓝圆、选中 2px 内描边、计划/实学/容量摘要、`+N` 溢出；保持只读（禁用新建/拖拽）；保留 `calendar-overview`、`calendar-mode-switch` 等既有 Key 与可查找文本。
2. **引入 `fl_chart`（MIT）**：替换日视图两张自研图与周视图（`calendar_day_chart.dart` / `calendar_week_chart.dart`）。坐标轴、网格、图例、Tooltip、配色全部走 `PlannerColors` 令牌（fl_chart 默认样式必须覆写，否则会比现在更丑）；保留 `ValueKey('calendar-day-chart')`、图表语义摘要与只读行为。
3. **引入 `lucide_icons_flutter`（ISC/MIT）**：替换 shell/日历/今日/设置页的页面级图标（16–18px）；`Semantics(label)`、tooltip、测试 `find.byIcon` 不能被破坏；同一区域不混用两套图标。
4. 删除不再使用的自研 painter/网格代码；若 W1 后存在冗余文件，一并清理（不要留下死代码）。
5. 在 `THIRD_PARTY_NOTICES.md` 登记 table_calendar / fl_chart / lucide 三项（版本、许可证、引入方式、无修改或修改说明），并写清 Web 构建体积变化。

## 3. 硬约束（违反即回退）

1. **许可证**：只允许 MIT/ISC/BSD/Apache-2.0 的代码或依赖；**AGPL/GPL（AppFlowy、Plane、FlClash、Loop 等）只读，不得复制源码**。仓库根目录没有 LICENSE，默认保留所有权利；Web 部署会触发 AGPL §13，不能冒险。`forui`、`flex_color_scheme` 会拉入 `material_ui`/`cupertino_ui`（两套 Material 类型），**不得直接依赖**；`shadcn_ui` 当前镜像解析到 0.0.0，**不可依赖**，只能借鉴结构。只允许新增：`table_calendar`、`fl_chart`、`calendar_view`（备选）、`lucide_icons_flutter`。
2. **依赖**：新增包前先跑 `flutter pub add <pkg> --dry-run` 验证解析；禁止引入 `material_ui`/`cupertino_ui`；禁止 build_runner 代码生成链路；字体保持现状（子集进 FontManifest，16.95MB 全量继续懒加载）。
3. **不改业务**：计时、事项完成、容量、只读日历、同步、AI 流程全部保持现有行为；不改 `apps/api/`、数据库、部署脚本；不做无关重命名/格式化/目录搬迁。
4. **保留测试契约**：改前先 grep `apps/flutter_client/test` 与 `integration_test`；重点 Key：`dashboard-empty-plan`、`dashboard-ai-planning`、`dashboard-complete-cycle`、`study-clock-*`、`study-timer-action-*`、`task-extra-timer-*`、`task-menu-*`、`task-extra-chip-*`、`extra-minutes-*`、`calendar-mode-switch`、`calendar-overview`、`calendar-day-chart`、`undo-study-session-*`；中文文案「今日学习」「全部事项」「今日加学」「新建事项」「登录不白学 · 学习执行台」等。若替换控件确实需要改断言，说明原因并保持同等或更强覆盖。
5. **设计约束**（见 `DESIGN.md`）：无渐变/装饰插画/营销文案；卡片 hairline、无重投影；中文正文 ≥12.5px、行高 1.5–1.6；不用 w300 显示中文；强调色只有墨蓝；数字 tabular。
6. **最小 diff + 一次只推一个工作包**：W0/W1 跑通验收后再进入 W2；不要自行 `git commit`，把改动留在工作区并汇报 diff 摘要；`.dsh-verify/` 只做临时验证，不提交。

## 4. 环境与验证命令

```powershell
# 依赖解析（新增包前）
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client
$env:PUB_CACHE = 'D:\_projects\sjtu-study-planner\.dart_tool\pub-cache'
& D:\tools\flutter\bin\flutter.bat pub add <pkg> --dry-run

# 静态检查 / 测试 / 格式化（只格式化本次改动文件）
& D:\tools\flutter\bin\flutter.bat analyze --no-pub      # 目标 0 error（既有 6 条 info 可保留）
& D:\tools\flutter\bin\flutter.bat test --no-pub         # 基线 704 条全绿
& D:\tools\flutter\bin\dart.bat format <改动文件>
```

启动（另开两个终端）：

```powershell
Set-Location D:\_projects\sjtu-study-planner
npm run api:dev                          # API :8787（当前可能未启动，需要时先起）
npm run dev -- -Device web-server        # 客户端 :5180（当前 :5180 有服务在跑，可直接用）
```

热重载：`flutter run` 终端按 `r` / `R`；后台进程无法输入时重启 dev server（替换控件/改 const 类字段必须热重启）。

**截图验收（Playwright 已装）**：仓库根 `node_modules/playwright` + `.playwright-browsers/`；演示账号 `.dsh-verify/calendar-demo/account.json`。沙箱若阻止直接 launch（`spawn EPERM`），用「外部启动 Chromium（`--remote-debugging-port`）+ `connectOverCDP`」，可参考 `.dsh-verify/ui-redesign/capture-pages.mjs`、`shot-helpers.mjs`（临时脚本，不提交）。每轮至少截：桌面 1366（今日、日历日/周/月、设置、登录）、移动 390/320（今日、日历月）；控制台 `console.error`/`pageerror` 必须为空（401 登录失败除外）。

## 5. 验收标准（W0+W1 完成定义）

1. `flutter analyze --no-pub` 0 error；`flutter test --no-pub` 全绿（704+ 或说明新增测试）。
2. table_calendar 月视图、fl_chart 日/周图、lucide 图标在 1366/390/320 下截图正常，无 overflow、无 console error。
3. 只读语义不变：不能新建/拖拽日历事件；既有 Key 与文案可被测试找到。
4. `THIRD_PARTY_NOTICES.md` 三条登记完整；无 AGPL/GPL 代码片段；`pubspec.yaml`/`pubspec.lock` 变更说明体积影响。
5. 删除替换后的死代码；`git status`/`git diff --stat` 无意外文件。

## 6. 结束时按这个格式汇报

```
## W0+W1 完成情况
- 做了什么（逐条）
- 新增依赖与版本 / 许可证 / 体积影响
- 改动文件（git diff --stat 摘要）
- 验证结果：analyze（0 error/6 info）、test（N 条通过）、截图路径
- 遗留问题 / 未做项 / 建议下一步（W2/W3…）
```

## 7. 常见坑

1. Flutter 3.47 的 Material 解耦：出现 `material_ui`/`cupertino_ui` 依赖即放弃该依赖，改用 vendor/重写。
2. fl_chart 默认观感很“通用”：grid/border/tooltip/axis/label 必须用令牌覆写，否则视觉回退。
3. table_calendar 只覆盖月/周：日视图时间轴若需要，二选一（`calendar_view`）或保留自研，避免两套日历并存。
4. 替换控件会改变 Semantics 树：先跑测试再改断言，覆盖不能降低。
5. 不要复制 AGPL/GPL 源码（git 历史不可回滚干净）；vendor 必须保留 LICENSE/NOTICE 并登记。
6. 中文排版：第三方控件默认字体/行高不适合中文，必须覆写正文 ≥12.5px。
7. 时间格式/数字：时间与分钟数继续使用 tabular figures。
