# 021 — Amendment: Sparkle 2.9.2 & Update-Driver Isolation (2026-05-25)

## Context

Sentry issue `PROWL-MACOS-AC`: a one-off `EXC_BAD_ACCESS` on a background thread
entirely inside `Sparkle.framework` (wild-pointer / use-after-free signature in the
registers), on `prowl@2026.5.20` running Sparkle `2.9.0-beta.2`. Not reproducible and
not root-causable from app frames, so the response was low-risk hardening rather
than a targeted fix. (Observability context: entry
[020-observability](../020-observability/000-plan.md).)

## Change

1. **Sparkle `2.9.0-beta.2` → `2.9.2`** — the app had been pinned to a January beta
   of the auto-updater in notarized builds; 2.9.2 picked up three stable releases of
   fixes (including a crash fix in `clearDownloadedUpdate` and a `CFRelease`
   NULL-guard).
2. **`SilentUpdateDriver` isolation hardening** — `SPUUserDriver` is declared
   `NS_SWIFT_UI_ACTOR` as of Sparkle 2.9, so the `nonisolated` +
   `MainActor.assumeIsolated` boilerplate on every callback was replaced by plain
   `@MainActor` methods, removing ~16 `assumeIsolated` trap points that would
   hard-crash on any future off-main delivery. Behavior unchanged.
3. **Sparkle dSYM upload on release** — Sparkle ships as a prebuilt `binaryTarget`
   xcframework, so the archive's `dSYMs/` never contains its symbols; the release
   script now uploads the dSYMs bundled inside the xcframework so each Sparkle
   version symbolicates on Sentry automatically (previously covered only by a one-off
   manual upload on 2026-04-18). See the release runbook,
   [../001-fork-bootstrap-and-release-pipeline/release-runbook.md](../001-fork-bootstrap-and-release-pipeline/release-runbook.md).

Scope correction from the PR itself: this does not symbolicate every Sparkle frame —
for the triggering event the matching dSYM was already on Sentry, and some other
events drop the Sparkle image from `debug_meta` entirely (a sentry-cocoa limitation
no dSYM upload can recover).

## Refs

- PR #347 (merged 2026-05-25)

## Current state

Sparkle remains pinned at exact `2.9.2` (`supacode.xcodeproj/project.pbxproj`). The
`@MainActor` callback style is still in place in
`supacode/Clients/Updates/UpdaterClient.swift`, with the isolation rationale kept as
an inline comment.
