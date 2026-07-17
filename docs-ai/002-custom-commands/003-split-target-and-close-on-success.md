# 002 — Amendment: New Split Target + Close on Success (#205)

## Context

With two execution targets (New Tab, In Place), a common workflow was missing: run a
command *next to* the current pane — e.g. a dev server or test watcher alongside the agent
session — and have short-lived commands clean up after themselves instead of leaving dead
tabs behind.

## Change

PR #205 (merged 2026-04-17, "Custom Command: New Split target + Close on success"):

- Third execution target **New Split** (`UserCustomCommandExecution.split`): runs the
  command in a new pane splitting the focused terminal surface. Each command stores its
  own `splitDirection` (default `.right`, matching `Cmd+D`).
- Per-command **Close on success** toggle for the New Tab and New Split targets: when the
  command exits `0`, Prowl dismisses the tab/split. One-shot semantics — failure or
  non-zero exit leaves the pane open and consumes the flag.
- Setup-script injection is skipped for tabs marked auto-close, so a successful setup
  script cannot close the pane before the user command runs.
- Decode compatibility: `UserCustomCommand.init(from:)` uses `decodeIfPresent` with
  defaults for the new fields, so older settings files keep decoding.
- Same-branch refinements: auto-close delayed by 800 ms so the final output stays visible
  (`5d2c2836`), and a status toast when a Custom Command succeeds (`8b5aa0b5`).

## Refs

- PR #205; branch commits `a890fdbb`, `5d2c2836`, `8b5aa0b5`.
- Tests added with the PR: `splitCommandCreatesSplitWithInput`,
  `closeOnSuccessFlagIsForwarded`, `userCustomCommandDecodesWithoutNewFields`,
  `autoCloseFlagIsConsumedOnSuccess`, `autoCloseFlagIsConsumedOnFailureButDoesNotClose`,
  `unmarkedSurfaceDoesNotConsumeAutoCloseState`.

## Current state

`TerminalClient.Command.createSplitWithInput` and the `autoCloseOnSuccess` flag on both
create commands (`supacode/Clients/Terminal/TerminalClient.swift`); flagged surfaces
tracked in `WorktreeTerminalState.autoCloseSurfaceIds` and consumed one-shot in
`handleCommandFinished`
(`supacode/Features/Terminal/Models/WorktreeTerminalState+Notifications.swift`), with
cleanup threaded through the surface-close paths in
`WorktreeTerminalState+Surfaces.swift`. The settings UI shows the direction picker only
for `.split` and the toggle only for targets that support it (not In Place).
