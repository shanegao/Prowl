# 024.003 — Keyboard & Layout Wave (#393–#396, #400–#402)

## Context

A concentrated two-day burst (2026-06-05 → 06-06) attacked the remaining "leaves Canvas
when it shouldn't" paths and the visual quality of card layout. Multi-agent keyboard
flow was interrupted by mouse-only layout buttons (fork issue #392); New Tab created
tabs in the *Normal-selected* worktree rather than the focused card; clicking sidebar
rows, Active Agents entries, or palette results silently exited Canvas; Organize/Arrange
animated the card chrome but snapped the terminal content; the fixed default card size
made text unreadably small on 14" screens after fit-to-view; and "expand" still meant
leaving Canvas.

## Change

- **#393 — Arrange/Organize shortcuts.** `⌘⌥R` (Rearrange) and `⌘⌥G` (Grid) join the
  Canvas `⌘⌥` family (`Cmd+Shift+R` was taken by `refreshWorktrees`). Registered in
  `supacode/App/AppShortcuts.swift` with `.localInteraction` scope, so they enter the
  keybinding schema user-rebindable; grouped with Canvas actions in
  `ShortcutsSettingsView`. Handled by `.onKeyPress` inside `CanvasView.body` — mounted
  only while Canvas is visible — with shared `arrangeCardsWithFit()` /
  `organizeCardsWithFit()` helpers used by both buttons and keys; button tooltips show
  the shortcut via `AppShortcuts.helpText`.
- **#394 — New tab target fix.** New Terminal/New Tab route through the active
  terminal target so Canvas creates tabs in the focused card's worktree; Ghostty
  terminal commands appear in the command palette when Canvas has a focused action
  target.
- **#395 — Sidebar navigation stays in Canvas.** Clicking sidebar repo/worktree/folder
  rows or Active Agents entries no longer exits Canvas: they emit Canvas focus requests
  that create a missing card when needed, select/cycle matching cards, and
  center/scale the focused card. Introduces `CanvasFocusRequest`/`CanvasFocusCandidate`
  and the pure `CanvasFocusResolver`
  (`supacode/Features/Canvas/Models/CanvasFocusRequest.swift`).
- **#396 — Palette card focus.** Command palette worktree/plain-folder selection routes
  to `focusCanvasWorktree` / `focusCanvasRepository` instead of Normal selection while
  Canvas is active (palette internals belong to
  [031](../031-command-palette-architecture/000-plan.md)).
- **#400 — Resize animation.** The Canvas terminal subtree's pinned size animates
  during card resize transitions and non-interactive refits (Organize/Arrange), keeping
  terminal content in sync with the title bar; the explicit size animation is disabled
  while a drag-resize gesture is active so interactive resize stays immediate.
- **#401 — Adaptive default card size.** `CanvasCardLayout.adaptiveDefaultSize(forScreenWidth:)`
  interpolates 800×550 (≤1512 pt) → 1000×680 (≥2560 pt), clamped; wired into
  `ensureLayouts` (new cards) and `organizeCards` (uniform grid). Smaller cards on
  small screens raise the fit-to-view scale so text renders larger. Covered by
  `CanvasCardSizingTests`.
- **#402 — Expand a card in place (magic-move).** Replaces the expand-to-tab-view
  stopgap from #226. The focused card raises to the top and animates alone from its
  in-canvas frame to scale 1 covering the viewport; the canvas transform is never
  mutated, so the background stays frozen behind a dimmed/blurred scrim while other
  cards keep running. Restore via button toggle, scrim tap, or title-bar double-click;
  Arrange/Organize cancel the expansion; pan/pinch/scroll/middle-drag are locked while
  expanded. Driven by `AnimatedExpandableCard` (`Animatable`, `animatableData =
  progress`) so size/center/scale interpolate per frame and the terminal reflows in
  lock-step. Adds `⌘⌥E`, Canvas-only palette entries (Expand/Restore, Arrange,
  Organize, Select All) routed via the one-shot `CanvasCommandRequest`
  (reducer-requested, `CanvasView`-consumed), the `forceMaterialScrim` toolbar flag,
  and `CanvasExpandGeometry` (+ tests).

## Refs

- PRs #393, #394, #395, #396, #400, #401, #402 (all merged 2026-06-05/06)
- Fork issue #392 (layout shortcuts)

## Current state

All named types verified in the tree: `AppShortcuts.arrangeCanvasCards` /
`organizeCanvasCards` / `expandCanvasCard`; `CanvasFocusRequest.swift` (including
`CanvasCommandRequest` and `CanvasFocusResolver`); `CanvasExpandGeometry.swift`;
`AnimatedExpandableCard` in `CanvasSupportViews.swift`; `adaptiveDefaultSize` in
`CanvasCardLayout.swift`; `arrangeCardsWithFit()` / `organizeCardsWithFit()` and the
shortcut `.onKeyPress` handlers in `CanvasView.swift` (the set has since grown a tile
handler from [043](../043-canvas-tile-layout/000-plan.md)). Tests:
`CanvasCardSizingTests`, `CanvasExpandGeometryTests`, `CanvasFocusResolverTests`.
