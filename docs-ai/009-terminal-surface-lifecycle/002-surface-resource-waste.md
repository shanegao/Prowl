# 009.002 — Surfaces Alive When They Should Not Be (#198, #372)

## Context

The main investigation ([000-plan.md](000-plan.md)) chased surfaces that failed to render
when they *should*. Two further defects were the inverse: surfaces consuming resources —
or entire shell processes — while they should have been paused or gone.

- **CPU spin of restored non-displayed surfaces** (2026-04-11). Session restore (see
  [014-terminal-layout-persistence](../014-terminal-layout-persistence/000-plan.md))
  creates surfaces that may never be attached to a window. The deferred-apply rule from
  #156 deferred *all* occlusion changes until attachment, so `setOcclusion(false)` for a
  never-attached restored surface was never delivered and its Metal render loop kept
  spinning the CPU/GPU.
- **Terminal surface leak on tab close** (2026-05-29, fixes issue #370). A tab could
  close while SwiftUI still rendered a stale selected tab id. `splitTree(for:)` treated
  any missing tree as lazily creatable, so the stale render silently created a fresh
  Ghostty surface — and a new shell process — for the already-closed tab, outside the
  visible tab lifecycle. Separately, the first terminal tab was created with Ghostty's
  *window* context even though Prowl embeds all terminal tabs in its own window/tab UI.

## Change

- #198: make the deferral asymmetric — occluding (pausing render) applies immediately,
  even without a surface view hierarchy; only un-occluding waits for attachment. Added
  `occlusionFalseAppliesImmediatelyWithoutViewAttachment` coverage.
- #372: `splitTree(for:)` now returns an empty `SplitTree` for tab ids no longer present
  in `tabManager.tabs` instead of lazily creating a surface; the initial tab surface uses
  `GHOSTTY_SURFACE_CONTEXT_TAB` like every subsequent tab. Regression coverage for the
  normal close path and the Ghostty close-callback path.

## Refs

PR #198, PR #372 (fixes #370).

## Current state

- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift` — `setOcclusion(_:)` has the
  immediate-pause fast path in both the live-surface and testing branches ("Occluding
  (pausing render) is always safe, even without a view hierarchy").
- `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift` —
  `splitTree(for:)` guards `tabManager.tabs.contains(where: { $0.id == tabId })` and its
  default surface context is `GHOSTTY_SURFACE_CONTEXT_TAB`;
  `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` `createTab` also uses
  `GHOSTTY_SURFACE_CONTEXT_TAB`.
- Tests: `supacodeTests/WorktreeTerminalManagerTests.swift`
  (`splitTreeDoesNotRecreateSurfaceForClosedTab`,
  `ghosttyCloseRequestDoesNotRecreateSurfaceForClosedTab`) and
  `supacodeTests/GhosttySurfaceViewTests.swift`
  (`occlusionFalseAppliesImmediatelyWithoutViewAttachment`).
