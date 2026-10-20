# 不白学设计规范

按用户明确的视觉约束直接实现。模式：Operate。

「今日」页合并学习执行与事项管理：单页单滚动，上半部分「今日学习」按事项展示当天计划事项的计时卡（开始/暂停/继续计时为主操作），计划外事项的加学与复习从下半部分事项行的闹钟发起，计时中的事项显示在「今日加学」；下半部分「全部事项」为扁平事项目录，事项可有零个或多个标签，支持按所选标签的任一匹配筛选；可在目录内创建、编辑、重命名、改色和删除标签。桌面左侧导航 4 个栏目（今日、日历、调整、设置），其中「日历」合并了日/周/月只读视图与进度概览，主区内容宽度上限 1200px；手机底部导航、单列布局。

账号相关功能统一放在设置页：当前登录身份、退出登录与账号注销；今日、日历、调整等页面和全局框架不提供账号头像、账号对话框或其它账号入口。

使用本地中文系统字体保证离线和移动显示，数字采用 tabular-nums。

一层面板仅分割不同功能区域。按钮、状态、错误、键盘焦点统一；不使用装饰插画、渐变、营销文案。

计时采用紧凑事项行：事项标题独立展示，标签仅作补充分类，不能改变排程容量。开始、暂停和继续计时为主操作，调整日期、展开详情和撤销计时使用带提示的图标。暂停后显示最近一段用时；撤销前确认起止时间与扣除时长。实际用时由计时器累计，不提供手动修改入口或今日完成勾选；达到今日目标后自动计入达标事项，超出目标仍继续保留实际用时。

事项目录只显示事项名称，不显示时间投入、预计时长、进度条或圆环、起止/截止日期、优先级或状态，也不设当前/后续/已完成页签；加学计时从行内闹钟开始（未计时 ⏰、计时中 ⏸、暂停后回到 ⏰），记录为「加学」关系，已完成事项为复习计时，已归档事项不提供计时入口；不提供拖拽排程、标记完成等执行操作。今日页不再显示用时饼图、净容量统计、全局「开始计时」按钮，也不再提供临时学习功能。

## 视觉语言：雾蓝墨水（Mist Ink）

2026-10 视觉改版。目标是「安静的学习工具 + 精确的时间记录」：冷调中性灰做界面外壳，只有一个低饱和墨蓝强调色，颜色只用于状态（计时中、选中、标签、超期），信息密度靠字号层级和 hairline 结构而不是卡片堆叠。

### 借鉴的开源项目（仅借鉴设计语言与令牌，不引入运行依赖，不复制受 AGPL/GPL 保护的代码）

