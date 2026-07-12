# 034 — Amendment: Symlinked Roots Series (#406, #555)

## Context

Two symlink-related identity failures, a month apart, with the same underlying theme:
Prowl and git disagreeing about what a path is called.

**#406 — undeletable external worktrees.** Worktrees created outside Prowl (by another
CLI or app) under symlinked roots like `/tmp` could not be deleted: right-click →
Delete worktree made the row disappear briefly, then reappear on the next refresh; the
directory was never removed. Root cause: `GitClient.worktrees(for:)` stores each
worktree's path via `standardizedFileURL`, which resolves the macOS `/private` symlink
(`/private/tmp/foo` → `/tmp/foo`), while the removal guard in
`removeWorktree(_:deleteBranch:)` compared that against the raw paths from
`git worktree list --porcelain`, which keep the `/private` prefix. `/tmp/foo` was never
in `{ /private/tmp/foo, … }`, so the guard silently returned and the optimistic UI
removal was undone by the next refresh. Prowl-created worktrees under `~/.prowl/…` have
no symlink components, which is why only externally-created worktrees were affected.

**#555 — symlinked repository roots load nothing.** Fork issue #526: a user moved a
project to `/Volumes/…` and left a symlink at the original path; Prowl showed the
repository but no branch or worktree info. The persisted entry path resolved through
the symlink did not string-match the Git-reported root, so
`upgradedRepositoryEntriesIfNeeded` took the nested-inside-another-repository fallback
and classified the entry as `.plain`.

## Change

**#406 (merged 2026-06-07).** New `GitClient.canonicalWorktreePath(_:)` — the same
`standardizedFileURL` transform `worktrees(for:)` uses — applied to both the tracked
path and every porcelain-reported path in `registeredWorktreePaths(rootPath:)`, so the
removal guard matches regardless of `/private` prefixes. Regression test
`removeWorktreeMatchesWhenGitReportsPrivateSymlinkPath` (git reports `/private/tmp/…`,
Prowl tracks `/tmp/…`, removal now relocates and prunes).

**#555 (merged 2026-07-12).** `pathsReferToSameFileSystemLocation(_:_:)` compares the
persisted path and the Git-reported root after
`resolvingSymlinksInPath().standardizedFileURL` on both sides. When they refer to the
same location, the persisted entry is migrated to the canonical Git root (kind `.git`),
so branch and worktree loading use one identity from then on. Paths that genuinely sit
inside another repository keep the existing `.plain` classification. The behavior is
documented in `docs/components/repositories-and-worktrees.md`.

## Refs

- PR #406 — "Fix deletion of externally-created worktrees under symlinked roots"
- Fork issue #526 — "[Bug] can not work when link"
- PR #555 — "Resolve symlinked repository roots"; tests in
  `supacodeTests/RepositoriesFeatureTests.swift` (upgrade/downgrade group)

## Current state

Verified: `canonicalWorktreePath(_:)` and the canonicalized removal guard in
`supacode/Clients/Git/GitClient.swift`; `pathsReferToSameFileSystemLocation(_:_:)` and
the entry migration in
`supacode/Features/Repositories/Reducer/RepositoriesFeature+RepositoryLoading.swift`.
Note the residual gap recorded in [001-action.md](001-action.md) Open questions: the
two fixes use different symlink-resolution strengths.
