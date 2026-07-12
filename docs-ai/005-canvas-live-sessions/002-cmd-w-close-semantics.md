# 005 — Amendment: Cmd-W close semantics in Canvas (2026-03-25)

## Context

Upstream commit `b78042c` (picked up via fork sync) added a **Close Window** command
bound to Cmd+W. Correct for the main app window, but Canvas relies on terminal close
semantics for the same shortcut: close the focused split pane if one exists, otherwise
close the focused card/tab. Because Canvas did not expose a non-nil focused
close-surface action, the new Window command won the shortcut overlap — pressing Cmd+W
inside Canvas closed the entire app window.

## Change

Restore Canvas-specific focused actions while preserving upstream's Close Window for
the non-Canvas case:

- Route Canvas Cmd+W through the **currently focused canvas worktree** (tracked as
  `canvasFocusedWorktreeID`, from #11) instead of the selected worktree, which is
  cleared while Canvas is showing.
- Expose non-nil `closeSurfaceAction` / `closeTabAction` focused scene values whenever
  a canvas card has focus, so the terminal close menu commands out-prioritize the
  Window command on the shared shortcut.
- Main terminal view behavior unchanged.

## Refs

- PR #54 (merged 2026-03-25)

## Current state

Still the mechanism in use: `supacode/Features/Repositories/Views/WorktreeDetailView.swift`
computes the action target as the selected terminal worktree, falling back to the
canvas-focused one, and publishes `.focusedSceneValue(\.closeTabAction, …)` /
`.focusedSceneValue(\.closeSurfaceAction, …)`; `supacode/Commands/TerminalCommands.swift`
consumes those focused values for the Close menu commands (shortcut display resolved
via Ghostty bindings).
