# 013.002 — `prowl agents`: Active Agents roster over the CLI

## Context

Issue #330 asked to expose the Active Agents roster (already shown in the sidebar
panel) through the CLI, so automation can answer "which of my agents are working /
blocked / done?" without screen-scraping. Prerequisite work made agent detection
scheduling reliable independently of whether the Active Agents panel is expanded or any
UI-only preference — the detection pipeline itself is documented in
[030-agent-status-detection](../030-agent-status-detection/000-plan.md). Plan source:
`doc-onevcat/plans/2026-06-13-prowl-cli-agents-plan.md` (absorbed here).

## Change

A read-only `prowl agents` / `prowl agents --json` command (schema
`prowl.cli.agents.v1`). Key semantics as planned and shipped:

| Aspect | Decision |
| --- | --- |
| Status source | Per-pane agent detection state (`working \| blocked \| done \| idle`, plus `raw_state`) — deliberately distinct from the worktree-level `task.status` (`running \| idle \| null`) that `prowl list` reports |
| Membership | Only panes with a currently detected agent or a retained Active Agents entry; empty shells and ordinary commands excluded. Idle/done entries included by default (mirrors panel retention); automation filters by status |
| Identity | `id` equals `pane.id` (surface UUID), matching Active Agents entries; `type` is the normalized detected agent, `name` preserves command aliases |
| `project` vs `worktree` | Both exposed: `project` is the display-oriented repo/branch resolved from the agent's working directory (same rules as the panel); `worktree` is the actual terminal owner used for `focus`/`read`/`send` targeting. An agent may run outside the worktree owning its pane |
| Per-agent metadata | Nested `project`, `worktree`, `tab` (with `selected`), `pane` (with `index`, `cwd`, `focused`), `last_changed_at` (ISO-8601) |
| Text output | One scannable line per agent, ranked `blocked` → `working` → `done` → `idle`, insertion order preserved within a group |
| No switch subcommand | Deliberate: resolve `pane.id` from `agents --json`, then use existing `prowl focus/read/send --pane <id>` |
| No filter flags in v1 | JSON + `jq` deemed sufficient; `--status` filters deferred |

## Refs

- PR #442 (merged 2026-06-14), closing issue #330.
- Plan doc: `doc-onevcat/plans/2026-06-13-prowl-cli-agents-plan.md`.
- Manual validation in #442 also confirmed multi-instance socket behavior: only the app
  owning the default socket serves default CLI commands; a dev instance needs a
  matching `PROWL_CLI_SOCKET` on both sides.

## Current state

- CLI: `ProwlCLI/Commands/AgentsCommand.swift`; text rendering with the status ranking
  map in `ProwlCLI/Output/OutputRenderer.swift` (`renderAgents`).
- App: `supacode/CLIService/AgentsCommandHandler.swift`; payload models in
  `supacode/CLIService/Shared/AgentsCommandPayload.swift`.
- The payload later gained an optional `session` field (id + confidence, rendered as a
  `session=` suffix in text mode) as part of native agent session detection — see
  [045-native-agent-session-detection](../045-native-agent-session-detection/000-plan.md).
- Skill/manual coverage: `skills/prowl-cli/SKILL.md` and `docs/components/cli.md`
  document the command; no contract doc exists under `docs-ai/013-prowl-cli/contracts/`
  (noted in [001-action.md](001-action.md) open questions).
