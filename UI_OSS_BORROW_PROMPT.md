# 借鉴开源前端源码做 UI 深度优化 · 实施 Prompt（v2：允许大规模借鉴）

请把本文件全文作为任务提示词交给编码 Agent。目标：在「雾蓝墨水 / Mist Ink」视觉改版已完成的基础上，**大规模借鉴成熟开源项目的实现代码**（不限于少量转写：允许整体 vendor 内部包、允许把 MIT/BSD/Apache 包作为依赖引入、允许替换自制组件为开源实现），把「看起来干净」推进到「用起来专业」。

> v2 相对 v1 的变化：新增 §3.5「借鉴规模策略」、W0「第三方代码引入机制」；W1/W3/W6 允许整模块引入或替换；新增 `THIRD_PARTY_NOTICES.md` 要求与依赖兼容性实测结论。**许可证边界仍然不可突破**（见 §3.4）。

---

## 0. 使用方式与角色设定

- 角色：本项目的 Flutter UI 工程师（兼设计系统维护者、第三方代码合规负责人）。
- 工作目录：`D:\_projects\sjtu-study-planner`。
- 只在现有 Flutter 客户端内工作：`apps/flutter_client/`；第三方包放在 `packages/`（monorepo 已有 `packages/planner-engine` 先例）。除非任务明确要求，不动 `apps/api/`、数据库与部署脚本。
- 先读代码与文档，再实施；每个工作包完成后自测、截图、再进入下一个。不要一次性大改后才发现回归。
- 遇到实现路线选择时按 `DESIGN.md` 与本文档的优先级自行决定，并记录理由；只有会影响数据、产品语义、发布安全或**许可证合规**时才需要停下来询问。

---

## 1. 背景：当前 UI 状态（已完成，不要重做视觉方向）

2026-10-20 已完成一轮视觉改版，设计语言为「雾蓝墨水 / Mist Ink」：

- `apps/flutter_client/lib/core/theme.dart`：显式 `ColorScheme` + Material 组件主题（卡片 12px 圆角 hairline、按钮/输入 10px、字号阶梯 22/15/14/13.5/13/12.5、tabular figures）。
- `apps/flutter_client/lib/core/widgets.dart`：`PlannerPanel / PageHeader / SectionHeader / MetricTile / PlannerTag / PlannerSegmented / PlannerIconAction / PlannerEmpty / PlannerNotice / TimeProgressTrack / PlannerScrollBehavior` 等共享组件。
- 已完成视觉重构：`features/shell/app_shell.dart`（240px 侧栏 + 移动端底部导航 + 顶部计时条）、`dashboard`、`tasks/task_directory`、`calendar`（日/周/月 + 概览）、`adjust`、`settings`、`auth`。
- `DESIGN.md` 已记录令牌、组件约定与开源项目借鉴出处。
- 验证基线：`flutter analyze --no-pub` 0 error（6 条既有 info）；`flutter test --no-pub` 704 条全部通过；1366/390/320 宽截图无 overflow。
- 已修复：设置页 `granularity_minutes=15` 的下拉断言、`PlannerPage` 的 Scrollbar 断言、日历 320px 溢出。

本轮定位：**用开源实现替换/增强自研 UI 代码**，补齐桌面专业度（键盘/焦点/密度）、动效纪律、暗色主题、图标一致性与性能细节；能用成熟实现就不要继续手写。

---

## 2. 本轮目标与非目标

### 2.1 目标（按价值排序）

1. **设计系统可维护性**：令牌层收敛为 `ThemeExtension` 语义角色；允许直接借鉴 shadcn_ui / flex_color_scheme 的主题代码结构。
2. **桌面可用性**：侧栏、日历、分段控件、对话框的键盘导航/焦点环/状态统一；允许 vendor forui 的相应实现（重写或移植均可，见 §3.5）。
3. **日历与图表升级**：允许把自研 CustomPainter 日历/图表替换为 MIT 许可的成熟实现（`table_calendar` / `calendar_view` / `fl_chart`），保留全部只读语义与测试可查找文本。
4. **动效纪律**：统一时长/曲线令牌，全部动画响应 `MediaQuery.disableAnimations`。
5. **暗色主题**：`plannerDarkTheme()`，跟随系统 + 设置页开关，全页面/图表/日历暗色映射，对比度达标。
6. **图标一致性**：引入 `lucide_icons_flutter`（零运行时依赖、字体离线）替换散落 Material outlined 图标。
7. **性能与回归**：`RepaintBoundary`、减少无意义重建、Web/桌面滚动与字体加载不退化。
8. **合规与文档**：`THIRD_PARTY_NOTICES.md` + `DESIGN.md` 记录每处借鉴的项目、许可证、上游版本/commit、修改人；交付可审计。

