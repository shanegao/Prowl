# 008 Amendment — Sound Picker & Viewed-Surface Mute (2026-07-08)

## Context

Two ports from the 2026-07-09 upstream review batch (post-v0.10.5), landed as a stacked
pair: upstream `ce03d3c3` (#511, customizable notification sound) → fork PR #545, and
upstream `f15420ce` (#562, mute notifications for the viewed surface) → fork PR #546.
Both were adapted to the fork's single-target settings architecture and its unified
notification funnel (all notification types — agent OSC desktop notifications and the
fork-only command-finished notifications — flow through one playback/effect point in
`AppFeature+TerminalEvents.swift`).

## Change

**Notification sound picker (#545):** replaces the boolean `notificationSoundEnabled`
with a `NotificationSound` enum — `never`, 14 `/System/Library/Sounds` system sounds, and
the bundled `supacodeClassic` (the fork's existing notification.wav, displayed as "Prowl
Classic"). Selecting a sound in settings previews it immediately (in-app path only; when
system banners are enabled the picker is disabled since the banner carries its own
sound). `NSSound` instances are cached per case (`@MainActor`).

Fork adaptations (deliberate differences from upstream):

- Default and legacy-`true` migration target is `.supacodeClassic`, **not** upstream's
  `.hero` — existing fork users keep hearing the same chime after upgrading.
- Enum raw values are byte-identical to upstream (including the `supacodeClassic`
  spelling) so future upstream sound commits cherry-pick with zero migration; only the
  `displayName` says "Prowl Classic".
- Migration: legacy `notificationSoundEnabled == true` → default sound, `== false` →
  `.never`; unknown raw values are isolated with `try?` and fall back to the default
  without breaking decoding of sibling fields.

**Mute for the viewed surface (#546):** new `muteNotificationsForActiveSurface` setting
(default on). A notification originating from the surface the user is actively viewing
skips the macOS banner, sound, and Dock bounce (sidebar move-to-top still runs; the
inbox unread flag is deliberately untouched — muting external effects is a separate
concept from read state).

- "Viewed" = `WorktreeTerminalState.isViewedSurface(_:)`: selected worktree AND focused
  pane AND window key AND window visible.
- Fork adaptation: `isViewed` is threaded through the event pipeline —
  `onNotificationReceived` and `TerminalClient.Event.notificationReceived` widened to
  carry `isViewed: Bool` — and **canvas-managed surfaces are always treated as
  not-viewed** (`guard !isCanvasManaged`), because their stale window flags would
  otherwise silently drop notifications. Unknown window state likewise counts as
  not-viewed: the design errs toward notifying, never toward silent drops.
- The effect parameters were consolidated into a `TerminalNotificationPayload` struct.

## Refs

PR #545 and PR #546 (both merged 2026-07-08); upstream #511 (`ce03d3c3`) and #562
(`f15420ce`). Batch context and the fork-adaptation note are recorded in the upstream
review ledger (`docs-ai/017-upstream-sync-process/upstream-ledger.md`).

## Current state

- `supacode/Features/Settings/Models/NotificationSound.swift` — the enum (`never`, 14
  system cases, `supacodeClassic`) with a source mapping (`system(name:)` /
  `bundled(resource:withExtension:)`).
- `supacode/Clients/Notifications/NotificationSoundClient.swift` — playback + per-case
  `NSSound` cache.
- `supacode/Features/Settings/Models/GlobalSettings.swift` — `notificationSound`
  (default `.supacodeClassic`, legacy-bool migration in `decodeNotificationSound`) and
  `muteNotificationsForActiveSurface` (default `true`).
- `supacode/Features/App/Reducer/AppFeature+TerminalEvents.swift` —
  `TerminalNotificationPayload` and the mute gate
  (`state.settings.muteNotificationsForActiveSurface && notification.isViewed`).
- `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift` —
  `isViewedSurface(_:)` with the canvas-managed guard.
- Tests: `supacodeTests/NotificationSoundTests.swift` (raw-value contract, grouping,
  decode), plus updated `AppFeatureSystemNotificationTests` / `AppFeatureDockTests` /
  settings-persistence suites.
- Documented for users in `docs/components/notifications.md` and
  `docs/reference/settings-fields.md`.
