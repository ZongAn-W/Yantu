# AI 一键调整后续计划 · 实现契约（v1）

> 状态：2026-10-18 实现中。本文是服务端、Flutter 客户端和验收测试的共同契约；实现以本文的字段名为准，不得各自改名。

## 1. 产品决策

1. **移除今日页「智能重排」入口**：不再提供该操作；`generateReplanPreview` 等纯领域代码与 `replan_runs` 历史数据保留（跨端 golden 契约与旧数据兼容需要），但客户端不再暴露入口。
2. **「一键调整后续计划」改为 AI 驱动**：点击后调用服务端 AI，基于 **人物画像、学习进度、近期学习时间（近 7/14 天实际执行）** 与当前计划，输出一次调整方案；先预览、用户确认后由服务端原子写入。
3. **不再用本地确定性算法自动调整计划**：调整页不再调用 `reschedulePlan`；设置页保存容量/周期、容量编辑器保存容量时也不再自动重排，只保存设置，并提示用户到调整页使用 AI 一键调整。
4. **AI 的调整杠杆**（v1）：
   - 规划周期结束日期（总时长可变；开始日期不变）；
   - 学习强度：一周七天可用分钟模板（总容量可变）；
   - 事项总工作量（只改 `estimated_minutes`，不低于已完成分钟）与**新增事项**（用于补齐目标所需学习量，例如 408 真题、政治强化等）；
   - 不得删除/归档既有事项，不得修改真实截止日期（`deadline_kind=deadline`），不得改动固定事项。
5. **目标导向与合理性审查**是硬性要求：AI 必须先估算「达成该目标所需总学习时长区间」，与当前计划总时长、剩余时间、近期执行强度对比，得出 `reasonable | too_light | too_heavy` 结论，并在方案里真正修正（例如交大计算机考研只排了 400 小时 → 判定 `too_light`，增加工作量/周期/强度）。预览必须向用户展示所需时长、当前时长、调整后时长和结论。
6. **失败时不得静默回退到本地算法**：AI 未配置、超时、返回非法方案时直接报错并保留原计划。
7. **保护记录**（与现有本地重排一致）：历史日期（今天之前）、固定块/固定事项、已完成块、`actual_minutes>0`、被学习日志引用的块（按 block_id 或 task_id+date）、已完成/归档事项，全部保持不动；排不下的剩余量必须显式返回，不得静默丢弃。
8. 确认后服务端 `commitPlannerState` 原子提交并推进 revision，客户端拉取新计划；本机存在未同步修改（pending）时禁止发起调整。

## 2. HTTP 接口

所有接口要求登录（`requireUser`）。AI 接口客户端超时 240s（`ApiClient` 已对 `/api/ai/` 放大到 240s）。

### 2.1 创建调整预览

`POST /api/ai/plan-adjustments`

请求：

```json
{ "expectedRevision": 12, "requestId": "uuid-可选，幂等键" }
```

- `expectedRevision`：客户端已知的云端 revision。服务端读取当前计划后若 revision 不一致 → `409 { "error": "云端计划已更新，请先同步后再调整" }`。
- `requestId`：可选；同一用户同一 requestId 的已生成预览直接复用，避免重复扣 AI。

响应 `200`：

```json
{ "id": "job-uuid", "preview": { ...见 §3... } }
```

失败：AI 未配置/生成失败 `502 { "error": "..." }`；方案不合法 `422 { "error": "AI 调整方案不合法，请重试" }`（具体原因写服务端日志）；没有计划 `409/404`。

服务端流程：
1. 读取 `readPlannerState` 得到 `{data, revision}`；
2. 校验 revision；无计划报错；
3. 组装 AI 上下文（§4），调用 `requestStructuredAI`（label `plan-adjust`，`reasoningEffort` 用 planning 档，超时 210s）；
4. 用 §5 的规则把 AI 输出应用到当前文档，生成新文档 + 预览；
5. 将 `{baseRevision, document, preview}` 写入 `ai_jobs`：`kind='plan_adjustment'`、`status='previewed'`、`request_id`、`input_payload={expectedRevision}`、`output_payload={document,preview,ai}`；返回 `{id, preview}`。

### 2.2 读取预览（可选、供超时重试用）

`GET /api/ai/plan-adjustments/:id` → `{ id, preview }`（只允许本人，`kind='plan_adjustment'`）。

### 2.3 确认调整

`POST /api/ai/plan-adjustments/:id/confirm`

请求：

```json
{ "expectedRevision": 12 }
```

响应 `200`：

```json
{ "confirmed": true, "revision": 13 }
```