| 项目 | 许可证 | 借鉴内容 |
| --- | --- | --- |
| [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy)（`appflowy_ui`） | AGPL-3.0 | 冷调中性色阶、间距/圆角刻度（4/6/8/12/16/20）、14/22 正文、hairline 边框而非卡片投影、浮层才用软阴影 |
| [Super Productivity](https://github.com/super-productivity/super-productivity) | MIT | 任务+计时产品密度、状态透明度（hover 6% / pressed 14%）、flat 任务行而非每行卡片、单一主计时器的结构 |
| [Cal.com / cal.diy](https://github.com/calcom/cal.diy) | MIT | 日历白色画布 + 灰色 hairline 网格、今日 24px 圆点、选中 2px 内描边、事件块 4px 左侧色条、近黑主按钮 |
| [shadcn/ui](https://github.com/shadcn-ui/ui) + [Radix Colors](https://www.radix-ui.com/colors) | MIT | 语义 token 分层（`border` / `input` / `ring` 分离）、单一 radius 基准派生刻度、12 级颜色职责划分 |
| [LocalSend](https://github.com/localsend/localsend) / [FlClash](https://github.com/chen08209/FlClash) | Apache-2.0 / GPL-3.0（仅读） | 桌面端内容宽度与留白纪律、单强调色、显式 light/dark token 映射 |
| [forui](https://github.com/forus-labs/forui) / [shadcn_ui](https://github.com/nank1ro/shadcn-ui) | MIT | 仅借鉴组件结构与 token 组织方式（`FSidebar` / `FCalendar` / `FTabs`），不引入依赖 |

### 颜色令牌（`apps/flutter_client/lib/core/theme.dart` → `PlannerColors`）

| 令牌 | 值 | 用途 |
| --- | --- | --- |
| `background` | `#F6F7F9` | 页面底色 |
| `surface` | `#FFFFFF` | 面板、卡片、对话框 |
| `surfaceMuted` | `#F0F3F7` | 内嵌区块、进度条底、hover 底 |
| `sidebar` | `#F3F5F8` | 左侧导航 |
| `hover` / `selected` | `#F1F3F6` / `#E9F1F8` | 行 hover / 选中 |
| `text` | `#1C2530` | 主文字（对底色 14.4:1） |
| `muted` | `#5A6675` | 次级文字（对白 5.9:1） |
| `subtle` | `#8B96A5` | 三级文字、占位、图标 |
| `border` | `#E4E8EE` | 1px hairline |
| `borderStrong` | `#CDD5DF` | 输入框、需强调的分隔线 |
| `blue` | `#2F5D8A` | 唯一强调色：主操作、选中、计时 |
| `blueSoft` | `#E9F1F8` | 选中底、计时光晕 |
| `green` / `orange` / `danger` | `#2E7D66` / `#B7791F` / `#B54747` | 完成达标 / 加学与超期提示 / 仅删除等破坏性操作 |

不使用 `ColorScheme.fromSeed` 推导中性色（会把蓝色种成灰紫）；`ThemeData` 显式覆写 `surface*`、`outline*`，并给 Card/AppBar/Dialog 设置 `surfaceTintColor: Colors.transparent`。标签色使用事项/标签自带颜色，但降低饱和度并以 8% 底色 + 22% 边框呈现。

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
- 阴影：卡片一律无阴影；只有弹出层/浮动条使用一层 `0 4 16 rgba(15,23,42,0.06)`。
- 分隔线：`Divider(height: 1, thickness: 1)`，颜色 `border`；面板内分组用分隔线，不用嵌套卡片。

### 布局

- 桌面（≥ 900px）：左侧固定 240px 导航（品牌、`工作台` 分组、4 个 34px 导航项、底部目标卡与同步状态），主区内容最大 1200px、左右 28px 留白；导航选中态 = `blueSoft` 底 + 3px 左侧蓝条 + 蓝字。
- 窄屏：底部 4 项导航，顶部 AppBar 只保留页面名与同步状态，单列布局。
- 页面头部：可选小标签 + 22px 标题 + 一行说明 + 右侧操作；区块用 `SectionHeader`（标题 + 数量 + 说明 + 右侧操作）。
- 全局计时条：任何页面顶部 46px，白底 + 底部 hairline，显示关系、事项名、tabular 时钟与暂停按钮。

### 组件约定（`lib/core/widgets.dart`）

`PlannerPanel`（白底/12 圆角/hairline/无阴影）、`SectionHeader`、`MetricTile`（21px 600 tabular 数值 + 12px 说明）、`PlannerStat`、`PlannerTag`（11.5px、8% 底色、6 圆角）、`PlannerSegmented`（30px 高、滑动态胶囊、替代 Material `SegmentedButton`）、`PlannerIconAction`（30px 图标按钮 + hover）、`PlannerEmpty`、`PlannerNotice`、`TimeProgressTrack`（6px 圆角进度）、`PlannerScrollBehavior`（桌面禁用 Android 辉光）。

### 禁止

- 装饰插画、渐变、大面积色块、营销口号。
- 每个区域都做成重投影卡片；卡片与阴影同时使用。
- 12px 以下的中文正文；用 `FontWeight.w300` 显示中文。
- 多个强调色竞争；蓝色只用于主操作、选中与计时状态。
- 修改业务语义（计时、容量、事项完成、只读日历等）来换取视觉效果。
