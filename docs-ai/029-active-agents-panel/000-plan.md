# 029 — Active Agents Panel: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-09 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #274, #335, #336, #344, #363, #386, #475 |
| **Sources** | `doc-onevcat/plans/2026-05-09-active-agents-panel-plan.md` (absorbed here; original removed in the docs-ai migration), `doc-onevcat/active-agents-panel-task-log.md` (absorbed here; original removed in the docs-ai migration), change-list entry 2026-05-09 (Ghostty fork patch), PR descriptions |
| **Related** | [030-agent-status-detection](../030-agent-status-detection/000-plan.md), [013-prowl-cli/002-agents-command](../013-prowl-cli/002-agents-command.md), `docs/components/active-agents.md`, `docs/components/agent-detection.md` |

## Background

Before this work, Prowl's notion of "is an agent running" was weak: a two-state
`idle`/`running` per-worktree status (`supacode/Domain/WorktreeTaskStatus.swift`) whose
only signal source was Ghostty's OSC progress state. That meant (a) nothing was detected
when shell integration was missing or the agent did not report progress; (b) multiple
split panes in one tab each running an agent could not be distinguished; (c) there was
no `blocked` state (agent waiting for user input); (d) there was no cross-worktree
global view of running agents.

The goal was a new **Active Agents** panel: docked at the bottom of the left sidebar
(below the worktree list), drag-resizable, collapsible via a footer button with a
slide-in-from-bottom animation, listing **every** running agent across all
worktrees/tabs/panes with a four-level status (working / blocked / done / idle), and
click-to-focus jumping to the owning worktree → tab → pane.

