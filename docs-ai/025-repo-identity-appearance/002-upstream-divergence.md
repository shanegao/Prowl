# 025 — Amendment: Upstream Title/Color Divergence

## Context

The fork and upstream built overlapping features almost simultaneously: upstream added
per-repository title/color (upstream #276, `9bae228e`, committed 2026-04-25) two days
before the fork merged its repo-level identity model (#240, 2026-04-27). Upstream later
moved identity down a level entirely: per-*worktree* title + color (upstream #308
`4d07b0a5`, 2026-05-29; upstream #367 `563e6913`, 2026-05-30), reviewed in the fork's
v0.9.0 → v0.10.2 upstream batch. Both tracks overlap what this entry built, so each
upstream review had to decide whether to port, merge, or ignore.

## Change

No code change — a standing decision, recorded in the upstream review ledger
(→ `docs-ai/017-upstream-sync-process/upstream-ledger.md`):

- **2026-05-08 review** (post-v0.8.5 batch): upstream #276 skipped — "Repository
  title/color conflicts with Prowl's richer repository appearance model." The fork's
  model already covered title (per-repo `customTitle`), color (system palette), and
  icons (SF Symbol presets / free-form / user PNG-SVG) across three render surfaces,
  backed by one global `@Shared` dictionary; upstream's feature was a subset with a
  different persistence shape.
- **2026-06-09 review** (post-v0.10.2 batch): upstream #308/#367 per-worktree
  title+color skipped — "fork uses its richer repo-level appearance model, consistent
  with the earlier #276 decision."

The consequence is a deliberate model divergence, not a gap to close later: in the
fork, visual identity attaches to the *repository*; per-worktree distinction is served
at the tab layer (custom tab titles/icons,
[022-tab-title-and-icon](../022-tab-title-and-icon/000-plan.md)). Future upstream
appearance work touching these areas should be evaluated against this baseline rather
than ported mechanically.

## Refs

- upstream #276 (`9bae228e`), upstream #308 (`4d07b0a5`), upstream #367 (`563e6913`)
- Ledger entries 2026-05-08 and 2026-06-09 —
  `docs-ai/017-upstream-sync-process/upstream-ledger.md`

## Current state

As of 2026-07-12 the fork has no per-worktree title or color override (no
`WorktreeAppearance`-like type exists in the tree); repo-level appearance remains the
only repo identity mechanism, and per-tab identity is handled by entry 022.
