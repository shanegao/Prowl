# 018 — Amendment: Archived Button Toggle (#512)

## Context

Entering the Archived Worktrees view had no obvious way out: the sidebar footer button
only navigated *into* the view, so users had to click a different worktree or repository
to leave, with no visual feedback that they were "inside" the archived view. Canvas and
Shelf already behaved as toggles; the archived button was the odd one out. Community
contribution by Alex-ai-future, merged with one review-feedback round.

## Change

- `RepositoriesFeature.State` gained `preArchivedWorktreeID` to remember the selection
  before entering the archived view.
- `selectArchivedWorktrees` became a toggle: when already showing archived worktrees it
  restores the previous worktree (re-opening it and queuing terminal focus via
  `pendingTerminalFocusWorktreeIDs`), or clears the selection if the remembered worktree
  is no longer valid; otherwise it records the current selection and enters the archived
  view.
- `SidebarFooterView` swaps the button icon `archivebox` → `arrow.uturn.left` while in
  the archived view; the menu item and tooltip switch between "Archived Worktrees" and
  "Exit Archived Worktrees" (`supacode/Commands/WorktreeCommands.swift`).
- Test `selectArchivedWorktreesTogglesBackToPreviousWorktree` added
  (`supacodeTests/ShelfFeatureTests.swift`); existing archived-selection tests updated
  for the new state field.

## Refs

- PR #512 (merged 2026-06-26), commits `09c8d33b` (implementation), `321d5762`
  (review feedback), merge `f5e6ad81`.

## Current state

Verified in the tree as of 2026-07-12: `preArchivedWorktreeID` in
`supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`; toggle logic in
`RepositoriesFeature+CoreReducer.swift` (`case .selectArchivedWorktrees`); dynamic
icon/label in `supacode/Features/Repositories/Views/SidebarFooterView.swift` and
`supacode/Commands/WorktreeCommands.swift`. The toggle behavior (⌘⌃A to enter, press
again to return) is documented in `docs/components/repositories-and-worktrees.md`.
