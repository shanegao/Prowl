# 037 — Amendment: Deferred Refresh After Commit

## Context

After committing, the sidebar badge kept showing stale `+N/-M` for up to 5 minutes even
though `git diff HEAD` was already 0/0 — only the 300 s safety refresh eventually
corrected it.

Root cause: an interaction between two #365-era mechanisms. Worktrees added after the
initial load go into `deferredLineChangeIDs`, and the central `emit(_:)` function drops
`.filesChanged` events for deferred worktrees. The HEAD watcher path
(`scheduleFilesChanged`, fired on commit/branch switch) emitted `.filesChanged`
*directly* after its debounce — so for a deferred worktree the event was silently
swallowed, and nothing ever cleared the deferred flag.

## Change

- PR #508 (2026-06-25): route `scheduleFilesChanged` through
  `scheduleLineChangesRefresh`, whose timer fires `emitLineChangesChanged` — which
  removes the worktree from `deferredLineChangeIDs` before emitting, so the event can no
  longer be dropped. The faster HEAD-path timing (1/2/5 s per tier, vs the 2/5/15 s
  FSEvents debounce) is preserved by passing `filesChangedDebounce` as the delay.
- PR #511 (2026-06-25, merged together with #508's fix): made the regression testable
  without real file-system event delivery by extracting the HEAD watcher
  `DispatchSource` behind a `WorktreeHeadEventMonitoring` protocol
  (`DispatchSourceWorktreeHeadEventMonitor` in production), and added
  `headWatcherEventNotBlockedByDeferredLineChanges()` — load one worktree, add a second
  (which becomes deferred), emit a HEAD event for it, assert `.filesChanged` fires after
  the debounce.

## Refs

- PR #508 — "fix: sidebar diff badge not refreshing after commit (deferredLineChangeIDs gate)"
- PR #511 — "test: cover deferred HEAD watcher refresh"

## Current state

`scheduleFilesChanged` in
`supacode/Features/Repositories/BusinessLogic/WorktreeInfoWatcherManager.swift` carries
an inline comment explaining the routing; `WorktreeHeadEventMonitoring` lives in
`supacode/Features/Repositories/BusinessLogic/WorktreeInfoMonitors.swift`; the
regression test is in `supacodeTests/WorktreeInfoWatcherManagerTests.swift`.
