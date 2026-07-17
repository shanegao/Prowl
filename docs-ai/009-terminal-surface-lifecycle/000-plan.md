# 009 — Terminal Surface Lifecycle: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-23 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #42, #50, #132, #156, #198, #201, #203, #372 |
| **Sources** | `doc-onevcat/canvas-exit-terminal-blank-tracking.md` (absorbed; investigation closed 2026-04-29), PR descriptions |
| **Related** | [005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md), [014-terminal-layout-persistence](../014-terminal-layout-persistence/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md) |

## Background

Prowl keeps one `GhosttySurfaceView` (an `NSView` wrapping a `ghostty_surface_t`) alive per
terminal pane and reparents it between SwiftUI hosts: the normal tab view
(`WorktreeTerminalTabsView`) and Canvas cards (`CanvasView`) both host the *same* AppKit
view. Rendering cost is controlled by "occlusion": `ghostty_surface_set_occlusion` pauses
or resumes a surface's Metal render loop.

Shortly after Canvas shipped (see
[005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md)), a persistent symptom
appeared: **exiting Canvas returned to the correct tab, with correct reducer/tab state,
but the terminal rendered blank** until the user switched away and back. The bug was
intermittent and timing-dependent, which turned this into a multi-week investigation
(2026-03-23 → 2026-04-29) rather than a single fix.

## Goals

- Terminal surfaces must render correctly after every Canvas enter/exit transition and
  any other SwiftUI/AppKit reparenting.
- Occlusion state sent to Ghostty must match what the UI actually needs — no surface left
  paused while visible, and (later wave) no surface left rendering while invisible.
- Exactly one live host owns a surface at a time; host changes must never leave the
  surface detached from the view tree.

**Non-goals**: changing the shared-surface architecture itself (one `ghostty_surface_t`
reparented between hosts was kept throughout), or Canvas interaction behavior (tracked in
[024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md)).

## Investigation record (hypotheses in order)

The root-cause understanding evolved across four hypotheses; each produced a fix that was
kept, because each addressed a real (if not always the primary) failure mode.

1. **SwiftUI `onAppear`/`onDisappear` ordering race** (#42). In SwiftUI's if/else view
   swap, the incoming view's `onAppear` fires *before* the outgoing view's `onDisappear`.
   `deactivateCanvas()` (in `onDisappear`) occluded all surfaces *after* the tab view's
   `syncFocus()` had already un-occluded them. Regression introduced by commit `ff4f7c6`
   (clearing `selectedWorktreeID` when entering Canvas), which made the nil→ID transition
   in `setSelectedWorktreeID` pass its same-ID guard with no compensating un-occlude.
   Fix: stop occluding in `deactivateCanvas()`; move canvas-exit cleanup (occlude
   non-selected worktrees) into `WorktreeTerminalManager.setSelectedWorktreeID`.

2. **Occlusion sent while the renderer could not resume** (#50, #156). A
   `setOcclusion(true)` call could land while the surface was detached from the view tree
   during reparenting; Ghostty could not resume rendering, but the caller believed the
   value was applied. Fix: give `GhosttySurfaceView` an `OcclusionState` cache tracking
   `desired` vs `applied`; invalidate `applied` on every NSView attachment change
   (`viewDidMoveToWindow` / `viewDidMoveToSuperview`) so the desired value is re-sent
   after real reattachment; and (#156) defer *un*-occluding until the surface has both a
   superview and a window, storing only `desired` in the meantime.

3. **Still reproducible → instrument the critical path** (#132). With reducer state
   verified correct, the fix added an aggressive surface-activity refresh on canvas exit
   plus `[CanvasExit]` diagnostics across selection, tab-view appearance, and surface
   reattachment, to catch the surviving repro in logs.

4. **Host ownership loss during reparenting — the accepted root cause** (#201). Canvas
   and terminal wrappers both host the same `GhosttySurfaceView`. A stale terminal
   wrapper could re-adopt a surface still owned by the live Canvas host; when that stale
   wrapper later deinitialized, AppKit removed the surface from the view tree again,
   leaving the *active* host blank even though selection and tab state were correct.
   Fix: terminal hosts only defensively reattach **orphaned** surfaces
   (`surfaceView.superview == nil`) and never steal a surface from another live host.

A related regression was fixed in the same frame: **Canvas split-pane rendering freeze**
(#203). After commit `979e8e2f` routed tree mutations through `syncFocusIfNeeded` →
`applySurfaceActivity`, entering Canvas removed `WorktreeTerminalTabsView`, whose
`WindowFocusObserverNSView` recorded stale `windowIsVisible=false`; any split-tree change
in Canvas then occluded every surface. Fix: an `isCanvasManaged` flag on
`WorktreeTerminalState` makes `syncFocusIfNeeded` skip `applySurfaceActivity` while Canvas
owns visibility, and new split panes are explicitly un-occluded while the flag is active.

## Alternatives & decisions

- **Adopt-orphans-only over ownership tracking**: rather than a central registry of which
  host owns which surface, the rule is local and defensive — a terminal wrapper reattaches
  a surface only if it is not attached anywhere. The tracking doc records the residual
  risk: any future host of `GhosttySurfaceView` must follow the same rule.
- **Occlude eagerly, un-occlude lazily**: pausing rendering is always safe (applied
  immediately, even with no view hierarchy — #198), while resuming is deferred until the
  surface is genuinely attached. Asymmetry is deliberate.
- **Keep low-frequency diagnostics**: most investigation logging was removed at closure,
  but `[CanvasExit] enteringCanvas / setSelectedWorktreeID / deferOcclusion /
  hostReattach / hostReattachComplete` and `[TerminalWake]` summaries were kept as a
  regression tripwire.
- **Investigation closed, not proven**: the tracking doc explicitly labels host ownership
  loss as the "most likely failure mode"; closure was based on non-reproduction after
  #201/#203, backed by host-ownership and occlusion unit tests.

## Amendments

- Updated 2026-05-29: surfaces alive when they should not be — CPU spin of restored
  non-displayed surfaces (#198) and terminal surface leak on tab close (#372) — see
  [002-surface-resource-waste.md](002-surface-resource-waste.md)
