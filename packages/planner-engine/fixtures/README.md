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
