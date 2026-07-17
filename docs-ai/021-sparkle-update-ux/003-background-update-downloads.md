# 021 — Amendment: Background Update Downloads (2026-06-06)

## Context

#206 had disabled automatic downloads entirely (`automaticallyDownloadsUpdates`
always `false`) because Sparkle's auto-download path bypasses `showUpdateFound` and
would have defeated silent detection. That left users clicking the badge and then
waiting for the full download every time.

## Change

- Let Sparkle own the "automatically download and install updates in the future"
  preference through its standard update window checkbox — Prowl Settings stays
  scoped to automatic update *checks* only, avoiding a duplicate toggle (the app no
  longer sets `automaticallyDownloadsUpdates` at all).
- Surface auto-downloaded updates as a ready-to-install toolbar state:
  `SparkleUpdateDelegate.updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`
  captures the immediate-install handler and yields
  `.downloadedUpdateReadyToInstall(version:)`; `UpdatesFeature` sets
  `isUpdateReadyToInstall`, and clicking the badge then installs and relaunches
  directly instead of re-running a check.
- Reducer coverage added for available vs. downloaded update states.

## Refs

- PR #397 (merged 2026-06-06)
- Supersedes the "auto-download always off" decision in [000-plan.md](000-plan.md)

## Current state

The two-state badge (`isUpdateAvailable` vs `isUpdateReadyToInstall`) lives in
`supacode/Features/Updates/Reducer/UpdatesFeature.swift` and
`supacode/Features/Repositories/Views/ToolbarUpdateButton.swift` (distinct tooltip
wording per state). The install path was later gated behind an explicit confirmation
— see [004-install-confirmation.md](004-install-confirmation.md).