### 2.2 非目标

- 不改业务逻辑、数据模型、同步协议、排程算法、AI 交互与文案语义。
- 不整体迁移到 forui / shadcn_ui / flex_color_scheme 的运行时依赖（技术原因见 §3.5：Flutter 3.47 的 material_ui 解耦会引入第二套 Material 类型）。
- 不做多套主题市场；只交付浅色 + 深色。
- 不引入 AGPL/GPL 代码；不引入商用（Syncfusion 等）组件。
- 不为视觉效果破坏 `DESIGN.md` 中的功能约束与信息架构。

---

## 3. 借鉴来源、许可证与大规模借鉴策略

### 3.1 许可证总原则（先看这一节，违反即回退）

| 许可证 | 大规模借鉴是否允许 | 本任务做法 |
| --- | --- | --- |
| MIT / ISC / BSD-2/3 / Apache-2.0 | **允许**，可整文件、整模块、乃至整包 fork/vendor | 保留版权声明与许可证文本；Apache-2.0 需保留 NOTICE 并声明修改；在 `THIRD_PARTY_NOTICES.md` 登记 |
| AGPL-3.0（AppFlowy、Plane 等） | **不允许复制代码** | 只读源码、提炼设计数值；**不得复制任何源码片段**。本项目无根 LICENSE、默认保留所有权利；Web 部署还触发 AGPL §13 网络使用条款，整包会被要求以 AGPL 开源 |
| GPL-2.0/3.0（FlClash、Loop Habit Tracker 等） | **不允许复制代码** | 同上，只读设计语言 |
| 商用许可（Syncfusion 等） | 不允许 | 不使用 |

> 当前仓库根目录**没有 LICENSE 文件**，即视为「保留所有权利」。如果未来计划把项目整体开源，可以在落地前统一决策一次许可证（例如 AGPL）——那会解锁 AppFlowy/forui 生态的整体引入；**本轮按闭源/未授权处理，禁止 AGPL/GPL 代码进入仓库。** 该决策不在 Agent 权限内，遇到必须询问用户。

### 3.2 可大规模借鉴的来源（本轮核心）

| 项目 | 许可证 | 本轮允许的借鉴形态 | 具体做什么 |
| --- | --- | --- | --- |
| **table_calendar 3.3.0** | MIT | **直接依赖**（已实测可解析） | 月/周/日只读日历控件；用 `eventLoader`/`calendarBuilders` 定制我们的计划/实学标记；替换自研 `calendar_month_chart.dart` 的网格逻辑，保留“今天/选中/容量”语义 |
| **fl_chart** | MIT | **直接依赖**（已实测可解析） | 替换日/周自研 CustomPainter：折线/柱状/面积图；统一令牌配色、tabular 标签、无竖向网格；保留图表外框与语义摘要 |
| **calendar_view** | MIT | 备选依赖（已实测可解析） | 若需要日/周时间轴视图再引入；与 table_calendar 二选一，避免两套日历并存 |
| **lucide_icons_flutter 4.x** | ISC（图标）/ MIT（包） | **直接依赖**（已实测可解析） | 统一 16–18px 线性图标；保持 Semantics/tooltip 不变 |
| **LocalSend**（Flutter，Apache-2.0） | Apache-2.0 | **vendor 整文件/整目录** | `packages/ui_vendor/localsend/`：主题组织、桌面滚动行为、列表/设置行组件；保留 LICENSE/NOTICE、记录修改 |
| **shadcn_ui**（Flutter，MIT） | MIT | **vendor 主题与组件子集** | `packages/ui_vendor/shadcn_theme/`：`ShadcnTheme` 数据类结构、token 角色、按钮/输入/卡片的样式聚合；去掉 slang/codegen 与重依赖后再接入；**不直接依赖**（当前镜像解析到 0.0.0，不可用） |
| **flex_color_scheme 9.x** | BSD-3-Clause | **vendor 小文件 + 重写** | `FlexSubThemes` 的 input/appbar/button compact 写法；**不直接依赖**（会拉入 material_ui） |
| **forui 0.27.x** | MIT + OFL | **vendor/移植关键组件** | `FSidebar`（展开收起、键盘遍历）、`FCalendar`（月格键盘导航、`+N`）、`FTabs`（滑动态 + reduced-motion）；只移植需要的文件并适配本项目主题；**不直接依赖**（会拉入 material_ui/cupertino_ui） |
| **Super Productivity** | MIT | **转写主题契约与行样式** | `docs/theming-contract.md` 的状态透明度、`ink-on-channel` 思路、`zen.css`/`classic.css` 的行处理；可整段转写为 Dart 常量/样式 |
| **Cal.com / cal.diy** | MIT（以仓库当前 LICENSE 为准） | 转写 CSS token 与网格几何 | `packages/config/theme/tokens.css` 的 radius/颜色/阴影；日历格与事件块几何 |
| **AppFlowy / appflowy_ui** | **AGPL-3.0** | **只读** | 只提炼数值（色阶、间距/圆角刻度、字号字重、两级阴影）；**禁止复制代码** |
| **material_3_demo** | BSD-3 | vendor/参考 | 焦点、键盘、组件状态示例代码可复制并登记 |

