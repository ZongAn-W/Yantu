# AI planning upgrade

## Existing entry points

- First plan: Flutter `OnboardingFlow.act` -> onboarding advance -> `confirmDraft` -> relational daily rows -> canonical sync document.
- Reinterview: same saved session -> `replanDocument` -> `commitPlannerState`; existing IDs and protected records survive.
- Settings: `reschedulePlan` -> preview -> local coordinator -> revision/base sync.
- Next cycle: `extendPlanCycle` -> `generatePlanBlocks` -> local save/sync.
- Daily local replanning: scheduler preview -> coordinator confirmation/undo -> sync. Legacy AI draft/generate/settle endpoints remain compatibility interfaces, not the maintained Flutter onboarding path.

## Data contract

New dispatch replaces both first confirmation and reinterview allocation with `buildPlanningDocument` -> independent checks -> `commitPlannerState`. Compatibility endpoints reject strategy-bearing plans. Flutter next-cycle, settings, rolling detail and daily replan use the Dart mirror of `scheduleStrategy`.

| Field | Origin and authority | PostgreSQL projection | Missing/clear behavior |
| --- | --- | --- | --- |
| `planning` | Confirmed route, frozen user constraints, program quality; canonical document | `profiles.planning_metadata` JSONB | Missing: legacy whole-cycle behavior; capable writer null: explicit clear |
| `tasks[].planning.workload` | AI estimate or user amendment; arithmetic checked by program | `items.planning_metadata` JSONB | Missing: original scalar estimate, no invented evidence |
| `tasks[].planning.activity/dependencies` | Confirmed strategy; finite scope and logical order | Same task JSONB | Missing: finite legacy behavior, no inferred frequency or prerequisites |
| `tasks[].planning.feedback/content_progress` | Explicit user content/difficulty feedback; immutable to AI generation | Same task JSONB | Missing: unknown; timer minutes never imply mastery |
| `blocks[].activity_instance_id` | Program task/week/occurrence identity | `daily_plan_items.activity_instance_id` | Missing: legacy task/day reservation; moved instances keep identity |
| `planning.quality/forecast/detailed_until` | Program calculation and current rules version | Plan JSONB | Local condition changes clear quality/forecast and set `needs_review`; forecasts never count as actual daily tasks |

These fields round-trip through the onboarding session JSON, API schemas, Flutter Freezed `JsonMap?`, IndexedDB/Sembast, JSON export/restore and three-way sync. No extra user-operated task level is introduced.

`task.planning` is optional: legacy tasks retain scalar budgets and gain no invented evidence. `workload.components` contains selected additive components (quantity x minutes_per_unit), optional uncertainty bounds, source/confidence/calibration. Unselected alternatives are visible but excluded. Finite `estimated_minutes` maps to the calculated total; recurring activities use the finite cycle demand, never a lifetime budget plus repeated weekly demand.

`activity` carries kind, inclusive window, weekly frequency, session duration and active/paused/ended state. Dependencies identify a task and whether the relationship is a future planned order or requires actual content confirmation. Spending the time budget never satisfies a confirmed dependency.

`block.activity_instance_id` identifies task + Monday week + occurrence index. Execution blocks reserve future capacity only; actual minutes remain exclusively in timer logs. Partial weeks use ceil(frequency x effective calendar days / 7), capacity and rest days may cause an explained deficit.

`document.planning` holds format/prompt/rules versions, route, milestones, assumptions, risks, uncovered scope, frozen inputs, quality and detailed_until. New plans default to 14 detailed inclusive days, capped by the confirmed cycle. Legacy documents without this envelope keep their existing daily horizon. Routes are metadata, not a third task hierarchy.

## Authority and compatibility

The canonical sync document is authoritative. PostgreSQL JSONB columns project the envelope/task metadata and stable occurrence identity; snapshots, Flutter JSON, backups and three-way merge preserve them. Old writers are rejected with an upgrade response when a strategy exists; a missing field is not an implicit clear. Explicit null is a clear from a capable writer.

## Generation and confirmation

Confirm the finite cycle, full seven-day capacity and current fixed events before item generation. Model work runs outside transactions. Program calculation, trial schedule and independent quality checks run before preview. At most two directed model repairs share a bounded time budget. Failed repairs remain recoverable drafts. A preview token binds the candidate, all constraints, protected data and plan revision. Final confirmation rechecks the token and revision inside the existing transaction; retries are idempotent.

## Feedback

Actual time, user-confirmed content progress and difficulty are separate inputs. Small samples remain estimates. Offline changes retain the strategy and flag a need for review; they never silently increase capacity, shrink scope or infer mastery. Adjustments affecting future execution require preview and confirmation.
