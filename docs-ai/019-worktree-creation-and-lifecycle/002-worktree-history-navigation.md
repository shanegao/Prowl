# 019 — Amendment: Worktree History Navigation (#260, #419)

## Context

With many worktrees across repositories, jumping between two or three active sessions by
sidebar clicking is slow, and "go back to where I just was" had no keyboard answer.
Upstream added worktree selection history in its post-v0.8.1 window; the 2026-05-08
upstream review batch (see `docs-ai/017-upstream-sync-process/upstream-ledger.md`) lists
"worktree history (#260)" among the ports to Prowl.

## Change

PR #260 (merged 2026-05-09, "Add worktree history navigation"):

- Browser-style back/forward stacks over worktree selection in the standard
  sidebar/detail navigation mode.
- History is intentionally **disabled while Shelf or Canvas is active** — those views are
  the higher-level session navigation surfaces.
- Worktrees-menu commands with configurable shortcuts; defaults `⌘⌥[` / `⌘⌥]`, chosen to
  avoid the existing `⌘[` / `⌘]`, `⌘⇧[` / `⌘⇧]`, and Shelf shortcuts.

PR #419 (merged 2026-06-08, "Focus the terminal after next/previous and history worktree
navigation"): sidebar clicks and arrow selection already requested terminal focus, but
Select Next/Previous Worktree and history navigation landed on a worktree without
focusing its terminal, so keystrokes went nowhere. Ported from upstream #371 but
reimplemented on the fork's `pendingTerminalFocusWorktreeIDs` mechanism (the fork does
not use upstream's row-action focus model): next/previous now selects with
`focusTerminal: true`, and history navigation inserts the destination into
`pendingTerminalFocusWorktreeIDs`. Plain `selectWorktree` still does not steal focus.

## Refs

- PRs #260, #419; upstream #371 (focus fix source).
- #419 updated the exhaustive navigation tests (wrap-around, collapsed-repo skipping,
  no-selection, stale-history) in `supacodeTests/RepositoriesFeatureTests`.

## Current state

`worktreeHistoryBackStack` / `worktreeHistoryForwardStack` and the
`worktreeHistoryBack`/`worktreeHistoryForward` actions live in
`supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`;
`navigateWorktreeHistory` plus stack pruning (50-entry `worktreeHistoryStackLimit`,
stale-ID tail pruning) in
`supacode/Features/Repositories/Reducer/RepositoriesFeature+Selection.swift`. Menu
commands with shortcut hints are in `supacode/Commands/WorktreeCommands.swift`, shortcut
IDs in `supacode/App/AppShortcuts.swift`. Behavior documented in
`docs/components/repositories-and-worktrees.md`.