### 3.3 已实测的依赖兼容性（2026-10-20，`flutter pub add --dry-run`，Flutter 3.47.3）

| 包 | 解析结果 | 结论 |
| --- | --- | --- |
| `table_calendar` | 3.3.0，仅新增 `simple_gesture_detector` | ✅ 可直接依赖 |
| `fl_chart` | 可解析，新增 1–2 个纯 Dart 依赖 | ✅ 可直接依赖 |
| `calendar_view` | 可解析，新增 1 个依赖 | ✅ 备选 |
| `lucide_icons_flutter` | 可解析，仅 1 个依赖 | ✅ 可直接依赖 |
| `shadcn_ui` | 当前解析为 `0.0.0`（0.57.2 不可达） | ❌ 不可依赖；只 vendor/借鉴结构 |
| `flex_color_scheme` | 9.0.0，会新增 `material_ui 1.7.0` + `cupertino_ui 1.1.3` | ⚠️ 不依赖；vendor 小段代码或重写 |
| `forui` | 0.27.6，会新增 `material_ui` + `cupertino_ui` + `forui_lucide` + `sugar` + `intl` | ⚠️ 不依赖；vendor/移植组件 |

> 新增包前必须重跑上述 dry-run 并记录结果；Flutter 3.47 的 `material_ui` 解耦会让同一应用出现两套 Material 类型，**出现 `material_ui`/`cupertino_ui` 即默认视为不可依赖**（除非完成一次独立的技术验证并写入文档）。

### 3.4 依赖引入 vs vendor vs 重写的决策顺序

按以下优先级选择（能靠前就不往后）：

1. **直接依赖**：MIT/BSD/Apache 且 dry-run 干净、维护活跃、离线可用 → 首选（table_calendar、fl_chart、lucide）。
2. **整目录 vendor 到 `packages/ui_vendor/<name>/`**：许可允许但依赖树不干净、或需要深度定制 → 复制上游文件 + 改 import + 保留 LICENSE + 记录上游版本/commit 与修改清单。
3. **移植关键文件（部分 vendor）**：只需要一个组件/一个算法（如 forui 的 FSidebar 键盘逻辑）→ 复制最小文件集，去掉不需要的依赖，加 `// Adapted from <repo>@<commit> (<path>), MIT` 文件头。
4. **重写**：只有逻辑简单或必须贴合本项目（如令牌层、页面编排）才自己写。
5. **只读数值**：AGPL/GPL 项目。

### 3.5 第三方代码落地规范（W0）

1. 新建 `packages/ui_vendor/`（Flutter package，可选多个子包）与根目录 `THIRD_PARTY_NOTICES.md`。
2. 每个被引入的项目在 `THIRD_PARTY_NOTICES.md` 里登记：项目名、URL、许可证、上游版本/commit、引入路径、修改概要、引入日期。
3. vendor 目录必须保留上游 `LICENSE`（Apache-2.0 还要 `NOTICE`），文件头保留原始版权行；在改动文件顶部加 `// Modified by 不白学 for <原因>`。
4. 不得把 vendor 代码与业务代码混在同一文件；不得为了“看起来像自己写的”而删除版权声明。
5. `packages/ui_vendor/` 的代码必须通过 `flutter analyze` 与测试；若上游代码使用旧 API/废弃接口，允许最小修改并在 NOTICE 记录。
6. 提交前跑 `git grep -n "AGPL\|GNU AFFERO" packages/ apps/flutter_client/lib` 自检，确认没有 AGPL/GPL 片段进入源码。

