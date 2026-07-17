# 021 — Amendment: Confirmation Before Install (2026-06-24)

## Context

Fork issue #497: with background downloads enabled (amendment 003), a plain "Check
for Updates" could quit and relaunch the app without asking. Prowl forwards
user-initiated checks to Sparkle's standard driver; when Sparkle reports an
already-downloaded update in the *installing* stage, that path continues straight
into install-and-relaunch even though the user only asked to check. Background
silent checks could also preserve an installing state that later installs on app
termination.

## Change

In `supacode/Clients/Updates/UpdaterClient.swift`:

- User-initiated `showUpdateFound` at the installing stage no longer forwards to the
  standard driver; it runs an explicit "Install Update and Relaunch?" `NSAlert`
  (`confirmInstallAndRelaunchChoice`) and replies `.install` only on confirmation
  (`shouldConfirmInstallAndRelaunchImmediately(for:)` gates this to `.installing`).
- `showReady(toInstallAndRelaunch:)` runs the same confirmation.
- Choosing **Later** replies `.skip`, canceling the current install attempt without
  permanently skipping the version, so the update is re-offered on the next check.
- Background checks at the installing stage also reply `.skip` (not `.dismiss`), via
  `silentBackgroundUpdateChoice(for:)`, so a silent check cannot leave a pending
  install armed for app termination.
- Focused tests for the choice helpers in `supacodeTests/UpdaterClientTests.swift`.

## Refs

- PR #498 (merged 2026-06-24), fixes fork issue #497
- Behavior documented in `docs/components/updates.md` ("Install confirmation")

## Current state

As described; a "Check for Updates" action can no longer install and relaunch on its
own.
