# 037 — Line-Diff Tracking: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-28 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #365 (event-driven refresh), #377 (per-repo toggles); #491 (adaptive debounce + untracked lines); #508/#511 (deferred-refresh fix); #298 (badge truncation) |
| **Sources** | `doc-onevcat/plans/2026-06-22-adaptive-line-diff-strategy.md` (absorbed here; original removed in the docs-ai migration), PR descriptions listed above, fork issues #364 and #488 |
| **Related** | [003-diff-window](../003-diff-window/000-plan.md) (the diff *viewer* the badge links to; also home of the `KeyedDebouncer` extraction), [028-pr-status-tracking](../028-pr-status-tracking/000-plan.md) (sibling sidebar pipeline; #377 also gates its refresh), `docs/components/diff-view.md` |

## Background

Every worktree row in the sidebar shows a `+N/-M` line-change badge (clicking it opens
the diff window, see [003-diff-window](../003-diff-window/000-plan.md)). The badge is
computed by `GitClient.lineChanges(at:)` running `git diff HEAD --shortstat` per
worktree, orchestrated by `WorktreeInfoWatcherManager`.

The inherited model was fixed-cadence polling: `git diff HEAD --shortstat` ran on **all**
worktrees at a fixed interval regardless of whether anything had changed. A user report
(fork issue #364) showed this creates sustained background CPU/IO in very large
repositories — `--shortstat` still computes line-level diffs, and its cost scales with
the number of dirty files (benchmarks in the 2026-06-22 plan doc measured ~2.0 s per
invocation for 20 000 dirty files).

## Goals

- Stop asking git for line diffs when nothing can have changed: refresh on *events*
  (file-system activity, HEAD changes, app foreground), not on a timer.
- Keep git as the single source of truth for counts; file-system events are only an
  invalidation signal, never a diff computation.
- Give per-repository escape hatches for repos where even reduced background work is
  unwanted (line-diff observation and PR-state fetching independently toggleable).
- Later wave (#491): make the badge feel instant on normal-sized repos without giving up
  the conservative behavior on huge ones, and stop ignoring untracked files.

**Non-goals**

- Exposing polling/debounce intervals as user settings — #365 explicitly chose reducing
  scheduled work over configurable cadence, and #491's adaptive tiers keep that stance.
- Changing PR polling — already batched to one GraphQL call per host
  ([028-pr-status-tracking](../028-pr-status-tracking/000-plan.md), #366).
- Replacing `git diff HEAD --shortstat` with `git status --porcelain`: the badge needs
  exact line counts, porcelain gives file counts only (2026-06-22 plan doc decision).

## Design / Approach

The anchor wave (#365) replaced polling with an activity-gated, event-driven model in
`WorktreeInfoWatcherManager`:

- **Active set**: a worktree is line-diff *active* iff it is selected or has an open
  terminal tab. `AppFeature` forwards tab lifecycle (`tabCreated` / last `tabClosed`)
  into the watcher via a new `setOpenedWorktreeIDs` command.
- **FSEvents invalidation**: active worktrees get a root-level FSEvents stream whose
  events are debounced (30 s at the time) before emitting `.filesChanged`, which drives
  the existing `GitClient.lineChanges` path in the reducer.
- **Safety refresh**: active worktrees keep a slow 300 s repeating refresh as a fallback
  for missed/coalesced FSEvents and sleep/wake; inactive worktrees get none.
- **One-shot refreshes preserved**: initial load refreshes immediately; worktrees added
  later get one deferred, phase-offset refresh (tracked in `deferredLineChangeIDs`) and
  then stay quiet; app foreground triggers a one-shot pass (`refreshLineChanges`).
- **HEAD watcher**: commits/branch switches fire a separate, faster debounce path
  (`scheduleFilesChanged`).

The follow-up (#377) added two per-repository settings, both default-on, decoded without
a schema bump (`Bool?`, `nil` ⇒ enabled): **Observe line diffs automatically** and
**Fetch pull request state**. Gating happens at the point the work would run — the
`.filesChanged` handler short-circuits before `gitClient.lineChanges`, and the PR
refresh choke point short-circuits before enqueueing.

The June wave (adaptive tiers + untracked lines, planned in the absorbed 2026-06-22 doc)
is described in [002-adaptive-debounce-and-untracked-lines.md](002-adaptive-debounce-and-untracked-lines.md).

## Alternatives & decisions

- **Event-driven reduction over interval settings** (#365): the #364 discussion
  considered exposing polling intervals; instead Prowl reduces how much work gets
  scheduled at all. FSEvents deliberately never computes diffs — worst failure mode is a
  delayed badge, never a wrong count.
- **Per-repo on/off over configurable cadence** (#377): landed in the #364 discussion as
  simpler and more useful; the PR toggle exists for API rate-limit budget rather than CPU.
- **One-size debounce cannot serve all repos** (#488 → #491): the 30 s FSEvents debounce
  chosen for worst-case repos made badges feel stuck on normal ones; resolved by sizing
  debounce per repository from the git index entry count instead of a global constant.

## Amendments

- Updated 2026-06-22: adaptive per-repo debounce tiers + untracked lines counted in the
  badge (#491) — see [002-adaptive-debounce-and-untracked-lines.md](002-adaptive-debounce-and-untracked-lines.md)
- Updated 2026-06-25: badge stuck after commit; HEAD watcher events were swallowed by the
  deferred gate (#508, #511) — see [003-deferred-refresh-after-commit.md](003-deferred-refresh-after-commit.md)
