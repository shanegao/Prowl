# 037 — Amendment: Adaptive Debounce & Untracked Lines in Badge

## Context

The #365 debounce constants (5 s HEAD / 30 s FSEvents) were chosen for worst-case large
repositories. Fork issue #488 reported the consequence for normal repos: edit a file and
the badge takes 30+ seconds to update — and keeps resetting if you keep editing.
Benchmarks (2026-06-22 plan doc, absorbed into this entry) showed the cost of
`git diff HEAD --shortstat` scales with dirty-file count, not repo size alone: ~14 ms on
a clean 5 000-file repo but ~2.0 s with 20 000 dirty files. A single global debounce
cannot serve both audiences.

A second inconsistency: the badge ran only `git diff HEAD --shortstat`, which reports
tracked changes, while the diff window (⌘⇧Y) includes untracked files via
`git ls-files --others --exclude-standard`. Creating a new file showed `+0` on the badge
but a listed file in the viewer ([003-diff-window](../003-diff-window/000-plan.md)).

## Change

PR #491 (2026-06-22, closes #488), implementing the plan doc:

- **Adaptive tiers**: read the repository's tracked-file count from the git index binary
  header (entry count is a big-endian `UInt32` at byte offset 8 — a 12-byte read, no
  subprocess), cache it per repository root, and map to a timing tier:

  | Tier | Tracked files | HEAD debounce | FSEvents debounce |
  |---|---|---|---|
  | Small | < 5 000 | 1 s | 2 s |
  | Medium | 5 000 – 20 000 | 2 s | 5 s |
  | Large | > 20 000 | 5 s | 15 s |

  The 300 s safety refresh stays uniform. The large tier keeps (slightly tightens) the
  #365 conservative behavior; `observeLineDiffsAutomatically = false` (#377) remains the
  hard opt-out for repos where even 15 s is too aggressive.
- **Untracked lines**: `GitClient.lineChanges(at:)` runs `git ls-files --others
  --exclude-standard` concurrently with the shortstat diff (`async let`) and adds the
  line counts of untracked files to `added` — same `(added:removed:)` return type, no
  badge layout change. Files with a NUL byte in the first 8 KB are treated as binary and
  skipped (matching git's heuristic); counting is pure in-process I/O.

Deliberately unchanged (plan doc non-goals): the `isLineChangesActive` gating, PR
polling ([028-pr-status-tracking](../028-pr-status-tracking/000-plan.md)), user-visible
interval settings, and the `--shortstat` command itself.

## Refs

- PR #491 — "Adaptive line-diff debounce and untracked lines in badge"
- Fork issue #488; design: `doc-onevcat/plans/2026-06-22-adaptive-line-diff-strategy.md`
  (absorbed here; original removed in the docs-ai migration)

## Current state

`LineChangesTiming` and `repositoryLineChangesTimings` in
`supacode/Features/Repositories/BusinessLogic/WorktreeInfoWatcherManager.swift`;
`indexEntryCount(at:)`, `countLinesInFiles(_:relativeTo:)` and the concurrent
`lineChanges(at:)` in `supacode/Clients/Git/GitClient.swift`. Tests in
`supacodeTests/WorktreeInfoWatcherManagerTests.swift` and
`supacodeTests/GitClientLineChangesTests.swift`.
