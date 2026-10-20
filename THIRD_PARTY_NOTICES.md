# 第三方代码与素材说明（THIRD PARTY NOTICES）

本文件记录「不白学 · 学习执行台」仓库中**实际包含或转写**的第三方代码、素材及其许可证。
新增任何第三方代码/素材前，必须先在本文件登记，并把对应的 LICENSE/NOTICE 文本放入被引入目录。

## 1. 当前包含的第三方素材

| 名称 | 许可证 | 位置 | 用途 | 修改说明 |
| --- | --- | --- | --- | --- |
| Noto Sans SC（字体） | SIL Open Font License 1.1 | `apps/flutter_client/assets/fonts/NotoSansSC.ttf`、`assets/fonts/PlannerSansSC-UI.ttf`、`assets/fonts/OFL.txt` | 客户端中文字体；子集用于首屏，全量文件运行时懒加载 | 使用 pyftsubset 生成 UI 子集，未修改字形 |

> Flutter SDK、Dart SDK 以及 `pubspec.lock` 中的 pub.dev 依赖按其各自许可证分发，不在本文件中逐条登记；新增**会被 vendor/转写进源码**的第三方代码时按下表登记。

## 2. 代码借鉴登记（转写 / vendor 时填写）

规则：
- MIT / ISC / BSD / Apache-2.0：允许整文件或整模块转写、vendor；必须保留版权声明与许可证文本；Apache-2.0 需保留 NOTICE 并声明修改。
- AGPL-3.0 / GPL-2.0 / GPL-3.0：**禁止复制源码**，只能阅读后提炼设计数值，不登记为代码来源。
- 每条记录至少包含：项目、URL、许可证、上游版本或 commit、引入路径、修改概要、引入日期。

| 项目 | URL | 许可证 | 上游版本/commit | 引入路径 | 修改概要 | 引入日期 |
| --- | --- | --- | --- | --- | --- | --- |
| （示例，待 W0/W1 实际引入后填写）table_calendar | https://pub.dev/packages/table_calendar | MIT | 3.3.0 | 作为依赖使用（不复制源码） | 无 | 待定 |

## 3. 仅作设计参考、不含代码的项目（不登记为代码来源）

以下项目的**设计数值/行为**被提炼到 `DESIGN.md`，但未复制任何源代码：

- AppFlowy / appflowy_ui（AGPL-3.0）：中性色阶、间距/圆角刻度、字号字重、阴影层级数值。
- Super Productivity（MIT）：状态透明度、行处理方式、计时器结构（如需转写代码须按上表登记）。
- Cal.com / cal.diy（MIT，以仓库当前 LICENSE 为准）：日历 token 与几何数值。
- shadcn/ui、Radix Colors（MIT）：语义 token 命名与颜色职责划分。
- forui、shadcn_ui（MIT）：组件结构与交互模式（如需 vendor 须按上表登记）。

## 4. 自检命令

```powershell
# 常规源目录不应出现 AGPL/GPL 代码片段
git grep -n -i "GNU AFFERO\|AGPL-3.0\|GNU GENERAL PUBLIC LICENSE" -- apps/flutter_client/lib packages/

# 列出 vendor 目录及其许可证文件
Get-ChildItem packages/ui_vendor -Recurse -File -Include LICENSE,NOTICE,COPYING -ErrorAction SilentlyContinue
```