规则：任务必须属于本人；`status` 必须为 `previewed`（重复确认 → 409「这次调整已经确认」）；当前云端 revision 必须等于 job 的 `baseRevision` 且等于请求 `expectedRevision`（否则 409「计划已更新，请重新预览」）；重新校验存储的文档后 `commitPlannerState`，插入 `plan_versions(kind='adjust', payload={summary, previous_revision, previous_document, preview})`，更新 job `status='confirmed'`。

### 2.4 其他

- 路由限流：`{ config: { rateLimit: { max: 5, timeWindow: "1 minute" } } }`。
- 需要新增迁移：`apps/api/db/migrations/202610210001_plan_adjustments.sql`，内容 `create table if not exists ai_jobs (...)`（与 `db/schema.sql` 中定义一致）+ `create index if not exists ai_jobs_user_kind on ai_jobs(user_id, kind, created_at desc)`。

## 3. 预览 JSON（客户端解析的字段，必须完全一致）

```json
{
  "id": "job-uuid",
  "base_revision": 12,
  "assessment": "AI 的中文审查结论，说明为什么这样调整",
  "verdict": "reasonable | too_light | too_heavy",
  "hours": {
    "current_minutes": 24000,
    "next_minutes": 108000,
    "remaining_minutes": 96000,
    "required_min_minutes": 90000,
    "required_max_minutes": 150000
  },
  "cycle": {
    "start_date": "2026-10-18",
    "previous_end_date": "2026-11-14",
    "end_date": "2027-09-30",
    "previous_days": 28,
    "days": 348,
    "remaining_days": 348
  },
  "intensity": {
    "previous_weekly_minutes": 840,
    "weekly_minutes": 1800,
    "reason": "近期实际每周约 11 小时，目标需要提高投入"
  },
  "workload": {
    "updated_tasks": [
      { "task_id": "t1", "title": "高数基础一轮", "subject": "数学", "previous_minutes": 12000, "minutes": 18000, "reason": "..." }
    ],
    "new_tasks": [
      { "title": "408 真题 15 套", "subject": "408", "minutes": 9000, "deadline_kind": "plan_end", "deadline": "2027-09-30", "reason": "..." }
    ],
    "subjects": [
      { "subject_id": "s1", "name": "数学", "previous_minutes": 12000, "minutes": 18000 }
    ]
  },
  "schedule": {
    "protected_blocks": 12,
    "released_blocks": 40,
    "released_minutes": 4800,
    "added_blocks": 60,
    "added_minutes": 7200,
    "unscheduled_minutes": 0
  },
  "deadline_risks": [
    { "task_id": "t2", "title": "英语真题", "deadline": "2027-12-20", "unscheduled_minutes": 600 }
  ],
  "warnings": ["调整后总时长仍低于目标所需下限"],
  "notes": ["规划周期延长到目标日期前一天；真实截止日期未改动"]
}
```

字段规则：
- `hours.current_minutes` / `next_minutes`：调整前/后全部未归档事项 `estimated_minutes` 之和；`remaining_minutes`：调整后剩余（`estimated-completed` 之和，非负）。
- `cycle.*_days` 为含首尾天数；`remaining_days` 为今天到新结束日（含）天数。
- `intensity.previous_weekly_minutes` / `weekly_minutes` 用 `adoptedWeeklyCapacity` 的口径（baseline > range_min > 七天模板合计；legacy_default 时为 null，前端显示“未设置”）。
- `workload.subjects` 覆盖调整前后所有有变化的课程（按课程汇总总工作量，含新增事项）。
- 所有分钟均为整数；无变化时数组为空。

## 4. 服务端 AI 上下文（`buildAdjustmentContext`）

给模型的 user JSON（**不得包含全量 blocks**，只给摘要）：