---

## 4. 工作包（按顺序执行，每个可独立验收）

### W0 — 第三方代码引入机制（先做）

按 §3.5 建立 `packages/ui_vendor/`、`THIRD_PARTY_NOTICES.md`、许可检查说明；把 `DESIGN.md` 的「借鉴表」升级为可审计表格（项目/许可证/版本/引入文件/修改）。本工作包不含视觉变化。

**验收**：目录与文档就绪；`flutter analyze` 0 error；给出“本轮计划引入的第三方清单与许可证结论”。

### W1 — 依赖引入：日历与图表换用成熟实现（大规模借鉴主战场）

1. 引入 `table_calendar 3.3.0`：用其 `TableCalendar` 替换月视图网格（只读）。通过 `calendarBuilders` 保留：今日蓝圆、选中内描边、计划/实学/容量摘要、`+N` 溢出；`eventLoader` 映射计划块；禁用交互中的“新建/拖拽”能力。
2. 引入 `fl_chart`：用 `LineChart`/`BarChart` 重写日视图“生长轨道”“计划与实际双河道”和周视图镜像/山脉图（只保留一种，避免两套视图并存）；坐标轴/标签/图例走 `PlannerColors` 令牌；保留 `ValueKey('calendar-day-chart')` 等测试键与语义摘要。
3. 引入 `lucide_icons_flutter`：替换 shell/日历/今日/设置页的页面级图标；保持 `Semantics(label)`、tooltip 与测试 `find.byIcon` 不破坏。
4. 替换后删除不再使用的自研实现（`calendar_month_chart.dart` 等）与相关 painter；保留的测试必须全部通过。

**验收**：`calendar_*` 测试全绿（必要时更新断言以匹配新控件语义，但不得降低覆盖）；桌面/390/320 截图；依赖体积变化说明；`THIRD_PARTY_NOTICES.md` 三条登记。

### W2 — Vendor 侧栏与键盘/焦点实现

从 forui（MIT）移植/借鉴 `FSidebar` 的展开收起、键盘遍历、hover/focus 状态；从 LocalSend（Apache-2.0）借鉴桌面滚动/列表行实现。要求：

1. 侧栏 240 ↔ 64px 折叠；方向键/Enter/Home/End 导航；焦点环令牌；移动端不折叠。
2. 日历（若 W1 已用 table_calendar，则在其 `calendarBuilders` 内）方向键切日、PageUp/Down 切月、Home 回今天。
3. 分段控件/标签筛选支持方向键 + Space/Enter。
4. 对话框 Esc 关闭、焦点限制与归还。

**验收**：新增 ≥4 个键盘/焦点 widget 测试；手动焦点态截图；无文本输入被误拦截。

### W3 — 令牌层重构（可整文件 vendor）

1. 新建 `lib/core/theme/{tokens,planner_theme,component_themes}.dart`；从 shadcn_ui（MIT）vendor `ShadcnTheme` 的数据类组织方式，从 flex_color_scheme（BSD-3）vendor `FlexSubThemes` 的 compact 子主题写法，改为本项目 `PlannerTokens extends ThemeExtension` + 组件子主题。
2. `PlannerColors` 保留为兼容别名；16 个已改页面逐步改读语义令牌。
3. 状态透明度、focus ring、motion 统一从令牌读取。

**验收**：`flutter analyze` 0 error；测试全绿；截图与基线差异 ≤2px（允许刻意微调并说明）；`PlannerColors` 直接引用计数下降数据。

### W4 — 动效与 reduced-motion

统一 `PlannerDurations`（120/180/240ms）与曲线；所有动画尊重 `disableAnimations`；只保留状态变化动画；计时器数字不重建整卡。

**验收**：reduced-motion 下正确；`pumpAndSettle` 不超时。

### W5 — 暗色主题（Dense Graphite）

实现 `plannerDarkTheme()`（令牌见调研报告 §7.3），跟随系统 + 设置页开关（本地持久化）；图表/日历/标签/Notice 暗色映射；正文对比度 ≥4.5:1、大字 ≥3:1；`grep` 无遗留浅色硬编码。

**验收**：浅/深 × 五页面截图；新增主题切换测试；对比度实测记录。

### W6 — 组件细节统一（可 vendor LocalSend / shadcn 片段）

