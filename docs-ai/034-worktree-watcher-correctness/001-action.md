# 034 — Worktree Watcher Correctness: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-25 | Deduplicate discovered worktrees: first-wins path dedup in `GitClient.worktrees(for:)`; defensive `IdentifiedArray(_, uniquingIDsWith:)` at repository load and snapshot restore; discovery + restore tests | PR #346 |
| 2026-05-30 | Refresh worktrees from git registry changes: `GitWorktreeRegistryMonitor` watching the git common dir and `worktrees/` registry, debounced `.repositoryWorktreesChanged` event → `reloadRepositories`; send initial scene phase from `ContentView.task` so the active refresh loop starts without a phase transition | PR #373 |
| 2026-06-07 | Fix deletion of externally-created worktrees under symlinked roots: `GitClient.canonicalWorktreePath(_:)` applied to both sides of the removal guard | PR #406 — see [002](002-symlinked-roots.md) |
| 2026-06-30 | Fix duplicate worktree watcher crash: first-wins dedup in `WorktreeInfoWatcherManager.setWorktrees`; SwiftLint rule banning `Dictionary(uniqueKeysWithValues:)` | PR #528 — see [003](003-duplicate-watcher-crash.md) |
| 2026-07-11 | Harden plain repository upgrade watchers (contributor PR #548 + hardening): FSEvents monitors on `.plain` roots, edge-triggered `.git` detection | PR #553 — detailed in [010's amendment](../010-plain-folder-support/002-plain-upgrade-watchers.md) |
| 2026-07-12 | Resolve symlinked repository roots: migrate persisted entries that resolve through a symlink to the Git-reported canonical root (fixes fork issue #526) | PR #555 — see [002](002-symlinked-roots.md) |

## Outcome & current state (as of 2026-07-12)

Verified against the working tree:

- `supacode/Clients/Git/GitClient.swift` — `worktrees(for:)` dedups via a
  `seenWorktreeIDs` set keyed on the standardized path; `canonicalWorktreePath(_:)`
  normalizes to the same form `worktrees(for:)` stores;
  `registeredWorktreePaths(rootPath:)` maps `git worktree list --porcelain` output
  through it; the guard in `removeWorktree(_:deleteBranch:)` compares canonical paths
  on both sides (and still returns silently when unmatched — see Open questions).
- `supacode/Features/Repositories/BusinessLogic/WorktreeInfoMonitors.swift` —
  `GitWorktreeRegistryMonitor` (DispatchSource sources on the common git directory and
  its `worktrees/` subdirectory; `GitCommonDirectory` resolves `.git`-file `gitdir:` and
  `commondir` indirection), alongside `FSEventsWorktreeFileEventMonitor` and
  `GitRemoteConfigMonitor`.
- `supacode/Features/Repositories/BusinessLogic/WorktreeInfoWatcherManager.swift` —
  `setWorktrees` builds its lookup with an explicit first-wins loop and configures
  watchers only for unique worktrees; `syncWorktreeRegistryMonitors` adds/cancels
  per-root monitors; `repositoryWorktreesDebouncer` defaults to 2 s; plain-root
  monitors and the edge-triggered `.git` marker set live here too (entry 010).
- `supacode/Clients/WorktreeInfoWatcher/WorktreeInfoWatcherClient.swift` — events
  `.repositoryWorktreesChanged(repositoryRootURL:)` and
  `.plainRepositoryBecameGitRepository(URL)`.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+CoreReducer.swift` — both
  events map to `.reloadRepositories(animated: true)`.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+RepositoryLoading.swift`
  — `upgradedRepositoryEntriesIfNeeded` migrates a persisted entry to the Git-reported
  root when `pathsReferToSameFileSystemLocation(_:_:)`
  (`resolvingSymlinksInPath().standardizedFileURL` on both sides) matches; repository
  load builds worktree arrays with `uniquingIDsWith:`.
- `supacode/Clients/Repositories/RepositoryPersistenceClient.swift` — snapshot restore
  also uses `IdentifiedArray(restoredWorktrees, uniquingIDsWith:)`.
- `.swiftlint.yml` — custom rule `dictionary_unique_keys_with_values` (severity error)
  bans `Dictionary(uniqueKeysWithValues:)` repo-wide.
- `docs/components/repositories-and-worktrees.md` — documents the symbolic-link
  resolution behavior added by #555.

Regression tests exist for the two trickiest fixes:
`removeWorktreeMatchesWhenGitReportsPrivateSymlinkPath` in
`supacodeTests/GitClientRemoveWorktreeTests.swift` and
`buildsWorktreeLookupWithoutTrappingOnDuplicateID()` in
`supacodeTests/WorktreeInfoWatcherManagerTests.swift`.

## Deviations from plan

None known — this is a retrospective entry; each wave shipped as described in its PR.

## Open questions

- The `removeWorktree` guard is still a silent no-op when the tracked path is not among
  the registered paths: a future path-identity mismatch class would reproduce the
  #406 symptom (row disappears, then reappears) with no log line to diagnose it.
- Two canonicalization strengths coexist: `canonicalWorktreePath` relies on
  `standardizedFileURL` (which resolves `/private`-style prefixes but not arbitrary
  symlinks), while repository-root identity uses `resolvingSymlinksInPath()`. This is
  consistent as long as `wt ls --json` and `git worktree list --porcelain` report the
  same on-disk path form; a worktree reached through an arbitrary symlink that one tool
  reports resolved and the other does not would still bypass the removal guard. Not
  observed in practice; noted as a residual gap.
- PR #528's crash (Sentry `PROWL-MACOS-D6`) was fixed defensively; the exact
  reproduction of duplicate `Worktree.ID`s reaching `setWorktrees` was not established.
  Since the watcher receives `repositories.flatMap(\.worktrees)`
  (`worktreesForInfoWatcher()` in `RepositoriesFeature+StateQueries.swift`), duplicates
  imply cross-repository collisions — e.g. one repository persisted under two path
  identities — a class that #555's entry canonicalization narrows but does not prove
  eliminated.
