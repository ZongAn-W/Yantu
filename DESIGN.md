# 不白学设计规范

按用户明确的视觉约束直接实现。模式：Operate。

「今日」页合并学习执行与事项管理：单页单滚动，上半部分为居中标题的「今日安排」列表：计划内事项以单行紧凑计时行展示（标题、今日原定进度、实时用时与开始/暂停/继续计时为主操作；加学分钟内联显示，标签、总进度、撤销与建议收进展开），今天没有原定安排、纯加学或复习的事项以同样的紧凑行排在后面；下半部分「全部事项」为扁平事项目录，事项可有零个或多个标签，支持按所选标签的任一匹配筛选；可在目录内创建、编辑、重命名、改色和删除标签。页面顶部不展示日期与今日原定/已学汇总，分区也不带图例说明。桌面左侧导航 4 个栏目（今日、日历、调整、设置），其中「日历」合并了日/周/月只读视图与进度概览，主区内容宽度上限 1200px；手机底部导航、单列布局。

账号相关功能统一放在设置页：当前登录身份、退出登录与账号注销；今日、日历、调整等页面和全局框架不提供账号头像、账号对话框或其它账号入口。

使用本地中文系统字体保证离线和移动显示，数字采用 tabular-nums。

一层面板仅分割不同功能区域。按钮、状态、错误、键盘焦点统一；不使用装饰插画、渐变、营销文案。

计时采用紧凑事项行：事项标题独立展示，标签仅作补充分类，不能改变排程容量。开始、暂停和继续计时为主操作，调整日期、展开详情和撤销计时使用带提示的图标。暂停后显示最近一段用时；撤销前确认起止时间与扣除时长。实际用时由计时器累计，不提供手动修改入口或今日完成勾选；达到今日目标后自动计入达标事项，超出目标仍继续保留实际用时。

事项目录只显示事项名称与时间进度胶囊（未开始 / 进行中百分比 / 完成 / 超额百分比），不显示预计时长的明细、进度条或圆环、起止/截止日期、优先级或六态状态，也不设当前/后续/已完成页签；时间进度由实际计时 / 预计时长派生，预计时长用完即完成，也可提前确认完成；加学计时从行内闹钟开始（未计时 ⏰、计时中 ⏸、暂停后回到 ⏰），记录为「加学」关系，已完成事项为复习计时，已归档事项不提供计时入口；不提供拖拽排程、手动标记完成等执行操作。今日页不再显示用时饼图、净容量统计、全局「开始计时」按钮，也不再提供临时学习功能。

## 视觉语言：雾蓝墨水（Mist Ink）

2026-10 视觉改版。目标是「安静的学习工具 + 精确的时间记录」：冷调中性灰做界面外壳，只有一个低饱和墨蓝强调色，颜色只用于状态（计时中、选中、标签、超期），信息密度靠字号层级和 hairline 结构而不是卡片堆叠。

**Mist Ink 2.0（2026-10-21 层次升级）**：在不引入第二个强调色相、不加渐变/插画的前提下，补两套阶梯——「画布（品牌洗底）→ 面板（白纸 + hairline + 1px 微影）→ 内嵌（下沉底色）→ 浮层」的面层阶梯，以及「主操作实心 → soft 浅底 → 文字」的控件主次。品牌色只出现在可操作、当前、状态三类位置；数据色仍只属于数据。

### 借鉴的开源项目（仅借鉴设计语言与令牌，不引入运行依赖，不复制受 AGPL/GPL 保护的代码）

> 登记规则见 `THIRD_PARTY_NOTICES.md` §2。**直接依赖**会在 Web 构建中包含上游代码，但通过依赖参数/样式覆写配置，不复制源码；**仅数值**表示只读源码提炼设计值、不复制代码（AGPL/GPL 一律仅数值）。

