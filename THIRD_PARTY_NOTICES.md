# 第三方代码与素材说明（THIRD PARTY NOTICES）

本文件记录「不白学 · 学习执行台」仓库中**实际包含或转写**的第三方代码、素材及其许可证。
新增任何第三方代码/素材前，必须先在本文件登记，并把对应的 LICENSE/NOTICE 文本放入被引入目录。
规则全文见 `UI_OSS_BORROW_PROMPT.md` §3；vendor 目录规则见 `packages/ui_vendor/README.md`。

## 1. 当前包含的第三方素材（assets / 字体）

| 名称 | 许可证 | 位置 | 用途 | 修改说明 |
| --- | --- | --- | --- | --- |
| Noto Sans SC（字体） | SIL Open Font License 1.1 | `apps/flutter_client/assets/fonts/NotoSansSC.ttf`、`assets/fonts/PlannerSansSC-UI.ttf`、`assets/fonts/OFL.txt` | 客户端中文字体；子集用于首屏，全量文件运行时懒加载 | 使用 pyftsubset 生成 UI 子集，未修改字形 |
| Lucide 图标字体 | ISC（图标）/ MIT（`lucide_icons_flutter` 包代码） | `packages/ui_vendor/lucide/lucide.ttf`（+ `LICENSE-ISC.txt` / `LICENSE-MIT.txt`），通过 `packages/ui_vendor` 的 `Lucide` 字族接入 | 页面级 16–18px 线性图标；默认 400 字重 `LucideIcons.*` 子集 | 只复制默认字族字体文件；release web 构建由 `--tree-shake-icons` 子集化（925,600 → 14,096 bytes） |

> Flutter SDK、Dart SDK 以及 `pubspec.lock` 中的 pub.dev 依赖按其各自许可证分发，**Flutter 构建会把全部依赖的许可证收集到应用内** `NOTICES.Z`（AssetBundle LicenseCollector），无需在本文件逐条复制全文；本文件登记所有**被直接使用/复制/转写**的第三方代码与素材。本轮直接使用的依赖见 §2。

## 2. 代码借鉴登记（转写 / vendor / 直接依赖）

规则：
- MIT / ISC / BSD / Apache-2.0：允许整文件或整模块转写、vendor 或直接依赖；必须保留版权声明与许可证文本；Apache-2.0 需保留上游 NOTICE（若上游提供）并声明修改。
- AGPL-3.0 / GPL-2.0 / GPL-3.0：**禁止复制源码**，只能阅读后提炼设计数值，不登记为代码来源。
- 直接依赖（不复制源码）登记版本与用途；vendor 的代码登记上游版本/commit、引入路径与修改清单。

### 2.1 本轮（W1，2026-10-20）新增直接依赖

