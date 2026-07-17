# 006 — Startup Performance: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-19 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #13, #15, #17, #18 |
| **Sources** | `doc-onevcat/plans/2026-03-20-repository-snapshot-cache-design.md` (absorbed here; original removed in the docs-ai migration), PR descriptions, change-list entries |
| **Related** | [014-terminal-layout-persistence](../014-terminal-layout-persistence/000-plan.md), [039-gh-cli-hardening](../039-gh-cli-hardening/000-plan.md), `docs-ai/017-upstream-sync-process/upstream-ledger.md` |

## Background

With many repositories added (benchmark: 13 repos on Apple Silicon), app launch took ~4.8s
before the UI was usable. Three compounding costs:

- Repository/worktree discovery (`loadRepositoriesData` in `RepositoriesFeature`) ran as a
  serial `for` loop over all repositories.
- Every bundled `wt` invocation (`wt root`, `wt ls --json`) spawned a login shell to resolve
  the GUI environment, paying shell startup cost per call.
- The sidebar rendered nothing until the full live discovery pass finished.

## Goals

- Make the UI usable near-instantly on launch, even with many repositories.
- Parallelize discovery without breaking repository order or last-focused selection restore.
- Remove the per-invocation login-shell overhead from bundled `wt` execution.
- Restore repository UI immediately from a small startup cache while keeping live discovery
  as the only source of truth.

### Non-goals

Per the snapshot-cache design doc:

- Do not cache PR state, line changes, watcher state, notifications, or
  `lastFocusedRepositoryID` (selection restore keeps using existing `lastFocusedWorktreeID`
  persistence).
- No TTL/freshness machinery — the cache is only a startup accelerator; freshness comes
  from the unconditional live refresh that always runs after restore.

## Design / Approach

Three stacked optimizations, landed over two days:

1. **Parallel repository loading** (#13, reworked as #15). Replace the serial loop with a
   `TaskGroup` fanning out one worktree-discovery task per repository. #13 additionally
   loaded the last-focused repository first (UI usable at 0.39s vs 4.83s, ~12x) and added
   startup benchmark logging; #15 re-landed the parallelization in a simpler form that
   preserves persisted repository/root order in the final snapshot even when fetches
   complete out of order, with tests for order preservation and last-focused selection
   restore.
2. **Direct bundled `wt` execution** (#17). Run the bundled `wt` binary directly via
   `ShellClient` instead of always going through a login shell; fall back to login-shell
   execution only for obvious GUI environment resolution failures. Implemented in
   `supacode/Clients/Git/GitClient.swift`.
3. **Repository snapshot startup cache** (#18), per the absorbed design doc:
   - **Storage**: standalone JSON file at `~/.prowl/repository-snapshot.json` (deliberately
     not inside `settings.json`) so cache decode failures stay isolated from settings, the
     file is safely deletable, and the payload can evolve behind an explicit schema version.
   - **Payload**: only data needed for first paint — repositories in UI order, root path,
     display name; per worktree: name, detail string, working-directory path, `createdAt`.
   - **Invalidation**: treat as a miss (discard the file, run a normal live load) when the
     file is missing/empty, the schema version mismatches, JSON decoding fails, or any
     cached repository root / worktree path no longer exists on disk.
   - **Startup flow**: load persisted pinned/archive/order/last-focused state → load the
     snapshot → if present, restore repositories into state immediately and mark initial
     load complete so the main UI renders → always run the normal live loading flow →
     apply live results.
   - **Refresh rules**: overwrite the snapshot only after a complete successful live load
     (initial refresh, manual refresh, or any flow ending in a full successful snapshot);
     never on partial or failed loads.

## Alternatives & decisions

- **Priority loading vs snapshot cache for first paint**: #13's "load last-focused repo
  first, rest in background" approach shipped first but was superseded within a day — its
  merge commit is not part of current `main` history, and #15 re-implemented the parallel
  load without the priority phase or benchmark logging. Instant first paint is delivered by
  the snapshot cache (#18) instead, which restores *all* repositories at once.
- **Standalone cache file vs settings.json**: standalone file chosen so bad cache data can
  never affect settings loading and the cache stays disposable with no migration burden.
- **No TTL**: rejected as unnecessary; the unconditional post-restore live refresh is the
  freshness mechanism.
- **Upstream contribution**: the two generally-useful optimizations (#15 parallel loading,
  #17 direct `wt`) were contributed and merged upstream; the snapshot cache was offered but
  not accepted, so it remains fork-only code. See amendment 002.

## Amendments

- Updated 2026-03-22: parallel loading and direct `wt` merged upstream (upstream #160/#161);
  snapshot cache upstream PR closed unmerged — see
  [002-upstream-contribution.md](002-upstream-contribution.md)