| 项目 | 许可证 | 版本 | 引入方式 | 借鉴内容 | 修改说明 |
| --- | --- | --- | --- | --- | --- |
| [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy)（`appflowy_ui`） | AGPL-3.0 | —（只读） | 仅数值 | 冷调中性色阶、间距/圆角刻度（4/6/8/12/16/20）、14/22 正文、hairline 边框而非卡片投影、浮层才用软阴影 | 未复制任何源码 |
| [Super Productivity](https://github.com/super-productivity/super-productivity) | MIT | —（只读） | 仅数值 | 任务+计时产品密度、状态透明度（hover 6% / pressed 14%）、flat 任务行而非每行卡片、单一主计时器的结构 | 未复制任何源码 |
| [Cal.com / cal.diy](https://github.com/calcom/cal.diy) | MIT | —（只读） | 仅数值 | 日历白色画布 + 灰色 hairline 网格、今日 24px 圆点、选中 2px 内描边、事件块 4px 左侧色条、近黑主按钮 | 未复制任何源码 |
| [shadcn/ui](https://github.com/shadcn-ui/ui) + [Radix Colors](https://www.radix-ui.com/colors) | MIT | —（只读） | 仅数值 | 语义 token 分层（`border` / `input` / `ring` 分离）、单一 radius 基准派生刻度、12 级颜色职责划分 | 未复制任何源码 |
| [shadcn_ui（Flutter）](https://github.com/nank1ro/shadcn-ui) | MIT | —（只读） | 仅数值（结构与 token 组织） | W3 令牌层：ThemeExtension 角色划分与组件子主题的数据类组织方式 | 未复制源码；主题组织按本项目 PlannerTokens 重写 |
| [flex_color_scheme](https://github.com/rydmike/flex_color_scheme) | BSD-3-Clause | —（只读） | 仅数值（子主题组织） | W3 组件子主题：一个组件族一个构造函数、从令牌对象取值的 compact 写法 | 未复制源码；`PlannerComponentThemes` 为本项目重写 |
| [LocalSend](https://github.com/localsend/localsend) / [FlClash](https://github.com/chen08209/FlClash) | Apache-2.0 / GPL-3.0（仅读） | —（只读） | 仅数值 | 桌面端内容宽度与留白纪律、单强调色、显式 light/dark token 映射 | 未复制任何源码 |
| [forui](https://github.com/forus-labs/forui) / [shadcn_ui](https://github.com/nank1ro/shadcn-ui) | MIT | —（只读，W2 可能 vendor） | 仅数值（W2 视需要 vendor） | 组件结构与 token 组织方式（`FSidebar` / `FCalendar` / `FTabs`） | 未复制任何源码；vendor 时按 `packages/ui_vendor/README.md` 登记 |
| [table_calendar](https://pub.dev/packages/table_calendar) | **Apache-2.0**（3.3.0 包内 LICENSE 实测） | 3.3.0 | **直接依赖** | 仅剩日期选择器网格与月份翻页（`calendarBuilders`）；月历网格已改为自绘马赛克，不再使用本包 | 不改源码；只读配置 + 全部样式覆写，见下节 |
| [fl_chart](https://pub.dev/packages/fl_chart) | MIT | 1.2.0 | **直接依赖** | 日/周图表坐标系、柱/线绘制、轴与 Tooltip 基础设施 | 不改源码；坐标轴/网格/图例/配色全部用 `PlannerColors` 令牌覆写 |
| [lucide_icons_flutter](https://pub.dev/packages/lucide_icons_flutter) / [Lucide](https://lucide.dev) | MIT（包）/ ISC（图标） | 4.0.0（Lucide 1.58.0） | **vendor 子集**（`packages/ui_vendor/lucide/`） | 16–18px 线性图标（24px 网格、默认 400 字重） | 只复制默认字体文件 + 39 个实际使用的 `IconData` 常量；不保留 100–600 变体字族（实测会整包打入 Web、~2.9 MB，见 `THIRD_PARTY_NOTICES.md` §5） |

> 暗色 Dense Graphite 的色值来自本项目 research/domain-apps.md §7.3（由 AppFlowy / Linear / Radix 的设计数值整理），未复制任何源码。

### W1 日历 / 图表 / 图标实现约定（2026-10-20）

- **月视图（自绘马赛克，只读，2026-10-21 改造）**：不再使用 `TableCalendarBase`，改为自绘星期头 + 7 列月网格（`calendar_month_chart.dart`）。格内只有日期与课程色块：方块 = 当日容量，色块面积 = 该课程计划分钟，填充高度 = 计划/容量，浅色 = 未排满容量；今天 18px 墨蓝圆、选中 2px 描边、超容量右上角琥珀圆点；每格一个中文全量 `Semantics` 按钮节点（计划/容量/事项计划时长，不含完成度）。宽屏（内容 ≥940）网格右侧 296px 选中日计划栏，窄屏堆到网格下方（含「在日视图中查看」入口）；<620 用缩小的马赛克方块。月汇总只含计划口径：本月计划 / 学习日 / 超容量天数，不再展示实学、状态或热度。保留方向键/PageUp/PageDown/Home 键盘契约与 Tooltip 只读事实。课程色优先取事项第一个有颜色的标签，缺失时按 `tagFallbackColors` 稳定散列。
- **日视图（fl_chart）**：两张图都用 `LineChart`（1.2.0 无横向 BarChart；横线描边宽度=色带厚度，`betweenBarsData` 画计划/实学 ribbon），生长轨道与计划/实学双河道共用同一分钟比例；effort 纹理（加学 `/`、未排程 `\`、历史点阵）由 `IgnorePointer + CustomPaint` 叠加层补足“颜色+纹理”双重编码；计划=墨蓝（`PlannerColors.blue`/blueSoft）、已有事项加学与计划外学习=橙、历史记录=灰；无竖向网格线、无渐变；坐标标签 11px + tabular figures；Tooltip 只显示事实文本，不引入第三方默认配色。事项标签（`calendar-chart-label-*`）保持可聚焦、可点击、带 Tooltip。
- **周视图（fl_chart）**：镜像图 = `BarChart` 以 0 轴为中心，向上画计划、向下画实学并按 effort 堆叠；山脉图 = `LineChart` 以固定堆叠顺序画面积。两图都关闭 fl_chart 内置触摸/动画，由 `_WeekGraphic` 独占 hover/tap；effort 纹理同样用装饰叠加层保留。两者共用同一分钟分母与同一图例顺序；hover 只显示 overlay 文本，不改变选中日期；点击列才打开当日详情。
- **键盘与焦点（W2）**：桌面侧栏 240 ↔ 64px 折叠（折叠后仅图标 + Tooltip，移动端底部导航不折叠）；侧栏方向键上下移动焦点、Home/End 首尾、Enter/Space 进入页面，焦点环统一 `PlannerColors.focusRing`（2px，不改变控件尺寸）；月视图网格方向键切日（±1/±7）、PageUp/Down 切月、Home 回今天；分段控件/标签筛选支持方向键 + Space/Enter 且组内只占一个 Tab 焦点；对话框保持 Material 默认的 Esc 关闭、焦点 trap 与关闭后焦点归还，输入框不被方向键拦截。动画统一尊重 `MediaQuery.disableAnimations`。
- **图标（Lucide vendor 子集）**：页面级图标统一 16–18px、默认 400 字重、颜色走 `PlannerColors.muted/subtle/blue`；图标常量来自 `packages/ui_vendor/lib/lucide.dart`（`fontPackage: planner_ui_vendor`），字体由该包 `pubspec.yaml` 的 `Lucide` 字族提供；release Web 构建自动 tree-shake 到约 14 KB。不改变 `Icon` 外层 `Semantics(label)`、`Tooltip` 与 `find.byIcon` 契约。行内状态图标（今日事项行的闹钟/暂停）在 W1 暂时保留 Material outlines 以维持既有测试契约，**后续工作包（W6 视觉细节）统一图标族时一并替换**（届时同步更新 `learning_relations_ui_test.dart` 的 3 处 `find.byIcon` 断言，保持同等覆盖）。

### 颜色令牌（W3 语义层：`lib/core/theme/tokens.dart` → `PlannerTokens` / `PlannerPalette`）

桌面/移动代码读取 `context.tokens.<语义角色>`；`PlannerColors` 保留为兼容别名（值与语义令牌完全相等，供 const 上下文），由 `test/unit/planner_tokens_test.dart` 断言等值。

| 语义令牌 | 旧别名 | 值 | 用途 |
| --- | --- | --- | --- |
| `canvas` | `background` | `#EEF2F8` | 页面底色（品牌洗底） |
| `surface` | `surface` | `#FFFFFF` | 面板、卡片、对话框 |
| `surfaceMuted` | `surfaceMuted` | `#EEF3F9` | 内嵌区块、进度条底、chip 底 |
| `surfaceInset` | 新增 | `#F1F5FA` | 输入框、图标动作等下沉控件 |
| `sidebar` | `sidebar` | `#E3ECF5` | 左侧导航（比画布深一档） |
| `hover` / `selected` | 同名 | `#EDF2F8` / `#E2EDF8` | 行 hover / 选中 |
| `text` | `text` | `#1C2530` | 主文字（对底色 13.8:1） |
| `muted` | `muted` | `#5A6675` | 次级文字（对白 5.9:1） |
| `subtle` | `subtle` | `#8B96A5` | 三级文字、占位、图标 |
| `border` / `borderStrong` | 同名 | `#E1E8F0` / `#C8D4E2` | hairline / 输入框与分隔 |
| `accent` | `blue` | `#2F5D8A` | 唯一强调色：主操作、选中、计时 |
| `accentHover` / `accentSoft` | `blueHover` / `blueSoft` | `#244A70` / `#E4EFF9` | 强调色 hover / 选中底、光晕 |
| `accentOn` | — | `#FFFFFF` | 强调色上的文字/图标 |
| `success` / `warning` / `danger` | `green` / `orange` / `danger` | `#2E7D66` / `#B7791F` / `#B54747` | 达标 / 加学与超期 / 破坏性操作 |
| `focusRing` / `selection` / `shadow` / `scrim` | 同名（selection 等为新增） | `#592F5D8A` / `#332F5D8A` / `#1A0F172A` / `#660F172A` | 键盘焦点环 / 文本选中 / 浮层阴影 / 模态遮罩 |
| `panelShadow` | 新增 | `#140F172A`（约 8% 墨黑） | 面板 1px 微影，只和 hairline 一起出现 |
| `accentBorder` | 新增 | `#B0CBE4` | 选中标签、soft 控件的描边 |

不使用 `ColorScheme.fromSeed` 推导中性色（会把蓝色种成灰紫）；`ThemeData` 显式覆写 `surface*`、`outline*`，并给 Card/AppBar/Dialog 设置 `surfaceTintColor: Colors.transparent`。标签色使用事项/标签自带颜色，以 12% 底色 + 30% 边框呈现，标签文字向 `text` 混 30% 以保证 11–11.5px 中文的对比度（实测 4.86–7.35:1）。

### 面层与强调阶梯（Mist Ink 2.0，2026-10-21）

同一层次只用一种“分隔语言”，避免现在所有层级都是一条 hairline：

| 层级 | 组成 | 实现 |
| --- | --- | --- |
| L0 画布 | 品牌洗底 `canvas`，两侧内容区不铺白 | `scaffoldBackgroundColor` |
| L1 面板 | 白纸 + hairline + 1px `panelShadow`；桌面窗口层级靠它建立 | `PlannerPanel` / `PlannerSurface` / 今日计时行容器 |
| L2 内嵌 | `surfaceInset` 下沉底：输入框、图标动作、分段轨道 | `InputDecorationTheme.fillColor`、`PlannerIconAction` |
| L3 浮层 | 对话框/菜单/提示条，沿用 `shadow` + `floatingShadow` | DialogTheme / PopupMenuTheme / Tooltip |

强调阶梯：主操作 = `accent` 实心；soft 操作 = `accentSoft` 底 + `accent` 字 + `accentBorder` 边（选中标签、图标动作）；状态胶囊按语义取 `success`/`accent`/`muted`/`warning`（完成/进行中/未开始/超额），进度胶囊不再一律灰色。分区标题左侧加 3×15px 圆角 `accent` 色条，数量 chip 保持 `surfaceMuted` 中性。

暗色沿用同一层级语义：`surfaceInset #14181E`、`panelShadow #4D000000`；暗色下阴影不可见，层次主要由 surface 提亮与边框对比承担，不为暗色重设第二套强调色。

### 层次升级验证（2026-10-21，今日页试点）

- **改动范围**：`PlannerTokens` 新增 `surfaceInset` / `panelShadow`，浅色 `canvas` / `sidebar` / `surfaceMuted` / `hover` / `selected` / `border*` / `accentSoft` / `accentBorder` 换为 Mist Ink 2.0 值；`PlannerPanel` / `PlannerSurface` 加 1px 微影；`SectionHeader` 左缘 3px 色条；`PlannerTag` 改 12% 底 + 30% 边 + 30% ink，进度胶囊按 `taskProgressTone` 取语义色；`PlannerIconAction` 与深色行内紧凑 `IconButton` 走 `surfaceInset` 方块；输入框、`PlannerSegmented` 轨道、日历周图表选择器统一下沉到 `surfaceInset`；桌面目标卡、设置危险卡、登录卡补微影。今日页为试点，其余页面继承共享层并完成上述控件级收口；onboarding/访谈聊天区仍为既有样式。
- **验证（实测）**：`flutter analyze --no-pub` 0 error / 0 warning（仅既有 6 条 info）；`flutter test --no-pub` **786/786 全绿**（当前工作树基线 780 + 新增 `test/unit/theme_hierarchy_test.dart` 6 例）；新增断言覆盖画布/侧栏/面板/内嵌四层可区分、面板微影强度、标签 12% 底 + 70% tone 在浅/深主题下均 ≥4.5:1、进度胶囊四态取色；release Web 构建通过，本地预览逐页浅/深抽查（今日 1366×860 浅/深 + 390×844 手机、日历日/周/月、设置、调整、登录）0 console error、0 page error。
- **截图**：`.dsh-verify/ui-hierarchy/screens/`（`today-desktop-light/dark`、`today-mobile-light`、`calendar-day/week/month-light`、`calendar-day/month-dark`、`settings-light/dark`、`adjust-light`、`login-light/dark`）。设计对比稿与选型记录见 `design/ui-hierarchy/`。
- **未做 / 后续**：onboarding/访谈聊天区的气泡与输入区重绘；soft 按钮档在更多操作位的落地；图表/饼图数据色与新 tint 体系的进一步统一。

### 令牌分层与读取约定（W3，2026-10-20）

```
lib/core/theme/
  tokens.dart            # PlannerPalette（唯一字面色值）+ PlannerTokens ThemeExtension + PlannerSpace/PlannerRadius + context.tokens
  component_themes.dart  # PlannerComponentThemes：一个组件族一个构造函数，从令牌取值（flex_color_scheme 式）
  planner_theme.dart     # plannerTheme() + buildPlannerTextTheme()（字号阶梯）
lib/core/theme.dart      # 兼容层：继续导出 PlannerColors（const 别名）与 plannerHairline/plannerBorderSide/plannerShadow/tabularFigures
```

- **读取顺序**：有 `BuildContext` 且非 const 处读 `context.tokens.<role>`（同一 build 内取一次局部 `tokens` 下传）；const 树、CustomPainter、静态色映射函数保留 `PlannerColors` 别名（值相等，W5 深色主题落地时再按 context 传入）。
- **状态透明度**：`hoverAlpha = 6%`、`pressedAlpha = 14%`（Super Productivity 数值），组件用 `tokens.hoverOn(base)` / `pressedOn(base)` 叠加，不新造不透明灰。
- **圆角/动效**：`radiusCard 12 / radiusDialog 14 / radiusControl 10 / radiusSmall 8 / radiusXs 6 / radiusPill`；`motionFast 120ms / motionBase 180ms / motionSlow 240ms`、`motionCurve = easeOutCubic`（W4 统一消费，当前侧栏折叠已用 motionBase）。
- **子主题**：按钮/输入/卡片/对话框/导航/开关/滚动条等全部由 `PlannerComponentThemes` 从令牌生成，`plannerTheme()` 只负责 ColorScheme + TextTheme + 注册扩展。
- 迁移进度：W3 把页面/组件层非 const 的 `PlannerColors` 引用迁到 `context.tokens`；渲染值完全相等，W3 截图与 W2 基线逐像素对比为 0 差异。

### 动效纪律与 reduced-motion（W4，2026-10-20）

- **统一时长/曲线**：PlannerDurations.fast/base/slow = 120/180/240ms，曲线 easeOutCubic；PlannerTokens.motion* 引用同一组常量，业务代码不再写 Duration(milliseconds: 150/250…) 这类散装时长。
- **只做状态变化动画**：页面进场（PlannerPageTransitionsBuilder，全平台 180ms fade + 6px 上浮）、侧栏折叠（180ms）、分段滑块（120ms）、日历日/周/月切换（120ms 淡入）、滚动定位（240ms）、hover/focus/pressed 状态。
- **不做**：无限/循环动画（onboarding「对方正在输入」改为静态点阵）、装饰性动画、渐变；动画只动 opacity/transform，不动布局属性。
- **reduced-motion**：所有动画经 PlannerMotion.duration/curve（或显式 MediaQuery.disableAnimationsOf）；系统开启减少动态效果时一律 Duration.zero/线性，直接终态、不创建 ticker，pumpAndSettle 不会被装饰动画拖住。
- **计时器隔离**：TaskStudyTimer 只把每秒变化的 elapsed/ratio 放进独立的 _StudyClock（select + RepaintBoundary），父卡不再整包 watch 计时 provider，tick 只重绘数字与圆环；全局计时条同理只重建时钟文本。
- **验收**：test/unit/planner_motion_test.dart 7 例（时长阶梯/曲线、reduce 零时长、PlannerFadeSlide 终态、页面 builder 全平台安装、路由进场与 reduce 立即显示）；全量测试的 pumpAndSettle 无超时。
- **W4 实测（2026-10-20）**：`flutter analyze --no-pub` 0 error/0 warning（仅既有 6 info）；`flutter test --no-pub` **737/737 全绿**（W3 728 + motion 7 + timer 2）；6 页 settle 后截图与 W3 基线**逐像素 0 差异**；浏览器实测路由切换 180ms 淡入中途帧可见、日历模式切换 120ms 中途帧可见，`prefers-reduced-motion: reduce` 下点击后立即截图与 settle 后**0 差异**；release Web 体积 60,829.8 KB（W3 60,822.7，**+7.1 KB**，无新依赖）。

### 暗色主题：Dense Graphite（W5，2026-10-20）

- **定位**：可选暗色，不设为默认；跟随系统或设置页「外观」三段选择（跟随系统 / 浅色 / 深色），选择写入本机 Sembast（app-preferences/theme-mode），不参与账号同步。实现：plannerDarkTheme() + PlannerTokens.dark，MaterialApp 接 darkTheme/themeMode。
- **令牌（Dense Graphite，调研报告 §7.3）**：canvas #0F1115、surface #161A20、surfaceMuted #1C2128、surfaceInset #14181E、sidebar #12161B、hover #232B35、selected #1E2F42、text #E7EAF0、muted #A8B2C0、subtle #808C9B、border #2A2F3A、borderStrong #3C4552、success #6CC7A6、warning #E0AE5A、danger #E68A8A、focusRing 0x997FAAD8、panelShadow 0x4D000000、scrim 0x99000000。
- **强调色决策**：报告 §7.3 的 Graphite accent 是 indigo #6E8BFF；本项目坚持「全产品只有一个墨蓝色相」，暗色 accent 取同色相提亮值 #7FAAD8（对 canvas 7.78:1、对 surface 7.19:1），不引入第二色相。accentOn 反转为 #0B0E12（对 accent 7.96:1），保证按钮文字可读。
- **对比度实测**（WCAG 相对亮度，详见 test/unit/planner_dark_theme_test.dart）：text/canvas 15.68、muted/canvas 8.81、subtle/canvas 5.53、text/surface 14.49、muted/surface 8.14、accent/canvas 7.78、success/canvas 9.32、warning/canvas 9.33、danger/canvas 7.53、accent/selected 5.61；Notice 三色与标签回退色均 ≥4.5:1。
- **组件映射**：所有组件子主题从令牌生成，暗色自动切换；snackbar/tooltip 内容色改用 inverseOn（暗色下反转为深字浅底）；Notice 使用新增 notice* 三元组（底/边/字）；选中标签描边 accentBorder；分段滑块阴影 floatingShadow；dataTone() 在暗色下把标签自带色提亮 45% 再与 surface 混合，保证小字号标签可读。
- **图表/日历/onboarding**：W5 把剩余 PlannerColors 与硬编码浅色全部改为 context.tokens；无 BuildContext 的 painter/静态 helper 通过参数接收 PlannerTokens。浅色取值与 W4 完全相等（浅色截图逐像素 0 差异）。
- **验收**：test/unit/planner_dark_theme_test.dart（令牌/对比度/主题注册）、test/unit/theme_preference_test.dart（恢复/抢先选择/坏存储）、test/widget/theme_switch_test.dart（设置页三段切换）；浅/深 × 五页面 + 登录页截图；grep 硬编码浅色清单见 W5 报告。
- **W5 实测（2026-10-20）**：`flutter analyze --no-pub` 0 error/0 warning（仅既有 6 info）；`flutter test --no-pub` **747/747 全绿**（W4 737 + dark 5 + preference 4 + theme switch 1）；`PlannerColors` 在 `lib/` 直接引用 **0 处**；浅色 5 页截图与 W4 基线逐像素 **0 差异**（设置页因新增「外观」面板而有意变化，见 diff 记录）；`prefers-color-scheme: dark` + 跟随系统实测生效；release Web 60,839.1 KB（W4 60,829.8，**+9.3 KB**，无新依赖）；剩余硬编码仅 tag/热度数据色（经 `dataTone`）与 onboarding 浅色回退分支（`isDark` 守卫）。

### 组件细节统一（W6，2026-10-21）

- **等待/空/错三态**：lib/core/widgets.dart 新增 PlannerSpinner（按钮/行内 15px，2px 描边，accent/border 令牌）与 PlannerLoading（页面级 20px spinner + 12.5px muted 文案 + liveRegion）；PlannerPageState 与路由 bootstrap 统一使用，禁止再出现裸 Material CircularProgressIndicator；空态用 PlannerEmpty、错误/提示用 PlannerNotice（tone 三色已令牌化）。
- **对话框**：DialogThemeData 统一 barrierColor=scrim、insetPadding 24、actionsPadding (20,0,20,16)、radius 14 + hairline；日期选择器改为自绘中文选择器 PlannerDatePicker（见 W7 额外收口），DatePickerThemeData 保留作 Material fallback。
- **菜单**：DropdownButtonFormField 统一下拉底色 surface、圆角 10、图标 muted（旧式 Dropdown 菜单项高度仍由 Material 控制，列入残留清单）。
- **滚动条**：桌面 7px、圆角 4、crossAxisMargin 2，thumb 常规 18% / 拖动 30% muted，hover 不变粗；PlannerScrollBehavior 保持桌面无 Android 辉光。
- **中文排版下限**：正文/说明 >=12.5px（bodySmall 提到 12.5/19），标签/角标/图注 >=11px，禁止 <11px 中文；数字/刻度可 10.5 但必须 tabular；行高统一 1.4–1.6。
- **行密度**：设置行约 52px，事项行约 44–52px，导航项 34px，按钮 32/36px；不通过缩小字号换密度。
- **W6 实测（2026-10-21）**：`flutter analyze --no-pub` 0 error/0 warning（既有 6 info）；`flutter test --no-pub` **754/754 全绿**（W5 747 + component_polish 7）；五处状态截图（loading / tooltip / popup menu / dialog / date picker）在 `.dsh-verify/w6-shots/`，无 console error；裸 `CircularProgressIndicator` 仅剩 `PlannerSpinner` 内部实现与计时环确定值进度（非 spinner）；中文 <11px 在 lib 中清零；release Web 60,840.4 KB（W5 60,839.1，**+1.3 KB**，无新依赖）。
- **已解决（2026-10-21 额外收口）**：Material showDatePicker 已由自绘中文选择器 PlannerDatePicker 替换（中文月份/星期/按钮、浅深令牌、无新依赖、release JS -43.8KB），不再有英文标题残留。
- **Material 默认观感残留清单（W6 收口）**：见下表，除清单外页面不再出现 Material 默认配色/圆角/阴影。

| 残留项 | 原因 | 处理 |
| --- | --- | --- |
| DropdownButton 弹出菜单项高度（48px）、菜单动画 | Flutter 旧 Dropdown 路由内部实现，主题无法配置项高 | 保留；颜色/圆角已令牌化，菜单本身可接受 |
| 自绘日期选择器内部 PageView | table_calendar 内部翻页实现（已禁用翻页动画、只读网格） | 保留；无 Material 文案/配色依赖 |
| InkWell splash/hover 覆盖层动画 | Material 状态层，已通过 hoverAlpha/pressedAlpha 与 focusRing 统一 | 保留 |
| SnackBar 浮动定位/进出场 | Material 组件行为 | 颜色/圆角/文本已令牌化，保留 |

详细残留（W6 实测，仅列不改）：
- DropdownMenuItem 48dp 行高、菜单项内边距、选中高亮与菜单定位动画（planner 4 个 DropdownButtonFormField、settings 2 个）；
- CheckboxListTile（planner 2、capacity 3）行高 ≥48dp 与 InkWell 水波纹，颜色/形状已令牌化；
- FilterChip（planner 1、tasks 1）Material 密度与选中 checkmark 动画，chipTheme 已令牌化；
- PopupMenuButton（tasks 1）菜单项 48dp 行高/内边距/水波纹，popupMenuTheme 已令牌化；
- ListTile（tasks 1、capacity 2）无 ListTileTheme，行高/文本走 Material 默认（颜色来自 TextTheme）；
- DateField（planner 5、capacity 3）Material 日历日格密度与默认确定/取消文案；InputDecoration/DatePickerTheme 已令牌化；
- TextField（planner 4、tasks 5、capacity 4）Material 默认 helper/counter 间距与文本选择工具栏；
- 全局：InkWell 水波纹、Scrollbar 拖拽惯性、文本选择手柄/上下文菜单（组件行为，视觉已尽量令牌化）；
- 已无残留：Divider / AlertDialog shell / Tooltip / TextSelection / ProgressIndicator（含新增 date picker 容器）。

### 性能与回归收口（W7，2026-10-21）

- **RepaintBoundary（13 处）**：PlannerPanel 面板层（core/widgets.dart）、桌面侧栏（shell/app_shell.dart）、日/周图 4 张 fl_chart 画布（calendar_day_chart ×2、calendar_week_chart ×2）、月历只读网格、TaskStudyTimer 时钟与卡片、今日页计划卡/加学卡（dashboard ×2）、事项目录每行（task_directory）。原则：只包静态/低频绘制层，hover overlay、InkWell 命中层、纹理 overlay、Focus/Semantics 全部留在边界外；行/卡粒度，不包整列。
- **无意义重建**：W4 已把 TaskStudyTimer 每秒 tick 收进只 select elapsed/running 的 _StudyClock（+RepaintBoundary）；本轮未新增任何整页/整列 provider watch；周/月切换、暗色切换只重建对应子树。
- **性能基线对比**：冻结 W7 前快照 .dsh-verify/optfix/perf/flutter-w7-before.json 与定时器 flutter-timer-w7-before.json，W7 代码完成后再跑 flutter-w7-after.json / flutter-timer-w7-after.json。对比结果：**全部 20 个场景的结构性计数（requests/localWrites/physicalBackups/bytes/documentBytes/samples）delta = 0**（阈值 ≤5%，实际 0%）；耗时字段是单次观测（同一机器，本次运行整体更快，属环境/缓存波动，不作为收益宣称）。
- **字体懒加载（复验）**：FontManifest.json 只含 MaterialIcons（14.6KB tree-shaken）、PlannerSansSC-UI 子集（1.14MB）、vendor Lucide（14.1KB tree-shaken）；全量 NotoSansSC.ttf 17.77MB 不在 manifest，main.dart.js 仅保留 FontLoader 引用，首帧后后台加载（loadFullPlannerFontInBackground），失败 3 次重试且不阻塞界面。
- **125% / 150% 缩放**：浏览器缩放等价于缩小 CSS 逻辑视口，实测 125% → 1093×720、150% → 911×600（均 ≥900 桌面断点，侧栏保留）；今日/日历/设置三页无横向溢出、无裁切、无 console error，截图 .dsh-verify/w7-shots/scale-125-* / scale-150-*。
- **最终门禁（2026-10-21，含中文日期选择器收口）**：flutter analyze --no-pub 0 error/0 warning（仅既有 6 info）；flutter test --no-pub **756/756 全绿**（+2 中文选择器测试）；dart format 0 changed；release Web 60,796.8 KB（相对 HEAD +0.24%，无新依赖）；AGPL/GPL grep CLEAN；截图目录 W1–W7 见 .dsh-verify/w1-shots/ … w7-shots/。
- **额外收口（2026-10-21）**：新增 lib/core/planner_date_picker.dart，用 TableCalendarBase 自绘中文日期选择器（月份/星期/按钮全中文、浅深令牌、取消/确定、月份翻页、日期范围 clamp），替换 calendar_page 与 planner_dialogs.DateField 的 Material showDatePicker；新增 2 个 widget 测试；release main.dart.js 从 3,917.2 KB 降到 3,873.4 KB（Material date picker 代码被 tree-shake）。
- **遗留**：DropdownMenuItem/CheckboxListTile 等 Material 组件行高沿用默认（W6 残留清单）；.dsh-verify/ 为本地验证产物，未提交。

### 日历「本期完成事项」时间饼图（2026-10-21）

- **位置与口径**：只读日历的日/周/月三个 scope 内容顶部各一张「本期完成事项」环形图；本期 = 当前选中的日 / 含选中日的自然周 / 含选中日的自然月。分片 = 本期有实际学习记录的事项，面积 = 该事项本期的实际用时；中心为本期总实学时长与事项数。数据由同一批 `buildCalendarDayData` 快照经 `buildCalendarCompletionData` 聚合，与页面下方的计划/实学总量同源。
- **自绘与依赖**：不引入新依赖，用 `CustomPainter` 画环形（12 点方向起顺时针、片间 ~1.4° 透明缝、无渐变/阴影/纹理），图例为普通文本行；颜色优先取事项第一个有颜色的标签（`#rrggbb`，暗色经 `tokens.dataTone`），无标签色时按 owner id 稳定散列取 `tokens.tagFallbackColors`。同一标签的多个事项保留同一色相，重复颜色按出现顺序向 surface/text 微提亮 18%–54% 以保证环上可区分。超过 8 个事项时前 7 个 + 一个 `tokens.subtle` 的「其他 N 个事项」，中心仍显示真实事项数。
- **只读与无障碍**：无计时、编辑、完成或拖拽入口，无 hover 改变选中日期的行为；环形图外层一个 `Semantics` 汇总（本期实学 + 事项数），图例文字可读；空态显示「本期还没有学习记录」，不画空环。
- **排版与响应式**：面板复用 `PlannerPanel`（白底 12 圆角 hairline + 1px 微影）；面板内容宽 ≥560 时环形图（168px）与图例左右排列，否则上下堆叠；中文标签 ≥11.5px，数字全部 tabular figures；320px 无横向溢出，浅/深令牌都可用。
- **测试与验证（2026-10-21）**：`flutter analyze --no-pub` 0 error / 0 warning（仅既有 6 条 info）；`flutter test --no-pub` **775/775 全绿**（基线 756 + 新增 19：completion data 8、饼图组件 8、三 scope 集成 3）；Playwright 本地预览 106 项检查全 PASS、0 page error、0 未预期 console error、Flutter 日志 0 条 RenderFlex overflow，日/周/月 × 1366 浅色 + tall + 320 + 暗色 + 空态截图见 `.dsh-verify/period-pie/screens/final/`，结果 `.dsh-verify/period-pie/last-run-final.json`。lib 侧只新增 2 个 Dart 文件（另加 3 个测试文件），无新依赖、无 API/数据库变更；详细测试清单见 `design/calendar/merged-views.md`「验证」。

### 字号阶梯（中文正文不小于 12.5px）

| 角色 | 字号 / 行高 | 字重 |
| --- | --- | --- |
| 页面标题 | 22 / 28 | 600 |
| 区块标题 / 面板标题 | 15 / 22（大标题 18 / 24） | 600 |
| 事项标题、列表主文字 | 13.5–14.5 / 20–22 | 500–600 |
| 正文 | 13–14 / 20–22 | 400 |
| 次级信息 | 12 / 18 | 400 |
| 标签、角标、图注 | 11–11.5 / 15–16 | 500 |
| 计时数字、金额、日期 | 同上字号 + `FontFeature.tabularFigures()` | 600 |

### 间距、圆角、边框、阴影

- 间距基于 8px 网格：4 / 8 / 12 / 16 / 24 / 28 / 32（`PlannerSpace`）。
- 圆角：卡片 12、对话框 14、按钮/输入 10、标签 6–8（`PlannerRadius`）；嵌套控件的圆角 = 外圆角 − 内边距。
- 边框：`plannerHairline(context)` 在 dpr ≥ 2 时取 1/dpr，配合 `strokeAlignInside`，避免高 DPI 下发虚、相邻边框加粗。
- 阴影：L1 面板 = hairline + 1px 微影（`panelShadow`，约 8%，blur 3 / y 1），只建立“纸在画布上”的一层关系；L3 弹出层/浮动条使用一层 `0 4 16 rgba(15,23,42,0.06)`；不使用重投影、不给卡片叠加多层阴影。
- 分隔线：`Divider(height: 1, thickness: 1)`，颜色 `border`；面板内分组用分隔线，不用嵌套卡片。

### 布局

- 桌面（≥ 900px）：左侧固定 240px 导航（品牌、`工作台` 分组、4 个 34px 导航项、底部目标卡），主区内容最大 1200px、左右 28px 留白；导航选中态 = `blueSoft` 底 + 3px 左侧蓝条 + 蓝字。新建事项与管理标签在「全部事项」区块右上角以图标呈现。
- 窄屏：底部 4 项导航，顶部 AppBar 显示页面名，右侧为新建事项（＋）与管理标签两个图标，单列布局；同步状态统一在设置页顶部展示。
- 页面头部：可选小标签 + 22px 标题 + 一行说明 + 右侧操作；区块用 `SectionHeader`（标题 + 数量 + 说明 + 右侧操作）。
- 全局计时条：任何页面顶部 46px，白底 + 底部 hairline，显示关系、事项名、tabular 时钟与暂停按钮。

### 组件约定（`lib/core/widgets.dart`）

`PlannerPanel`（白底/12 圆角/hairline/1px 微影）、`PlannerSurface`（非 PlannerPanel 的白纸面板：列表卡、空态卡等，复用同一微影）、`SectionHeader`（3×15px accent 色条 + 标题 + 中性数量 chip + 右侧操作）、`MetricTile`（21px 600 tabular 数值 + 12px 说明）、`PlannerStat`、`PlannerTag`（11.5px、12% 底色 + 30% 边框 + 文字向 text 混 30%，6 圆角）、`PlannerSegmented`（30px 高、滑动态胶囊、替代 Material `SegmentedButton`）、`PlannerIconAction`（30px 图标按钮，surfaceInset 底 + hairline + hover）、`PlannerEmpty`、`PlannerNotice`、`TimeProgressTrack`（6px 圆角进度）、`PlannerScrollBehavior`（桌面禁用 Android 辉光）。任务时间进度胶囊用 `taskProgressTone` 取语义色：完成 success / 进行中 accent / 未开始与已归档 muted。

### 禁止

- 装饰插画、渐变、高饱和大面积色块、营销口号（低饱和品牌洗底画布与侧栏属于外壳，不算色块）。
- 每个区域都做成重投影卡片；同一面板内再嵌套带阴影的卡片。
- 12px 以下的中文正文；用 `FontWeight.w300` 显示中文。
- 多个强调色竞争；蓝色只用于主操作、选中与计时状态。
- 修改业务语义（计时、容量、事项完成、只读日历等）来换取视觉效果。