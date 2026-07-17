# 010 — Amendment: Plain→Git Upgrade Watchers

## Context

Since #48, a `.plain` entry upgrades to `.git` only when
`upgradedRepositoryEntriesIfNeeded` runs — at app launch, scene-active refresh, or the
periodic refresh. Running `git init` inside a plain folder's terminal therefore left the
sidebar unchanged (no worktree rows, git UI hidden) until a reload happened for some
other reason. Contributor PR #548 identified the missing piece: nothing watches `.plain`
roots for `.git` creation.

## Change

Two waves, merged together as #553 (which retains #548's original commit unchanged):

**#548 — the watcher path.** FSEvents monitors for `.plain` non-workspace repository
roots. When `.git` appears, emit `plainRepositoryBecameGitRepository(URL)`, which the
reducer turns into `reloadRepositories(animated: true)`; the existing upgrade logic then
reclassifies the entry and discovers worktrees. New
`WorktreeInfoWatcherClient.Command.setPlainRepositoryRoots([URL])` is sent from
`AppFeature` alongside `setWorktrees` whenever repositories change, fed by
`RepositoriesFeature.State.plainRepositoryRootsForInfoWatcher()`.

**#553 — hardening on top.**

- Isolate monitor creation failures: one unavailable root no longer aborts the
  unordered `Set` iteration and skips the remaining roots.
- Injectable `PlainRepositoryFileEventMonitorFactory` so
  `WorktreeInfoWatcherManagerTests` can cover root addition/removal, cancellation,
  debounce, and stop behavior deterministically.
- Edge-triggered detection: a root that already fired keeps a
  `plainRepositoryRootsWithGitEvent` marker so a failed upgrade cannot turn every
  subsequent file event into a full repository reload; the trigger re-arms if `.git`
  disappears again.

## Refs

- PR #548 (closed unmerged; commit retained) — "Fix sidebar not updating after git init
  in plain repository"
- PR #553 (merged 2026-07-11) — "Harden plain repository upgrade watchers"; validated
  end-to-end by opening a plain folder, running `git init`, and watching `prowl list`
  flip the target from `kind=plain` to `kind=git`
- Sibling watcher-correctness work:
  [034-worktree-watcher-correctness](../034-worktree-watcher-correctness/000-plan.md)
  (#553 is also listed there as part of the watcher hardening arc)

## Current state

Verified in `supacode/Features/Repositories/BusinessLogic/WorktreeInfoWatcherManager.swift`:
per-root monitors in `plainRepositoryMonitors`, a 1-second `KeyedDebouncer<URL>`, a
`.git` existence check before emitting, and the edge-trigger set with re-arm. Event and
command types live in
`supacode/Clients/WorktreeInfoWatcher/WorktreeInfoWatcherClient.swift`; the reducer
handling is in `RepositoriesFeature+CoreReducer.swift`.
