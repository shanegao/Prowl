# 031 — Amendment: Post-buildout fixes (Canvas focus, color-scheme flicker)

## Context

Two independent palette fixes landed in June 2026, after the May buildout settled.

## Change

**Canvas card focus (#396, 2026-06-05).** Selecting a worktree from the palette
while Canvas mode was active left Canvas and performed a Normal-mode selection.
The `selectWorktree` delegate handler now stays inside Canvas: when
`repositories.isShowingCanvas`, it routes to
`RepositoriesFeature.Action.focusCanvasWorktree` (or `focusCanvasRepository` for
plain folders) instead of `selectWorktree`. Covered by `AppFeature` tests for both
worktree and plain-folder selections in Canvas.

**Color-scheme flicker on first open (#421, 2026-06-08).** In Light mode the
palette's first frame briefly rendered dark. Root cause: `CommandPaletteCard`
forced a color scheme computed from `NSColor.windowBackgroundColor.isLightColor`
inside `body`; that dynamic catalog color resolves against the current drawing
appearance context, which is not settled on the first render. Fix: drop the forced
override and inherit the ambient `@Environment(\.colorScheme)` (correct on first
render, reactive to appearance changes); the now-unused `isLightColor` NSColor
extension was removed. An intermediate attempt using `NSApp.effectiveAppearance`
was rejected — it reads the app/system appearance, not the window's.

## Refs

- PR #396 — Focus canvas cards from command palette
- PR #421 — Fix command palette color-scheme flicker on first open

## Current state

Both fixes verified in the tree as of 2026-07-12: the Canvas routing lives in
`reduceCommandPaletteNavigationDelegate`
(`supacode/Features/App/Reducer/AppFeature+CommandPalette.swift`), and no
`isLightColor` helper or forced card scheme remains in
`supacode/Features/CommandPalette/Views/CommandPaletteOverlayView.swift` (only the
intentional selected-row dark override via `transformEnvironment(\.colorScheme)`).