| 项目 | URL | 许可证（实测自包内 LICENSE） | 上游版本 | 引入方式 / 路径 | 修改概要 | 引入日期 |
| --- | --- | --- | --- | --- | --- | --- |
| table_calendar | https://pub.dev/packages/table_calendar | **Apache-2.0**（3.3.0 包内 LICENSE；上游无 NOTICE 文件） | 3.3.0 | 直接依赖，不复制源码。使用位置：`apps/flutter_client/lib/features/calendar/presentation/calendar_month_chart.dart` | 不使用源码修改；用同包导出的 `TableCalendarBase` + `dayBuilder`/`dowBuilder` 自绘日格（`TableCalendar` 高层控件的 `CellContent` 会用英文日期 `excludeSemantics` 覆盖自定义语义，故降级到 Base），只读配置 `availableGestures: AvailableGestures.none`、无长按/拖拽/新建；样式全部用 `PlannerColors` 覆写 | 2026-10-20 |
| fl_chart | https://pub.dev/packages/fl_chart | **MIT**（Copyright (c) 2022 Flutter 4 Fun） | 1.2.0 | 直接依赖，不复制源码。使用位置：`calendar_day_chart.dart`、`calendar_week_chart.dart` | 不使用源码修改；日视图用 `LineChart`（横线描边=色带厚度、`betweenBarsData`=计划/实学 ribbon），周视图镜像用 `BarChart`、山脉用 `LineChart`；所有轴/网格/Tooltip/图例样式以 `PlannerColors` 令牌覆写，关闭 fl_chart 内置触摸与动画，不保留默认配色/边框 | 2026-10-20 |
| lucide_icons_flutter（vendor 子集） | https://pub.dev/packages/lucide_icons_flutter · https://lucide.dev | **MIT**（包代码，Copyright (c) 2024 vqhapp）；**ISC**（Lucide 图标，Copyright (c) Lucide Contributors 2022） | 4.0.0（Lucide 1.58.0） | **vendor 子集**：`packages/ui_vendor/lucide/lucide.ttf`（原字体文件，未改字形）、`packages/ui_vendor/lib/lucide.dart`（39 个实际使用的 `IconData` 常量，`fontPackage: planner_ui_vendor`）、`packages/ui_vendor/lucide/LICENSE-MIT.txt` + `LICENSE-ISC.txt`。使用位置：外壳/日历/今日/设置页面级图标 | 修改概要：① 只保留默认 400 字重字族，去掉上游 `pubspec.yaml` 声明的 Lucide100–600 六个变体字族（它们是整包打入 Web、~2.9 MB 的无用资产，实测后弃用直接依赖）；② 图标常量按客户端实际引用裁剪为 39 个并改写 `fontPackage`；③ 保留原始 MIT/ISC 许可证文本与版权行。字体在 release web 构建中被 tree-shake 到 14,096 bytes | 2026-10-20 |

### 2.2 本轮新增依赖带来的传递依赖（pub.dev 分发，不复制源码）

| 包 | 版本 | 许可证 | 引入原因 |
| --- | --- | --- | --- |
| intl | 0.20.3 | BSD-3-Clause（Dart project authors） | table_calendar 的日期格式化依赖 |
| simple_gesture_detector | 0.2.1 | Apache-2.0 | table_calendar 的手势依赖 |
| equatable | 2.1.0 | MIT（Copyright (c) 2026 Felix Angelov） | fl_chart 数据类相等性依赖 |

> 说明：`UI_OSS_BORROW_PROMPT.md` 把 table_calendar 标为 MIT；**实测 3.3.0 包内 LICENSE 为 Apache-2.0**。Apache-2.0 在本项目许可证矩阵中允许（§3.1）且上游未提供 NOTICE 文件，因此按依赖引入，无需额外 NOTICE；已在 `DESIGN.md` 与提交说明中更正。

### 2.3 本轮 vendor 内容（`packages/ui_vendor/`）

| 项目 | 引入路径 | 保留的许可证 | 修改说明 |
| --- | --- | --- | --- |
| lucide_icons_flutter 4.0.0 / Lucide 1.58.0 | `packages/ui_vendor/lucide/lucide.ttf`、`packages/ui_vendor/lib/lucide.dart` | `lucide/LICENSE-MIT.txt`、`lucide/LICENSE-ISC.txt` | 见 §2.1 lucide 行；文件头保留 “Adapted from …” 与修改声明 |

`packages/ui_vendor/README.md` 仍然是后续（W2+）vendor forui `FSidebar` / LocalSend 桌面行 / shadcn 主题结构的规则入口；引入时在本表追加行并保留上游 LICENSE/NOTICE。

## 3. 仅作设计参考、不含代码的项目（不登记为代码来源）

以下项目的**设计数值/行为**被提炼到 `DESIGN.md`，但未复制任何源代码：

