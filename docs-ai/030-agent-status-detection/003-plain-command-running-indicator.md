# 030 — Amendment: Plain-Command Running Indicator — #484 Merge → Revert (2026-06-23)

## Context

The worktree/tab running indicator (`WorktreeTaskStatus`) is fed by two signals:

- **OSC 9;4 progress reports** (`tabIsRunningById` via `updateRunningState` in
  `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift`). This is
  agent-*self-reported* and decoupled from terminal rendering — a tab can read idle
  before the pane finishes painting.
- **Agent busy state** (`tabAgentBusyById` via `PaneAgentState.isBusy`, #475 / entry
  [029](../029-active-agents-panel/000-plan.md)), added because Claude Code emits no
  OSC 9;4 while it works.

Plain commands (`sleep 60`, `npm run build`, `git clone`) emit neither signal, so they
never show the sidebar spinner. PR #484 (community, merged 2026-06-22) tried to close the
gap by enumerating the pty's foreground process group: treat "the group contains any
process other than the shell" as running, re-evaluated on title changes and
command-finished events.

## Change

**Reverted on `main` the next day** (commit `5b219791`, 2026-06-23) after investigation
found the approach unsound in practice:

- `childPID()` can return a `login` wrapper PID instead of the shell PID → the group
  never looks empty → infinite spinner;
- zsh `preexec` fires before `fork`, so title-change-triggered probes raced command
  startup (needed a 150 ms delay hack);
- hardcoded shell-name list, zombie-process false positives, mise-shim edge cases;
- poor cost/benefit: real syscall/enumeration complexity for a cosmetic spinner on
  manually typed commands.

The recorded successor design is issue #495: patch Ghostty to fire a new
`GHOSTTY_ACTION_COMMAND_STARTED` action from OSC 133;C (shell integration already parses
it internally for `durationNs`), pairing with the existing command-finished action —
no process enumeration, no races. It would be another fork patch on top of the
[ghostty-fork-sync](../007-ghostty-embedding-integration/ghostty-fork-sync.md) branch.

## Refs

- PR #484 (merged 2026-06-22) — `hasRunningForegroundProcess` + extra
  `updateRunningState` triggers.
- Revert commit `5b219791` (2026-06-23, direct commit on `main`, no revert PR); the full
  investigation lives in the #484 PR comment thread.
- Issue #495 — OSC 133;C proposal, open as of 2026-07-12.

## Current state

Verified 2026-07-12: `hasRunningForegroundProcess` does not exist in the tree;
`updateRunningState` reads only `surface.bridge.state.progressState`
(`isRunningProgressState`). Plain non-OSC-9;4 commands still show no running indicator
unless an agent is detected in the pane.
