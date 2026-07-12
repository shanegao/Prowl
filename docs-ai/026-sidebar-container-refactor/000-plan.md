# 026 — Sidebar Container Refactor: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-03 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #250, #252 (amendment: #254) |
| **Sources** | `doc-onevcat/plans/2026-05-03-sidebar-container-refactor-plan.md` (absorbed here; original removed in the docs-ai migration), fork issues #249 and #222, PR #250/#252/#254 descriptions |
| **Related** | [015-repositories-feature-refactor](../015-repositories-feature-refactor/000-plan.md), [032-performance-hardening](../032-performance-hardening/000-plan.md), [033-ui-refresh-2026-05](../033-ui-refresh-2026-05/000-plan.md), [042-project-workspaces](../042-project-workspaces/000-plan.md), `docs/components/repositories-and-worktrees.md` |

## Background

The repository sidebar was a single SwiftUI `List(selection:)` in which repository
headers and expanded worktree rows were *separate list cells*, while the app's data model
treats each repository as one reorderable unit. That structural mismatch produced three
user-visible bugs:

1. **Wrong drag insertion indicator**: dragging a repository downward across an expanded
   repository drew the indicator *between* the target's header and its worktree rows —
   `List` only knows row boundaries, not repository boundaries.
2. **Unstable bulk expand/collapse animations**: collapsing many repositories at once
   removed a large set of cells in one transaction and `List` cell reuse made tail items
   animate from wrong starting positions. This became prominent when PR #250 added the
   sidebar-header expand/collapse-all toggle, and was filed as issue #249.
3. **Drag-time flicker** (issue #222): live terminal notification / task state updates
   reached rows mid-drag, and notification-driven "move worktree to top" reordering could
   mutate row order with animation while a drag session was active.

The old `List` also carried a lot of implicit behavior (multi-selection, plain-folder
repository selection, native `onMove` for repositories and pinned/unpinned worktrees,
`ScrollViewReader.scrollTo` reveal, native styling/accessibility) that any replacement
had to preserve or intentionally re-own.

## Goals

- Make each repository one stable visual and drag unit: repository containers are the
  only repository-level siblings in the outer stack; worktrees are children *inside*
  the container.
- Repository drag insertion indicators render only at repository-container boundaries.
- Expand/collapse animates inside the container, so bulk collapse no longer reshapes the
  outer list.
- Defer notification-driven worktree reordering while a sidebar drag is active
  (fixes #222-class flicker), flushing deterministically on drag end.
- Keep existing reducer ordering actions and persistence paths
  (`pinnedWorktreesMoved`, `unpinnedWorktreesMoved`, repository order, `@Shared`
  collapsed-repository-ID write-back) unchanged.
- Preserve selection semantics (multi-select, plain folders, Canvas/Shelf/Archived
  rows), focused values, context menus, drag previews, root-level URL drop, and
  reveal-in-sidebar.

### Non-goals

- Cross-repository worktree drag (the model does not support moving worktrees between
  repositories).
- Finder-grade keyboard navigation; V1 only preserves the existing command shortcuts
  (`selectNextWorktree`, `selectPreviousWorktree`, reveal, numbered hotkeys).
- Moving Canvas, Shelf, and the footer into the scroll content — they stay safe-area
  inset chrome around the list.

## Design / Approach

The plan (kept as `doc-onevcat/plans/2026-05-03-sidebar-container-refactor-plan.md` at
the time, absorbed here) chose a full custom container over patching `List`:

- **M1 — reducer-level drag gate** (hard prerequisite): add sidebar drag state to
  `RepositoriesFeature`; while a drag is active, `worktreeNotificationReceived` records
  pending worktree IDs instead of reordering immediately; drag end flushes pending
  reorders in deterministic order, dropping stale IDs, and persists only when a reorder
  is actually applied.
- **Pure presentation model**: a `SidebarPresentation` struct built by pure functions
  from reducer state, with one `SidebarItem` per repository
  (`listHeader` / `repository` / `failedRepository` / `archivedWorktrees`), worktree
  sections nested inside `SidebarRepositoryContainerModel`, stable
  `SidebarScrollID`s, and pure drop-destination mapping that dispatches the *existing*
  ordering actions. High-frequency terminal state stays in leaf views, not in the
  presentation model.
- **Container view**: replace `List(selection:)` with `ScrollViewReader` + `ScrollView`
  + `LazyVStack` where `RepositoryContainerRow`s are the outer rows. Selection visuals,
  click handling, and the `sidebarSelections → setSidebarSelectedWorktreeIDs` sync
  become explicit code instead of `List` side effects.
- **Custom drag/drop**: repository rows drag a repository-ID payload with a custom
  insertion indicator drawn at container boundaries; worktree reorder stays scoped to
  pinned/unpinned sections inside one container, with main/pending rows non-movable.
- Phased execution (baseline metrics → M1 → presentation model + tests → render-only
  new path behind a switch → explicit selection/reveal → custom repo reorder → custom
  worktree reorder → delete the old `List` path), with a manual verification matrix of
  18 checks and reducer/presentation unit tests.

## Alternatives & decisions

- **Option A — keep `List`, nest worktrees inside one repository row**: rejected;
  nested selectable rows no longer participate in `List(selection:)`, worktree `onMove`
  becomes awkward, and it leaves a hard-to-debug mix of native and custom drag logic.
- **Option B — full `ScrollView` + explicit rows**: chosen; model and visual structure
  match, drag/drop and selection become explicit and testable, and `List` cell reuse is
  eliminated as a bug class — at the cost of re-owning selection, keyboard, reorder,
  and accessibility.
- **Option C — drag-time freeze only**: demoted from alternative to the mandatory M1
  prerequisite; it helps #222 but cannot fix the insertion indicator because row
  boundaries stay wrong.
- **Do not fix the indicator via reducer index changes** — it is a symptom of `List`
  row structure, not of the persisted ordering logic.
- **`LazyVStack` first, plain `VStack` as fallback**, to be decided by expand/collapse
  latency and drag frame-stability metrics rather than visual impression (this fallback
  was in fact taken later — see 001-action.md).
- **Failed repository rows are reorderable** and persist through the same root ordering
  path (the plan required making this an explicit product decision either way).

## Amendments

- Updated 2026-05-05: Add Repository moved from the sidebar footer to the (now
  unconditional) "Repositories" header with a zero-repo onboarding hint (#254); both
  affordances were later superseded — see
  [002-add-repository-entry-point.md](002-add-repository-entry-point.md)
