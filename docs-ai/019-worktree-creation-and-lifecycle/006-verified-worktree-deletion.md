# 019.006 — Verified Worktree Deletion

## Context

Fork issue #454 reports that a deleted worktree disappears briefly and returns after
repository refresh. `GitClient.removeWorktree` currently treats two incomplete cleanup
paths as success: a missing porcelain path match returns without an error, and a
successful `git worktree prune` exit code is accepted without verifying that the target
registration disappeared. The fallback `git worktree remove --force` also discards its
error, so the reducer can emit `worktreeDeleted` even while Git still lists the worktree.

## Planned change

- Compare registered and requested worktree paths after resolving filesystem symlinks,
  while retaining lexical normalization for paths whose final component no longer
  exists.
- Treat a missing registration as a deletion failure instead of a successful no-op.
- After relocating a worktree directory and pruning, read porcelain output again. If
  the target remains registered, run `git worktree remove --force` and propagate any
  Git error (including a lock reason) to the existing deletion alert.
- Propagate `git worktree remove --force` failures on the non-relocation path as well.
- Add regression coverage for a prune-success/locked-registration failure, direct
  removal failure, and reducer behavior when `removeWorktree` throws.

## Decisions

Verification uses the same `git worktree list --porcelain` source as the initial safety
guard. This keeps the change local to `GitClient` and preserves the existing reducer
contract: only a thrown error prevents `worktreeDeleted` and surfaces the existing
"Unable to delete worktree" alert.

An explicit forced remove remains the fallback after relocation. It does not bypass a
Git worktree lock; Git rejects that command and its stderr becomes the user-visible
failure reason. Branch deletion stays after verified worktree cleanup, so it cannot run
when registration removal fails.

## Refs

- Fork issue #454.
- Planned code: `supacode/Clients/Git/GitClient.swift`.
- Planned tests: `supacodeTests/GitClientRemoveWorktreeTests.swift` and
  `supacodeTests/RepositoriesFeatureTests.swift`.

## Implementation

Implemented on 2026-07-12:

- `GitClient.removeWorktree` now fails when the requested path is absent from Git's
  worktree registry instead of reporting a successful no-op.
- A relocated worktree is pruned and then checked against a fresh porcelain listing.
  If it remains registered, Prowl runs `git worktree remove --force` and propagates any
  error. On failure, the relocated directory is restored before the error reaches the
  reducer.
- Direct `git worktree remove --force` errors are no longer discarded.
- Worktree path identity resolves arbitrary filesystem symlinks in addition to lexical
  normalization.
- The existing reducer failure path keeps the worktree in state and displays Git's
  error in the "Unable to delete worktree" alert.

## Verification

- `make check` passed.
- `make test` passed 1,790 tests with no failures.
- `make build-app` passed with no errors or warnings.

Regression tests cover prune-success with a locked registration, direct removal
failure, arbitrary symlinked parent paths, missing exact registration, directory
restoration after fallback failure, and reducer failure behavior.

## Current state

Implemented and locally verified. The fork PR reference remains to be added.
