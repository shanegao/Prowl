# 020 — Observability: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-18 | Credentials pipeline `Config/Secrets.env` → Makefile → `Info.plist` → `Bundle`; install-UUID identity with reset-on-opt-out; Sentry tuning (traces 5%, App Hang on, no Watchdog Termination) | #207 |
| 2026-04-18 | PostHog super properties (`AnalyticsContext`), Sentry `environment` from update channel, `session_duration_seconds` on `app_quit`, all autocapture off | #208 |
| 2026-04-18 | dSYM upload (`--include-sources`) + Sentry release registration/finalize in `release.sh`, best-effort with `SKIP_SENTRY=1` | #210 |
| 2026-04-18 | `SentryEventFilter` `beforeSend` filter for system-induced App Hangs; `appHangTimeoutInterval` 2s → 3s | #211 |
| 2026-04-18 | `MemoryProbe` + `MemoryWatchdog`: baseline at 3 min, monotonic 2/4/8 GB threshold events, 4 GB+ escalated to Sentry | #212 |
| 2026-04-18 | Observability runbook documenting the whole stack | #213 |
| 2026-04-19 | `nonisolated` fix: Sentry's ANR thread calls `beforeSend` off-main, crashing the implicitly `@MainActor` filter (PROWL-MACOS-5) | #216 |
| 2026-04-22 | Cheapen release-build TCA action breadcrumbs: case-path label instead of reflection dump; watcher staggering; no-op action skip | #233 |
| 2026-04-23 | Remove App Hang tracking and delete `SentryEventFilter` after noise analysis | #236 |
| 2026-04-27 | Explicit `enableAppHangTracking = false` — #236's removal had silently reverted to the SDK default (on, 2s, unfiltered) | #241 |
| 2026-05-13 | Sentry `user.id` set to the PostHog install identifier for cross-system correlation | #284 |
| 2026-06-09 | `enableCaptureFailedRequests = false` — stop reporting third-party 5xx responses (GitHub 502s on appcast fetch) as app errors | #429 |

The App Hang rows (#211 → #216 → #233 → #236 → #241) are a single decision arc; see
[002-app-hang-removal.md](002-app-hang-removal.md).

## Outcome & current state (as of 2026-07-12)

Verified against the working tree:

- `supacode/App/supacodeApp.swift > bootstrapTelemetry` initializes both SDKs inside
  `#if !DEBUG`. Sentry is gated on `crashReportsEnabled`, PostHog on `analyticsEnabled` —
  two separate settings (the split comes from upstream's "advanced analytics settings",
  pre-fork commit `0bf94e69`; the original PRs only mention one analytics toggle).
  `infoPlistSecret` rejects empty/unsubstituted values.
- Current Sentry options: `environment` tip/production, `releaseName = "prowl@<version>"`,
  `tracesSampleRate = 0.05`, `enableAppHangTracking = false`,
  `enableCaptureFailedRequests = false`; `SentrySDK.setUser` with
  `InstallIdentifier.current`.
- Supporting types all exist: `supacode/Clients/Analytics/AnalyticsClient.swift`,
  `supacode/Support/AnalyticsContext.swift`, `supacode/Support/InstallIdentifier.swift`,
  `supacode/Support/MemoryProbe.swift`, `supacode/Support/MemoryWatchdog.swift`
  (defaults: `baselineDelay = 180`, `thresholdsMB = [2048, 4096, 8192]`).
- `supacode/Support/SentryEventFilter.swift` no longer exists (deleted in #236, together
  with its tests).
- Release-build breadcrumbs: `supacode/Support/DebugCaseOutput.swift` (`LogActionsReducer`)
  uses the cheap `releaseActionLabel` and feeds `SentrySDK.addBreadcrumb` plus
  `SentrySDK.logger` in release; the reflection-based `debugCaseOutput` runs in DEBUG only.
- `release.sh` still runs the #210 sentry-cli steps, and additionally uploads the Sparkle
  xcframework dSYMs (a later extension beyond #210's scope).
- Secrets flow intact: `Config/Secrets.env.template` committed, Makefile `-include
  Config/Secrets.env` feeds the `archive` target, `supacode/Info.plist` carries
  `ProwlSentryDSN` / `ProwlPostHogAPIKey` / `ProwlPostHogHost` placeholders.
- Tests: `supacodeTests/AnalyticsContextTests.swift`,
  `supacodeTests/AppFeatureSessionDurationTests.swift`,
  `supacodeTests/MemoryWatchdogTests.swift`.
- The living diagnostic runbook is [runbook.md](runbook.md) in this folder; user-facing
  settings behavior is documented in `docs/reference/settings-fields.md` and
  `docs/components/settings.md`.

## Deviations from plan

- The App Hang half of #211 was fully reversed within nine days: tracking is now off and the
  filter deleted. Hang diagnosis moved to MetricKit/Instruments
  (see [002-app-hang-removal.md](002-app-hang-removal.md)).
- Everything else (credentials, super properties, dSYM pipeline, memory watchdog) landed as
  planned and is still in place.

## Open questions

- [runbook.md](runbook.md) has drifted from the code: it still documents
  `enableAppHangTracking = true` + 3s threshold + `SentryEventFilter` (removed in
  #236/#241) and a file-map row pointing at the filter file that no longer exists. It also
  references the release script by its pre-migration `doc-onevcat/scripts/` location. Needs
  an update pass during/after the docs-ai migration.
- The runbook's "16 hand-instrumented events" count dates from 2026-04-18 and was not
  re-verified against today's call sites; the catalog may have drifted.
