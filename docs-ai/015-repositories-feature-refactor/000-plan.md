# 015 — RepositoriesFeature Refactor: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-03 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #131, #403, #426 |
| **Sources** | Fork issue #114, PR descriptions |
| **Related** | [019-worktree-creation-and-lifecycle](../019-worktree-creation-and-lifecycle/000-plan.md), [028-pr-status-tracking](../028-pr-status-tracking/000-plan.md) |

## Background

By late March 2026, `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` had
grown past 4,000 lines with roughly 114 action handlers and about 220 `Action` enum cases.
Fork issue #114 recorded two concrete costs:

1. **TCA `@CasePathable` macro type-check failures.** Adding new cases to the huge `Action`
   enum could make the compiler fail with generic "type cannot conform to Reducer" errors,
   because the macro expansion exceeded type-check budgets. This was hit for real in PR
   #113 when adding a `setLaunchRestoreMode` action — a hard blocker, not just a smell.
2. **Developer velocity.** Every change required understanding the whole file, and
   incremental build times suffered.

The issue was filed as "not urgent, but should be done before the next round of feature
work that needs to add actions to RepositoriesFeature".

## Goals

- Split the monolithic `Reduce` body into focused sub-reducers so the `Action` enum and
  handler logic are grouped by domain.
- Keep `RepositoriesFeature.State` flat — no state re-nesting.
- Minimize call-site churn during the transition.
- Preserve behavior; existing `RepositoriesFeatureTests` must keep passing.

**Non-goals**

- No behavior or UX changes; this is a pure decomposition.
- No extraction of state into child feature states (`Scope`-per-child was considered as a
  mechanism, but slicing `State` was not a goal).

## Design / Approach

Issue #114 proposed candidate groupings based on the observed action-handler clusters:

| Group | Actions (examples) |
| --- | --- |
| Worktree creation/deletion/archive | `createRandomWorktree`, `archiveWorktree*`, `deleteWorktree*`, `worktreeCreationPrompt` |
| Pull request actions | `pullRequestAction`, merge/close/checkout flows |
| GitHub integration | `refreshGithubIntegration*`, `repositoryPullRequestsLoaded` |
| Pin/reorder | `pinWorktree`, `unpinWorktree`, `*Moved` |
| Repository management | `requestRemoveRepository`, `repositoryRemoved`, `openRepositories` |

Each sub-reducer owns a slice of the `Action` enum (as a nested namespaced action enum)
plus the corresponding handler logic; the ~40 private helper functions move alongside
their consumers. The implementation (PR #131) realized this as grouped action cases —
`Action.worktreeCreation(...)`, `.worktreeLifecycle(...)`, `.worktreeOrdering(...)`,
`.githubIntegration(...)`, `.repositoryManagement(...)` — reduced by dedicated reducer
helpers composed with `CombineReducers`, while `State` stays flat.

Two later code-health waves belong to the same thread:

- PR #403 (2026-06-07) extended the file-splitting discipline repo-wide (non-test sources
  under 1,000 lines), which for this feature extracted the remaining core reducer, loading,
  selection, and state-query logic into dedicated extension files.
- PR #426 (2026-06-08) cleaned up the worktree-creation dependency surface by introducing
  a `GitWorktreeCreateRequest` value instead of long positional parameter lists on
  `GitClient.createWorktreeStream`.

## Alternatives & decisions

- **Compatibility shims: temporary only.** PR #131 initially kept static forwarding
  constructors on `RepositoriesFeature.Action` (old flat case names constructing the new
  grouped cases) to limit call-site churn — then, still within the same PR, migrated all
  call sites and tests to the grouped syntax and deleted the ~300 lines of shims. The
  merged result carries no compatibility layer.
- **Grouped cases over `Scope` children.** The issue floated `Scope` composition; the
  implementation chose `CombineReducers` over a shared flat `State` with namespaced action
  groups, avoiding state re-nesting and keeping views/tests addressing one feature.
- **PR actions folded into GitHub integration.** The plan's separate "pull request
  actions" group ended up inside the `githubIntegration` group (handled in
  `RepositoriesFeature+GithubIntegration.swift`) rather than as its own sub-reducer.

## Amendments

- Updated 2026-06-07: repo-wide large-file split adds five more RepositoriesFeature
  extension files (PR #403) — see [002-split-large-swift-files.md](002-split-large-swift-files.md)
- Updated 2026-06-08: `GitWorktreeCreateRequest` groups worktree stream creation inputs
  (PR #426) — see [003-worktree-stream-request-api.md](003-worktree-stream-request-api.md)
