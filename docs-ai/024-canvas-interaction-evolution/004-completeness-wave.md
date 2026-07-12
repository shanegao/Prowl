# 024.004 — Completeness Wave (#457, #507, #509, #514)

## Context

After the June keyboard/layout wave, the remaining gaps were parity leftovers rather
than structural problems: tab management actions (rename, icon, close variants) existed
only in the Normal tab bar; the Canvas `?` help required a click while the visually
identical notifications bell opened on hover; the Canvas toolbar lacked the center
status item and the code-host/PR actions targeted the Normal-selected worktree; and
`⌘⌃`-arrows — worktree navigation in Default view — forced an unwanted view-mode switch
when pressed in Canvas.

## Change

- **#457 — Card tab context menu** (fixes fork issue #453, 2026-06-16). The shared
  terminal tab context menu (`TerminalTabContextMenuActions`) attaches to Canvas card
  title bars, wired to the owning worktree's tab state: Rename Tab, Change Tab Icon,
  and the tab close variants. A Canvas-local icon picker sheet keeps the reused menu
  functional outside Default/Shelf views.
- **#507 — Help on hover** (2026-06-25). The bottom-left help affordance was extracted
  into `CanvasHelpButton` (`supacode/Features/Canvas/Views/CanvasHelpButton.swift`) and
  reuses the notifications-bell interaction: hover opens the popover, leaving dismisses
  after a 150 ms grace period, click pins it open. `docs/components/canvas.md` was
  updated in the same PR.
- **#509 — Toolbar code-host actions** (2026-06-25). The Normal toolbar's center status
  item (PR/check status, toasts, time hint) now renders on Canvas for the focused card,
  and Open on Code Host / Open Pull Request plus the palette's PR entries route through
  the Canvas-focused card while Canvas is active. PR-state semantics belong to
  [028-pr-status-tracking](../028-pr-status-tracking/000-plan.md).
- **#514 — Spatial card navigation** (2026-06-27). `⌘⌃`-arrows navigate between cards
  by 2D center coordinates instead of falling through to Default view's linear worktree
  selection (which forced an unwanted view-mode switch). `CanvasSpatialNavigation`
  (`supacode/Features/Canvas/Models/CanvasSpatialNavigation.swift`) is a pure-logic
  nearest-card finder using weighted distance (primary axis + 2× cross axis) to prefer
  aligned neighbors over diagonal ones. As merged, the arrows are not view-local key
  handlers: when `isShowingCanvas`, the worktree-selection actions in
  `supacode/Features/Repositories/Reducer/RepositoriesFeature+CoreReducer.swift`
  redirect to `.requestCanvasCommand(.navigate(...))`, fulfilled by
  `CanvasView+Focus.swift` calling `navigateCard(_:)` with viewport follow (an earlier
  in-PR iteration used four `.onKeyPress` handlers; fix commit `29de4e5f` moved it to
  the reducer→command channel). 18-case `CanvasSpatialNavigationTests` cover grid,
  strip, waterfall, and edge cases.

## Refs

- PRs #457, #507, #509, #514
- Fork issue #453 (context menu)

## Current state

All four changes verified present: `tabContextMenuActions` in
`supacode/Features/Canvas/Views/CanvasCardView.swift`, `CanvasHelpButton.swift`,
`canvasToolbarState`/`canvasToolbarContent` in
`supacode/Features/Repositories/Views/WorktreeDetailView.swift`,
`CanvasSpatialNavigation.swift` + `CanvasSpatialNavigationTests.swift`, and the
`isShowingCanvas` selection guard in `RepositoriesFeature+CoreReducer.swift`.