```json
{
  "today": "2026-10-18",
  "goal": { "type": "exam", "text": "...", "subtype": "考研", "target_school": "上海交通大学",
            "target_program": "计算机技术", "target_date": "2027-12-25", "foundation": "...", "constraints": "..." },
  "plan_cycle": { "start": "2026-10-01", "end": "2026-11-14", "remaining_days": 28 },
  "capacity": { "basis": "net", "weekly_minutes_template": {"0":120,...}, "weekly_baseline_minutes": 840,
                "weekly_range": null, "adopted_weekly_minutes": 840, "date_override_count": 2, "week_override_count": 1 },
  "totals": { "planned_minutes": 24000, "completed_minutes": 1200, "remaining_minutes": 22800,
              "subject_totals": [{"subject":"数学","planned_minutes":12000,"completed_minutes":600,"remaining_minutes":11400}] },
  "tasks": [
    { "task_id": "t1", "subject": "数学", "title": "高数基础一轮", "estimated_minutes": 12000,
      "completed_minutes": 600, "remaining_minutes": 11400, "deadline": "2027-10-01", "deadline_kind": "deadline",
      "earliest_date": "2026-10-01", "priority": 3, "is_fixed": false,
      "activity": {"kind":"finite|recurring","starts_on":"...","ends_on":"...","sessions_per_week":2,"session_minutes":60,"state":"active"},
      "workload_components": [{"label":"章节","quantity":10,"minutes_per_unit":90}],
      "content_progress": {"completed_units":2,"confirmed":false},
      "feedback": {"content_units":10,"content_completed":false,"difficulty":"manageable"} }
  ],
  "recent_execution": {
    "days": [{"date":"2026-10-17","planned_minutes":120,"actual_minutes":90,"scheduled_minutes":90,"extra_minutes":0,"ad_hoc_minutes":0}],
    "last7_actual_minutes": 540, "last7_planned_minutes": 840,
    "last14_actual_minutes": 1200, "last14_planned_minutes": 1680,
    "per_subject_last14": [{"subject":"数学","actual_minutes":700,"planned_minutes":840}]
  },
  "future_load": { "next14_days": [{"date":"...","planned_minutes":120}], "scheduled_remaining_minutes": 18000 },
  "rules": {
    "verdict": "依据目标估算所需总学习时长；当前计划明显低于下限判 too_light，明显高于上限判 too_heavy，否则 reasonable",
    "goal_examples": "考研交大计算机：数学+408+英语+政治+真题复盘通常需要约 1500–3000 小时（视基础和脱产程度）；400 小时属于明显不合理",
    "intensity": "新的每周分钟模板必须可排程（每日 0–1440，考虑近期实际执行，避免一次提高超过 2 倍）；周期结束日不得晚于 target_date（若有），且不得早于今天",
    "real_hours": "required_minutes/required_max_minutes 必须为整数分钟，表示达成目标的现实总学习时长区间"
  }
}
```

## 5. AI 输出 schema（`PlanAdjustmentSchema`，服务端解析后应用）

```ts
z.object({
  assessment: z.string().min(1).max(4000),
  verdict: z.enum(["reasonable", "too_light", "too_heavy"]),
  required_minutes: z.object({ min: int(0..1_000_000), max: int(0..1_000_000) }),
  cycle: z.object({ end_date: date, reason: z.string().max(2000) }),
  intensity: z.object({
    weekly_minutes: z.record(z.enum(["0","1","2","3","4","5","6"]), z.number().int().min(0).max(1440)),
    reason: z.string().max(2000),
  }).nullable().optional(),
  task_updates: z.array(z.object({
    task_id: z.string().min(1).max(80),
    estimated_minutes: z.number().int().min(30).max(1_000_000),
    reason: z.string().max(1000),
  })).max(1000).default([]),
  new_subjects: z.array(z.object({
    key: z.string().min(1).max(80),
    name: z.string().min(1).max(100),
    priority: z.number().int().min(1).max(3),
  })).max(20).default([]),
  new_tasks: z.array(z.object({
    key: z.string().min(1).max(80),
    subject: z.string().min(1).max(100),        // 已存在 subject id，或 new_subjects 的 key
    title: z.string().min(1).max(200),
    description: z.string().max(4000).default(""),
    estimated_minutes: z.number().int().min(30).max(200_000),
    earliest_date: date.optional(),
    deadline_kind: z.enum(["deadline", "plan_end"]),
    deadline: date.optional(),
    priority: z.number().int().min(1).max(3),
    reason: z.string().max(1000),
  })).max(200).default([]),
  warnings: z.array(z.string().max(1000)).max(20).default([]),
})
```

