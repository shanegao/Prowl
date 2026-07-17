# 014 — Amendment: Launch-Ordering Races (2026-06)

## Context

Two independent startup races surfaced about two months after the feature stabilized,
both rooted in the same property: layout restore participates in app launch, so anything
else that runs at launch (Default View application, the scene-phase bootstrap) can
observe or destroy restore state before restore has run.

## Change

**#380 — Default View launch race and restoration hang (2026-06-01).** With
`restoreTerminalLayoutOnLaunch` enabled but no snapshot on disk,
`WorktreeTerminalManager` never signalled completion and the restoration phase stalled
indefinitely; separately, the Default View (Shelf/Canvas) could be applied before
settings and the snapshot were reliably loaded. Fixes:

- `WorktreeTerminalManager` emits `.layoutRestored(selectedWorktreeID: nil)` when no
  snapshot exists, so the pipeline always terminates.
- Default View application was centralized into `AppFeature.applyDefaultViewMode` and
  moved to `repositoriesChanged` (deferred while `launchRestoreMode == .restoreLayout`,
  then applied after `.layoutRestored` / `.layoutRestoreFailed`); the redundant early
  launch-view logic in `RepositoriesFeature` was removed.

**#459 — scenePhase save clears the snapshot before restore (2026-06-16).** A
`ContentView.task` bootstrap (added in `73d1b07a`) sends `scenePhaseChanged(.background)`
at launch, before any terminal state exists. The async save path found zero active
states, treated that as "nothing to persist", and *cleared the snapshot file* — so the
subsequent restore found nothing on disk. Fix: the scenePhase-triggered save is skipped
while `launchRestoreMode == .restoreLayout` (i.e. until the pending restore has been
consumed), alongside the existing setting and `suppressLayoutSaveUntilRelaunch` gates.

## Refs

- PR #380, PR #459 (fork)

## Current state

Both gates are visible in `supacode/Features/App/Reducer/AppFeature.swift` (scene-phase
save condition, `applyDefaultViewMode` call sites in `AppFeature+Support.swift` /
`AppFeature+TerminalEvents.swift`) and the no-snapshot `.layoutRestored(nil)` emission in
`supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`.
