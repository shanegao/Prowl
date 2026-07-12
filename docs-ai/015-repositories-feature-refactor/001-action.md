# 015 — RepositoriesFeature Refactor: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-31 | Fork issue filed: 4,000+ line reducer, `@CasePathable` macro type-check blocker | issue #114 |
| 2026-04-03 | Action enum split into grouped cases; handler logic moved to sub-reducer helpers (initially behind compatibility shims) | PR #131 (`33bc7b79`) |
| 2026-04-03 | Same PR: all call sites/tests migrated to grouped syntax; ~300 lines of shims removed; sub-reducers extracted into dedicated files; `CancelID` moved into the struct | PR #131 (`cb7e441a`, `292546eb`, `c00bd5f4`) |
| 2026-06-07 | Repo-wide large-file split; RepositoriesFeature gains `+CoreReducer`, `+RepositoryLoading`, `+Selection`, `+StateQueries`, `+WorktreeState` extensions | PR #403 — see [002](002-split-large-swift-files.md) |
| 2026-06-08 | `GitWorktreeCreateRequest` replaces positional parameters on `createWorktreeStream` | PR #426 — see [003](003-worktree-stream-request-api.md) |

PR #131 touched 27 files (+2,952/−2,693); `RepositoriesFeature.swift` alone dropped by
roughly 2,500 lines, with the logic landing in five new extension files
(`+WorktreeCreation` 619, `+WorktreeLifecycle` 505, `+GithubIntegration` 551,
`+RepositoryManagement` 222, `+WorktreeOrdering` 186 lines at merge time).

## Outcome & current state (as of 2026-07-12)

`supacode/Features/Repositories/Reducer/` is now a directory of focused files:

- `RepositoriesFeature.swift` (~580 lines) — `State`, the grouped `Action` enum, and a
  `body` that composes `CombineReducers { Reduce(reduceCore); worktreeCreationReducer;
  worktreeLifecycleReducer; worktreeOrderingReducer; githubIntegrationReducer;
  repositoryManagementReducer; workspaceCreationReducer; Scope(\.activeAgents, ...) }`
  plus `.ifLet` presentation reducers for the worktree/workspace creation prompts.
- Grouped action cases in the current tree: `.worktreeCreation`, `.worktreeLifecycle`,
  `.worktreeOrdering`, `.githubIntegration`, `.repositoryManagement`, and
  `.workspaceCreation` — the last added by later workspace/plain-folder work
  (see [010-plain-folder-support](../010-plain-folder-support/000-plan.md)), which reused
  the pattern established here.
- Sub-reducer extension files from #131: `RepositoriesFeature+WorktreeCreation.swift`,
  `+WorktreeLifecycle.swift`, `+WorktreeOrdering.swift`, `+GithubIntegration.swift`,
  `+RepositoryManagement.swift`.
- Further extensions from #403: `+CoreReducer.swift` (the `reduceCore` catch-all switch),
  `+RepositoryLoading.swift`, `+Selection.swift`, `+StateQueries.swift`,
  `+WorktreeState.swift`.
- Later feature work added `+WorkspaceChildren.swift`, `+WorkspaceCreation.swift`, and
  `WorkspaceCreationPromptFeature.swift` alongside `WorktreeCreationPromptFeature.swift`
  (not part of this refactor, but shaped by its layout).

The worktree stream request API from #426 is current: `GitWorktreeCreateRequest` is
defined in `supacode/Clients/Git/GitClientTypes.swift` and consumed by
`GitClient.createWorktreeStream(_:)` (`supacode/Clients/Git/GitClient.swift`), the TCA
dependency in `supacode/Clients/Repositories/GitClientDependency.swift`, and the reducer
in `RepositoriesFeature+WorktreeCreation.swift`.

## Deviations from plan

- The plan's "pull request actions" candidate group was merged into the GitHub
  integration group instead of becoming a sixth sub-reducer; `pullRequestAction` is
  handled in `RepositoriesFeature+GithubIntegration.swift`.
- The compatibility-shim strategy described in the PR summary was superseded within the
  same PR: shims were added and then fully removed before merge, so no transitional API
  ever shipped.

## Open questions

- `RepositoriesFeature+GithubIntegration.swift` is currently ~1,027 lines, slightly above
  the 1,000-line ceiling that PR #403 set for non-test sources — later PR-status feature
  growth has re-crossed the threshold this refactor established.
