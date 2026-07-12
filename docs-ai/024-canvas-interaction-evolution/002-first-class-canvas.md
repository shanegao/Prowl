# 024.002 — Canvas as a First-Class View (#329, #337, #362)

## Context

By late May 2026, Canvas navigation felt good but the mode was still a guest in its own
app: card positions reset on every launch (an auto-arrange ran on first Canvas entry
and clobbered whatever the user had built), the Default View setting only offered
Normal and Shelf, and the toolbar's Run Script / Custom Commands cluster
([002-custom-commands](../002-custom-commands/000-plan.md)) was inert in Canvas — using
a custom action meant leaving the view.

## Change

- **#329 — persist card layout order** (fixes fork issue #328, 2026-05-24). Saved card
  positions are preserved on first Canvas entry after launch instead of being
  auto-arranged over; card z-order persists and focused cards are brought to front. The
  previous `UserDefaults` layout dictionary format is migrated. `CanvasLayoutStore`
  (in `supacode/Features/Canvas/Models/CanvasCardLayout.swift`) owns the persistence,
  with dedicated `CanvasLayoutStoreTests`.
- **#337 — Canvas in Default View** (2026-05-25). `DefaultViewMode` gains `.canvas`;
  the Appearance settings picker and `Codable` persistence pick it up via
  `CaseIterable`/`Codable`. On non-Layout-Restore launches `RepositoriesFeature`
  dispatches `.toggleCanvas` after the initial repository snapshot; on Layout-Restore
  launches `AppFeature` enters Canvas on `.layoutRestored` *after* selection effects so
  `.selectCanvas` records the just-selected worktree as the pre-Canvas anchor. With no
  worktree rows it falls back to Normal, mirroring Shelf's guard.
- **#362 — Canvas custom actions + toolbar refinements** (2026-05-28). Carries
  community PR #358 by vince-hz (fixes fork issue #357): Run Script / Stop Script /
  Custom Commands route through the focused Canvas card, per-repo settings sync as
  focus moves between cards, and the actions surface in toolbar/menu/palette. Fork
  refinements on top: the toolbar honors `showRunButtonInToolbar`; repository + user
  settings apply in a single reduce pass on `canvasFocusedWorktreeChanged` (shared
  `applyWorktreeSettings` helpers, reused by the normal selection path); and the Run +
  Custom Command cluster renders as a single `ToolbarItem { HStack }` to stop NSToolbar
  from animating per-item insert/remove when switching between cards with different
  command counts (documented in-code as an intentional divergence from the Normal
  toolbar).

## Refs

- PR #329, PR #337, PR #362 (supersedes community #358)
- Custom command semantics: [002-custom-commands](../002-custom-commands/001-action.md)

## Current state

- `CanvasLayoutStore` and its tests exist as described.
- `supacode/Features/Settings/Models/DefaultViewMode.swift` has `case canvas`.
- The Canvas toolbar is built by `canvasToolbarState`/`canvasToolbarContent` in
  `supacode/Features/Repositories/Views/WorktreeDetailView.swift`; focused-card action
  routing now goes through the generalized `actionTargetWorktree` fallback in
  `supacode/Features/App/Reducer/AppFeature+Support.swift` (see
  [001-action.md](001-action.md)).
