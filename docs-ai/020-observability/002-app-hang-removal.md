# 020 — Amendment: App Hang tracking, enable → tune → remove

## Context

App Hang reporting was enabled in the initial observability wave (#207, threshold tuned in
#211). The very first hang event in Sentry was a false positive: wake-from-sleep triggered
`_NSMenuBarDisplayManagerActiveSpaceChanged` → NSWindow replicant rebuild → `mach_msg` IPC
blocking the main thread >2s — an all-AppKit stack with zero app frames, reproduced on every
laptop-lid-open. What followed was a nine-day arc where the observer itself generated most of
the work, ending in the deliberate decision to stop collecting the signal.

## Change

The arc, step by step:

1. **#211 (2026-04-18) — filter + 3s threshold.** `SentryEventFilter.filterSystemHang` as
   `beforeSend`: drop only when mechanism is `AppHang` AND no in-app frames AND a frame
   matches a known system signature (menu-bar replicant family). Threshold raised 2s → 3s.
2. **#216 (2026-04-19) — the filter crashed the app.** The project sets
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Sentry's ANR tracker invokes `beforeSend`
   synchronously from its background detection thread, and Swift 6.2's executor check
   aborted the process (`EXC_BREAKPOINT`, PROWL-MACOS-5). Fixed by marking the filter
   `nonisolated`, with a compile-time regression guard (an off-main `@Sendable` test that
   fails to build if `nonisolated` is dropped).
3. **#233 (2026-04-22) — the observer showed up in its own data.** Release builds were
   computing reflection-based `debugCaseOutput` labels for every TCA action just to feed
   Sentry breadcrumbs; hang samples even caught `-[SentryScope maxBreadcrumbs]` as a leaf
   frame. Release breadcrumbs switched to a cheap enum case-path label
   (`releaseActionLabel`); the PR also staggered periodic watcher work and skipped no-op
   line-change actions to cut reducer/Sentry traffic.
4. **#236 (2026-04-23) — remove the signal.** Retrospective analysis of 100 sampled events
   from the main dedupe bucket (PROWL-MACOS-7, 509 events / 32 users): 90% had zero app
   code in their top-5 leaf frames; common leaves were `mach_msg2_trap`, `swift_retain`,
   `objc_msgSend` — non-actionable kernel/runtime primitives. Of the five App-Hang-driven
   changes to date, only one (#231, the main-worktree flag cache — see
   [032-performance-hardening](../032-performance-hardening/000-plan.md)) was a real
   performance fix; the rest were maintenance of the observer itself. Tracking config lines
   and `SentryEventFilter` (+ tests) were deleted. Replacements: MetricKit
   `MXHangDiagnosticPayload` via Xcode Organizer's Hangs tab, and Instruments for active
   profiling. Crashes and traces unchanged.
5. **#241 (2026-04-27) — the removal was incomplete.** The Sentry Cocoa SDK defaults
   `enableAppHangTracking` to **true**, so deleting the three config lines silently
   reverted to tracking ON at the more sensitive 2s default with no filter — confirmed by
   fresh unfiltered system-noise issues (PROWL-MACOS-61..67) on `prowl@2026.4.25`. Fixed
   with an explicit `options.enableAppHangTracking = false`.

Why this order of events matters: the decision to remove was data-driven (the 90% table),
but the lasting lesson is #241's — never turn a feature "off" by removing its enable line
without checking the SDK default.

## Refs

- PRs #211, #216, #233, #236, #241
- Sentry issues: PROWL-MACOS-5 (filter crash), PROWL-MACOS-7 (noise bucket),
  PROWL-MACOS-61..67 (post-#236 regression evidence)

## Current state

`supacode/App/supacodeApp.swift` sets `options.enableAppHangTracking = false` explicitly;
no `SentryEventFilter` exists in the tree. The cheap release-breadcrumb path from #233
remains in `supacode/Support/DebugCaseOutput.swift`.
