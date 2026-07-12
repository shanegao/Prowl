# 028 — Amendment: Flicker Elimination & Explicit No-PR Semantics

## Context

Two visible flickers remained after all previous waves, both rooted in the pipeline
conflating distinct states:

1. Sidebar PR labels briefly disappeared on every 30/60 s refresh cycle: a transient
   empty result from `resolveGithubRemoteInfos`, or a partial fetch failure across
   multiple remotes/hosts, was treated the same as "confirmed: no PR" and cleared state.
2. The badge flashed red "Blocked" before settling: GitHub computes GraphQL `mergeable`
   asynchronously and returns `"UNKNOWN"` mid-calculation, which
   `PullRequestMergeReadiness` mapped to `.blocked`.

## Change

The chain is #533 → #538 → #539:

- **PR #533** (2026-07-05, community contribution): introduce tri-state semantics.
  `Outcome.refreshed` carries `confirmedNoPrBranches: Set<String>`, computed by the
  coordinator only when *all* candidate repos for a branch were queried successfully.
  Apply rules: branch in `prsByBranch` → update; branch in `confirmedNoPrBranches` →
  clear; in neither (partial failure) → preserve existing state. A `Set` was chosen
  over `[String: GithubPullRequest?]` deliberately, because a Swift dictionary's
  `dict[key] = nil` removes the key rather than storing `.some(nil)`.
- **PR #538** (2026-07-05, supersedes #533, keeping its commits): the design was sound
  but the implementation had two gaps —
  1. The confirmed-no-PR clear was dead code: `prsByWorktreeID[worktreeID] = nil` on a
     `[Worktree.ID: GithubPullRequest?]` removed the key, so the downstream handler
     (which iterates present keys) never saw the clear. Fixed with
     `updateValue(nil, forKey:)`; a red-check test proved the old version fails.
  2. Cross-host suppression was arrival-order dependent: a `.failed` batch arriving
     before the final `.refreshed` outcome left the accumulated confirmed set intact, so
     a healthy host could still clear a PR living on the failed host. Failed batches are
     now tracked per repository (`prRefreshFailedBatchRepositoryIDs`) and confirmed
     clears are suppressed whenever any batch failed, in either order.
  All #533 test call sites had passed `confirmedNoPrBranches: []` — the non-empty path
  was untested, which is why the no-op was invisible; #538 added reducer and coordinator
  coverage for both orderings.
- **PR #539** (2026-07-08): preserve the last-known `mergeable` and `mergeStateStatus`
  at the reducer level when the incoming value is `UNKNOWN`, applied in
  `repositoryPullRequestsLoaded` before the equality check so the UI never sees the
  intermediate state. All other fields (title, checks, commits) update normally; a first
  load with `UNKNOWN` stays `UNKNOWN` (nothing to preserve).

## Refs

- PRs #533, #538, #539.
- Code: `supacode/Features/Repositories/Reducer/RepositoriesFeature+GithubIntegration.swift`
  (`pullRequestsByWorktreeID`, `prRefreshFailedBatchRepositoryIDs`, the UNKNOWN
  preservation), `supacode/Features/Repositories/BusinessLogic/PullRequestRefreshCoordinator.swift`
  (confirmed-set computation).
- Tests: `BatchedPullRequestRefreshReducerTests.swift`,
  `PullRequestRefreshCoordinatorTests.swift`, `RepositoriesFeatureTests.swift`
  (UNKNOWN-preservation cases).

## Current state

As described; verified in the working tree 2026-07-12: the explicit clear uses
`updateValue(nil, forKey:)` with an in-code comment documenting the nil-literal pitfall,
failed-batch tracking suppresses confirmed clears order-independently, and UNKNOWN
`mergeable` carries the previous known value forward.