应用规则（服务端，纯函数 `applyAdjustment(document, ai, today)`）：
1. **周期**：`end_date` 必须为合法日期、≥ today、且 ≤ target_date（若 target_date 存在且 ≥ today）；超过 `today+1095` 截断。写入 `profile.plan_end_date`；`plan_start_date` 不变。`plan_end` 类事项的 deadline 改为新 end（若新 end 早于该事项 earliest_date，则保留原 deadline 并 warning）。
2. **强度**：若 `intensity` 存在：写入 `profile.weekly_minutes`（7 键）；显式把 `weekly_baseline_minutes`、`weekly_range_min_minutes`、`weekly_range_max_minutes` 置为 `null`；`daily_limit_minutes = clamp(max(weekly values), 30, 1440)`；保留周/日期覆盖不动，并在预览 `notes` 提醒覆盖仍生效。若不存在：容量不变。
3. **事项**：`task_updates` 只能命中未归档既有事项；固定/已完成事项忽略并 warning；`estimated_minutes = max(ai 值, completed_minutes)`（被 clamp 时 warning）；更新 `updated_at`。真实截止日期、earliest_date、status、subject 一律不动。
4. **新增事项**：`subject` 先按既有 subject id 匹配，再按 `new_subjects.key` 匹配（同时创建 subject，颜色用固定调色板循环）；`deadline_kind=plan_end` → deadline=新 end；`deadline_kind=deadline` → 必须有 `deadline` 且 ≥ today；新 task 生成 UUID，`status="not_started"`、`completed_minutes=0`、`is_fixed=false`、时间戳 now。
5. **planning**：保留现有 route/milestones/assumptions；`mode="full"`、`rolling=false`、`detail_days=新周期天数`、`detailed_until=新 end`、`forecast=null`、`needs_review=false`、`quality=null`、`capacity` 用容量摘要（`summarizePlanCapacity` 同口径），`risks` 追加 AI warnings，`assumptions` 追加 AI 周期/强度 reason，`uncovered` 不清空。
6. **释放 + 重排**：
   - 释放所有 `date >= today` 且不属于保护集合的 block；保护集合 = 历史日期、`is_fixed`、`status=completed`、`actual_minutes>0`、被日志引用的 block（block_id 命中，或无 block_id 但 task_id+date 命中）、所属事项固定/已完成/归档。
   - 以 `scheduleStrategy(document, today, new_end, runtime)` 重新生成；runtime 用 `crypto.randomUUID()` 与 `new Date()`。
   - 校验 `checkScheduledPlan(document, today, new_end, protectedIds)`，error 级问题写入 warnings（正常不应出现）。
7. **预览统计**：按 §3 组装；`deadline_risks`：真实截止日期在 `[today, new_end]` 内且有剩余量未排进 deadline 前的事项。
8. **非法方案**：任一硬约束不满足（end 非法、新事项引用不存在、estimated<completed 等）→ 抛 `PlanAdjustmentError`，路由映射 422；不得部分应用。

## 6. Flutter 客户端

新增 `lib/features/adjust/data/plan_adjust_api.dart`：
- `PlanAdjustPreview`（按 §3 字段解析，字段缺失/类型错 → `ResponseFailure`）
- `PlanAdjustApi`：`Future<PlanAdjustPreview> create({required int expectedRevision, required String requestId})`（POST，带 `Idempotency-Key` 头）；`Future<void> confirm(String id, {required int expectedRevision})`；provider `planAdjustApiProvider`。
- 错误映射复用 `ApiClient`（409 → `ConflictFailure` 的 message）。

`adjust_plan_page.dart`：
- 删除本地 `reschedulePlan` 调用及 `ScheduleChangeDialog` 依赖；
- 点击按钮：若 `snapshot.pending` 为真 → 提示“本机修改尚未同步，请等待同步完成后再调整”；否则置 `_applying`，调 `create(expectedRevision: snapshot.revision)`；成功后弹新预览对话框；确认后 `confirm(id, expectedRevision: snapshot.revision)`，再 `await plannerSession.sync()` 拉取新计划，提示成功；失败提示错误消息。
- 面板文案改为 AI 审查口径（保留区间/剩余天数/待安排/剩余工作量四项统计）；重排中按钮显示“AI 正在调整…”，并说明可能需要 1–2 分钟。
- 新增 `lib/features/adjust/presentation/plan_adjust_dialog.dart`，按 §3 展示：结论（合理/偏轻/偏重）、所需/当前/调整后总时长（小时取整显示）、周期变化（+N 天）、学习强度变化（每周分钟 → 分钟及百分比）、事项变化（更新/新增，最多展示 10 条 + “另有 N 条”）、日程影响（保护/释放/新增/未安排）、截止风险、warnings/notes；取消不写任何数据。

移除：
- 今日页顶部「智能重排」按钮与 import（`dashboard_page.dart`）；删除 `planner_dialogs.dart` 中 `ReplanDialog` 类（以及其他引用）。
- `settings_page.dart`：保存设置不再调用 `reschedulePlan`/`ScheduleChangeDialog`，只保存 profile；提示“已保存；如需按新容量/周期重排，请到调整页使用一键调整后续计划”。
- `capacity_overrides_dialog.dart`：保存容量时不再调用 `reschedulePlan`，不再展示释放/重排/未安排预览；改为保存后提示到调整页调整（可保留编辑/校验/冲突接受逻辑）。
- 相应更新 `adjust_plan_page_test.dart`、`capacity_overrides_test.dart`、`dashboard/app` 相关 widget 测试。