The reference implementation is [herdr](https://github.com/ogulcancelik/herdr)
(Rust, ratatui). The plan deeply borrowed its hybrid process-detection +
screen-heuristics algorithm, adapted to Swift/GhosttyKit. Work was split into
**Phase 1: detection layer rewrite** (the part that decides whether the whole feature
is trustworthy) and **Phase 2: UI and wiring**.

## Goals

- Per-surface (pane-level) agent detection: identity, liveness, and state.
- Four display states: `working`, `blocked`, `done` (unread idle), `idle`, where
  `done` is derived as `idle && !seen`.
- Sidebar panel listing all detected agents globally; click a row to focus its surface.
- Panel height persisted and drag-resizable; hidden/shown state persisted; animated
  slide from the bottom edge.
- Full unit-test coverage for the pure detection logic (classifier, screen heuristics,
  state stabilization), porting herdr's `detect.rs` test fixtures.

### Non-goals (deferred)

- Hook/socket integration where agents self-report authoritative state (herdr's
  socket API model) — explicitly out of scope for Phase 1/2; treated as the eventual
  fix for the known fragility of text heuristics. (This later materialized as entry
  [045-native-agent-session-detection](../045-native-agent-session-detection/000-plan.md).)
- Automated end-to-end tests against a real pty — manual smoke testing instead.

## Design / Approach

### Prerequisite: Ghostty fork with a PID export

GhosttyKit's C API did not expose a surface's child process PID, which herdr-style
process detection requires. Decision: create an `onevcat/ghostty` fork with
per-upstream-tag patched branches (`release/v<TAG>-patched`, starting at
`release/v1.3.1-patched`), carrying a small patch that exports
`ghostty_surface_pid()`. Branches are never history-rewritten; upgrading to a new
upstream tag means creating a new branch and cherry-picking the patch set. The upgrade
procedure is a living runbook, now at
[`docs-ai/007-ghostty-embedding-integration/ghostty-fork-sync.md`](../007-ghostty-embedding-integration/ghostty-fork-sync.md).

### Phase 1 — detection layer

Three-layer responsibility split (from herdr's INTEGRATIONS.md):

- **Process detection owns identity and liveness**: read the pty's foreground process
  group, list PIDs in that group (`proc_pidinfo`, `proc_listallpids`), recover
  `argv[0]`/cmdline via `sysctl(KERN_PROCARGS2)` —
  `supacode/Infrastructure/AgentDetection/ProcessDetection.swift`.
- **Agent classifier** maps process names to a `DetectedAgent` enum (initially herdr's
  full list of 11: pi, claude, codex, gemini, cursor, cline, opencode, copilot, kimi,
  droid, amp), including wrapped-runtime handling (`node /path/to/codex` → codex) with
  priority scoring — `supacode/Infrastructure/AgentDetection/AgentClassifier.swift`.
- **Screen heuristics decide fallback state**: per-agent pure functions
  `(String) -> AgentRawState` over the viewport text (via `ghostty_surface_read_text`),
  checking blocked → working → default idle, ported from herdr `detect.rs` together
  with its test fixtures — `supacode/Infrastructure/AgentDetection/ScreenHeuristics.swift`.

State machine: internal `AgentRawState = {working, blocked, idle, unknown}` maps to a
display state `{working, blocked, done, idle}`; `seen` flips false when a
working/blocked → idle transition happens while the surface is not foreground,
producing the `done` badge. Stabilization rules: a 1.2 s sticky "working hold" for
Claude (tool-result rendering briefly looks idle), and 6 consecutive process-probe
misses before releasing a detected agent. Polling: 300 ms tick with an agent detected,
500 ms otherwise; process probes throttled to ~5 s unless a change is suspected.

Multi-language strategy: prefer language-neutral signals (spinner glyphs, box-drawing
chars, `[y/n]`, key names like `esc`/`ctrl+c`) over English phrases inside each
detector; Kimi (the only realistically localized CLI) gets a multi-pattern list that
can grow Chinese patterns later.

### Phase 2 — UI and wiring

- Layout: plain `VStack` in `SidebarListView` with the panel conditionally rendered
  under `.transition(.move(edge: .bottom))` — deliberately **not** a `SplitView`
  (SplitView rebuilds the hierarchy on hidden/visible flips and cannot animate the
  slide). The panel carries its own top-edge drag handle; height clamped so the
  repository list keeps a minimum visible height.
- Persistence via `@Shared(.appStorage(...))` for panel hidden state and height.
- TCA: `ActiveAgentsFeature` mounted as a child of `RepositoriesFeature` (sidebar
  scope; no need to lift to `AppFeature`), fed by new `TerminalClient` events.
- Row UI: agent icon + name + status pill using system colors only; sort by status
  priority in the reducer; empty state text when nothing is detected.
- Click-to-focus: a new `TerminalClient` `focusSurface` command that selects the
  worktree, switches the tab, and focuses the target surface; focusing also flips
  `seen` so `done` demotes to `idle`.

## Alternatives & decisions

- **Swift port of herdr's `detect.rs` vs. embedding a Rust dylib** — port chosen:
  the detection code is ~95% `.contains(...)` string checks, while embedding would
  need a cross-compile pipeline, universal dylib signing, library-validation
  exemptions, and per-tick FFI marshalling; customization (e.g. Kimi Chinese
  patterns) would also become far more painful. A periodic "drift-check" against
  upstream herdr `detect.rs` was proposed instead of binary reuse.
- **Ghostty fork model** — per-version patched branches (`release/v<TAG>-patched`)
  chosen so no branch is ever force-pushed and every version stays traceable;
  accepted cost: a cherry-pick per upstream upgrade.
- **Screen-text heuristics accepted as a maintenance cost** — agent CLI UI strings
  are stable but can change on upgrades; mitigated by fixture tests and the
  language-neutral-signal preference, with hook integration as the long-term fix.
- **No automated e2e** — real-pty end-to-end testing judged too expensive; pure
  functions get exhaustive unit tests, the rest is manual smoke.

## Amendments

- Updated 2026-05-25: keyboard navigation (⌃⌥↑/↓), selection flicker fix, and
  plain-folder selection fix — see [002-selection-and-keyboard-navigation.md](002-selection-and-keyboard-navigation.md)
- Updated 2026-06-04: row repo/branch resolved from the agent's cwd, and an optional
  tab-title row display setting — see [003-row-display-resolution.md](003-row-display-resolution.md)
- Updated 2026-06-19: agent working/blocked state folded into the worktree running
  indicator — see [004-agent-busy-running-indicator.md](004-agent-busy-running-indicator.md)