滚动条、空/错/载入态、菜单/对话框/Tooltip、行高与中文排版下限统一；能 vendor 的就 vendor，不能的按令牌重写。

**验收**：五处页面状态截图；无 Material 默认观感残留清单。

### W7 — 性能与回归收口

`RepaintBoundary`、避免无意义重建；与 `.dsh-verify/optfix/perf/flutter-current.json` 基线对比（阈值 ≤5% 或说明基线不可用）；字体继续懒加载；125%/150% 缩放检查；全量 analyze/test/截图。

**验收**：0 error、全绿测试、性能结论、缩放结论、截图目录。

---

## 5. 硬性约束（违反即回退）

1. **不改业务语义**：计时、完成、容量、只读日历、同步、AI 流程保持现有行为。
2. **保留全部 Key / Semantics / 文案与测试可查找文本**（改造前 grep `apps/flutter_client/test`、`integration_test`）。重点 key：`dashboard-empty-plan`、`dashboard-ai-planning`、`dashboard-complete-cycle`、`study-clock-*`、`study-timer-action-*`、`task-extra-timer-*`、`task-menu-*`、`task-extra-chip-*`、`extra-minutes-*`、`calendar-mode-switch`、`calendar-overview`、`calendar-day-chart`、`undo-study-session-*`；中文文案：「今日学习」「全部事项」「今日加学」「新建事项」「登录不白学 · 学习执行台」等。
3. **设计禁忌**（见 `DESIGN.md`）：不用渐变/装饰插画/营销文案；卡片 hairline + 无重投影；中文正文 ≥12.5px；不用 `w300` 显示中文；强调色只有墨蓝一个；数字 tabular。
4. **依赖纪律**：允许新增包仅限 §3.3 的 ✅ 项（table_calendar / fl_chart / calendar_view 备选 / lucide_icons_flutter）与 `packages/ui_vendor/` 内部包；新增依赖必须 dry-run 记录、说明体积/许可证/离线可用性；禁止 forui/shadcn_ui/flex_color_scheme 直接依赖；禁止引入 `material_ui`/`cupertino_ui`。
5. **许可证纪律**：严格按 §3.1；AGPL/GPL 只读；vendor 必须保留 LICENSE/NOTICE 并登记；`THIRD_PARTY_NOTICES.md` 与 `DESIGN.md` 必须同步更新。
6. **最小 diff 与顺序**：一个工作包完成后才进入下一个；不做无关重命名/格式化/目录搬迁；`dart format` 只格式化本次改动文件。
7. **测试不可降低覆盖**：替换实现时如确需修改断言，必须说明原因并保留同等或更强的行为断言。

---

## 6. 环境、命令与验证流程

### 6.1 环境

- Flutter SDK：`D:\tools\flutter`（3.47.3 stable，Dart 3.13.3）。
- 包缓存：`D:\_projects\sjtu-study-planner\.dart_tool\pub-cache`（必须显式设置 `$env:PUB_CACHE`）。
- API：`http://127.0.0.1:8787`；客户端开发服务器默认 `http://127.0.0.1:5180`。
- 演示账号（仅本地）：`.dsh-verify/calendar-demo/account.json`。
- Playwright 与浏览器已安装：`node_modules/playwright`、`.playwright-browsers/`。

### 6.2 静态检查与测试

```powershell
Set-Location D:\_projects\sjtu-study-planner\apps\flutter_client
$env:PUB_CACHE = 'D:\_projects\sjtu-study-planner\.dart_tool\pub-cache'
& D:\tools\flutter\bin\flutter.bat pub add <pkg> --dry-run    # 新依赖先验证解析
& D:\tools\flutter\bin\flutter.bat analyze --no-pub           # 0 error（既有 6 条 info 可保留）
& D:\tools\flutter\bin\flutter.bat test --no-pub              # 基线 704 条全部通过
& D:\tools\flutter\bin\dart.bat format <改动文件>
```

### 6.3 启动与热重载

```powershell
Set-Location D:\_projects\sjtu-study-planner
npm run dev -- -Device web-server     # Web 服务 http://127.0.0.1:5180
npm run api:dev                       # 另一个终端
```

热重载：`flutter run` 终端按 `r` / `R`；后台进程无法输入时直接重启 dev server（改 const 类字段/控件替换必须热重启）。

### 6.4 截图与视觉验收（Playwright）