## 7. 测试要求

服务端（`apps/api/src/plan-adjust.test.ts` + `plan-adjust-ai.test.ts`）：
- 应用规则：周期延长、`plan_end` 事项 deadline 跟随、真实截止不变；强度替换并清空 baseline/range；任务预算上调/被 completed clamp；新增事项/课程；固定/已完成/历史/有日志块的保护；释放可调整块并重排；unscheduled 保留；预览字段完整。
- AI 模块：mock `fetch`，断言输入包含 recent_execution/画像/进度，输出被 schema 解析；非 2xx、非法 JSON、超时分别报错。
- 不依赖数据库（纯函数 + mock AI）；路由行为可用现有集成测试模式（无 DB 时跳过）可选。

Flutter：`adjust_plan_page_test.dart` 用 fake `PlanAdjustApi` 覆盖 provider，断言按钮触发 create、预览内容渲染、取消不 confirm、确认后调用 confirm；移除智能重排后现有测试不引用该按钮。

## 8. 文件 ownership（避免并行写冲突）

- 服务端（server-ai）：`apps/api/src/plan-adjust-ai.ts`、`apps/api/src/plan-adjust.ts`、`apps/api/src/plan-adjust.test.ts`、`apps/api/src/plan-adjust-ai.test.ts`、`apps/api/src/server.ts`（仅注册路由与 import）、`apps/api/db/migrations/202610210001_plan_adjustments.sql`
- 客户端调整流（client-adjust）：`apps/flutter_client/lib/features/adjust/**`、`apps/flutter_client/test/widget/adjust_plan_page_test.dart`
- 客户端移除（client-removal）：`dashboard_page.dart`、`planner_dialogs.dart`、`settings_page.dart`、`capacity_overrides_dialog.dart`、对应测试文件
- Lead：本文件、README/PRODUCT/apps/flutter_client/README 文档、最终集成与全量测试

## 9. 实现落地补充（as built，2026-10-18）

以下是实现时为了满足既有校验/调度器约束而确定的细节，后续修改需保持：

1. **活动窗口随周期延展**：只修改 `plan_end` 事项的 deadline 不够——调度器的有效窗口是 `min(deadline, activity.ends_on)`。因此 `plan_end` 事项的 `planning.activity.ends_on` 跟随新周期结束日；真实截止事项仅在 `activity.ends_on` 正好等于旧周期边界时延展（窄窗口视为有意范围，不动），真实 `deadline` 始终不变。
2. **结构化工作量同步缩放**：`PlannerDocumentSchema`/规划校验要求 finite 事项的 `ceil(Σ quantity*minutes_per_unit) == estimated_minutes`。AI 只给 `estimated_minutes` 时，服务端会按比例缩放该事项 workload components 的 `quantity`（保留单价/单位/标签，取 `estimated-0.5` 保证向上取整精确），并在 preview notes 中说明；recurring 事项以 `session_minutes` 为一致性基准，不缩放。
3. **周期截断**：`end_date = min(today+1095, plan_start+1094, target_date 若在未来)`，被截断写 warning；`end < today` 直接 422。
4. **固定/完成/归档优先**：`plan_end` deadline 跟随与强度/预算调整都跳过固定、已完成、归档事项；固定事项的工作量/活动策略不被 AI 修改。
5. **预览 id/revision 注入**：`ai_jobs.output_payload.preview` 只存纯预览；POST/GET/confirm 返回时由路由补 `id` 与 `base_revision`（客户端从 preview 内读取）。
6. **confirm 原子性**：重新读取并校验 revision（job base_revision 与请求 expectedRevision 都必须等于当前 revision），`PlannerDocumentSchema.parse` 后 `commitPlannerState`，事务内写 `plan_versions(kind='adjust')` 并标记 job confirmed；任何校验失败不部分写入。
7. **AI 失败不回退**：未配置 AI、超时、Zod 校验失败分别映射为 502/502/422；不调用本地 `reschedulePlan`。
8. **旧代码清理**：今日页「智能重排」按钮、`ReplanDialog`、旧的 `ScheduleChangeDialog` 及其入口均已删除；`reschedulePlan`、`local_replanning`、`replan_runs` 模型保留给旧数据/跨端 golden 对照及单测，不再有页面调用。