- AppFlowy / appflowy_ui（AGPL-3.0）：中性色阶、间距/圆角刻度、字号字重、阴影层级数值。
- Super Productivity（MIT）：状态透明度、行处理方式、计时器结构（如需转写代码须按上表登记）。
- LocalSend（Apache-2.0）：桌面端内容宽度、滚动行为与设置行密度（W2 的 `PlannerScrollBehavior` 桌面滚动沿用既有实现，仅借鉴行为模式，未复制源码）。
- Cal.com / cal.diy（MIT，以仓库当前 LICENSE 为准）：日历 token 与几何数值。
- shadcn/ui、Radix Colors（MIT）：语义 token 命名与颜色职责划分。
- Dense Graphite（暗色）色值整理自本项目 .dsh-verify/ui-redesign/research/domain-apps.md §7.3（AppFlowy / Linear / Radix 的设计数值）；只使用数值与对比度方法，未复制任何上游代码。
- Super Productivity（MIT）：W4 动效纪律——状态切换 120/180/240ms、快速微交互、不做装饰/循环动画（仅数值与模式，未复制源码）。
- shadcn_ui（Flutter，MIT）、[flex_color_scheme](https://github.com/rydmike/flex_color_scheme)（BSD-3-Clause）：W3 令牌层组织方式（ThemeExtension 角色划分、一个组件族一个子主题构造函数、从令牌对象取值）；只读结构，未复制源码，代码按本项目 `PlannerTokens`/`PlannerComponentThemes` 重写。
- forui、shadcn_ui（MIT）：组件结构与交互模式。W2 借鉴 `FSidebar` 的 FocusScope + traversalEdgeBehavior 结构、`FSidebarItem` 的 hover/focus 状态与可折叠语义，自行实现侧栏折叠与方向键遍历（未复制源码；如需 vendor 须按 §2 登记）。
- Lucide（ISC）：图标造型与 24px 网格规范（通过 vendored 子集使用，见 §2.1 / §2.3）。

## 4. 本轮依赖解析实测记录（2026-10-20，Flutter 3.47.3 / Dart 3.13.3）

`dart pub add <pkg> --dry-run`（等价 `flutter pub add <pkg> --dry-run`）。记录时本机 flutter CLI 尚未解禁，使用同一 SDK 的 `dart pub` 执行；最终态已用 `flutter pub get` 重新解析并跑通 analyze/test/build。

```text
=== dry-run table_calendar ===
+ intl 0.20.3
+ simple_gesture_detector 0.2.1
+ table_calendar 3.3.0
Would change 3 dependencies.

=== dry-run fl_chart ===
+ equatable 2.1.0
+ fl_chart 1.2.0
Would change 2 dependencies.

=== dry-run lucide_icons_flutter ===
+ lucide_icons_flutter 4.0.0
Would change 1 dependency.
```

结论：三个包均可解析；**未引入 `material_ui` / `cupertino_ui`**（Flutter 3.47 Material 解耦风险），无 build_runner/codegen 链路，无原生插件。

> 许可证实测补充：table_calendar 3.3.0 包内 LICENSE 为 **Apache-2.0**（非任务书写的 MIT），simple_gesture_detector 同为 Apache-2.0；两者均在本项目允许矩阵内，上游未提供 NOTICE 文件，因此无额外 NOTICE 义务。

## 5. Web / 包体积影响（实测）

2026-10-20 在本机 Flutter 3.47.3 上执行 `flutter build web --release`，对比 HEAD（W1 之前）与 W1 最终态：

| 指标 | HEAD（W1 前） | W1 最终（vendor Lucide） | 差值 |
| --- | --- | --- | --- |
| `build/web/main.dart.js` | 3,754.3 KB | 3,889.0 KB | **+134.7 KB（+3.6%）** |
| `build/web/assets/` 总大小 | 19,859.0 KB | 19,884.9 KB | **+25.9 KB（+0.13%）** |
| `build/web/` 总计 | 60,652.1 KB | 60,812.4 KB | **+160.3 KB（+0.26%）** |

结论：W1（table_calendar + fl_chart + vendored Lucide 图标）对 release Web 产物的净增约 **+160 KB**，没有引入额外字体/图片资产膨胀。

W7 收口（2026-10-21，最终态，累计 W0–W7；W2–W7 未新增 pub 依赖）：

| 指标 | HEAD（W1 前） | W1 最终 | W7 最终（累计） | 相对 HEAD |
| --- | --- | --- | --- | --- |
| build/web/main.dart.js | 3,754.3 KB | 3,889.0 KB | 3,873.4 KB | **+119.1 KB（+3.17%）** |
| build/web/assets/ 总大小 | 19,859.0 KB | 19,884.9 KB | 19,884.9 KB | **+25.9 KB（+0.13%）** |
| build/web/ 总计 | 60,652.1 KB | 60,812.4 KB | 60,796.8 KB | **+144.7 KB（+0.24%）** |

W1 之后 main.dart.js 净减约 15.6 KB：W2–W7 的键盘/令牌/暗色/动效/组件细节代码增加，但移除 Material showDatePicker（改用自绘中文选择器 PlannerDatePicker）后其代码被 tree-shake，净效果为 -15.6 KB；assets 未再增长，说明没有新增字体/图片资源。字体懒加载在 W7 复验：FontManifest.json 只含 3 个字族（MaterialIcons tree-shaken、PlannerSansSC-UI 子集 1.1 MB、vendor Lucide tree-shaken）；全量 NotoSansSC.ttf（17,772,300 bytes）不在 manifest 中，仅被 main.dart.js 的 FontLoader 引用并在首帧后按需加载。

字体实测（最终 `FontManifest.json` 只有 3 个字族）：
- `MaterialIcons-Regular.otf`：1,645,184 → 14,604 bytes（tree-shaken 99.1%）。
- `packages/planner_ui_vendor/Lucide/lucide.ttf`：925,600 → 14,096 bytes（tree-shaken 98.5%）。
- `NotoSansSC`：首屏子集 1,112.6 KB + 懒加载全量 17,355.8 KB（与 W1 前一致）。

反证：如果按任务书保留 **直接依赖 `lucide_icons_flutter 4.0.0`**，Flutter 会把包 `pubspec.yaml` 声明的全部 7 个字族打进 asset bundle；实测只使用默认字族时，`assets/` 仍会比 W1 前多 **+2,904.2 KB**（6 个 452–511 KB 的 Lucide100–600 变体字体），Web 总增量约 +3.06 MB。因此本轮按 W0 §3.4 的 vendor 路线只保留默认字体 + 39 个图标常量，并在 §2.1 / §2.3 登记 MIT/ISC 许可证。

> 说明：`intl`（table_calendar 依赖）与 `equatable`（fl_chart 依赖）为纯 Dart 代码，被 dart2js tree-shake，未增加独立资源；上表已包含其代码体积。

## 6. 自检命令

```powershell
# 1) 常规源目录不应出现 AGPL/GPL 代码片段（输出必须为空）
git grep -n -i "AGPL-3.0\|GNU AFFERO\|GNU GENERAL PUBLIC LICENSE" -- apps/flutter_client/lib packages/

# 2) 列出 vendor 目录及其许可证文件
Get-ChildItem packages/ui_vendor -Recurse -File -Include LICENSE,NOTICE,COPYING -ErrorAction SilentlyContinue

# 3) 校验依赖许可证（本地 pub cache）
Get-ChildItem .dart_tool/pub-cache/hosted/pub.flutter-io.cn -Directory |
  Where-Object { $_.Name -match '^(table_calendar|fl_chart|lucide_icons_flutter|intl|simple_gesture_detector|equatable)-' } |
  ForEach-Object { $_.Name + ' -> ' + (Get-Content (Join-Path $_.FullName 'LICENSE') -TotalCount 2 | Out-String).Trim() }

# 4) 体积实测（需可运行 Flutter CLI 的环境）
flutter build web --release
Get-Item apps/flutter_client/build/web/main.dart.js | Select-Object Length
Get-Content apps/flutter_client/build/web/assets/FontManifest.json
```