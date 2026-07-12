# 008 — Terminal Notifications: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-22 | Canvas notification dot made per-tab via `hasUnseenNotification(for:)` | PR #34 |
| 2026-03-22 | Command-finished notification (OSC 133), threshold setting (default 10 s), SIGINT/SIGTERM filtering | PR #35 (`182e165a`) |
| 2026-03-22 | Canvas card title bar fully highlighted orange for unseen notifications, replacing the dot | PR #36 (`d7bb4b68`) |
| 2026-03-22 | Mark notifications read on key input to the focused surface (`onKeyInput` → `markNotificationsRead`) | PR #37 (`26968c1f`) |
| 2026-03-22 | Suppress command-finished notification when the user typed in that surface recently | commit `2db9ae5e` |
| 2026-05-08 | Jump to Latest Unread (⌘⌥U), surface IDs threaded through notifications, unread dots on tabs/splits (upstream #266 port) | PR #257 → [002](002-notification-jump-and-indicators.md) |
| 2026-05-27 | Toolbar item visibility options; Dock notification dot + bounce modes (community PR + refinement) | PR #340 + #361 → [003](003-toolbar-dock-options-and-stuck-indicator.md) |
| 2026-05-27 | Stuck bell/Dock-badge fix: prune a surface's notifications on teardown via `forgetSurface(_:)` | PR #360 → [003](003-toolbar-dock-options-and-stuck-indicator.md) |
| 2026-07-08 | Customizable notification sound picker (upstream #511 port; fork keeps its classic chime as default) | PR #545 → [004](004-sound-picker-and-viewed-surface-mute.md) |
| 2026-07-08 | Mute banner/sound/bounce for the surface currently being viewed (upstream #562 port; `isViewed` threading) | PR #546 → [004](004-sound-picker-and-viewed-surface-mute.md) |

## Outcome & current state (as of 2026-07-12)

- `supacode/Features/Terminal/Models/WorktreeTerminalState+Notifications.swift` — the
  notification core: `handleCommandFinished`-style filtering (enabled flag, `durationSeconds >=
  commandFinishedNotificationThreshold`, exit codes 130/143 skipped, `lastKeyInputTimeBySurface`
  + `recentInteractionWindow` suppression), `appendNotification(title:body:surfaceId:)` with
  auto-read when the surface is selected and focused, and notification pruning helpers.
- `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift` — surface teardown
  (`forgetSurface`), key-input timestamping, and `isViewedSurface(_:)` (see 004).
- `supacode/Features/Settings/Models/GlobalSettings.swift` — `commandFinishedNotificationEnabled`
  (default `true`), `commandFinishedNotificationThreshold` (default `10`), plus the later-wave
  fields: `notificationSound`, `muteNotificationsForActiveSurface`, `showRunButtonInToolbar`,
  `showDefaultEditorInToolbar`, `dockBounceMode`, `showNotificationDotOnDock`.
- `supacode/Features/Settings/Views/NotificationsSettingsView.swift` — three sections:
  "Notifications" (bell, sound picker, move-to-top, mute-viewed, bounce), "System" (banners,
  Dock badge with disabled-state caption), "Command Finished" (toggle + threshold field).
- `supacode/Features/Canvas/Views/CanvasCardView.swift` — title-bar overlay
  `Color.orange.opacity(0.55)` when `hasUnseenNotification`; a code comment documents that the
  notification tint deliberately wins over the repo color tint.
- `supacode/Features/App/Reducer/AppFeature+TerminalEvents.swift` — reducer-side handling of
  `TerminalClient.Event.notificationReceived` (banner/sound/Dock effects, mute gate).
- Toolbar bell: `supacode/Features/Repositories/Models/ToolbarNotificationGroup.swift` and
  `supacode/Features/Repositories/Views/ToolbarNotificationsPopoverView.swift`.
- Tests exist for each wave: `supacodeTests/CommandFinishedNotificationTests.swift`,
  `ToolbarNotificationGroupingTests.swift`, `WorktreeTerminalNotificationPruneTests.swift`,
  `AppFeatureSystemNotificationTests.swift`, `AppFeatureDockTests.swift`,
  `NotificationSoundTests.swift`.
- User-facing behavior is documented in `docs/components/notifications.md`.

## Deviations from plan

- The Canvas title-bar tint shipped at `opacity(0.3)` (PR #36) but is `opacity(0.55)` today —
  raised during later Canvas appearance work so the orange stays recognizable over per-repo
  color tints (rationale kept as an inline comment in `CanvasCardView.swift`).
- PR #37's mark-read-on-input landed as planned, but the companion suppression (recent-input
  window for command-finished) went in as a direct commit (`2db9ae5e`) the same evening rather
  than through a PR.
- The plan's initial-wave scope otherwise matches; everything beyond it arrived as the three
  amendment waves.

## Open questions

- PR #35's test plan says a `sleep 15` finishing while the tab stays focused produces no
  *unread* notification (auto-marked read); in current code an in-window keystroke suppresses
  the notification entirely while a hands-off focused wait still appends a read notification to
  the inbox. This looks intentional (inbox keeps history) but the two mechanisms overlap.
- Exit code filtering treats every 130/143 as user-initiated; a long job killed externally by
  SIGTERM is silently unnotified. No evidence this was ever revisited.
