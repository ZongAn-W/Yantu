# 月历 · 学习马赛克（K 方案）实现说明

2026-10-21 落地：月视图从「计划/容量/实学/状态」文字格改为**纯计划马赛克**。
格子里只有日期和课程色块，所有文字移到右侧计划栏（窄屏时在网格下方）。

## 视觉与信息

- 每天一个容量方块：色块从底部向上填充，填充高度 = `计划分钟 / 当日容量`；
- 色块面积 = 各事项计划分钟占比，颜色取事项第一个有颜色的标签（无标签按 `tagFallbackColors` 稳定散列）；
- 1 项铺满填充区、2 项左右分、3 项 L 形、4 项两列；超过 4 项时尾部分钟折叠进第 4 块，
  内容以 tooltip / 右侧栏为准；
- 今天日期实心墨蓝圆；选中日 2px 墨蓝描边；未来日期变浅；
- 超过容量：格子右上角琥珀圆点 + 月汇总 `N 天超容量`；
- 月汇总：`本月计划 X · N 个学习日 · M 天超容量`；
- 图注：课程色、未排满容量、超容量；月历面板本身不再展示实学/完成度/中断/热度。
- 页面顶部的「本期完成事项」饼图是并行改动中的既有功能，本次没有改动它；
  如果月视图里也要隐藏它，只需从 `_monthScope` 去掉那个 `CalendarCompletionPie`。

## 布局

- 面板内容宽 ≥ 940：网格 + 右侧 296px 计划栏（左细线分隔）；
- 面板内容宽 < 940：计划栏堆到网格下方（上细线分隔）；
- 内容宽 < 620：格子退化为「日期 + 3px 课程色条」，计划栏仍堆在下方；
  `320px` 下无横向溢出（widget test 覆盖）。

右侧计划栏内容：日期 + 星期、`计划 X · N 项`、超容量胶囊、逐项课程色点 + 标题 + 计划时长、
「在日视图中查看 →」（切到日视图并保留选中日期）；计划栏高度受限时事项列表可滚动。

## 代码

- `lib/features/calendar/domain/calendar_month_mosaic.dart`
  - `layoutMosaicBlocks`：1–4 项的精确面积布局（超过 4 项折叠尾部）；
  - `mosaicFillRatio`、`mosaicOverCapacity`；
  - 单元测试 `test/unit/calendar_month_mosaic_test.dart`（8 条）。
- `lib/features/calendar/presentation/calendar_month_chart.dart`
  - 重写月视图：自绘星期头 + 7 列月网格（不再依赖 `TableCalendarBase`），
    保留方向键/PageUp/PageDown/Home/Enter 键盘行为与焦点环；
  - 每个日格是一个 `Semantics` 按钮，tooltip/读屏只包含计划事实；
  - `RepaintBoundary` 包住网格。
- `lib/features/calendar/presentation/calendar_month_day_panel.dart`
  - 选中日计划栏（只读、可滚动、带日视图入口）。
- `lib/features/calendar/presentation/calendar_month_colors.dart`
  - 标签色 → 马赛克色（暗色经 `dataTone` 提亮；无标签时稳定散列兜底）。
- `lib/features/calendar/presentation/calendar_page.dart`
  - 月视图传入 `onOpenDayView`。

## 测试与验证

- `flutter analyze --no-pub`：0 error / 0 warning（仅既有 6 条 info）；
- `flutter test --no-pub`：**780 passed / 0 failed**（含新增 8 条马赛克布局测试；
  月视图 widget test 更新为纯计划汇总、右侧计划栏、日视图入口与 320px 无溢出）；
- 键盘、只读、饼图（并行开发中）、周/日视图测试均通过；
- Playwright 本地预览：1366×1400 桌面与 320×900 移动端各截图，
  月汇总/图注/右侧计划栏存在，320px `scrollWidth = 320`，0 console error；
  预览目录 `.dsh-verify/month-mosaic/`（本地验证产物，未提交）。

## 与并行开发的关系

写入时工作区还有另一组未提交的「任务完成时间 / 本期完成事项饼图」改动
（`calendar_day_data.dart` 的 `tagColor`、`calendar_page.dart` 顶部饼图等）。
本实现复用了其中的 `tagColor`，没有修改饼图相关文件；合并时只需保留双方改动。
`design/calendar/merged-views.md` 的月视图旧描述（实学/热度/状态）需要由合并方同步更新。
