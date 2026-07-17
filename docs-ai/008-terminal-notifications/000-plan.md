# 008 — Terminal Notifications: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-22 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #34, #35, #36, #37 (initial wave); #257, #340, #360, #361, #545, #546 (follow-up waves) |
| **Sources** | PR descriptions; fork-only rows and upstream-port decisions in the upstream review ledger (`docs-ai/017-upstream-sync-process/upstream-ledger.md`); commits `182e165a`…`d7bb4b68`, `26968c1f`, `2db9ae5e` |
| **Related** | [005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md), [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md), `docs/components/notifications.md` |

## Background

Prowl's whole point is running many coding agents in parallel, which means the user is
usually *not* looking at the pane where something interesting just happened. The app
already had a notification inbox per worktree (fed by Ghostty desktop-notification
callbacks) with a toolbar bell, a sidebar indicator, Canvas card dots, and optional macOS
system notifications. Three gaps remained as of 2026-03-22:

1. **Long-running commands gave no signal.** A `make build` or test run finishing in a
   background tab was invisible unless the tool itself emitted a desktop notification.
2. **The Canvas dot was per-worktree**, so a notification in one tab lit up every card of
   that worktree, and the 6×6pt dot was easy to miss when scanning many cards.
3. **Read-state had holes**: a notification arriving on the already-focused Canvas card
   could not be dismissed at all, and interactive tools (e.g. typing `/exit` in Claude
   Code) produced noisy "command finished" notifications for exits the user caused.

## Goals

- Notify when a long-running command finishes, with a user-configurable duration
  threshold and an enable/disable toggle.
- Track unseen notifications per tab, not per worktree, so Canvas cards light up
  individually.
- Make the Canvas indicator visible at a glance (full title-bar highlight instead of a
  dot).
- Clear notifications on any key input to the focused surface; suppress command-finished
  notifications when the user was just typing in that surface.

**Non-goals** (at anchor time): system-notification routing changes, Dock integration,
and notification sounds beyond the existing single chime — these arrived in later waves
(see Amendments).

## Design / Approach

**Command-finished detection** rides on Ghostty's OSC 133 shell integration: the
`COMMAND_FINISHED` action surfaces as a new `onCommandFinished` callback on
`GhosttySurfaceBridge`, carrying duration and exit code. `WorktreeTerminalState` applies
the filters:

- feature enabled and `duration >= threshold` (default 10 s);
- skip user-initiated termination (exit codes 130/SIGINT and 143/SIGTERM);
- skip if the user typed in that surface within a recent-interaction window
  (`lastKeyInputTimeBySurface`, added in commit `2db9ae5e` right after the PR wave).

Anything that passes goes through the existing `appendNotification` path, so the bell,
sidebar indicator, Canvas highlight, and system notifications all work without new
plumbing. Notifications are auto-marked read when the producing surface is both selected
and focused.

**Settings**: two new `GlobalSettings` fields (`commandFinishedNotificationEnabled`,
`commandFinishedNotificationThreshold`) with a "Command Finished" section in
`NotificationsSettingsView`, propagated to the terminal layer via `TerminalClient` →
`WorktreeTerminalManager` (the standard reducer→terminal command path).

**Per-tab unseen state**: `WorktreeTerminalState.hasUnseenNotification(for:)` filters the
notification list by the surfaces belonging to one tab; `CanvasView` queries per tab
instead of reading the worktree-level flag.

**Visibility**: the Canvas card title bar gets a full-width orange tint overlay when the
tab has unseen notifications (initially `Color.orange.opacity(0.3)` over the `.bar`
material).

**Mark-read on input**: `GhosttySurfaceView` gains an `onKeyInput` callback on `keyDown`,
wired to `markNotificationsRead(forSurfaceID:)` — any keystroke into a focused surface
clears its unseen notifications. The same timestamp feeds the command-finished
suppression window.

## Alternatives & decisions

- **Reuse the existing notification inbox instead of a parallel "command finished"
  channel** — deliberate; one `appendNotification` funnel keeps every indicator surface
  consistent and later made follow-up features (sound gating, mute-when-viewed) one-line
  gates (see 004 amendment).
- **Exit-code filtering over "always notify"** — SIGINT/SIGTERM exits are treated as
  user-initiated and skipped, accepting that a genuinely failed long command killed by
  signal is silent; the recent-input window covers the interactive-tool case (`/exit`,
  `quit`) that exit codes alone cannot.
- **Per-tab rather than per-surface Canvas indication** — Canvas cards represent tabs, so
  tab granularity matches what the user can click; per-surface (split) indicators came
  later via the upstream #266 port (002 amendment).

## Amendments

- Updated 2026-05-08: notification jump (⌘⌥U) + per-tab/per-split unread indicators,
  upstream port — see [002-notification-jump-and-indicators.md](002-notification-jump-and-indicators.md)
- Updated 2026-05-27: toolbar-item visibility + Dock badge/bounce options, and the stuck
  bell/Dock-badge fix — see [003-toolbar-dock-options-and-stuck-indicator.md](003-toolbar-dock-options-and-stuck-indicator.md)
- Updated 2026-07-08: notification sound picker + mute-for-viewed-surface, upstream ports
  with fork adaptations — see [004-sound-picker-and-viewed-surface-mute.md](004-sound-picker-and-viewed-surface-mute.md)
