# 月历格子改版 · 静态方案图

针对 `apps/flutter_client/lib/features/calendar/presentation/calendar_month_chart.dart`
桌面月视图格子的静态原型。所有图共用一份示意数据（2026-10，今天 21 日、选中 24 日），
避免不同方案之间因为数据不同而无法比较。

## 最新方向：学习马赛克（K / L）

用户选了「2 学习马赛克」：格子里用课程色块拼贴，色块面积 = 计划分钟，格内不出现文字。
两版都保留 G 的右侧计划栏，课程色沿用第 5 节的颜色映射。

- `scheme-k-course-mosaic-capacity.png`：方案 K · 容量方块
- `scheme-l-course-mosaic-fullbleed.png`：方案 L · 满格拼贴

共同规则：

- 每格 = 当天容量方块，浅色余量 = 没排满的容量；色块面积 = 各课程计划分钟；
- 色块按课程取色（高数墨青、线代紫、英语赭、数据结构绿、操作系统玫、概率蓝紫）；
- 今天日期实心蓝圆；选中 2px 墨蓝描边；未来日期变浅；
- 超过容量时格子右上角出现琥珀色圆点，月汇总同步 `N 天超容量`；
- 右侧栏显示选中日的日期、计划总时长、超容量提示、逐项课程色点 + 时长、日视图入口；
- 图注解释课程色 / 未排满容量 / 超容量。

### K · 容量方块

日期在方块上方，方块表示当天容量；色块从底部填充，填充高度 = 计划 / 容量。
信息最清楚：既能看到每天排了多少，也能看到课程构成。

### L · 满格拼贴

色块铺满整个格子，日期浮在左上角的白色小胶囊里，格与格之间留白色间隙。
月份更像一张色块拼贴海报；容量只作为浅色余量存在，读负荷不如 K 直接。

## 上一版：替换日历本体（H / I / J）

用户反馈：G 的布局可以，但月历网格太丑，希望换一个日历样式。下面三个方案都保留 G 的
右侧计划栏，格子里依然没有文字（只有日期 + 图形），计划详情留在右栏。

- `scheme-h-round-day-grid.png`：方案 H · 圆形日格
- `scheme-i-soft-tile-grid.png`：方案 I · 软底卡片
- `scheme-j-big-date-course-bar.png`：方案 J · 大日期 + 课程配比条

共同规则：

- 格内只有日期和图形，没有标题、时长、状态等文字；
- 圆点/条形按课程配色（高数墨青、英语赭、数据结构绿、操作系统玫、线代紫、概率蓝紫），
  颜色是示意，实现时取事项所属标签色；
- 琥珀色空心点 = 当天计划超过容量；月汇总同步显示 `N 天超容量`；
- 今天浅蓝底/浅蓝圆，选中墨蓝实心/描边，未来日期变浅；上下月空格透明；
- 右侧计划栏显示选中日的日期、计划总时长、超容量提示、逐项课程色点 + 时长、日视图入口。

### H · 圆形日格

去掉表格线与格子边框，日期居中在 34px 圆里，圆下是课程色小点。今天浅蓝圆、选中墨蓝实心圆。
最接近主流日历（Google Calendar / shadcn 日历）的观感，最轻。

### I · 软底卡片

每天一个圆角卡片：有安排的日子按计划负荷上 3 级蓝色底纹，超容量转琥珀底；课程色圆点在卡片底部。
比 H 更有分量，适合希望月历本身有「图」感的场景。

### J · 大日期 + 课程配比条

日期放大到 19px，下面一条 4px 的计划条：长度 = 计划占容量，颜色分段 = 课程构成。
超过容量时计划条右侧出现琥珀色空心点。最像「数据可视化」，能看出这个月各课程的投入结构。

## 上一版：纯计划 + 格内不放文字（F / G）

用户反馈：月历要尽可能简洁，**不要在日历格子里放文字**，也不需要展示完成度，只要展示计划。

- `scheme-f-dot-calendar-bottom-agenda.png`：方案 F · 点阵月历 + 底部计划条
- `scheme-g-dot-calendar-side-panel.png`：方案 G · 点阵月历 + 右侧计划栏

### 共同点

- 格子里只有日期和 1–3 个圆点（圆点数量 = 当天事项数，最多 3 个）；
- 圆点是墨蓝色；当天计划超过容量时变琥珀色（汇总里同步显示 `N 天超容量`）；
- 今天仍是实心蓝圆，选中仍是 2px 墨蓝描边，未来日期数字变浅；
- 月汇总只保留计划口径：`本月计划 X · N 个学习日 · M 天超容量`；
- 不出现完成度、实学、状态、热度、容量条，也没有图注。

### 方案 F · 底部计划条

选中日期后在网格下方显示一条计划条：日期 + 计划总时长 + 超容量提示 + 全部事项与各自时长 +
「在日视图中查看 →」。宽屏下 3 条事项可以排成一行，所以面板增高很少；窄屏时自然换行/堆叠。

### 方案 G · 右侧计划栏

桌面宽屏把选中日的计划放到右侧 296px 栏：日期、计划总时长、事项数、超容量提示、逐条事项
与时长、日视图入口。左侧网格仍是纯日期 + 圆点。宽度不足时右侧栏应落到网格下方（等同 F 的
底部计划条布局）。

## 上一版：纯计划（文字仍在格内，保留作参考）

- `scheme-d-plan-only.png`：方案 D · 纯计划（最简）：日期 + 计划时长 + 事项标题
- `scheme-e-plan-capacity-meter.png`：方案 E · 纯计划 + 容量刻度（3px 细条）

