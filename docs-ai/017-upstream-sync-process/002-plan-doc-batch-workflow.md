# 017 — Amendment: Plan-Doc-First Batch Workflow (2026-07 round)

## Context

The first four review rounds wrote their conclusions directly into the ledger after the
fact. The post-v0.10.5 round (70 upstream commits, v0.10.3→v0.10.5) was large enough
that decisions needed to be recorded — and reviewable — *before* any port PR was
opened, and two upstream tracks were too big to either port or silently skip.

## Change

The round introduced a three-artifact workflow on top of the existing process:

1. **Batch plan doc first** (PR #547, merged 2026-07-08): a standalone investigation
   record with per-commit verdicts in four buckets — already present in fork, port,
   skip (decision recorded), defer with tracking — plus a PR checklist. Kept verbatim
   in this folder as [batch-2026-07-06-post-v0.10.5.md](batch-2026-07-06-post-v0.10.5.md);
   the ledger entry for the round points at it instead of restating rationale.
2. **Port PRs referencing the plan**: each port theme landed as its own fork PR —
   #541 (gh detection & login-shell hardening), #542 (Zed Preview / IDEA EAP / Nova),
   #543 (`TERM_PROGRAM=prowl`), #544 (symlink-preserving JSON config writes),
   #545 (notification sound picker, fork default kept as the classic chime), #546
   (mute notifications for the viewed surface, stacked on #545). All merged 2026-07-08.
3. **Linear-tracked deferrals**: work too large for the round is moved out of the
   ledger's "re-evaluate next round" limbo into tracked issues — the remote SSH track
   (≈ +12k/−3.7k lines) → **CLAW-98**, the searchable base-ref filter → **CLAW-99** —
   each with the fork's preferred adoption approach captured in the issue.

The round also fixed the baseline-advance ordering: the baseline moves to the new tip
(`bcbc4059`) only after the batch's port PRs merge (PR #549, commit `2197d13e`,
2026-07-09).

## Refs

- PR #547 (batch plan), PRs #541–#546 (ports), PR #549 (baseline advance)
- [batch-2026-07-06-post-v0.10.5.md](batch-2026-07-06-post-v0.10.5.md) (verbatim record)
- [upstream-ledger.md](upstream-ledger.md) — entry "2026-07-09 — Review through post-v0.10.5"
- Linear CLAW-98, CLAW-99 (CLAW team, project Prowl)

## Current state

Baseline is `bcbc4059` (post-v0.10.5). CLAW-98/CLAW-99 remain open deferrals. The next
`/check-upstream-changes` run diffs against `bcbc4059` only. Whether future rounds
always start with a batch plan doc is a per-round judgment; the pattern is available
and this round is its precedent.
