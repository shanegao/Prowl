# 035 — Protected Terminal Close: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-25 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #345 |
| **Sources** | Fork issue #341, PR #345 description |
| **Related** | [030-agent-status-detection](../030-agent-status-detection/000-plan.md), [013-prowl-cli](../013-prowl-cli/000-plan.md), `docs/components/terminal.md`, `docs/components/cli.md` |

## Background

Fork issue #341: the user repeatedly pressed Cmd+W on a tab hosting a running
agent, believing keyboard focus was in another app, and lost in-flight agent
work with no warning. Ghostty's own `confirm-close-surface` handling was not
enough here because the thing worth protecting is not "a process is attached"
but "an agent is doing (or has just finished) work the user has not seen".
The issue asked for a second confirmation when closing a tab whose agent is
still executing.

## Goals

- Confirm before closing panes, tabs, or tab batches that would discard
  protected terminal work.
- Protect two kinds of panes:
  - an agent pane whose display state is `working`, `blocked`, or `done`
    (`done` = finished but the result has not been viewed yet);
  - a non-agent pane whose foreground command has been running for at least
    10 seconds (long-running builds, scripts).
- Never prompt on closes that are already safe or intentional: idle agents,
  short-lived commands, surfaces whose process has exited, and internal
  run-script tab replacement.

**Non-goals**

- Keep the protection scoped to terminal pane activity (per PR #345); no
  worktree- or repository-level close guard.

## Design / Approach

Two layers, both landing in one PR:

1. **Pure decision policy** — `TerminalCloseConfirmationPolicy`
   (`supacode/Features/Terminal/Models/TerminalCloseConfirmationPolicy.swift`)
   maps `[TerminalCloseProtectionCandidate]` (per-pane `hasAgent`,
   `agentDisplayState`, `commandRunningDuration`) to a
   `TerminalCloseConfirmationDecision` (protected pane count + reason set:
   `agentActive` / `longRunningCommand`). Agent presence takes priority: an
   idle agent pane is never protected even if a command duration is recorded.
   The long-running threshold is a policy constant (10 s), injectable for
   tests. Being a pure function makes the rules unit-testable without any
   terminal state.
2. **Wiring in `WorktreeTerminalState`** — every close entry point takes a
   `TerminalCloseConfirmationMode` (`.prompt(target)` / `.skip`). Targets
   (`.pane` / `.tab` / `.tabs(count:)`) select the `NSAlert` title and confirm
   button copy; the informative text is derived from the decision's reason
   set. Batch operations (Close Other Tabs / Tabs to the Right / All Tabs)
   confirm once over the union of all affected surfaces, then close each tab
   with `.skip` so the user is not prompted N times. Ghostty-driven surface
   close requests prompt only when the child process is still alive.

Both protection signals reuse state that already existed:

- `surfaceAgentStates` — per-surface agent detection results from
  [030-agent-status-detection](../030-agent-status-detection/000-plan.md);
  the protection is a direct consumer of its `displayState` machine
  (including the `seen` flag that turns `done` back into `idle`).
- `surfaceRunningStartedAtById` — new map recording when a surface's Ghostty
  progress state (OSC 9;4-driven) first reported running, sampled inside the
  existing `updateRunningState(for:)` pass.

## Alternatives & decisions

- **Scope**: PR #345 explicitly kept protection limited to terminal pane
  activity rather than a broader "worktree is busy" guard.
- **`done` counts as protected**: the confirmation protects unseen completed
  results, not only running work — closing right as the agent finishes is the
  same accident the issue describes.
- **Batch confirm-once**: one aggregate prompt for multi-tab operations
  instead of per-tab prompts; individual closes inside the batch use `.skip`.

## Amendments

None. Later refactors that moved this code are recorded in
[001-action.md](001-action.md).
