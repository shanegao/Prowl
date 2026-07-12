# 038 — docs/ Agent-Facing Manual: Amendment — docs-ai History Record System

## Context

`docs/` deliberately documents only *current* behavior: the `sync-docs` skill
keeps it minimal and present-tense, so design rationale and the evolution of
features had no durable home — they were scattered across PR bodies and a
fork-private notes directory that is being dissolved into `docs-ai/`.

## Change

On 2026-07-12 a second documentation set was introduced as the history-side
complement to `docs/`:

- `docs-ai/` — numbered, spec-driven work records: `000-plan.md` written before
  implementation, `001-action.md` after, `002+` amendments for later waves;
  indexed by `docs-ai/README.md`. Non-numbered files inside an entry folder are
  living documents (runbooks, contracts) that keep being updated.
- The `write-ai-doc` skill (`.claude/skills/write-ai-doc/SKILL.md`) creates and
  amends entries.
- `AGENTS.md` / `CLAUDE.md` gained a rule to write the plan entry before
  starting medium/large features, decision-shaping fixes, or non-trivial
  investigations, and a header pointer to `docs-ai/README.md`.
- Prior fork history (including this entry) was backfilled retrospectively.

Division of labor going forward: `docs/` is the user-facing behavior manual
(what Prowl does today, kept accurate by `sync-docs`); `docs-ai/` is the
engineering history (how and why it got that way). `sync-docs` governs only
`docs/`.

## Refs

- `docs-ai/README.md`
- `.claude/skills/write-ai-doc/SKILL.md`
- `AGENTS.md` / `CLAUDE.md` (write-ai-doc rule in `## Rules`; `docs-ai/`
  pointer in the header line)
