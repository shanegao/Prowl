# 027 — Split Pane UX: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-04 | Dim unfocused split panes: scheme-adaptive overlay, `dimUnfocusedSplits` toggle (default on), `focusedSurfaceID` wired through tab/Shelf/Canvas hosts, divider softened to `NSColor.separatorColor` | PR #253 |
| 2026-05-08 | Tint sourced from Ghostty config (`unfocused-split-fill` / `unfocused-split-opacity`); shared active-surface path for click and explicit split focus; overlays refresh on Ghostty config reload | PR #258 (upstream ref: upstream #260) |
| 2026-05-12 | Honor `split-divider-color`; fork-only `prowl-split-divider-width` parsed from the primary Ghostty config file, clamped 0…32 pt; `dividerVisibleSize` argument on `SplitView` | PR #279 (closes #278) |
| 2026-06-10 | Split-zoom UX wave: per-pane zoom buttons, `⌘⌥⇧F` → `toggle_split_zoom`, palette focus-race fix | PR #435 — see [002-split-zoom-ux.md](002-split-zoom-ux.md) |

## Outcome & current state (as of 2026-07-12)

Verified against the working tree:

- `supacode/Infrastructure/Ghostty/GhosttyRuntime.swift` — the config surface:
  `unfocusedSplitOverlayOpacity()` (reads `unfocused-split-opacity`, default
  0.85, inverted and clamped to 0…1), `unfocusedSplitFill()` (reads
  `unfocused-split-fill`, falls back to `background`, warns and returns `nil`
  if both are missing), `splitDividerColor()` (reads `split-divider-color`),
  and `splitDividerWidth()` backed by the `nonisolated static
  parseProwlSplitDividerWidth` parser (skips comments, last assignment wins,
  clamps to 0…32 pt).
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift` —
  `unfocusedSplitOverlay()` and `splitDividerAppearance()` expose both tuples
  to the view layer, returning inert values when the runtime is absent.
- `supacode/Features/Terminal/Views/TerminalSplitTreeView.swift` — `LeafView`
  computes `shouldDim` (`isSplit && !isFocused && dimUnfocusedSplits` setting
  `&& fill != nil && opacity > 0`) and applies the fill overlay with a 0.12 s
  ease-out animation, hit-testing disabled. The settings toggle is read via
  `@Shared(.settingsFile)`.
- `supacode/Features/Terminal/Views/SplitView.swift` — `dividerVisibleSize:`
  init argument defaulting to `Self.defaultVisibleSize`, fed from
  `splitDivider.width` in `TerminalSplitTreeView`.
- `supacode/Features/Settings/Models/GlobalSettings.swift` —
  `dimUnfocusedSplits` (default `true`, decode-tolerant);
  `supacode/Features/Settings/Views/AppearanceSettingsView.swift` hosts the
  toggle; `supacode/Features/Settings/Reducer/SettingsFeature.swift` round-trips
  it.
- All three hosts read both appearance tuples per render:
  `supacode/Features/Terminal/Views/WorktreeTerminalTabsView.swift`,
  `supacode/Features/Shelf/Views/ShelfOpenBookView.swift`,
  `supacode/Features/Canvas/Views/CanvasView.swift`.
- Tests: `supacodeTests/GhosttyRuntimeSplitDividerWidthTests.swift` and
  `supacodeTests/SplitTreeTests.swift` exist.
- User-facing docs: `docs/reference/settings-fields.md` documents
  `dimUnfocusedSplits`; `docs/components/terminal.md` and
  `docs/reference/keyboard-shortcuts.md` document the split-zoom UX.

## Deviations from plan

- The #253 hardcoded scheme-adaptive tint (black at 0.30 dark / 0.12 light) no
  longer exists — #258 replaced it with the Ghostty-config-driven fill/opacity
  four days later, as recorded in the timeline.
- #253's divider color (`NSColor.separatorColor`) survives only as the
  fallback in #279's `split-divider-color` path.

## Open questions

- The upstream ledger records upstream #260 (inactive split dimming) under
  "Reviewed and skipped", while PR #258 explicitly cites upstream #260
  (supabitapp/supacode@4d19b068) as its reference. The ledger label undersells
  that #258 aligned the fork with it; bookkeeping-only inconsistency, no code
  impact.
