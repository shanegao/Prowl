# 003 — Amendment: Configurable External Diff Tools

## Context

Users asked to review diffs in their preferred tool instead of the built-in
window (fork issue #322). Terminal-native tools (Hunk) and GUI tools
(FileMerge, Kaleidoscope) have different launch models, and GUI tools cannot
show untracked files from a plain `git diff` invocation.

## Change

PR #449 (merged 2026-06-14):

- A global **Diff Tool** setting with `Built-in`, `Hunk`, `FileMerge`,
  `Kaleidoscope`, and `Custom Command` options
  (`supacode/Domain/ExternalDiffTool.swift`). Tools not installed on the Mac
  are shown disabled in the menu.
- One launcher, `supacode/Clients/ExternalDiff/ExternalDiffToolClient.swift`,
  behind both the worktree diff badge and the Show Diff action:
  - **Built-in** → `DiffWindowManager.shared.show(...)` (the 000-plan window).
  - **Hunk** → opens a Prowl terminal tab and runs `hunk diff` in the worktree.
  - **FileMerge / Kaleidoscope / Custom** → `ExternalDiffSnapshotClient`
    materializes HEAD/worktree snapshot folders (so untracked files are
    included without touching the index) and launches `opendiff`,
    `ksdiff --diff`, or the user's command with `{leftPath}`, `{rightPath}`,
    `{worktreePath}`, `{repoPath}`, `{branch}` placeholders.
- Settings and behavior documented in `docs/components/diff-view.md` and
  `docs/components/settings.md`.

## Refs

- PR #449; fork issue #322.
- Tests: `supacodeTests/ExternalDiffToolTests.swift`.

## Current state

As described; verified in the working tree 2026-07-12. The launcher is also the
path through which the appearance fix (amendment 004) threads the app's color
scheme into `DiffWindowManager.show()`.
