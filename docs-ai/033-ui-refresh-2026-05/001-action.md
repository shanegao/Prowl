# 033 — UI Refresh 2026-05: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-07 | Precursor: tint `window.backgroundColor` by appearance (dark ⇒ black @ 0.7 alpha) to counteract macOS 26's white-biased glass on non-opaque windows (fixes #163) | PR #168 |
| 2026-04-07 | Precursor: sidebar footer gets a `.regularMaterial` background when `background-opacity < 1` (wallpaper no longer bleeds through unblurred) | PR #169 |
| 2026-05-21 | Toolbar title hover layout shift fixed by pinning `WorktreeDetailTitleView` to `.navigation` and `ToolbarStatusView` to `.principal` (community fix by abhi21git, superseding closed fork attempt #324) | PR #326 |
| 2026-05-22 | Community "Major UI Enhancements" by abhi21git: single commit `13fc410d`, 20 files — tab bar, sidebar switcher, find-overlay redesign, command palette polish, Active Agents rows, Add Repository moved to sidebar toolbar, loading indicator replacement; fixes issues #311/#315/#317 | PR #331 |
| 2026-05-22..24 | Fork review on `feat/ui-enhancements` (21 commits on top of `13fc410d`): revert tab reshape and adopt #327 brightness ladder (`d027ea7a`); floating glass tabs, centered titles, full-width tabs, leading-edge hover close (`36a15ce9`, `76d0c0d3`, `a15ba291`); tab/terminal gap + dark-mode brightness (`3322606b`), tint across bottom gap (`41f49043`); sidebar switcher as fixed top bar (`85067862`), restore Expand/Collapse All (`b47be417`), brighten nav picker track (`09e9173c`); `WindowTintMode` chrome tint setting (`51af064e`), Shelf chrome tinted by open repo color (`64a79615`), custom (free) repository color (`8dc41bc3`), Canvas toolbar untinted (`5cfad79c`), solid repo color dot on focus loss (`6bfe1685`); restore bagua working indicator (`b6e8d3f2` + `7e558ef0`); zero-repo empty state (`18de41f2`), settings min width 800 (`eecdda08`), xcsift warnings in `build-app` (`0ca9bc9f`) | PR #332 (merges #331) |
| 2026-05-25 | Fullscreen toolbar tint: explicit toolbar background only during fullscreen enter/steady/exit, resolved from Prowl's appearance (not the launch-time system appearance), stable across toolbar host detach/reattach; regression tests | PR #343 |
| 2026-06-17 | Toolbar icon hover fix by Alex-ai-future | PR #467, [002-toolbar-icon-fixes.md](002-toolbar-icon-fixes.md) |

Later work by the same contributors landed in other entries: Alex-ai-future's #532/#539
(PR status polish → [028](../028-pr-status-tracking/000-plan.md)) and #540 (diff window
appearance → [003](../003-diff-window/000-plan.md)).

## Outcome & current state (as of 2026-07-12)

Chrome tint (the lasting architectural piece):

- `supacode/Domain/WindowChromeTint.swift` — unified tint resolution (`Fill`,
  `saturatedPeakAlpha` 0.20 / `neutralPeakAlpha` 0.10), plus the #343 fullscreen
  machinery: `ToolbarFallbackEvent`, `usesExplicitToolbarBackground(isFullScreen:)`,
  `toolbarFallbackState(current:event:)`, `fullscreenToolbarBackgroundComponents`, and
  a `WindowFullScreenReader` observing window fullscreen state.
- `supacode/Features/Settings/Models/WindowTintMode.swift` —
  `none` / `repositoryColor` / `custom`, raw-string persisted; setting UI in the
  "Window Tint" section of `supacode/Features/Settings/Views/AppearanceSettingsView.swift`;
  fields documented in `docs/reference/settings-fields.md` (`windowTintMode`,
  `windowTintCustomColor`).
- Render sites: `supacode/Features/Repositories/Views/WorktreeDetailView.swift`
  (nav/toolbar bands), `supacode/Features/Terminal/TabBar/Views/TerminalTabBarView.swift`,
  `supacode/Features/Shelf/Views/ShelfView.swift` / `ShelfSpineView.swift`,
  `supacode/Features/Terminal/Views/WorktreeTerminalTabsView.swift`.
- `supacode/Domain/RepositoryColorChoice.swift` — `case custom(TintColor)` from
  `8dc41bc3` is still the free-color escape hatch (presets keep legacy encoding; see
  [025](../025-repo-identity-appearance/001-action.md)).

Tab bar:

- `supacode/Features/Terminal/TabBar/TerminalTabBarColors.swift` — the #327 adaptive
  brightness ladder, with the dark-mode rationale preserved in comments;
  `TerminalTabBarMetrics.swift` and `Views/` (`TerminalTabView.swift`,
  `TerminalTabCloseButton.swift`, `TerminalTabBarBackground.swift`, ...) carry the
  floating-glass look and leading-edge hover close.

Toolbar and sidebar:

- #326's placement fix is current: `WorktreeDetailView.swift` puts
  `WorktreeDetailTitleView` in `ToolbarItem(placement: .navigation)` and
  `ToolbarStatusView` in `.principal`.
- `supacode/Features/Repositories/Views/SidebarListView.swift` — fixed view-mode
  switcher top bar; `EmptyStateView.swift` + `SidebarListView.swift` carry the
  zero-repo empty state (`18de41f2` also forces Normal view at zero repositories).
- Settings window minimum 800×500 in
  `supacode/Features/Settings/Views/SettingsView.swift` and
  `SettingsWindowManager.swift`.

Precursors' descendants:

- #168 lives on as `GhosttyRuntime.chromeBackgroundColor(for:)`
  (`supacode/Infrastructure/Ghostty/GhosttyRuntime.swift`), applied in
  `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift` for non-opaque windows.
- #169's `.regularMaterial` footer **no longer exists**: the refresh's sidebar/chrome
  rework superseded it — `supacode/Features/Repositories/Views/SidebarFooterView.swift`
  now derives its background from the `surfaceBottomChromeBackgroundOpacity`
  environment value.
- #331's redesigned find overlay now lives at
  `supacode/Features/Terminal/Views/GhosttySurfaceSearchOverlay.swift`.

Tests: `supacodeTests/WindowChromeTintTests.swift` (tint resolution + fullscreen
fallback) and `supacodeTests/BaguaWorkingIndicatorTests.swift` (post-revert indicator).

## Deviations from plan

- Relative to #331 as proposed, three pieces were deliberately reverted or replaced
  before merge (tab bar reshape, loading indicator, Expand/Collapse All removal) — that
  is the review-branch design working as intended, recorded in 000-plan.
- The #331 body's "Moved Add repository to sidebar toolbar" overlaps the earlier #254
  work; the entry point's evolution is tracked in
  [026](../026-sidebar-container-refactor/002-add-repository-entry-point.md), not here.

## Open questions

- The backfill outline attributed the whole refresh to Alex-ai-future; GitHub records
  show #326/#331 authored by **abhi21git** and only #467 by **Alex-ai-future**. This
  entry follows the GitHub data.
