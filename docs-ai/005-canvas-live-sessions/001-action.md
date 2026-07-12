# 005 — Canvas (Live Sessions) v1: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-15…17 | Feature branch: "Dashboard (Live Sessions)" free-form canvas; drag/resize/gesture fixes; renamed to Canvas (`74b13c2`); zoom-reflow fixes (`.offset()` positioning, `pinnedSize`); cursor-anchored pinch zoom (`c24e092`); two-finger pan (`2738c24`); all open tabs as per-tab cards (`e5992ea`); batched grid positioning (`80df1b1`); split panes in cards with `pinnedSize` propagation (`12496d5`) | PR #2 (merged 03-17) |
| 2026-03-17 | SwiftLint cleanup in `CanvasView` | PR #5 |
| 2026-03-18 | Sidebar button bleed-through/centering fixes; Canvas toolbar title as plain label | PR #6 |
| 2026-03-18 | Default card size 600×400 → 800×550; max resize 1200×900 → 2400×1600; first **Arrange** button (size-preserving waterfall packing) next to **Organize** | PR #7 |
| 2026-03-19 | Arrange packer rework: MaxRects-BSSF (`15bafd1`) → exhaustive row-break (`aca935d`) → waterfall + row-break hybrid maximizing fit-to-view scale (`fc81375`), extracted as `CanvasCardPacker` with unit tests; auto-arrange on first Canvas entry per session, re-armed when all tabs close | PR #8 |
| 2026-03-19 | ⌥⌘↩ toggles Canvas with two-way worktree+tab focus restoration; `canvasFocusedWorktreeID` introduced on the terminal manager; Canvas + Show Diff moved to the View menu; shortcut unbound in Ghostty | PR #11 |
| 2026-03-23 | Double-click on a card title bar exits Canvas into that tab (first click focuses; interval from `NSEvent.doubleClickInterval`) | PR #43 |
| 2026-03-23 | Arrange/Organize transitions animated (`withAnimation(.easeInOut(duration: 0.2))`) | PR #44 |
| 2026-03-25 | Cmd-W in Canvas restored to close-surface/close-tab semantics after upstream's Close Window command claimed the shortcut | PR #54, [002](002-cmd-w-close-semantics.md) |

The first exit-blank-surface fix (#42, 2026-03-23) landed in the same window but is
tracked as the opening of [009-terminal-surface-lifecycle](../009-terminal-surface-lifecycle/001-action.md).

## Outcome & current state (as of 2026-07-12)

Canvas lives in `supacode/Features/Canvas/`, now split into `Models/` and `Views/`:

- `Views/CanvasView.swift` (+ `CanvasView+Focus.swift`): card collection, gestures,
  `organizeCards()` / `arrangeCards()` / `tileCards()` and their animated `*WithFit()`
  wrappers, double-click title-bar handling.
- `Views/CanvasCardView.swift`: per-card chrome + live split tree with `pinnedSize`.
- `Views/CanvasSupportViews.swift`: `CanvasScrollContainer`, `CanvasZoomMath`,
  `CanvasViewportMath`, `CanvasViewportAnimator` (viewport animation came later).
- `Views/CanvasSidebarButton.swift`, `Views/CanvasHelpButton.swift`.
- `Models/CanvasCardLayout.swift`: `CanvasCardLayout`, the hybrid `CanvasCardPacker`
  (tests in `supacodeTests/CanvasCardPackerTests.swift`), `CanvasTileLayout` (from 043),
  and `CanvasLayoutStore` including `hasAutoArrangedInSession` /
  `shouldAutoArrangeOnInitialEntry(for:)` from PR #8.
- `Models/CanvasSelectionState.swift`, `CanvasSpatialNavigation.swift`,
  `CanvasFocusRequest.swift`, `CanvasExpandGeometry.swift` are later additions
  (011 / 024), not v1.

v1 mechanisms still in place:

- `pinnedSize` still threads `TerminalSplitTreeView` →
  `Infrastructure/Ghostty/GhosttyTerminalView.swift` → `GhosttySurfaceView.swift`.
- `WorktreeTerminalState.surfaceView(for:)`
  (`supacode/Features/Terminal/Models/WorktreeTerminalState.swift`) remains the card →
  surface bridge.
- `canvasFocusedWorktreeID` on `WorktreeTerminalManager` outgrew focus restoration: it
  now also drives the Canvas toolbar target, reducers, and CLI target resolution
  (`supacode/CLIService/TargetResolver.swift`).
- The ⌥⌘↩ default survives as `AppShortcuts.toggleCanvas` (command id `toggle_canvas`
  in `supacode/App/AppShortcuts.swift`), now resolved through the config-driven
  keybinding system ([012](../012-keybinding-system/000-plan.md)) rather than a
  hardcoded menu shortcut.
- Cmd-W routing per [002](002-cmd-w-close-semantics.md):
  `supacode/Features/Repositories/Views/WorktreeDetailView.swift` publishes
  close-surface/close-tab focused actions for the selected *or canvas-focused*
  worktree, consumed by `supacode/Commands/TerminalCommands.swift`.

Superseded v1 details: the fixed 800×550 default card size gave way to a screen-derived
`adaptiveDefaultCardSize` (024, #401); a third layout mode (Tile) joined
Organize/Arrange (043); Organize/Arrange/Tile gained keyboard shortcuts and palette
commands (024). User-facing behavior is documented in `docs/components/canvas.md`.

## Deviations from plan

- The Arrange algorithm was not stable at ship time — waterfall (#7) was rewritten into
  the hybrid packer (#8) the next day. Recorded as a decision in 000-plan.
- PR #2's initial per-worktree card model changed to per-tab cards before merge
  (`e5992ea`); the merged v1 already matched the per-tab goal.

## Open questions

- Stale doc comment: `arrangeCards()` in `supacode/Features/Canvas/Views/CanvasView.swift`
  still says "Arrange cards using MaxRects-BSSF bin packing", but the implementation
  delegates to `CanvasCardPacker`, the waterfall + row-break hybrid; MaxRects was
  replaced inside the PR #8 branch. Comment-only inaccuracy.
