# 032 — Performance Hardening: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-21 | Cache main-worktree flag on `Worktree` to fix the Sentry App Hang storm; `isMainWorktree(_:)` becomes O(1); `WorktreeIsMainTests` added | PR #231 |
| 2026-05-29 | Propagate Task cancellation into `ShellClient` processes (async `waitForExit`, SIGTERM on cancel, teardown on stream termination); `ShellClientStreamingTests` added | PR #371 |
| 2026-05-29 | FSEvents stream scheduling moved from run loop to dispatch queue (main queue) | PR #367 |
| 2026-06-06 | Sidebar top-level `LazyVStack` → `VStack` to stop the lazy placement cache spin after collapse/expand | PR #398 |
| 2026-06-08 | Wave 2: four upstream-ported fixes for agent-hot paths (menu-bar flicker, OSC-9 coalescing, event-stream cap/coalesce, split-tree AnyView removal) | PRs #414–#417, [002-june-upstream-ports.md](002-june-upstream-ports.md) |

## Outcome & current state (as of 2026-07-12)

All wave-1 changes are in the current tree:

- `supacode/Domain/Worktree.swift` stores `let isMain: Bool`, computed in `init` with the
  `==` fast-path plus `standardizedFileURL` fallback (a comment documents the hot-path
  rationale). `RepositoriesFeature.State.isMainWorktree(_:)` in
  `supacode/Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift` is the
  thin `worktree.isMain` wrapper. Tests: `supacodeTests/WorktreeIsMainTests.swift`.
- `FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)` lives in
  `supacode/Features/Repositories/BusinessLogic/WorktreeInfoMonitors.swift`; at the time
  of #367 this code sat in the `WorktreeInfoWatcherManager` area and was later split into
  the monitors file (tests remain `supacodeTests/WorktreeInfoWatcherManagerTests.swift`).
- `supacode/Clients/Shell/ShellClient.swift` contains `waitForExit(of:)` and the
  `withTaskCancellationHandler` wrapping described in the plan. Tests:
  `supacodeTests/ShellClientStreamingTests.swift`.
- The sidebar fix moved files: #398 patched `SidebarView.swift`, but after the #403 file
  split ([015-repositories-feature-refactor](../015-repositories-feature-refactor/000-plan.md))
  the scroll content lives in `supacode/Features/Repositories/Views/SidebarListView.swift`,
  where the `VStack(spacing: 0)` carries a comment explaining why `LazyVStack` is avoided.

Wave-2 current state is verified in [002-june-upstream-ports.md](002-june-upstream-ports.md).

## Deviations from plan

None known for wave 1; each fix landed as described in its PR. The #231 follow-up on
`orderedRepositoryRoots()` / `orderedRepositoryIDs()` was explicitly conditional on hang
signatures persisting and was never needed (see Open questions).

## Open questions

- `RepositoriesFeature.State.orderedRepositoryIDs()`
  (`RepositoriesFeature+StateQueries.swift`) still calls `standardizedFileURL` once per
  repository per call, the exact pattern #231 flagged for a conditional follow-up. No
  follow-up PR exists — presumably the Sentry signatures cleared (App Hang tracking was
  later removed entirely, see [020-observability](../020-observability/000-plan.md), so
  post-removal recurrence would be invisible anyway). Cheap per-repo (not per-worktree²),
  but unverified whether it ever shows up in traces today.
- The entry's anchor date (2026-05-21, from the backfill outline) postdates the first
  wave-1 PR: #231 merged 2026-04-21. The outline appears to anchor the entry where the
  *theme* sits chronologically; the timeline above records actual merge dates.
- The upstream ledger's 2026-06-09 batch table attributes commits slightly differently
  from the PR bodies (it lists the AnyView-drop commit `db2f39d0` under the #414 row and
  maps upstream #332 → #417 via `6fab2d28`, which is actually #416's merge commit). The
  PR bodies are taken as authoritative here; the ledger rows look like minor bookkeeping
  slips.
