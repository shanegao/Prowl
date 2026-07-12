# 029 — Amendment: Agent Busy Folded into the Running Indicator (2026-06-19)

## Context

The worktree **running indicator** (sidebar row spinner and `prowl list`'s
`task.status`) was driven solely by OSC 9;4 command progress. Claude Code never emits
OSC 9;4 while it works, so a busy pane — especially one running a background workflow
(turn ended, input box visible, subagents still churning) — showed as idle. Agent
detection already knew the pane was busy, but the signal only fed the Active Agents
panel, never `taskStatus`.

## Change

PR #475 (merged 2026-06-19):

1. **Agent-agnostic fold.** A per-tab `tabAgentBusyById` aggregate in
   `WorktreeTerminalState` is true when any surface in the tab has a detected agent
   whose stabilized `displayState` is working or blocked (`PaneAgentState.isBusy`).
   It is OR-ed into `taskStatus` next to the OSC-driven `tabIsRunningById`, recomputed
   on every detection tick, on agent release, and on surface/tab teardown, emitting a
   task-status change only when the merged value flips. Both consumers (sidebar and
   `prowl list`) read `taskStatus` live, so no extra wiring was needed.
2. **Claude background-workflow footer.** `detectClaude` additionally scans the
   below-prompt footer for Claude's `N/M agents done` status-line marker and reports
   working — anchored to the footer region so conversation text quoting the phrase
   cannot trip it. The marker is Claude-version-specific (taken from Claude Code
   v2.1.181's `statusText` template) and pinned by a test fixture.
3. **Documented-only alternative.** A Claude Code hook emitting OSC 9;4 via
   `terminalSequence` is described in docs as the restyle-proof, lower-latency option;
   no app code.

Per the agreed design, working + blocked + background workflows all count as busy and
merge into the single existing running indicator — no new CLI field or icon.

## Refs

- PR #475 (merged 2026-06-19)
- Tests: `ScreenHeuristicsTests` (workflow footer working / idle footer / mid-conversation
  false-positive guard), `PaneAgentStateTests` (`isBusy`), `WorktreeTerminalManagerTests`
  (fold, single emission, teardown clearing)
- Detection-side status semantics evolution is tracked in
  [030-agent-status-detection](../030-agent-status-detection/000-plan.md); the CLI
  consumer is [013-prowl-cli/002-agents-command](../013-prowl-cli/002-agents-command.md).

## Current state

`tabAgentBusyById` and the fold live in
`supacode/Features/Terminal/Models/WorktreeTerminalState.swift`; `isBusy` in
`supacode/Domain/AgentDetection/PaneAgentState.swift`; the workflow-footer heuristic in
`supacode/Infrastructure/AgentDetection/ScreenHeuristics.swift`.
