# 019 — Amendment: Safe Branch Deletion & Cleanup Hardening (#375, #383)

## Context

Worktree deletion originally preselected "also delete the local branch" in a destructive
alert, for every worktree — including branches the user created outside Prowl and
branches with unmerged work. Separately, the cleanup that runs when worktree *creation*
fails removed/relocated directories based on loose matching, which risked touching the
wrong directory (and requested branch deletion for a branch the user may want to keep).

## Change

PR #375 (merged 2026-05-30, "Make worktree branch deletion explicit and safe"):

- The destructive delete alert became a **confirmation sheet** with an explicit
  "delete local branch" toggle; default deletion no longer preselects branch deletion.
- Prowl now tracks which worktrees it created itself
  (`@Shared(.appStorage("prowlCreatedWorktreeIDs"))`); the toggle is preselected only for
  Prowl-created worktrees when the `deleteBranchOnDeleteWorktree` setting is on.
- Branch deletion runs `git branch -d` first, protects main/default branches, and only
  offers force deletion (`git branch -D`) behind a second confirmation alert
  (`ForceDeleteBranchRequest`) when `-d` fails.
- The merged-PR `.delete` automation (#190) inherits all of this because it dispatches
  the same `deleteWorktreeConfirmed` path, additionally gated on the worktree being
  Prowl-created.

PR #383 (merged 2026-06-03, "Harden failed worktree cleanup"):

- Require an **exact `git worktree list --porcelain` path match** before removing or
  relocating a worktree directory (porcelain reports raw on-disk paths, e.g.
  `/private/tmp/...`, so comparison handles that).
- Only relocate existing worktree directories that actually contain `.git` metadata.
- Failed-creation cleanup no longer requests branch deletion at all.

## Refs

- PRs #375, #383; tests in `supacodeTests/GitClientRemoveWorktreeTests` and
  `RepositoriesFeatureTests`.

## Current state

Deletion flow and `ForceDeleteBranchRequest` handling in
`supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeLifecycle.swift`;
sheet UI in `supacode/Features/Repositories/Views/DeleteWorktreeConfirmationView.swift`;
`deleteLocalBranch` plus the porcelain-match/`.git`-metadata guards
(`relocateWorktreeDirectory`) in `supacode/Clients/Git/GitClient.swift`.
`prowlCreatedWorktreeIDs` is registered on creation in
`RepositoriesFeature+WorktreeCreation.swift` and consulted in
`RepositoriesFeature+CoreReducer.swift` / `+GithubIntegration.swift` /
`+WorktreeLifecycle.swift`.
