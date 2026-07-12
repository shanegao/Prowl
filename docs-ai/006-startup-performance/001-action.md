# 006 — Startup Performance: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-19 | Parallel worktree loading with last-focused-repo priority + startup benchmark logging (UI usable 4.83s → 0.39s on 13 repos); closed fork issue #12 | PR #13 |
| 2026-03-20 | Order-preserving parallel repository loading re-landed via `TaskGroup`, superseding #13 (whose merge commit dropped out of `main` history); tests for root-order preservation and last-focused selection restore | PR #15 |
| 2026-03-20 | Bundled `wt root` / `wt ls --json` executed directly instead of via login shell, with login-shell fallback only for GUI environment resolution failures | PR #17 |
| 2026-03-20 | Repository snapshot startup cache: restore-before-live-refresh, save only after full successful loads, validation/discard rules, design doc committed | PR #18 |
| 2026-03-22 | #15 and #17 contributed and merged upstream; #18 offered upstream but closed unmerged | upstream #160, #161, #162 — see [002](002-upstream-contribution.md) |
| 2026-03-31 | Snapshot file relocated from `~/.prowl/` to the Application Support cache directory as part of persistence-safety hardening | PR #112 (see [014](../014-terminal-layout-persistence/000-plan.md)) |

## Outcome & current state (as of 2026-07-12)

- Parallel loading lives in
  `supacode/Features/Repositories/Reducer/RepositoriesFeature+RepositoryLoading.swift`:
  `loadRepositoriesData` fans out one `withTaskGroup` task per persisted entry, collects
  results keyed by normalized root ID, then reassembles them in persisted entry order —
  #15's order-preservation design, since extended to plain folders and project workspaces
  (`PersistedRepositoryEntry.kind`, `ProjectWorkspace`). `upgradedRepositoryEntriesIfNeeded`
  in the same file also runs entry upgrades in parallel. No last-focused priority phase and
  no benchmark logging exist in the current tree (#13's additions did not survive).
- Direct `wt` execution lives in `supacode/Clients/Git/GitClient.swift`:
  `runBundledWtProcess` runs the bundled script (`wtScriptURL()` resolves it from the
  app bundle's `git-wt` resources, backed by the `Resources/git-wt` submodule) via
  `shell.run`, falling back to `shell.runLogin` when `shouldFallbackToLoginShell`
  (`supacode/Clients/Git/GitClientShellHelpers.swift`) allows. Fallback semantics were
  later reworked (invert-fallback for git detection, #493/#541) — see
  [039-gh-cli-hardening](../039-gh-cli-hardening/000-plan.md).
- The snapshot cache lives in
  `supacode/Clients/Repositories/RepositoryPersistenceClient.swift`:
  `loadRepositorySnapshot`/`saveRepositorySnapshot` endpoints plus
  `RepositorySnapshotCachePayload` — now schema version 2 with hard caps (2 MiB file,
  256 repositories, 512 worktrees per repository) and payload extended with repository
  `kind` and `workspace` for plain folders/workspaces. Any validation failure discards the
  cache file, exactly as designed.
- Storage moved: `SupacodePaths.repositorySnapshotURL`
  (`supacode/Support/SupacodePaths.swift`) now points into
  `~/Library/Application Support/com.onevcat.prowl/cache/repository-snapshot.json`;
  `migrateLegacyCacheFilesIfNeeded` migrates the legacy `~/.prowl/repository-snapshot.json`
  on launch.
- The startup flow in
  `supacode/Features/Repositories/Reducer/RepositoriesFeature+CoreReducer.swift` matches
  the design: `.task` sets `snapshotPersistencePhase = .restoring`, loads persisted state
  plus the snapshot, `.repositorySnapshotLoaded` applies restored repositories and sets
  `isInitialLoadComplete = true`, then `.loadPersistedRepositories` runs the live refresh;
  the snapshot is saved only when a live load completes with no failures (also enforced in
  `RepositoriesFeature+RepositoryManagement.swift`).
- Tests: `supacodeTests/RepositoriesFeatureTests.swift`,
  `supacodeTests/RepositoryPersistenceClientTests.swift`,
  `supacodeTests/RepositoriesFeaturePersistenceTests.swift`.

## Deviations from plan

- #13's priority loading and benchmark logging shipped but were dropped: its merge commit
  (`833bb54e`) is not an ancestor of current `main`, and #15 re-implemented parallel
  loading on the pre-#13 base without them. First-paint latency is covered by the snapshot
  cache instead.
- Snapshot storage location deviates from the design doc's `~/.prowl/repository-snapshot.json`:
  moved to the Application Support cache directory by PR #112 (entry 014), with legacy
  migration.
- Snapshot schema evolved past the designed payload: version 2 adds repository `kind` and
  `workspace`, and size caps were introduced that the design doc did not specify.

## Open questions

- Why PR #13 disappeared from `main` history is undocumented: GitHub shows it merged
  (merge commit `833bb54e`), but that commit is unreachable from `main` and #15 was built
  on the pre-#13 base — presumably a deliberate branch reset before re-landing, but no
  revert commit or note records this.
- The upstream review ledger still marks the snapshot cache as "Pending upstream (#162)",
  but upstream #162 is closed unmerged — the ledger row is stale.