## 更早的方案（完成度版，保留作参考）

- `scheme-a-information-layering.png`：信息分层
- `scheme-b-plan-actual-bar.png`：计划–执行对照条
- `scheme-c-selected-day-summary.png`：A + 选中日摘要

## 文件

- `index.html`：全部方案的静态原型（内置示意数据，可直接浏览器打开）
- `tools/render-schemes.mjs`：Playwright 截图脚本
- `screens/`：导出的方案图（2x，面板宽 1040）
  - `scheme-k-course-mosaic-capacity.png`、`scheme-l-course-mosaic-fullbleed.png`：学习马赛克两版（最新）
  - `scheme-h-...`、`scheme-i-...`、`scheme-j-...`：替换日历本体的三种样式
  - `scheme-f-...`、`scheme-g-...`：纯计划版（底部计划条 / 右侧计划栏）
  - `scheme-d-...`、`scheme-e-...`：格内有文字的纯计划版
  - `scheme-a-...`、`scheme-b-...`、`scheme-c-...`：最早的完成度版

重新生成（需要 Playwright 浏览器；受限沙箱下 Chromium 无法启动）：

```powershell
$env:PLAYWRIGHT_BROWSERS_PATH = 'D:\_projects\sjtu-study-planner\.playwright-browsers'
node design\calendar\month-redesign\tools\render-schemes.mjs
```

示意数据覆盖完成 / 部分执行 / 中断 / 计划外 / 待执行 / 未到 / 休息日，但 F / G 只读取计划
字段，确保「纯计划」口径一致。

## 若采纳 K / L，落地范围

- `calendar_month_chart.dart`：桌面格改为「日期 + 马赛克方块」；用 `CustomPainter` 或
  `Stack`/`Positioned` 画色块，填充比 = 计划分钟 / `resolveDayCapacity` 容量；
  1–3 项按面积比例做 treemap（1 项整块、2 项左右分、3 项左一右二）。
- 课程颜色：同 H/I/J，需要把事项所属标签色带进 `CalendarMonthDay`（`PlannerData.tags` →
  任务 `tagIds` → 颜色；无标签用 `PlannerPalette.tagFallbackColors` 兜底）。
- 超容量：`plan > capacity` 时格子右上角琥珀圆点 + 月汇总计数；容量已在数据层可用。
- 空白天保留浅色容量方块（K）或浅色格子（L），不画色块、不加文字。
- 选中日详情沿用 G 右侧栏：日期、计划总时长、超容量提示、逐项课程色点 + 时长、日视图入口。
- 窄屏（<620）：格子放不下马赛克时退化为「日期 + 单条课程色条/圆点」，详情落到网格下方。
- 语义 / tooltip：保持日期 + 计划时长 + 各事项计划时长的只读事实，不展示完成度与实学。
- 测试：更新 `test/widget/calendar_month_view_test.dart` 与
  `test/unit/calendar_month_data_test.dart`；保留 320px 无溢出、键盘与只读断言。

## 若采纳 H / I / J，落地范围

- `calendar_month_chart.dart`：桌面格子改为「日期 + 图形」，按所选方案实现 H 圆形日格 / I 软底卡片 /
  J 日期 + 配比条；删除事项标题与全部文字；`_summary` 改为计划口径；图注移除。
- 继续用现有 `table_calendar` 的 `TableCalendarBase` + 自定义 `dayBuilder` 即可，不需要新增演示依赖；
  如果更想要完全自绘，也可以换成 `GridView`（月视图没有滑动翻页需求）。
- 课程颜色：当前 `CalendarDayItem` 只有 `tagNames`，没有颜色。需要把事项所属标签的颜色带进月数据
  （`PlannerData.tags` 里有颜色；任务 → `tagIds` → 标签色，取第一个有颜色的标签，没有则用
  `PlannerPalette.tagFallbackColors` 的兜底色）。这是本方案唯一的数据层小改动。
- 超容量：`resolveDayCapacity` 的每日容量已经可用；`plan > capacity` 时给空心的琥珀点 / 琥珀底纹。
- 选中日详情（`calendar_page.dart` 的 `_monthScope`）：右侧栏（G 布局），窄于阈值时落到网格下方；
  数据直接复用 `CalendarMonthDay.day.items`；「在日视图中查看 →」切换到 `CalendarMode.day` 并保留选中日期。
- 窄屏（`<620`）：格子只留日期 + 圆点（或更小的点），右侧栏落到下方；不再显示状态标记。
- 语义 / tooltip：月视图只保留计划事实（日期、计划时长、事项与各自计划时长、是否超容量）。
- 测试：更新 `test/widget/calendar_month_view_test.dart` 与
  `test/unit/calendar_month_data_test.dart` 中关于实学/状态/热度/图注的断言；
  保留 320px 无溢出、键盘与只读断言。

## 取舍

- H 最轻、最像标准日历；I 更有「一张图」的观感；J 能看出课程构成，但日期放大后信息密度最低。
- 课程色点最多 3 个：超过 3 项时不再增加点，事项数在右侧栏里可数。
- 若连点/条都觉得多余，可以退到「只有日期」的极简版：月份里只标今天与选中，计划完全靠
  点日期后在外部查看。
- F 更简单、所有宽度都能用；G 在桌面上信息更顺手，但需要一套宽度断点。H / I / J 都沿用 G 的
  右侧栏，所以断点逻辑与 G 相同。
