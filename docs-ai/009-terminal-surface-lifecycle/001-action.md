# 009 — Terminal Surface Lifecycle: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-23 | Fix blank surface when exiting Canvas via toggle shortcut: stop occluding in `deactivateCanvas()` (onAppear/onDisappear ordering race); occlude non-selected worktrees from `setSelectedWorktreeID` on canvas exit instead | PR #42 |
| 2026-03-24 | General occlusion cache (`OcclusionState`, desired vs applied); re-send current occlusion on `GhosttySurfaceView` reattachment, tied to real NSView lifecycle events; unit coverage | PR #50 |
| 2026-04-03 | Blank terminal still reproducible: force-refresh surface activity on canvas exit, invalidate per-surface occlusion caches before reapplying visibility/focus, add `[CanvasExit]` diagnostics | PR #132 |
| 2026-04-05 | Defer occlusion apply until the surface has both a superview and a window; keep desired value across canvas-exit reparenting so the real reattach triggers a fresh apply | PR #156 |
| 2026-04-11 | Stop restored, non-displayed surfaces from spinning CPU/GPU: occluding applies immediately even without a view hierarchy — see [002-surface-resource-waste.md](002-surface-resource-waste.md) | PR #198 |
| 2026-04-14 | Host ownership fix (accepted root cause): terminal wrapper reattaches only orphaned surfaces, never steals from a live host (e.g. Canvas); detach-intent diagnostics; host-ownership unit tests | PR #201 |
| 2026-04-16 | Fix Canvas split-pane rendering freeze: `isCanvasManaged` flag skips `applySurfaceActivity` while Canvas owns occlusion; new split panes explicitly un-occluded in Canvas | PR #203 |
| 2026-04-29 | Investigation closed in the tracking doc: no recurrence after #201/#203; most investigation logs removed, low-frequency `[CanvasExit]` / `[TerminalWake]` logs retained | `doc-onevcat/canvas-exit-terminal-blank-tracking.md` |
| 2026-05-29 | Fix terminal surface leak on tab close (fixes #370): stale SwiftUI renders no longer recreate surfaces for closed tabs; first tab uses Ghostty tab context — see [002-surface-resource-waste.md](002-surface-resource-waste.md) | PR #372 |

## Outcome & current state (as of 2026-07-12)

- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift` — `OcclusionState` struct
  (`desired`/`applied`, `setDesired`, `prepareToApply`, `invalidateForAttachmentChange`).
  `setOcclusion(_:)` pauses immediately (even with no surface/view hierarchy) but defers
  resume until `isReadyToApplyOcclusion` (superview + window), logging
  `[CanvasExit] deferOcclusion` when deferring. `viewDidMoveToWindow` /
  `viewDidMoveToSuperview` call `handleAttachmentChange()`, which invalidates the applied
  cache, asks the scroll wrapper to `ensureSurfaceAttached()` when orphaned, and reapplies
  the desired value once attached.
- `supacode/Infrastructure/Ghostty/GhosttySurfaceScrollView.swift` —
  `ensureSurfaceAttached(requiresLiveHost:)`: terminal-host-only (`hostKind == .terminal`),
  adopts the surface only when `surfaceView.superview == nil` (comment: "Only adopt an
  orphaned surface; never steal it from a live host such as Canvas"), with
  `[CanvasExit] hostReattach` / `hostReattachComplete` logs.
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift` —
  `setSelectedWorktreeID` handles the leaving-canvas transition (previous selection nil):
  occludes all worktrees except the newly selected one; `[CanvasExit] enteringCanvas` /
  `setSelectedWorktreeID` logs retained.
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` — `isCanvasManaged`
  flag; `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift` —
  `syncFocusIfNeeded()` guards on `!isCanvasManaged`; `createSplitOnFocusedSurface`
  un-occludes new panes when canvas-managed; `setAllSurfacesOccluded()` helper.
- `supacode/Features/Canvas/Views/CanvasView+Focus.swift` — `activateCanvas()` sets
  `isCanvasManaged` and manages occlusion for card surfaces; `deactivateCanvas()` clears
  the flag and deliberately does *not* occlude (comment documents the
  onAppear-before-onDisappear rationale from #42).
- `supacode/Infrastructure/Ghostty/GhosttyRuntime.swift` — `[TerminalWake]` sleep/wake
  summary log retained.
- Tests in `supacodeTests/GhosttySurfaceViewTests.swift`: the `OcclusionState` suite
  (resend-after-attachment-change, deferred desired values,
  `occlusionFalseAppliesImmediatelyWithoutViewAttachment`,
  `occlusionCanRecoverWhenAttachmentCallbackIsMissedAfterReattachment`) and the host
  ownership trio (`terminalHostReattachesSurfaceOnlyAfterItLeavesTheViewTree`,
  `terminalHostDoesNotStealSurfaceFromCanvasHost`,
  `canvasHostDoesNotStealDetachedSurfaceBack`) — all named in the tracking doc and present.

## Deviations from plan

- #132's "force-refresh terminal surface activity when exiting Canvas"
  (`refreshSurfaceActivity`) no longer exists in the tree; the mechanism was superseded by
  #156's deferred-apply and #203's `isCanvasManaged` ownership of visibility. Its
  surviving contribution is the `[CanvasExit]` diagnostic trail.
- Most per-step investigation logging added during #132/#201 was removed at closure
  (2026-04-29); only the low-frequency log set listed in the tracking doc remains.

## Open questions

- The root cause is the tracking doc's "most likely failure mode", established by
  elimination and non-reproduction rather than a captured repro of the stale-wrapper
  deinit; the entry reflects that confidence level.
