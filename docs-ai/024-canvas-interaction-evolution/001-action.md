# 024 — Canvas Interaction Evolution: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-20 | Hover close/expand buttons on card title bars; closing the highlighted card auto-advances selection to the nearest surviving neighbor (fork issue #225) | PR #226 |
| 2026-04-20 | Revert #204's no-scrollback scroll passthrough so TUIs with their own mouse protocol scroll again; gesture continuity + bounce window kept (fork issue #228) | PR #229 |
| 2026-04-25 | Cmd+wheel zoom (`CanvasScrollCoordinator.handleZoom` / `CanvasZoomMath`) and middle-click drag pan via window-scoped `NSEvent` monitor (fork issue #197) | PR #238 |
| 2026-05-24 | Persist Canvas card layout and z-order across launches (`CanvasLayoutStore`); no auto-arrange over restored layouts; `UserDefaults` format migration — see [002](002-first-class-canvas.md) | PR #329 |
| 2026-05-25 | Canvas added to Settings → Appearance → Default View; boots straight into Canvas (falls back to Normal with zero worktree rows) — see [002](002-first-class-canvas.md) | PR #337 |
| 2026-05-28 | Canvas custom actions: Run/Stop Script + Custom Commands routed through the focused card; atomic settings sync on card switch; single-item toolbar cluster (community #358 by vince-hz + refinements) — see [002](002-first-class-canvas.md) | PR #362 (shared with [002-custom-commands](../002-custom-commands/001-action.md)) |
| 2026-06-05 | New Terminal/New Tab route through the active terminal target so Canvas targets the focused card's worktree; Ghostty terminal commands in the palette with a Canvas target — see [003](003-keyboard-and-layout-wave.md) | PR #394 |
| 2026-06-05 | Arrange (`⌘⌥R`) / Organize (`⌘⌥G`) keyboard shortcuts, user-rebindable (fork issue #392) — see [003](003-keyboard-and-layout-wave.md) | PR #393 |
| 2026-06-05 | Sidebar repo/worktree/folder rows and Active Agents entries keep Canvas selected; `CanvasFocusRequest`/`CanvasFocusResolver` create-or-focus cards and center them — see [003](003-keyboard-and-layout-wave.md) | PR #395 |
| 2026-06-05 | Command palette worktree/folder selection focuses Canvas cards instead of switching to Normal — see [003](003-keyboard-and-layout-wave.md) | PR #396 (also touches [031](../031-command-palette-architecture/000-plan.md)) |
| 2026-06-06 | Animate the terminal subtree's pinned size during card resize/refit so content tracks the title bar; drag-resize stays immediate — see [003](003-keyboard-and-layout-wave.md) | PR #400 |
| 2026-06-06 | Default card size scales with host screen width (800×550 → 1000×680, clamped linear interpolation) — see [003](003-keyboard-and-layout-wave.md) | PR #401 |
| 2026-06-06 | Expand a card in place (magic-move) with frozen background, scrim, gesture lock, `⌘⌥E`, and palette entries via `CanvasCommandRequest` — see [003](003-keyboard-and-layout-wave.md) | PR #402 |
| 2026-06-16 | Shared terminal tab context menu on Canvas card title bars (Rename Tab, Change Tab Icon, close variants) with Canvas-local icon picker sheet (fork issue #453) — see [004](004-completeness-wave.md) | PR #457 |
| 2026-06-25 | Canvas `?` help popover reveals on hover (150 ms grace, click-to-pin), matching the notifications bell; extracted `CanvasHelpButton` — see [004](004-completeness-wave.md) | PR #507 |
| 2026-06-25 | Normal toolbar status item added to Canvas; Open on Code Host / Open Pull Request + palette PR entries route through the focused card — see [004](004-completeness-wave.md) | PR #509 |
| 2026-06-27 | Spatial card navigation with `⌘⌃`-arrows (`CanvasSpatialNavigation`, weighted 2D distance); the reducer redirects Default-view worktree selection into Canvas navigate commands while Canvas is active — see [004](004-completeness-wave.md) | PR #514 |

## Outcome & current state (as of 2026-07-12)

All verified in the working tree:

- **Pointer navigation** — `supacode/Features/Canvas/Views/CanvasSupportViews.swift`:
  `CanvasScrollCoordinator` (zoom entry point), `CanvasZoomMath`, `CanvasViewportMath`,
  `CanvasViewportAnimator`, and `CanvasScrollContainerView` whose local monitor matches
  `[.otherMouseDown, .otherMouseDragged, .otherMouseUp]` with `buttonNumber == 2`.
  The #229 revert holds: `hasScrollbackContent` no longer exists anywhere in
  `supacode/`.
- **Cards** — `supacode/Features/Canvas/Views/CanvasCardView.swift`: hover
  expand/restore + close (`xmark`) buttons with shortcut-bearing tooltips, and the
  shared `TerminalTabContextMenuActions` menu (#457). `AnimatedExpandableCard` and
  `CardScreenGeometry` (both in `CanvasSupportViews.swift`) plus
  `supacode/Features/Canvas/Models/CanvasExpandGeometry.swift` implement
  expand-in-place; the toolbar scrim flag `forceMaterialScrim` lives in
  `supacode/Domain/WindowChromeTint.swift` and is applied by
  `supacode/Features/Repositories/Views/WorktreeDetailView.swift`.
- **Layout & persistence** —
  `supacode/Features/Canvas/Models/CanvasCardLayout.swift`: `CanvasCardLayout` with
  `minDefaultSize`/`maxDefaultSize` and `adaptiveDefaultSize(forScreenWidth:)` (#401),
  `CanvasCardPacker`, and `CanvasLayoutStore` (#329). `CanvasTileLayout` in the same
  file is [043](../043-canvas-tile-layout/000-plan.md)'s work.
- **Focus & command routing** —
  `supacode/Features/Canvas/Models/CanvasFocusRequest.swift`: `CanvasFocusRequest`,
  `CanvasFocusCandidate`, `CanvasCommandRequest`, `CanvasFocusResolver`; request/consume
  actions (`focusCanvasWorktree`, `requestCanvasCommand`,
  `consumeCanvasCommandRequest`) in
  `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`; consumption in
  `supacode/Features/Canvas/Views/CanvasView+Focus.swift` / `CanvasView.swift`.
- **Action-target fallback** —
  `supacode/Features/App/Reducer/AppFeature+Support.swift`: `actionTargetWorktree`
  falls back to `canvasFocusedTerminalWorktree` (via
  `terminalClient.canvasFocusedWorktreeID()` when `isShowingCanvas`).
- **Keyboard** — `supacode/App/AppShortcuts.swift`: `arrangeCanvasCards` = `⌘⌥R`,
  `organizeCanvasCards` = `⌘⌥G`, `expandCanvasCard` = `⌘⌥E`.
  `supacode/Features/Canvas/Views/CanvasView.swift` mounts `.onKeyPress` handlers for
  escape (broadcast clear), select-all, arrange, organize, tile
  ([043](../043-canvas-tile-layout/000-plan.md)), and expand. `⌘⌃`-arrow navigation is
  *not* view-local: `RepositoriesFeature+CoreReducer.swift` redirects the worktree
  selection actions to `.requestCanvasCommand(.navigate(...))` when `isShowingCanvas`,
  fulfilled in `supacode/Features/Canvas/Views/CanvasView+Focus.swift` via
  `navigateCard(_:)`; `supacode/Features/Canvas/Models/CanvasSpatialNavigation.swift`
  holds the pure nearest-card logic.
- **Boot view** — `supacode/Features/Settings/Models/DefaultViewMode.swift` has
  `case canvas` (#337).
- **Help & toolbar** — `supacode/Features/Canvas/Views/CanvasHelpButton.swift` (#507);
  `WorktreeDetailView.swift` builds `canvasToolbarState`/`canvasToolbarContent`
  including the status item (#509) and the custom-action cluster (#362).
- **Tests** — `supacodeTests/`: `CanvasZoomMathTests`, `CanvasLayoutStoreTests`,
  `CanvasCardPackerTests`, `CanvasCardSizingTests`, `CanvasExpandGeometryTests`,
  `CanvasFocusResolverTests`, `CanvasSpatialNavigationTests`.
- **User docs** — `docs/components/canvas.md`, `docs/components/view-modes.md`.

## Deviations from plan

- #226's expand button was an acknowledged stopgap (exit Canvas to the tab view); it
  was replaced by the expand-in-place design in #402, so the original behavior no
  longer exists.
- The fixed default card size assumed by v1 and the early waves was retired by #401;
  `CanvasCardLayout.defaultSize` survives only as a transient fallback (kept at the max
  size).
- #514's PR description says arrow navigation is handled by four `.onKeyPress` handlers
  in `CanvasView`; a fix commit inside the same PR (`29de4e5f`) reworked it into the
  reducer→command channel described above, so the merged behavior matches the
  `CanvasCommandRequest` mechanism, not the PR body.

## Open questions

- PR #396 is listed as material for both this entry and
  [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md);
  it is logged here (Canvas-side routing) and should appear in 031 only as a
  cross-reference.
