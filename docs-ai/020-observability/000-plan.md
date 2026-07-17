# 020 — Observability: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-18 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #207, #208, #210, #211, #212, #213 |
| **Sources** | `doc-onevcat/observability.md` (migrated to [runbook.md](runbook.md) in the docs-ai migration), PR descriptions #207–#213 |
| **Related** | [001-fork-bootstrap-and-release-pipeline](../001-fork-bootstrap-and-release-pipeline/000-plan.md), [032-performance-hardening](../032-performance-hardening/000-plan.md), `docs/reference/settings-fields.md` |

## Background

The fork inherited Sentry + PostHog SDK wiring from upstream, but the upstream
`__SENTRY_DSN__` placeholder mechanism never worked in this fork — release builds shipped
with no working credentials, so crashes and usage were invisible. The concrete motivating
incident was a user report of the *"runs for hours, memory explodes to tens of GB"* class:
without telemetry there was no way to even scope the problem.

The response was an "observability reboot" planned as three waves (P0/P1/P2 in the PR
descriptions), landed as six PRs on a single day (2026-04-18).

## Goals

- **P0 — credentials** (#207): inject real Sentry DSN + PostHog key at archive time without
  committing secrets; missing/unsubstituted values must make SDK init a safe no-op.
- **P1 — event quality** (#208): every PostHog event sliceable by app version / OS / device /
  arch / locale; tip-channel users isolated in their own Sentry `environment`;
  `session_duration_seconds` on `app_quit`.
- **Readable crashes** (#210): dSYM upload + Sentry release registration in the fork release
  pipeline so stack traces symbolicate.
- **Hang signal** (#211): report main-thread stalls, but filter known system-induced hangs
  (wake-from-sleep menu-bar replicant rebuilds) client-side.
- **P2 — memory watchdog** (#212): turn the memory-explosion report into queryable data —
  per-session baseline plus monotonic threshold-crossing events.
- **Runbook** (#213): a single doc that lets a future human or agent start querying the right
  pipeline within 30 seconds.
- Stay inside the PostHog free tier (~1M events/mo): hand-instrumented events only, all
  autocapture off; Debug builds send nothing (`#if !DEBUG` gates every SDK call).

### Non-goals

- Sentry Profiling — samples only during transactions; useless for 8-hour memory drift.
- Watchdog Termination — iOS/tvOS/Catalyst only, unsupported on native macOS.
- `script_run` exit codes — Ghostty does not expose shell exit status via its public API.

## Design / Approach

- **Credentials pipeline**: `Config/Secrets.env` (gitignored, template committed) → Makefile
  `-include` passes `PROWL_SENTRY_DSN` / `PROWL_POSTHOG_API_KEY` / `PROWL_POSTHOG_HOST` as
  build settings on the `archive` target → substituted into `supacode/Info.plist` `$(VAR)`
  placeholders → read at startup. A guard rejects empty or still-`$(`-prefixed values so a
  dev build without secrets skips SDK init entirely.
- **Identity**: random install UUID persisted in `UserDefaults`
  (`supacode/Support/InstallIdentifier.swift`) replaces the hardware UUID; opting out of
  analytics resets both the PostHog identity and the install ID.
- **Sentry options**: `releaseName = "prowl@<CFBundleShortVersionString>"` (matches the name
  the release script registers), `environment` = `"tip"` or `"production"` from the update
  channel, `tracesSampleRate = 0.05`, App Hang tracking on with `appHangTimeoutInterval = 3`
  and a conservative `beforeSend` filter (`SentryEventFilter`) that drops an event only when
  it is an AppHang, has zero in-app frames, *and* matches a known system signature.
- **PostHog**: `enableSwizzling = false`, lifecycle/screen-view capture off; super properties
  registered once from `supacode/Support/AnalyticsContext.swift`.
- **Memory watchdog**: `supacode/Support/MemoryProbe.swift` reads `phys_footprint` via
  `task_info(TASK_VM_INFO)`; `supacode/Support/MemoryWatchdog.swift` (`@MainActor
  @Observable`) ticks every 5 minutes, fires `app_memory_baseline` once at 3 min uptime, then
  `memory_threshold_{2048,4096,8192}mb` at most once each; 4 GB+ also goes to Sentry as a
  message so it pairs with action breadcrumbs. A context-provider closure (wired in
  `supacode/App/supacodeApp.swift`) attaches repo/worktree/tab counters while keeping the
  watchdog TCA-agnostic.
- **Release pipeline**: `sentry-cli releases new` + `debug-files upload --include-sources
  --wait` + `set-commits --auto` after archive, `releases finalize` after publish — all
  best-effort (warn, never block a release), with a `SKIP_SENTRY=1` escape hatch. Lives in
  the fork release script `release.sh` (see
  `docs-ai/001-fork-bootstrap-and-release-pipeline/release-runbook.md`).

## Alternatives & decisions

- `phys_footprint` over `resident_size`: matches Activity Monitor and macOS's real memory
  pressure accounting (includes compressed memory).
- Monotonic thresholds (no re-arm after a drop): the session's envelope is wanted, not event
  storms from page-outs.
- Baseline at 3 min, not launch: lets first-run setup settle into a real steady state.
- 3s hang threshold over the SDK's 2s default: macOS users tolerate brief stalls
  (swap/iCloud/display changes) more than iOS users.
- Hang filter conservative by design: novel all-system hang patterns still pass through, so
  new noise is seen before it is filtered.
- Sentry steps never block a release: dSYMs can be re-uploaded manually later.
- PostHog autocapture off: `Application Opened`/`Backgrounded` fire on every Cmd+Tab and
  would burn the free tier at ~100 DAU.

## Amendments

- Updated 2026-04-27: App Hang tracking removed entirely after noise analysis (the
  enable → tune → remove arc) — see [002-app-hang-removal.md](002-app-hang-removal.md)
- Updated 2026-06-09: cross-system install identity on Sentry events and failed-HTTP-request
  noise disabled — see [003-identity-and-network-noise.md](003-identity-and-network-noise.md)