沙箱若阻止 Playwright 直接 launch（`spawn EPERM`），用「外部启动 Chromium（`--remote-debugging-port`）+ `connectOverCDP`」；示例脚本在 `.dsh-verify/ui-redesign/`（可复用/重写，不提交）。

每轮至少截：桌面 1366×900（今日、日历日/周/月、调整、设置、登录）；移动 390×844 与 320×760（今日、日历月）；交互态（侧栏焦点、日历选中/今日、对话框、分段控件）；暗色全套。控制台 `console.error`/`pageerror` 必须为空（401 登录失败除外）。

### 6.5 验收标准（全部满足才算完成）

1. `flutter analyze --no-pub` 0 error；新增依赖使体积变化有说明。
2. `flutter test --no-pub` 全绿，且新增键盘/主题/日历测试通过。
3. 浅/深色、桌面/移动端、关键交互态截图，无 overflow、无 console error。
4. 键盘：Tab 顺序、焦点可见、Esc、方向键、PageUp/Down 行为正确。
5. 对比度：正文 ≥4.5:1、大字 ≥3:1（记录实测值）。
6. 性能：与基线对比或说明基线不可用；无明显整页重建。
7. 合规：`THIRD_PARTY_NOTICES.md` 完整；`DESIGN.md` 借鉴表更新；无 AGPL/GPL 片段（自检命令通过）。
8. 交付说明：按 W0–W7 列出改了什么、截图路径、测试结果、许可证记录、遗留问题。

---

## 7. 建议提交拆分

- W0 第三方机制（文档 + 目录）单独提交。
- W1 依赖替换（日历/图表/图标）单独提交，便于回滚。
- W2 侧栏/键盘/焦点。
- W3 令牌重构（纯重构，单独提交）。
- W4/W6 动效 + 组件细节。
- W5 暗色主题。
- W7 性能收口 + 文档。

每次提交前跑 §6.2 与至少一组截图；提交信息写清工作包与验收结果。

---

## 8. 常见坑

1. **Flutter 3.47 Material 解耦**：出现 `material_ui`/`cupertino_ui` 依赖即视为不可直接用；否则 `ThemeData`/`Widget` 类型可能有两份。
2. **table_calendar 只有月/周视图语义**：日视图时间轴需要 `calendar_view` 或保留自研，二选一，避免两套日历并存。
3. **fl_chart 的默认观感很“通用”**：必须用令牌覆写 grid/border/tooltip/axis/label，否则会比现在的自研图表更丑；图例、tab 顺序与 tabular 数字要自己补。
4. **替换控件会改变语义树**：Playwright/Widget 测试依赖 `Semantics` 文案与 role，替换后先跑测试再改断言，保持覆盖不降低。
5. **vendor 代码的 import 与 API 漂移**：上游可能用旧 Flutter API（`withOpacity`、`CardTheme` 等），允许最小修改但要在 NOTICE 记录；不要顺手升级上游大版本。
6. **许可证自检**：AGPL/GPL 片段一旦提交就难以回滚干净（git 历史仍存在），务必在 vendor 前确认来源许可证。
7. **依赖体积**：Web 首帧只允许 Noto 子集字体进 FontManifest；新包的字体/资源要确认不会重复加载 16.95MB 全量字体。
8. **动画与测试**：`pumpAndSettle` 超时多半是未结束的动画/Ticker；计时器每秒刷新不要驱动整页动画。
9. **截图脚本**：`.dsh-verify/` 只做临时验证，不提交；不要把 Playwright 脚本/截图放入 `apps/`。
10. **中文排版**：任何替换控件都要保持正文 ≥12.5px、行高 1.5–1.6；第三方默认字体/行高通常不适合中文，必须覆写。

---

## 9. 交付物清单

- 代码：`apps/flutter_client/lib/core/theme/`（新增）、令牌/组件/页面改动、`packages/ui_vendor/`（如需 vendor）、`pubspec.yaml` 依赖变更。
- 测试：新增的键盘/焦点/暗色/日历交互 widget 测试。
- 合规：`THIRD_PARTY_NOTICES.md`（新增）、`DESIGN.md`（令牌 + 暗色 + 动效/焦点 + 借鉴明细）。
- 验证：浅/深色、桌面/移动端截图目录；`flutter analyze` / `flutter test` 输出；依赖 dry-run 记录；性能对比结论。
- 总结：按 W0–W7 列出完成度、第三方代码清单与许可证、遗留问题与下一轮建议（例如：命令面板、页面级快捷键、打印样式、i18n）。
