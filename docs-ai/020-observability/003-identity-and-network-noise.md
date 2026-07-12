# 020 — Amendment: Cross-system identity and HTTP-noise tuning

## Context

Two later, independent signal-quality fixes on the same pipeline.

1. Cross-referencing a PostHog event (e.g. `memory_threshold_4096mb`) to its Sentry
   breadcrumbs required pivoting through device + release tags, which often returned zero
   matches — the two systems had no shared user key.
2. Sentry's `enableCaptureFailedRequests` (on by default) swizzles `URLSession` and turns
   any 5xx response into an `HTTPClientError` event. The recurring high-priority issue
   PROWL-MACOS-4 was exactly this: Sparkle fetching the appcast from GitHub Releases got a
   502, reported as *our* error. Every HTTP request Prowl makes goes to servers we don't own
   (GitHub, PostHog, Sentry), so these events are pure noise.

## Change

- **#284 (2026-05-13)**: set Sentry `user.id` to `InstallIdentifier.current`, the same UUID
  PostHog uses as `distinct_id`, so one install carries one identity across both systems.
- **#429 (2026-06-09)**: `options.enableCaptureFailedRequests = false` in the Sentry
  bootstrap. Crash and error reporting unaffected; only auto-captured network-failure
  events stop.

## Refs

- PRs #284, #429
- Sentry issue PROWL-MACOS-4 (GitHub 502 on appcast fetch)
- Appcast infrastructure: [001-fork-bootstrap-and-release-pipeline](../001-fork-bootstrap-and-release-pipeline/000-plan.md)

## Current state

Both present in `supacode/App/supacodeApp.swift > bootstrapTelemetry`:
`SentrySDK.setUser(Sentry.User(userId: InstallIdentifier.current))` right after
`SentrySDK.start`, and `enableCaptureFailedRequests = false` in the options block.
