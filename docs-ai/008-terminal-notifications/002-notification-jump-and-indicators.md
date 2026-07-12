# 008 Amendment — Notification Jump & Surface Indicators (2026-05-08)

## Context

Part of the 2026-05-08 upstream review batch (post-v0.8.5): upstream `072ad1e7`
(supabitapp/supacode #266) added jump-to-unread notifications. The fork ported it as PR
#257, adapting it to the fork's notification model from the initial wave. Until then a
notification told you *that* something happened but offered no fast way to get *there*,
and unread state was only visible on Canvas cards and the worktree row — not on the tab
bar or on individual split panes.

## Change

- **Jump to Latest Unread** (⌘⌥U): focuses the newest unread notification's surface;
  exposed as a menu command and in the command palette.
- **Source surface IDs threaded through** terminal and system notifications, enabling
  tap-to-focus on macOS notification banners.
- **Unread dots on terminal tabs and split surfaces**, extending the per-tab model of PR
  #34 down to per-surface granularity.
- Tests added for newest-focusable-notification lookup and the jump/system-notification
  paths (`WorktreeTerminalManagerTests`, `AppFeatureJumpToLatestUnreadTests`,
  `AppFeatureSystemNotificationTests`, `AppShortcutsTests`).

## Refs

PR #257 (merged 2026-05-08), port of upstream #266 (`072ad1e7`). Batch decision recorded
in the upstream review ledger (`docs-ai/017-upstream-sync-process/upstream-ledger.md`).

## Current state

`jumpToLatestUnread` is defined in `supacode/App/AppShortcuts.swift` (⌘⌥U) and appears in
`supacode/Commands/WorktreeCommands.swift`, the command palette, and
`supacode/Features/App/Reducer/AppFeature.swift`. Unread indicators render in
`supacode/Features/Terminal/Views/WorktreeTerminalTabsView.swift` and the shelf/sidebar
views that query `hasUnseenNotification`.
