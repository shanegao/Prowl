# 028 — Amendment: Merge Queue State & Fork/Multi-Remote Lookup

## Context

After the wave-1 batching work, two gaps surfaced in what the pipeline could *see*:

- Repos using GitHub merge queues showed a queued PR as a plain open PR — no signal
  that it was mid-merge (upstream had added this as supacode #352).
- Fork workflows broke lookup: a repository whose PR lives on the `upstream` remote
  (not `origin`) showed nothing (fork issue #452), remotes edited while the app ran
  were never picked up (fork issue #463), and the fork-fallback matching could surface
  an unrelated PR whose fork reused the same branch name.

## Change

- **PR #425** (2026-06-08, port of upstream #352 from the 2026-06-09 review batch):
  `mergeQueueEntry { position estimatedTimeToMerge state }` added to both the
  single-repo and cross-repo GraphQL queries, decoded via
  `supacode/Clients/Github/GithubMergeQueueEntry.swift`.
  `PullRequestMergeQueueStatus.swift` summarizes membership — queued only when open,
  non-draft, with a live entry; 1-based position; "<1 min left" / "Cannot merge from
  queue" / "Merge queue locked" labels. Sidebar shows a brown "Queued" text segment
  (priority over the merge-readiness label), the checks popover an "In merge queue" row,
  and the accessory badge tints brown. Fork adaptations vs upstream: text summary
  instead of upstream's PR-icon sidebar, SF Symbol `arrow.triangle.merge` instead of a
  bundled asset, and the field is requested unconditionally (no GHES < 3.8 retry
  fallback).
- **PR #456** (2026-06-17, fixes fork issue #452): resolve *current* GitHub remotes per
  refresh instead of the stale single-remote cache; query and merge fork/upstream
  candidates preferring `origin`, then `upstream`, then other remotes alphabetically;
  PR write actions resolve their target repo from the displayed PR's URL
  (`GitClient.parseGithubRemoteInfo(pullRequest.url)`), so actions hit the repo that
  owns the PR.
- **PR #469** (2026-06-17, fixes fork issue #463): `WorktreeInfoWatcherManager` gains
  per-repository `RemoteConfigMonitoring` on the git config, a debounced (2 s)
  remote-change event, refresh of PR state + code-host labels on change, and clearing of
  stale badges when a repository loses its last GitHub remote.
- **PR #519** (2026-06-27): matches are filtered by the PR's `headRepository` against
  the remote being checked (`allowedHeadRepositories` in
  `PullRequestRefreshCoordinator.swift`); the earlier fork fallback that could surface
  same-name branches from unrelated forks was removed and the behavior documented.

## Refs

- PRs #425, #456, #469, #519; fork issues #452, #463; upstream #352.
- Tests: `PullRequestMergeQueueStatusTests.swift`, `GitRemoteInfoTests` (via #456),
  `WorktreeInfoWatcherManagerTests.swift`, `GithubBatchPullRequestsTests.swift`.
- Behavior: `docs/components/github-pull-requests.md` (remote preference order,
  head-repo filter, remote watching, merge queue).

## Current state

As described; verified in the working tree 2026-07-12. Note the toolbar status button
still has no queued tint (deferred in #425, never picked up) and the GHES < 3.8
fallback remains unported — both tracked in 001-action.md's Open questions.
