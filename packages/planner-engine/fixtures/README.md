# Shared planner goldens

`planner-goldens.json` is consumed directly by Vitest and Flutter tests; neither runner
removes fields or sorts result arrays. Object property order is JSON-semantic, while
IDs (including IDs consumed during failed slot attempts), millisecond UTC stamps,
optional key presence, task status snapshots and every array order are compared.

Inputs live in `../src/golden-cases.ts`. Expected output is an explicitly refreshed,
committed TypeScript oracle. Normal tests **never** update expected values.

From repository root:

```powershell
npm test -- packages/planner-engine
# Intentional fixture regeneration only; inspect the resulting JSON diff.
$env:UPDATE_PLANNER_GOLDENS = '1'
npm test -- packages/planner-engine/src/golden.test.ts
Remove-Item Env:UPDATE_PLANNER_GOLDENS
```

From `apps/flutter_client` with its documented SDK/cache environment:

```powershell
flutter test --no-pub test/golden/planner_scheduler_test.dart
flutter test --no-pub test/unit/local_replanning_test.dart
```

The domain functions reproduce the current TypeScript block-based confirmation and
undo checks. `LocalReplanning` additionally protects all local scheduling inputs and
optional guidance fields; its persistent `local_undo_guard` is an additive run field,
not part of the shared oracle. TypeScript historical runs without it remain readable.

`strategy-cases.json` contains hand-reviewed business outcomes for the new pure
strategy scheduler (`apps/api/src/planning-scheduler.ts`, re-exported by the engine).
The API owns this dependency-free module so its production build does not import
TypeScript source from outside the API's `rootDir`. Flutter mirrors the same rules in
`strategy_scheduler.dart`; both runners read these cases directly.

The cases include a deidentified 431-day activity, Monday week boundaries, partial
weeks, capacity deficits, confirmed versus forecast dependencies, cyclic references,
overlapping fixed events, cycle boundaries, real-time credits, protected pending
work, paused activities and legitimate unused capacity. Recurring identities are
`task_id:week_monday:ordinal`; dates can change while this identity remains stable.
Partial weeks request `ceil(sessions_per_week * active_calendar_days / 7)` sessions.
Zero-capacity days remain unavailable and create a shortfall when necessary.

The planning upgrade intentionally refreshes the older oracle: blocks with actual
minutes or linked logs remain byte-for-byte protected, and exhausted time budgets
never set a task's content status to completed.

```powershell
npx vitest run packages/planner-engine/src/strategy.test.ts
# From apps/flutter_client:
flutter test --no-pub test/golden/strategy_scheduler_test.dart
```
