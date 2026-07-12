# 043 — Canvas Tile Layout: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-06-24 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #502, #504 |
| **Sources** | `doc-onevcat/plans/2026-06-24-canvas-tile-layout-plan.md` (absorbed here; original removed in the docs-ai migration), PR descriptions |
| **Related** | [005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md), `docs/components/canvas.md`, `docs/reference/settings-fields.md` |

## Background

Canvas ([005](../005-canvas-live-sessions/000-plan.md)) had two auto-layouts, both
triggered from the toolbar, keyboard shortcuts, and the command palette
([024](../024-canvas-interaction-evolution/000-plan.md) added the shortcut/palette
wiring):

| Mode | Shortcut | Card size | Algorithm |
| --- | --- | --- | --- |
| **Organize** | ⌘⌥G | uniform default size (`adaptiveDefaultCardSize`) | √N balanced grid |
| **Arrange** | ⌘⌥R | preserves each card's current size | `CanvasCardPacker` hybrid bin-packing |

Both place cards in the infinite canvas coordinate space and rely on
`fitToView(canvasSize:)` to scale/center the group into the viewport. Neither fills
the screen: Organize uses a fixed card size, Arrange keeps whatever sizes cards have,
so with a handful of cards much of the viewport is empty. For the "watch all agents at
a glance" use case, users wanted an automatic-window-manager-style layout that gives
every card as much area as possible.

## Goals

- A third layout, **Tile** (⌘⌥T, toolbar icon `rectangle.split.2x1`), that **resizes
  every card** so the set tiles and fills the visible canvas.
- Balanced grid whose orientation follows the window: `s = max(1, floor(√N))` lines on
  the short axis; wide window → lines are rows, tall window → lines are columns
  (a pure transposition). Extra cards go to the later lines
  (`lineCounts`: first `s - rem` lines get `base`, last `rem` lines get `base + 1`).
- Each line independently fills its full extent — a 2-card row gets ½-width cards, a
  3-card row ⅓-width — so card sizes may differ between lines by design.
- All three trigger paths (toolbar button, shortcut, command palette) behave
  identically, reusing the arrange/organize infrastructure; the shortcut is
  rebindable/disableable in Settings.
- Readability at higher card counts: adaptive zoom so surfaces keep a comfortable
  terminal grid instead of showing huge text in tiny cards (v2 of the plan, added in
  response to "text too large, gaps too wide" feedback on the initial fixed-scale cut).

**Non-goals**: aspect-aware line-count tuning for extreme ratios (e.g. a 32:9 screen
still tiles 4 cards as 2×2, not 1×4) — noted as a possible later enhancement via
candidate scoring in `lineCounts`, deliberately out of scope to keep the deterministic
balanced-grid shape.

## Design / Approach

- **Pure layout core** — `CanvasTileLayout` in
  `supacode/Features/Canvas/Models/CanvasCardLayout.swift`, next to
  `CanvasCardPacker`: `static lineCounts(for:)` plus
  `layout(keys:viewport:comfortableSize:)` returning `[String: CanvasCardLayout]`.
  Testable without `@MainActor`. Row geometry divides the viewport minus spacing by
  the line count; the title bar height is subtracted so the *visual* card (title bar +
  terminal) tiles exactly. Empty keys or a degenerate viewport return an empty dict.
- **No min/max clamping**: tile card size is the frame divided by the grid; clamping
  to `minCard*`/`maxCard*` would only create overlap in small windows. Those bounds
  govern manual resize and default new-card sizing, not tiling. Small windows produce
  small cards; visual scaling stays `fitToView`'s job.
- **Adaptive zoom** (v2): the grid is laid out in a `viewport × zoom` frame so
  `fitToView` lands at `scale ≈ 1/zoom`. `zoom = 1` while tiled cards are at least
  `comfortableSize` (`adaptiveDefaultCardSize × 0.6`) — a handful of cards keeps
  native scale; beyond that, `zoom` grows so each surface keeps a readable terminal
  (more rows/columns, smaller text). Spacing uses a tighter `tileCardSpacing`
  (plan: 14 vs. the 20pt `cardSpacing`) living in the scaled frame, so the on-screen
  gap (`spacing × scale`) also tightens as counts rise. `fitToView` clamps scale to
  `[0.25, 1.0]`, so extreme counts degrade gracefully.
- **Triggers**: `tileCards()` / `tileCardsWithFit()` in
  `supacode/Features/Canvas/Views/CanvasView.swift` mirroring the organize/arrange
  pair; `.onKeyPress` handler; toolbar button; `CanvasCommandRequest.Command.tile`
  handled in `CanvasView+Focus.swift`; `AppShortcuts.tileCanvasCards`
  (`tile_canvas_cards`, ⌘⌥T — verified free among ⌘⌥ bindings) and the full
  command-palette registration ("Tile Canvas Cards").
- **Docs in the same PR**: `docs/components/canvas.md`,
  `docs/reference/keyboard-shortcuts.md`.

### Default-layout setting (follow-up, same day)

Canvas's one-shot initial auto-layout (first entry per session, see 005) was hardcoded
to the size-preserving pack. #504 makes it configurable: a `CanvasDefaultLayout` enum
(`uniform` = same-size packed to fit, i.e. the previous behavior; `tile` = the new
layout), stored in `GlobalSettings` (`canvasDefaultLayout`), surfaced as a "Canvas
layout" picker in Settings → General → Default Views alongside "Launch in". **Default
is `tile`**, including for legacy `settings.json` without the key — an intentional
behavior change (the old default was never a promise). Saved card positions are still
restored regardless of the setting.

## Alternatives & decisions

- **Viewport-derived sizes vs. existing modes**: Organize fixes size, Arrange preserves
  size; Tile derives size from the viewport — that inversion is the point of the third
  mode rather than tweaking either existing one.
- **Binary orientation flip only** (`W ≥ H`): keeps the documented deterministic
  shapes (2 → halves, 5 → 2+3, 9 → 3×3); aspect-aware `s` selection rejected for now.
- **Fixed scale = 1 rejected after review feedback**: replaced by the adaptive-zoom
  frame; native scale is preserved for few cards, degradation is smooth for many.
- **Reuse `fitToView` instead of custom tile scaling**: the tile bounding box matches
  the viewport aspect ratio, so the existing `min(W/bboxW, H/bboxH)` fit is exact.
- **Naming kept as Tile/Uniform** (#504): "Tile" matches the existing toolbar button
  and docs; the size-preserving initial layout is called "Uniform" in Settings without
  renaming any button.
- **Tile as the new default layout** (#504): judged the better default for most
  fleets; legacy settings intentionally migrate to it via decode fallback.

## Amendments

- Updated 2026-06-27: visual tuning after real use — `tileCardSpacing` 14 → 12,
  fit-to-view padding 30 → 12 (`viewportFitPadding`), `bottomToolbarReserve` 50 → 40 —
  see [002-spacing-and-fit-margin-tweaks.md](002-spacing-and-fit-margin-tweaks.md)
