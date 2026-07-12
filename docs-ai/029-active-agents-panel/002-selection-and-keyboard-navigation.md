# 029 — Amendment: Selection & Keyboard Navigation (2026-05-24/25)

## Context

After the panel shipped (#274), selecting agents had two gaps: there was no keyboard
way to walk the list, and clicking a row produced a visible tab flip plus a wrong-agent
highlight flash. A third issue surfaced with plain folders (non-git directories, entry
[010](../010-plain-folder-support/000-plan.md)): tapping their rows treated the plain
repository id as a git worktree and selection failed.

## Change

**⌃⌥↑/↓ navigation (PR #335, 2026-05-24).** Two new user-customizable commands,
*Select Next Agent* / *Select Previous Agent*, registered across all binding tables in
`supacode/App/AppShortcuts.swift` and added to the sidebar menu. `ActiveAgentsFeature`
gained a `focusedSurfaceID` anchor, `selectNextEntry` / `selectPreviousEntry` /
`focusedSurfaceChanged` actions, and a pure `entryID(navigatingFrom:direction:in:)`
helper (step + wrap-around; ↓ starts at the first entry and ↑ at the last when the
anchor is not in the list). Navigation re-dispatches the existing `entryTapped` flow so
no jump logic is duplicated. ⌃⌥ was chosen because ⌘⌥↑↓ (split panes) and ⌃⌘↑↓
(worktrees) were taken.

**Selection flicker fix (PR #336, 2026-05-24).** Selecting an entry had merged
`selectWorktree` and `focusSurface` effects; selection landed first, so the worktree
appeared showing its previously-focused tab before the focus switched — a visible tab
flip, and the panel highlight flashed the wrong agent. An earlier mask in #335 (reading
the reducer's focus anchor) failed for mouse clicks because `focusChanged` events are
deduplicated per worktree, leaving the anchor stale. The fix reorders at the source in
`RepositoriesFeature.entryTapped`: `focusSurface` first (pre-selects the target tab
while the worktree is still invisible), then `selectWorktree(focusTerminal: true)`.
`ActiveAgentsPanel`'s dimming logic reverted to plain `selectedSurfaceID`;
`focusedSurfaceID` remains keyboard-navigation-only.

**Plain-folder selection (PR #344, 2026-05-25, fixes #342).** Row activation for
agents running in plain folders now selects the plain repository instead of treating
its id as a git worktree, preserving the surface-first focus ordering from #336.

## Refs

- PR #335 (merged 2026-05-24), PR #336 (merged 2026-05-24), PR #344 (merged 2026-05-25)
- Tests: `ActiveAgentsFeatureTests` (step/wrap/empty-list/anchor),
  `RepositoriesFeatureTests` (focus-before-select ordering; plain-folder regression)

## Current state

`entryID(navigatingFrom:direction:in:)` and the anchor logic live in
`supacode/Features/ActiveAgents/Reducer/ActiveAgentsFeature.swift`; the shortcut ids
are `select_next_active_agent` / `select_previous_active_agent` in
`supacode/App/AppShortcuts.swift`. The `entryTapped` handling (focus-before-select
ordering, plain-folder branch) has moved to
`supacode/Features/Repositories/Reducer/RepositoriesFeature+CoreReducer.swift` in the
reducer split (see [015-repositories-feature-refactor](../015-repositories-feature-refactor/000-plan.md)),
and now also handles Canvas-mode focus.
