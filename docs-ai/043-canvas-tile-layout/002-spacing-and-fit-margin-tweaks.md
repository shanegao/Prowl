# 043 / 002 — Spacing and Fit-Margin Tweaks

## Context

After three days of real use with Tile as the default Canvas layout (#504), the tiled
view still wasted margin: the 30pt `fitToView` padding and 50pt bottom toolbar reserve
were sized for the free-form layouts, and the 14pt tile gap read wider than needed once
several cards were on screen.

## Change

Two direct-to-main commits on 2026-06-27 (no PR; released in v2026.6.27), both in
`supacode/Features/Canvas/Views/CanvasView.swift`:

- `2a40fa0a` "tweak: tighten Canvas fit margins" — extracted the hardcoded 30pt
  fit-to-view padding into a named `viewportFitPadding` constant set to **12**, reduced
  `bottomToolbarReserve` 50 → **40**, and dropped `tileCardSpacing` 14 → 10. These fit
  margins apply to `fitToView` generally, i.e. to all three layouts, not just Tile.
- `abceefe1` "tweak: adjust Canvas tile spacing" — partially reverted the gap:
  `tileCardSpacing` 10 → **12**, the value in the tree today.

## Refs

- Commits `2a40fa0a`, `abceefe1` (main, 2026-06-27)

## Current state

`CanvasView` constants: `tileCardSpacing = 12`, `viewportFitPadding = 12`,
`bottomToolbarReserve = 40`, unchanged since. Layout algorithm and tests were not
affected (`CanvasTileLayout` takes spacing as a parameter).
