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
| `planning.mode/rolling/detail_days/detailed_until` | Program mode: new plans `mode:"full", rolling:false, detail_days=周期天数, detailed_until=plan_end_date, forecast:null`; old rolling plans keep their window until the client confirms a full-cycle completion | `profiles.planning_metadata` JSONB | Missing: legacy rolling/horizon behavior; capable writer null: explicit clear |
| `planning.capacity` | Adopted capacity baseline, basis, range, override summary and assumptions confirmed with the full plan | Same plan JSONB | Missing: legacy capacity semantics; never re-randomised on rebuild |
| `profiles.capacity_basis/weekly_baseline_minutes/weekly_range_min_minutes/weekly_range_max_minutes/week_capacity_overrides/date_capacity_overrides` | User-confirmed flexible availability; resolved by the shared capacity core | New `profiles` columns (projection mirror of the document) | Missing: legacy gross-buffer per-day template; explicit 0 is a rest day; deleting an override restores the upper rule (not zero) |
| `planning` | Confirmed route, frozen user constraints, program quality; canonical document | `profiles.planning_metadata` JSONB | Missing: legacy whole-cycle behavior; capable writer null: explicit clear |
| `tasks[].planning.workload` | AI estimate or user amendment; arithmetic checked by program | `items.planning_metadata` JSONB | Missing: original scalar estimate, no invented evidence |
| `tasks[].planning.activity/dependencies` | Confirmed strategy; finite scope and logical order | Same task JSONB | Missing: finite legacy behavior, no inferred frequency or prerequisites |
| `tasks[].planning.feedback/content_progress` | Explicit user content/difficulty feedback; immutable to AI generation | Same task JSONB | Missing: unknown; timer minutes never imply mastery |
| `blocks[].activity_instance_id` | Program task/week/occurrence identity | `daily_plan_items.activity_instance_id` | Missing: legacy task/day reservation; moved instances keep identity |
| `logs[].relation/session_id/ad_hoc_id/quota_minutes` | Fact recorded at timing time: relationship (`scheduled`/`extra`/`ad_hoc`/`legacy_unknown`), stable session, temporary-learning owner and the original plan quota usable for achievement | New `study_logs` columns | Missing: `legacy_unknown` with limited evidence-based scheduled inference; never blanket-treated as scheduled or temporary |
| `ad_hoc_learnings` | Lightweight temporary learning entity (name only, optional subject, archived/converted reference) | New `ad_hoc_learnings` table (with revision trigger) | Missing: no temporary learning; deleting an entity with logs is restricted |
| `planning.quality/forecast/detailed_until` | Program calculation and current rules version | Plan JSONB | Local condition changes clear quality/forecast and set `needs_review`; full mode has `forecast:null`; forecasts never count as actual daily tasks |

These fields round-trip through the onboarding session JSON, API schemas, Flutter Freezed `JsonMap?`, IndexedDB/Sembast, JSON export/restore and three-way sync. No extra user-operated task level is introduced.

`task.planning` is optional: legacy tasks retain scalar budgets and gain no invented evidence. `workload.components` contains selected additive components (quantity x minutes_per_unit), optional uncertainty bounds, source/confidence/calibration. Unselected alternatives are visible but excluded. Finite `estimated_minutes` maps to the calculated total; recurring activities use the finite cycle demand, never a lifetime budget plus repeated weekly demand.

`activity` carries kind, inclusive window, weekly frequency, session duration and active/paused/ended state. Dependencies identify a task and whether the relationship is a future planned order or requires actual content confirmation. Spending the time budget never satisfies a confirmed dependency.

`block.activity_instance_id` identifies task + Monday week + occurrence index. Execution blocks reserve future capacity only; actual minutes remain exclusively in timer logs. Partial weeks use ceil(frequency x effective calendar days / 7), capacity and rest days may cause an explained deficit.

`document.planning` holds format/prompt/rules versions, route, milestones, assumptions, risks, uncovered scope, frozen inputs, quality, capacity assumptions and detailed_until. New plans default to full-cycle mode: one AI response defines the scope/strategy and the program expands every day from the confirmed start to end date; `mode:"full"`, `rolling:false`, `detail_days` equals the inclusive cycle span (≤1095), `detailed_until` is the cycle end and `forecast` is null. Legacy documents without this envelope keep their existing rolling horizon; old rolling plans are never silently upgraded, and the client offers a one-time "complete the cycle" preview/confirmation instead. Routes are metadata, not a third task hierarchy.

Flexible capacity is resolved by one shared core (TypeScript `apps/api/src/capacity.ts`, Dart `lib/features/planner/domain/capacity.dart`, both checked against `packages/planner-engine/fixtures/capacity-cases.json`): specific date value > explicit week day > confirmed week total distribution > adopted weekly baseline > default seven-day template > legacy daily limit. Net-basis profiles no longer deduct seven daily buffers; legacy `gross_buffer` profiles keep the historical formula and 480-minute cap. Weekly totals and baselines are distributed with integer largest-remainder arithmetic (Monday-first tie-break); explicit values consume the confirmed total and conflicts are surfaced, never silently chosen. Rest days (explicit 0) do not receive redistributed minutes.

Learning relations are recorded as execution facts: `scheduled` contributes to the original plan capped by the quota captured when timing started, `extra` covers add-study/overrun for an existing item, `ad_hoc` belongs to a lightweight temporary-learning entity, and `legacy_unknown` preserves old records without inferring a classification. One timing session may split into scheduled + extra records with the same `session_id`; cross-midnight splits re-evaluate the new day's relation. Capacity accounting counts each executed minute once: actual = all valid log minutes; reserved = unfinished original blocks minus their executed coverage; available = capacity − actual − reserved; over = max(0, actual − capacity).

## Authority and compatibility

The canonical sync document is authoritative. PostgreSQL JSONB columns project the envelope/task metadata and stable occurrence identity; snapshots, Flutter JSON, backups and three-way merge preserve them. New clients declare `writer_learning_version: 1` for relation/capacity/temporary-learning capability and `writer_planning_version: 1` for strategy metadata. A missing field is not an implicit clear: old writers preserve cloud values, except that a writer unable to represent existing task-less temporary-learning logs receives a 426 upgrade response with the transaction rolled back (same revision/base can be retried after upgrade). Explicit null/empty from a capable writer clears the field.

## Generation and confirmation

Confirm the finite cycle, full seven-day capacity and current fixed events before item generation. Model work runs outside transactions. Program calculation, trial schedule and independent quality checks run before preview. At most two directed model repairs share a bounded time budget. Failed repairs remain recoverable drafts. A preview token binds the candidate, all constraints, protected data and plan revision. Final confirmation rechecks the token and revision inside the existing transaction; retries are idempotent.

## Feedback

Actual time, user-confirmed content progress and difficulty are separate inputs. Small samples remain estimates. Offline changes retain the strategy and flag a need for review; they never silently increase capacity, shrink scope or infer mastery. Adjustments affecting future execution require preview and confirmation.
