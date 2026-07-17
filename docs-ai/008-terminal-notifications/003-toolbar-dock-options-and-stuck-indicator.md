# 008 Amendment — Toolbar/Dock Options & Stuck-Indicator Fix (2026-05-27)

## Context

Two related landings on 2026-05-27. First, community contributor @abhi21git proposed PR
#340 (hide toolbar items; Dock notification dot; Dock bounce). It was merged together
with PR #361, which builds on it with correctness/architecture refinements. Second,
users could get a toolbar bell (and now Dock badge) **stuck lit** with only "Dismiss All"
clearing it — fixed in PR #360.

## Change

**Toolbar & Dock options (#340 + #361):**

- Option-gated visibility for the Open-in-Editor toolbar item and the Run button (both
  shown by default); a toolbar-grouping fix so hiding Run does not merge Custom Commands
  into the neighboring group.
- Dock notification dot (badge) and Dock bounce on notification (off / once /
  continuous, `DockBounceMode`).
- Refinements in #361: Dock side effects routed through an injected `DockClient`
  (swift-dependencies) instead of direct `NSApp` calls in the reducer; badge actually
  renders (unread worktree count + forced `dockTile.display()`); Notifications settings
  split into app-controlled vs System sections, with the badge toggle disabled + captioned
  when macOS notification permission or "Badge app icon" is off (re-checked on app focus);
  friendlier permission-denied alert; `GlobalSettings.init(from:)` decode helpers extracted
  into a `ToolbarAndDockSettings` struct to drop a SwiftLint disable.

**Stuck indicator fix (#360):** notifications are keyed by producing surface and only
marked read when that surface gains focus or key input. Surface teardown (`removeTree` /
close handling) cleaned every per-surface dictionary *except* `notifications`, so an
unread notification from a closed tab/split had no surface left to clear it and the
bell/Dock badge stayed lit forever. Fix: consolidate per-surface teardown into
`forgetSurface(_:)`, drop that surface's notifications there (emitting the indicator
change), with a pure `prunedNotifications(from:removingSurfaceID:)` helper for unit
testing without a live Ghostty surface.

## Refs

PR #340 + PR #361 (merged 2026-05-27), PR #360 (merged 2026-05-27).

## Current state

- `supacode/Clients/Dock/DockClient.swift` — Dock badge/bounce client;
  `dockBounceMode` (default `.off`) and `showNotificationDotOnDock` (default `false`) plus
  `showRunButtonInToolbar` / `showDefaultEditorInToolbar` (default `true`) live in
  `supacode/Features/Settings/Models/GlobalSettings.swift` (decoded via the private
  `ToolbarAndDockSettings` struct).
- `supacode/Features/Settings/Views/NotificationsSettingsView.swift` — the app-controlled
  vs "System" section split, including the disabled Dock-badge caption.
- `forgetSurface` / `prunedNotifications` in
  `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift` and
  `supacode/Features/Terminal/Models/WorktreeTerminalState+Notifications.swift`; covered by
  `supacodeTests/WorktreeTerminalNotificationPruneTests.swift` and
  `supacodeTests/AppFeatureDockTests.swift`.
