# 015 — Amendment: Worktree Stream Request API (PR #426)

## Context

`GitClient.createWorktreeStream` and its TCA dependency wrapper had accumulated a long
positional parameter list (repo root, base directory, name, copy flags, base ref,
directory override — the last added by the name/parent-dir override work, #424). Mock
signatures in tests had to unpack the same long tuple, making call sites fragile every
time worktree creation gained an option.

## Change

- Added `GitWorktreeCreateRequest` (`nonisolated struct`, `Equatable`, `Sendable`) in
  `supacode/Clients/Git/GitClientTypes.swift`, grouping all worktree stream creation
  inputs.
- `GitClient.createWorktreeStream(_:)` (`supacode/Clients/Git/GitClient.swift`) and the
  TCA git dependency (`supacode/Clients/Repositories/GitClientDependency.swift`) now take
  the request value instead of positional parameters.
- Reducer call sites in `RepositoriesFeature+WorktreeCreation.swift` and tests
  (`GitClientCreateWorktreeStreamTests`, `RepositoriesFeatureTests`) inspect request
  fields instead of unpacking mock closure arguments.

Behavior-preserving; 6 files changed (+107/−85).

## Refs

- PR #426 (merge `87b0fbd9`, 2026-06-08)
- Cross-link: worktree creation option evolution lives in
  [019-worktree-creation-and-lifecycle](../019-worktree-creation-and-lifecycle/000-plan.md)

## Current state

Verified in the working tree: `GitWorktreeCreateRequest` is defined at
`supacode/Clients/Git/GitClientTypes.swift` and remains the sole input to
`createWorktreeStream` across `GitClient.swift`, `GitClientDependency.swift`, and
`RepositoriesFeature+WorktreeCreation.swift`.
