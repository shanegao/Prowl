# 005 — Canvas (Live Sessions) v1: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-17 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #2, #6, #7, #8, #11, #43, #44, #54 |
| **Sources** | PR descriptions, commit history (`2c1d9aa`…`80df1b1`, `15bafd1`…`fc81375`, `38a6361`…`d9dde25`), fork change ledger ([upstream-ledger](../017-upstream-sync-process/upstream-ledger.md)) |
| **Related** | [009-terminal-surface-lifecycle](../009-terminal-surface-lifecycle/000-plan.md), [011-canvas-multiselect-broadcast](../011-canvas-multiselect-broadcast/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md), [043-canvas-tile-layout](../043-canvas-tile-layout/000-plan.md), `docs/components/canvas.md` |

## Background

Prowl's core use case is running many coding agents in parallel, one per worktree tab.
The normal view shows a single worktree at a time, so there was no way to *watch* all
agents at once — checking on sessions meant cycling through worktrees. The fork-only
answer was a free-form canvas showing every open terminal tab as a live card. The
feature was initially built as "Dashboard (Live Sessions)" and renamed to Canvas
mid-branch (commit `74b13c2`) before PR #2 merged.

This entry covers Canvas v1 only (2026-03-17 → 2026-03-25). Later interaction work is
[024](../024-canvas-interaction-evolution/000-plan.md), multi-select broadcast is
[011](../011-canvas-multiselect-broadcast/000-plan.md), the Tile layout is
[043](../043-canvas-tile-layout/000-plan.md), and the canvas-exit blank-surface
investigation that Canvas triggered is [009](../009-terminal-surface-lifecycle/000-plan.md).

## Goals

- Show **every open tab of every worktree** as a live, draggable, resizable card
  (per-tab cards, not per-worktree), rendering the tab's full split-pane layout.
- Cards host the *real* terminal surfaces — the same `GhosttySurfaceView` instances the
  tab view uses — so Canvas is a viewport, not a snapshot.
- Zooming the canvas must **not reflow terminals** (no PTY resize storm under scale).
- Navigation: cursor-anchored pinch zoom, two-finger scroll panning, fit-to-view.
- Arrange affordances: reset to a uniform grid (**Organize**) and a size-preserving
  compact packing (**Arrange**).
- Fast toggle (⌥⌘↩) with focus continuity in both directions: entering Canvas focuses
  the card for the previously active worktree+tab; exiting returns to the worktree+tab
  focused in Canvas.

**Non-goals** (deferred, later delivered elsewhere): multi-select + input broadcast
(011), viewport-filling tile layout (043), card z-order/layout-order persistence
refinements, hover controls and expand-in-place (024).

## Design / Approach

- **View layer** (`supacode/Features/Canvas/`): `CanvasView` renders cards positioned by
  `CanvasCardLayout` values held in `CanvasLayoutStore` (UserDefaults-backed, key
  `canvasCardLayouts`), so positions/sizes persist across launches. `CanvasCardView`
  draws one card: title bar (drag handle) plus the tab's live split tree.
- **Shared surfaces**: cards obtain the live views via
  `WorktreeTerminalState.surfaceView(for:)` and reparent them; per-tab focus, resize,
  and occlusion are managed per card. This one-surface-many-hosts design is what later
  made exit-blank reattachment bugs possible (see 009).
- **Reflow prevention**: an optional `pinnedSize` is threaded through
  `TerminalSplitTreeView` down to each leaf `GhosttySurfaceView`, keeping surface sizes
  fixed while the canvas is scaled with `.scaleEffect()`; card positioning uses offsets
  rather than `.position()` to keep zoom transforms out of terminal layout.
- **Gestures**: `CanvasScrollContainer` (an `NSViewRepresentable`) intercepts
  scroll-wheel events not consumed by a focused card and turns them into canvas panning;
  pinch zoom is anchored at the cursor (`CanvasZoomMath`); fit-to-view computes the
  scale/offset enclosing all cards (`CanvasViewportMath`).
- **Arrange packing**: Organize resets all cards to a uniform grid. Arrange preserves
  each card's size and packs positions compactly. The packer went through three
  algorithms in two days (waterfall columns → MaxRects-BSSF → exhaustive hybrid) — see
  Alternatives. Auto-arrange runs once per app session on first Canvas entry, and
  re-arms when all tabs are closed.
- **Toggle & focus restoration** (#11): reducer-level `toggleCanvas`; the terminal layer
  tracks `canvasFocusedWorktreeID` on `WorktreeTerminalManager` so the reducer can exit
  to the card the user focused. The ⌥⌘↩ shortcut is explicitly unbound in Ghostty so the
  terminal never swallows it.

## Alternatives & decisions

- **Arrange packer: MaxRects rejected for exhaustive search** (PR #8 branch). The first
  Arrange (#7) used waterfall/masonry columns; `15bafd1` replaced it with MaxRects-BSSF
  bin packing; within the same branch that was replaced again by an exhaustive
  evaluation of waterfall (1…N columns) and row-break (2^(N-1) masks, N ≤ 20) layouts,
  scoring each by the resulting fit-to-view scale and keeping the best. Decision: for
  N ≤ 20 cards, exhaustively optimizing the actual objective (on-screen scale) beats a
  bin-packing heuristic optimizing area.
- **Per-tab cards over per-worktree cards**: the initial branch showed one card per
  worktree; `e5992ea` (still pre-merge) switched to one card per open tab, which became
  the model everything later (broadcast, tile, spatial navigation) builds on.
- **Auto-arrange once per session, not on every entry** (`e698c1f`…`9aea73d`): manual
  positions are user data; automatic layout only runs when there is nothing worth
  preserving (first entry, or after all tabs were closed).
- **Canvas shortcut owned by the app, not Ghostty** (#11): ⌥⌘↩ is force-unbound in the
  embedded Ghostty config so toggling works while a terminal has focus.
- **Cmd+W keeps terminal close semantics inside Canvas** (#54): after an upstream sync
  added a window-level Close Window on Cmd+W, Canvas re-exposed focused
  close-surface/close-tab actions so the shortcut closes the focused pane/card, not the
  app window — see [002-cmd-w-close-semantics.md](002-cmd-w-close-semantics.md).

## Amendments

- Updated 2026-03-25: restore Cmd-W close-surface/close-tab semantics in Canvas after
  upstream's Close Window shortcut took over (#54) — see
  [002-cmd-w-close-semantics.md](002-cmd-w-close-semantics.md)
