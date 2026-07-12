# 043 — Canvas Tile Layout: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-24 | Tile layout shipped: `CanvasTileLayout` (`lineCounts` + `layout`), `tileCards()`/`tileCardsWithFit()`, toolbar button (`rectangle.split.2x1`), ⌘⌥T key handler, `CanvasCommandRequest.tile`, full shortcut + command-palette wiring, `CanvasTileLayoutTests`, docs (`7c12d1fb`) | PR #502 |
| 2026-06-24 | Adaptive zoom added within the same PR: grid laid out in a `viewport × zoom` frame, `comfortableSize = adaptiveDefaultCardSize × 0.6`, tighter `tileCardSpacing = 14`; native/adaptive-zoom tests (`c751f8c9`) | PR #502 |
| 2026-06-24 | `canvasDefaultLayout` setting (Uniform / Tile, default `tile` incl. legacy decode fallback); "Default Views" pickers with descriptions in Settings → General; initial Canvas auto-layout branches on it (`7de630da`, copy simplification `dcf4c8dd`) | PR #504 |
| 2026-06-27 | Direct-to-main visual tuning: `tileCardSpacing` 14 → 10 → 12, fit padding 30 → `viewportFitPadding` 12, `bottomToolbarReserve` 50 → 40 (`2a40fa0a`, `abceefe1`) | [002](002-spacing-and-fit-margin-tweaks.md) |

## Outcome & current state (as of 2026-07-12)

- `supacode/Features/Canvas/Models/CanvasCardLayout.swift`: `CanvasTileLayout`
  (`spacing`, `titleBarHeight`; `static lineCounts(for:)`;
  `layout(keys:viewport:comfortableSize:)`), sitting next to `CanvasCardPacker` as
  planned. No min/max clamping, empty result for empty keys or non-positive viewport.
- `supacode/Features/Canvas/Views/CanvasView.swift`: `tileCards()` derives
  `comfortableSize` from `adaptiveDefaultCardSize × 0.6`; `tileCardsWithFit()` wraps it
  with `cancelExpandForRelayout()` + `fitToView` in a 0.2s ease-in-out animation,
  matching the arrange/organize pattern. Constants today: `tileCardSpacing = 12`
  (vs. `cardSpacing = 20`), `viewportFitPadding = 12`, `bottomToolbarReserve = 40`
  (post-[002](002-spacing-and-fit-margin-tweaks.md) values). The toolbar button uses
  `rectangle.split.2x1`; the ⌘⌥T `.onKeyPress` handler resolves
  `AppShortcuts.tileCanvasCards`.
- `fitToView` scale clamp `[0.25, 1.0]` lives in `CanvasViewportMath`
  (`supacode/Features/Canvas/Views/CanvasSupportViews.swift`).
- Command path: `CanvasCommandRequest.Command.tile` in
  `supacode/Features/Canvas/Models/CanvasFocusRequest.swift`, fulfilled in
  `supacode/Features/Canvas/Views/CanvasView+Focus.swift`; `tile_canvas_cards` /
  ⌘⌥T in `supacode/App/AppShortcuts.swift`; "Tile Canvas Cards" palette item
  (`globalTileCanvasCards` in
  `supacode/Features/CommandPalette/Reducer/CommandPaletteSupport.swift` and the
  related palette files); listed in
  `supacode/Features/Settings/Views/ShortcutsSettingsView.swift`.
- Default layout: `supacode/Features/Settings/Models/CanvasDefaultLayout.swift`
  (`uniform`/`tile` with titles and settings descriptions);
  `GlobalSettings.canvasDefaultLayout` (default `.tile`, legacy fallback via
  `decodeViewSettings`) in `supacode/Features/Settings/Models/GlobalSettings.swift`;
  picker in `supacode/Features/Settings/Views/AppearanceSettingsView.swift`
  ("Default Views" section of the General tab). `CanvasView`'s one-shot initial layout
  switches `arrangeCards()` vs `tileCards()` on it; saved layouts still short-circuit
  via `shouldAutoArrangeOnInitialEntry(for:)`.
- Tests: `supacodeTests/CanvasTileLayoutTests.swift` covers `lineCounts` (N = 1…10 and
  sum invariant), wide/tall orientation flip, top-2/bottom-3 for N = 5, non-overlap,
  full-width rows, native vs. adaptive zoom, and exact small-viewport tiling without
  clamping. Settings coverage in `supacodeTests/SettingsFilePersistenceTests.swift`
  (legacy payload → `.tile`) and `supacodeTests/SettingsFeatureTests.swift`
  (binding persists to the settings file).
- User-facing docs: `docs/components/canvas.md` (⌘⌥T Tile Cards),
  `docs/reference/keyboard-shortcuts.md` (`tile_canvas_cards`),
  `docs/reference/settings-fields.md` and `docs/components/view-modes.md`
  (`canvasDefaultLayout`).

## Deviations from plan

- Tuning constants moved after ship: `tileCardSpacing` 14 → 12, fit padding 30 → 12,
  bottom reserve 50 → 40 ([002](002-spacing-and-fit-margin-tweaks.md)). The plan's
  spacing-derivation reasoning (`14 × scale`) still holds with 12.
- An earlier draft of the plan's test list mentioned verifying min/max clamping at tiny
  viewports, while the final algorithm section decided *against* clamping; the shipped
  test asserts the opposite (`smallViewportTilesExactlyWithoutClamping`), consistent
  with the no-clamp decision.
- Otherwise the implementation follows the plan's file-by-file change list closely.

## Open questions

- None.
