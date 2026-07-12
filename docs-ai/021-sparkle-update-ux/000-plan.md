# 021 — Sparkle Update UX: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-18 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #206, #347, #397, #498 |
| **Sources** | PR descriptions (#206, #347, #397, #498) |
| **Related** | [001-fork-bootstrap-and-release-pipeline](../001-fork-bootstrap-and-release-pipeline/000-plan.md) (appcast infra: [003-appcast-from-github-releases.md](../001-fork-bootstrap-and-release-pipeline/003-appcast-from-github-releases.md)), [020-observability](../020-observability/000-plan.md), `docs/components/updates.md` |

## Background

Entry 001 established the delivery side of fork updates: Sparkle EdDSA signing,
date-based versions, and an appcast served from GitHub Releases. The consumption
side was stock Sparkle: an hourly background check that, on finding an update,
immediately popped a modal "Update Available" dialog. For an app whose whole point
is running long-lived agent sessions, a surprise modal interrupting work was the
wrong UX — updates should be *noticeable* but never *interrupting*.

## Goals

- Background update checks must never show a dialog; instead, surface availability
  as a passive toolbar badge next to the notifications bell.
- Clicking the badge (or any explicit "Check for Updates…") hands off to Sparkle's
  standard flow, keeping the native release-notes / install / relaunch dialogs.
- Dismissing an update ("Remind me later") must not permanently hide it — the badge
  reappears on the next background cycle while the update remains available.

### Non-goals

- No custom in-app update UI beyond the badge; user-initiated flows stay on
  `SPUStandardUserDriver` so Sparkle's dialogs, progress, and release notes are reused.

## Design / Approach

As designed in #206:

- **`SilentUpdateDriver`** (`supacode/Clients/Updates/UpdaterClient.swift`): a custom
  `SPUUserDriver` wrapping `SPUStandardUserDriver`. On
  `showUpdateFound(userInitiated: false)` it replies `.dismiss` (so Sparkle re-offers
  the update next cycle) and yields a `silentUpdateFound(version:)` event onto an
  `AsyncStream`. User-initiated callbacks forward to the standard driver.
- **`UpdaterClient`** (TCA dependency): `configure` / `setUpdateChannel` /
  `checkForUpdates` / `events`, owning the `SPUUpdater` singleton.
- **`UpdatesFeature`** (`supacode/Features/Updates/Reducer/UpdatesFeature.swift`):
  subscribes to the event stream from `.task` (kicked off at app launch), flips
  `isUpdateAvailable` and records `availableVersion`. A user-initiated check clears
  the badge state first; if the update is still available, Sparkle re-triggers
  `showUpdateFound` and the standard driver takes over.
- **`ToolbarUpdateButton`** (`supacode/Features/Repositories/Views/ToolbarUpdateButton.swift`):
  rendered next to the notifications bell in both the worktree and canvas toolbars
  when `isUpdateAvailable` is set.
- Settings keep only "Check for updates automatically"; the "Download and install
  automatically" toggle was removed because Sparkle's auto-download path bypasses
  `showUpdateFound` and would defeat the silent flow (`automaticallyDownloadsUpdates`
  forced `false` at the time — later revisited, see amendment 003).

## Alternatives & decisions

- **Dismiss, don't skip**: background checks reply `.dismiss` rather than `.skip`, a
  deliberate choice so the same version is re-offered every cycle instead of being
  permanently suppressed (#206).
- **Reuse the standard driver for user-initiated flows** instead of building custom
  update dialogs — smaller surface, native behavior preserved (#206).
- **Disable auto-download initially** (#206) because it conflicted with silent
  detection; amendment 003 (#397) later restored background downloads by letting
  Sparkle own the preference and teaching the silent driver about downloaded/
  installing stages.

## Amendments

- Updated 2026-05-25: Sparkle 2.9.2 upgrade, update-driver isolation hardening, and
  Sparkle dSYM upload on release — see [002-sparkle-292-and-driver-isolation.md](002-sparkle-292-and-driver-isolation.md)
- Updated 2026-06-06: background update downloads with a ready-to-install badge
  state — see [003-background-update-downloads.md](003-background-update-downloads.md)
- Updated 2026-06-24: explicit confirmation before install-and-relaunch — see
  [004-install-confirmation.md](004-install-confirmation.md)
