# packages/ui_vendor — 第三方 UI 代码 vendor 区

本目录是「不白学 · 学习执行台」客户端唯一允许存放**复制/移植的第三方 UI 源码**的位置。
业务代码（`apps/flutter_client/lib/`）中不得直接粘贴第三方源码；需要 vendored 的组件先落到这里，
由 `apps/flutter_client` 通过 path 依赖接入。

## 为什么需要它

`UI_OSS_BORROW_PROMPT.md` §3.4 的决策顺序是：
**直接依赖 → 整目录 vendor → 移植关键文件 → 重写 → 只读数值**。
当上游许可证允许（MIT / ISC / BSD-2/3 / Apache-2.0）但依赖树不干净（例如会拉入
`material_ui` / `cupertino_ui` 形成两套 Material 类型）、或需要按本项目主题深度定制时，
把**最小文件集**复制到这里，而不是继续手写。

## 目录约定

```
packages/ui_vendor/
  README.md                 # 本文件：引入规则、登记流程、自检命令
  pubspec.yaml              # Flutter package：声明 Lucide 字族（W1 vendor 子集）
  lib/planner_ui_vendor.dart
  lucide/                   # W1：Lucide 字体 + 许可证
    lucide.ttf
    LICENSE-MIT.txt
    LICENSE-ISC.txt
  lib/lucide.dart           # W1：39 个 IconData 子集，文件头标注 Adapted from …
  <upstream-name>/          # W2+：每个上游项目一个目录，例如 forui_fsidebar/
    LICENSE                 # 必填：上游 LICENSE 原文
    NOTICE                  # Apache-2.0 上游提供 NOTICE 时必填
    <adapted files>.dart    # 每个文件头保留版权行 + 修改声明
```

**当前内容（W1，2026-10-20）：`lucide/`。**
日历（table_calendar）与图表（fl_chart）通过 pub 依赖引入、不复制源码；图标原本也计划直接依赖
`lucide_icons_flutter 4.0.0`，但该包在 pubspec 里声明了 7 个 Lucide 字族，Flutter 会把未使用的
6 个变体字族（~2.9 MB）整包打进 Web 资产，且无法通过配置排除。因此按 §3.4 改用 vendor：
只复制默认字体 `lucide/lucide.ttf` + 客户端实际使用的 39 个 `IconData` 常量（`lib/lucide.dart`），
保留 `LICENSE-MIT.txt` 与 `LICENSE-ISC.txt`，登记见根目录 `THIRD_PARTY_NOTICES.md` §2.1/§2.3。
W2+ 若移植 forui `FSidebar` / LocalSend 桌面列表行 / shadcn 主题结构，按下列流程继续填充。

## 引入流程（每个 vendored 项目都执行一次）

1. **许可证前置检查**：只允许 MIT / ISC / BSD-2 / BSD-3 / Apache-2.0。
   AGPL-3.0 / GPL-2.0 / GPL-3.0 一律只读，不得复制源码（含注释、常量表、painter 逻辑）。
   仓库根目录没有 LICENSE，默认「保留所有权利」，Web 部署还会触发 AGPL §13，不能冒险。
2. **记录上游坐标**：仓库 URL、许可证、上游版本 tag 或 commit、源文件路径。
3. **复制最小文件集**：只复制用得到的文件，去掉不需要的依赖与示例代码；不得顺手升级上游大版本。
4. **保留版权与许可证**：`<upstream-name>/LICENSE` 必须存在；文件头保留原始版权行；
   每个被修改的文件顶部加：
   `// Adapted from <repo>@<commit> (<path>), <license>.`
   `// Modified by 不白学 for <原因>.`
5. **依赖适配**：把 import 改成本项目路径与 Flutter 3.47 API；禁止引入 `material_ui` / `cupertino_ui`
   类型的第二套 Material；不得引入 build_runner/codegen 链路。
6. **登记**：在根目录 `THIRD_PARTY_NOTICES.md` §2 表格新增一行（项目/URL/许可证/版本/引入路径/修改概要/日期），
   并同步 `DESIGN.md` 的「借鉴与版权」表。
7. **验证**：`cd apps/flutter_client && flutter analyze --no-pub` 0 error，相关 widget 测试通过；
   vendored 代码同样要格式化（`dart format`）并保持中文正文 ≥12.5px、tabular 数字等设计约束。
8. **自检**：
   ```powershell
   git grep -n -i "AGPL-3.0\|GNU AFFERO\|GNU GENERAL PUBLIC LICENSE" -- apps/flutter_client/lib packages/
   ```
   输出必须为空（只读设计参考不计入源码）。

## 禁止

- 把 vendored 代码与业务代码混在同一文件；删除上游版权声明；
- 把 AGPL/GPL 项目的源码「改写变量名后」视为自研；
- 在未登记 `THIRD_PARTY_NOTICES.md` 的情况下先提交代码。