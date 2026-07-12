# 038 — docs/ Agent-Facing Manual: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-06-07 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #408, #409, #410, #411, #412 (manual itself created in direct commit `49235800`) |
| **Sources** | PR descriptions #408–#412, commit `49235800`, `docs/README.md` |
| **Related** | [013-prowl-cli](../013-prowl-cli/000-plan.md) (`docs/components/cli.md`), [001-fork-bootstrap-and-release-pipeline](../001-fork-bootstrap-and-release-pipeline/000-plan.md) (release flow the sync hook lives in), `docs-ai/README.md` + `.claude/skills/write-ai-doc/SKILL.md` (the follow-on history-record system, see Amendments) |

## Background

By June 2026 Prowl had accumulated a large user-facing surface — Canvas, Shelf,
Active Agents, the `prowl` CLI, keybindings, per-repo settings — with no manual.
The design insight behind the fix: **the primary reader of Prowl docs is an AI
agent, not a human**. Users point their coding agent at the docs and ask
questions ("how do I broadcast a command to every agent?"); the agent reads the
relevant file and answers. That framing shaped everything: plain Markdown, no
images required, descriptive filenames, keyword-searchable, quotable.

A manual alone is not enough — three follow-on problems were anticipated:

1. **Rot**: docs drift from the implementation unless something forces re-sync.
2. **Release freshness**: a release tag should always contain docs that match it.
3. **Distribution**: end users (and their agents) must be able to find the docs
   without cloning the repo.

## Goals

- Ship a complete agent-readable manual under `docs/`: an index (`README.md`),
  a pitch (`overview.md`), a mental model (`concepts.md`), one file per feature
  under `components/`, and exact-lookup tables under `reference/` that name
  their source-of-truth Swift files.
- Keep it accurate with two complementary mechanisms: a one-line change-time
  rule in `AGENTS.md`, plus a periodic diff-driven audit (the `sync-docs`
  skill) that is deliberately conservative.
- Hook the audit into the release flow so docs ship correct inside every tag.
- Make the docs reachable by end users: bundle them into the app, add an
  "Ask Agent About Prowl" help action, and put a copyable agent prompt in the
  repository `README.md`.

### Non-goals

- A human-oriented docs website (deferred; the baseline file was deliberately
  named `.sync-meta.json` as a dotfile so a future site won't render it).
- Rewriting or restyling docs during sync — sync only restores factual accuracy.

## Design / Approach

- **Manual structure** (`49235800`, 20 files): `docs/README.md` is the map;
  `components/*.md` are self-contained per-feature manuals; `reference/`
  (`keyboard-shortcuts.md`, `settings-fields.md`) holds exhaustive tables.
- **Maintenance layer 1 — change-time rule** (#408): a single line in
  `AGENTS.md`'s `## Rules`: when you change user-facing behavior, update the
  matching `docs/` file in the same change. One line only, to avoid bloating
  every session's context.
- **Maintenance layer 2 — `sync-docs` skill** (#408): diff `HEAD` against a
  **committed** commit baseline, scoped to `supacode/` / `ProwlCLI/` etc.; map
  changed source → affected docs; verify claims against source-of-truth files
  (`AppShortcuts.swift`, settings types, `ProwlCLI/`); apply minimal edits only
  where behavior actually changed; bump the baseline; flag large/ambiguous
  changes for a human instead of applying silently.
- **Baseline storage** (#410): moved from `.claude/skills/sync-docs/baseline.md`
  to `docs/.sync-meta.json` — mutable state shouldn't churn the skill folder,
  and it's conceptually docs metadata. JSON (`last_synced_commit`,
  `last_synced_date`, `note`) so release tooling can read it with `jq`.
- **Release hook** (#411): a sync-docs step in the `release` skill after the
  clean-tree check and **before** version bump + tag ("never tag first"), so
  the docs commit is an ancestor of the release tag and ships inside it.
- **Distribution** (#412): an `embed-docs` Makefile target rsyncs `docs/` into
  `Contents/Resources/docs` (excluding `.sync-meta.json`; output gitignored),
  wired into `build-app`/`archive`/`test`; `SupacodePaths.bundledDocs*` resolve
  the runtime path; an "Ask Agent About Prowl" sheet (sidebar Help menu +
  macOS Help menu) hands the user a ready-to-paste, localized prompt pointing
  their agent at the bundled docs; the repo `README.md` gets an equivalent
  English prompt pointing at the raw GitHub `docs/README.md`.

## Alternatives & decisions

- **Baseline value at release sync** (#411): set `last_synced_commit` to the
  HEAD at sync time (the commit being released), not to the subsequent doc
  commit — a commit can't contain its own hash, so the alternative needs a
  second commit and is circular. No diff difference either way, since the
  doc/bump/CHANGELOG commits touch no files inside the sync scope.
- **Conservative-by-default sync** (#408): docs change only when a documented
  fact is wrong or a real feature was added/removed; internal refactors and
  wording drift are ignored. Chosen explicitly to keep churn low.
- **Help action without TCA** (#412): a lightweight shared `@Observable`
  presenter + a sheet on the main window, avoiding reducer changes for a
  purely presentational feature.
- **Localized prompts hardcoded per language** (#412): English, Simplified and
  Traditional Chinese, Japanese, with English fallback — resolved from the
  *system* preferred language (the app itself ships English-only), and every
  variant asks the agent to reply in the user's preferred language.

## Amendments

- Updated 2026-07-12: `docs-ai/` history-record system + `write-ai-doc` skill
  added as the history-side complement to `docs/` — see
  [002-docs-ai-follow-on.md](002-docs-ai-follow-on.md)
