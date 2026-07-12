# 021 — Sparkle Update UX: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-18 | Silent background detection via `SilentUpdateDriver`; `ToolbarUpdateButton` badge next to the notifications bell (worktree + canvas toolbars); auto-download toggle removed, `automaticallyDownloadsUpdates` forced `false` | #206 |
| 2026-05-25 | Sparkle `2.9.0-beta.2` → `2.9.2` (exact pin); driver callbacks rewritten as plain `@MainActor` methods (dropping ~16 `MainActor.assumeIsolated` trap points); Sparkle xcframework dSYMs auto-uploaded to Sentry on release | #347 |
| 2026-06-06 | Background downloads re-enabled: Sparkle owns the auto-download preference from its standard dialog; downloaded updates surface as a ready-to-install badge state that installs/relaunches on click | #397 |
| 2026-06-24 | Explicit "Install Update and Relaunch?" confirmation before any install-and-relaunch; "Later" replies `.skip` for the current attempt without permanently skipping the version (fork issue #497) | #498 |

## Outcome & current state (as of 2026-07-12)

- `supacode/Clients/Updates/UpdaterClient.swift` — `UpdaterClient` dependency
  (`configure`, `setUpdateChannel`, `checkForUpdates`, `installDownloadedUpdate`,
  `events`), `SilentUpdateDriver`, and `SparkleUpdateDelegate`. Background
  `showUpdateFound` yields `.silentUpdateFound` and replies via
  `silentBackgroundUpdateChoice(for:)` (`.dismiss` for not-downloaded/downloaded,
  `.skip` for installing). User-initiated checks forward to `SPUStandardUserDriver`,
  except the installing stage which goes straight to the confirmation alert
  (`shouldConfirmInstallAndRelaunchImmediately`). `showReady(toInstallAndRelaunch:)`
  always runs the `NSAlert` confirmation (`confirmInstallAndRelaunchChoice`).
- `SparkleUpdateDelegate.updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`
  captures the immediate-install handler and yields `.downloadedUpdateReadyToInstall`,
  which is what drives the ready-to-install badge state.
- `supacode/Features/Updates/Reducer/UpdatesFeature.swift` — state
  `isUpdateAvailable` / `isUpdateReadyToInstall` / `availableVersion`;
  `activateUpdateButton` installs when ready, otherwise runs `checkForUpdates`.
  Wired in `supacode/Features/App/Reducer/AppFeature.swift` (`Scope`, `.updates(.task)`
  at launch, `applySettings` on settings changes; first configure triggers a
  background check).
- `supacode/Features/Repositories/Views/ToolbarUpdateButton.swift` — badge with
  version-aware tooltip and distinct available vs. ready-to-install wording; rendered
  from two toolbar sites in `supacode/Features/Repositories/Views/WorktreeDetailView.swift`.
- `supacode/Features/Settings/Views/UpdatesSettingsView.swift` — channel picker,
  "Check for updates automatically" toggle, "Check for Updates Now" button.
  `automaticallyDownloadsUpdates` is not set anywhere in app code; Sparkle owns it
  via the standard dialog's checkbox (per #397).
- `supacode/Commands/UpdateCommands.swift` — "Check for Updates…" menu item using the
  resolved keybinding for `check_for_updates` (default ⌘⇧U per
  `supacode/App/AppShortcuts.swift`); the command palette routes the same action
  (`supacode/Features/App/Reducer/AppFeature+CommandPalette.swift`).
- Sparkle pinned at exact `2.9.2` in `supacode.xcodeproj/project.pbxproj` (resolved in
  `supacode.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).
  Check interval is set to 3600 s in `setUpdateChannel`.
- Tests: `supacodeTests/UpdatesFeatureTests.swift` (reducer: settings, downloaded/
  available states, badge activation) and `supacodeTests/UpdaterClientTests.swift`
  (choice helpers: background installing-state, confirmation requirements).
- User-facing behavior documented in `docs/components/updates.md`.

## Deviations from plan

- #206 asserted `automaticallyDownloadsUpdates` must always be `false` because
  auto-download bypasses the silent flow. #397 reversed this: the preference is now
  Sparkle-owned, and the silent driver handles the downloaded/installing stages
  instead of forbidding them. The plan's constraint no longer holds.
- #206's user-initiated path forwarded *all* `showUpdateFound` stages to the standard
  driver; #498 carved out the installing stage after it was found to install-and-
  relaunch without confirmation.

## Open questions

- `SparkleUpdateDelegate.allowedChannels(for:)` returns `[]` unconditionally (comment:
  tip channel is no longer published separately), yet `UpdatesSettingsView` still
  shows a Stable/Tip channel picker and `UpdatesFeature.applySettings` still threads
  `UpdateChannel` through `setUpdateChannel`. The picker is effectively a no-op;
  either the setting or the dead plumbing could be removed.
