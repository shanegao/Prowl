# 006 — Startup Performance: Amendment — Upstream Contribution Outcome

## Context

Immediately after landing in the fork, the two generally-useful startup optimizations were
offered to upstream `supabitapp/supacode` from dedicated contribution branches
(`contrib/parallel-loading`, `contrib/direct-bundled-wt`); the snapshot cache was offered
as well.

## Change

- upstream #160 "Parallelize repository startup loading" — merged upstream 2026-03-22
  (fork PR #15's change re-landed as commit `8dd8eac5`).
- upstream #161 "Run bundled wt discovery directly" — merged upstream 2026-03-22
  (fork PR #17's change re-landed as commit `ed27b311`).
- upstream #162 "Add repository snapshot startup cache" — closed unmerged; the snapshot
  cache (fork PR #18) remains fork-only.

## Refs

Fork PRs #15, #17, #18; upstream #160, #161, #162. The upstream review ledger rows for
these live in `docs-ai/017-upstream-sync-process/upstream-ledger.md`.

## Current state

Parallel loading and direct `wt` execution are shared code with upstream and evolve through
normal upstream syncs. The snapshot cache is fork-maintained code that must be watched for
conflicts during upstream syncs; the ledger's "Pending upstream (#162)" status is stale —
the upstream PR was closed without merging.
