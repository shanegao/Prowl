# 036 — Window Management Hardening: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-09 | Dynamic main-window titles (repository/worktree/canvas/archive/tab); centralized main-window surfacing for reopen, CLI open, Window menu, and quit confirmation; quit routed through injectable `AppLifecycleClient` (adaptation of upstream #297/#298) | #261 |
| 2026-05-26 | `MainWindowOpener` registers SwiftUI `openWindow(id:)` from the command tree; no-window `surfaceMainWindow()` goes through the opener before falling back to activation; SupaLogger-only diagnostics with narrow Sentry events for windowless timeouts/stalls (fixes fork issue #297) | #353 |
| 2026-06-03 | Only a visible `WindowID.main` window counts as the main window; helper-window fallback removed; windowless note moved before `openWindow(id:)` to avoid stale reports; Sentry tags for main/visible window counts; snapshot-based surfacing tests | #381 |
| 2026-06-09 | Windowless main-thread-stall reports suppressed while the app is inactive; visible-main-window recheck at report time resolves stale windowless tracking (Sentry PROWL-MACOS-AW) | #428 |
| 2026-06-09 | Same recheck applied to `main_window_timeout` reports; inactive launch suppression kept (Sentry PROWL-MACOS-AV) | #431 |
| 2026-06-23 | Auxiliary windows join the active (fullscreen) Space — see [002-fullscreen-auxiliary-windows.md](002-fullscreen-auxiliary-windows.md) | #494 |
| 2026-06-28 | Fullscreen Close Window no longer hides the main window — see [003-fullscreen-close-black-screen.md](003-fullscreen-close-black-screen.md) | #523 |

## Outcome & current state (as of 2026-07-12)

- `supacode/App/WindowSurfacing.swift` holds the whole surfacing/diagnostics stack:
  - `WindowID` (`main`, `settings`) window identifiers.
  - `NSApplication.surfaceMainWindow()` — deminiaturize/order-front an existing
    candidate, else request recreation via `MainWindowOpener.shared.openMainWindow()`,
    else activate-only.
  - `MainWindowSurface` — pure snapshot helpers (`hasVisibleMainWindow`,
    `mainWindowCandidate`, window counts) so the #381 rules are unit-testable; a main
    window is strictly `identifier == WindowID.main`.
  - `WindowLifecycleDiagnostics` — windowless tracking with 5 s log reminders, a 1 s
    main-thread heartbeat (0.3 s stall threshold), and release-only Sentry events
    `main_window_timeout` (≥ 10 s) and `windowless_main_thread_stall` (lag ≥ 5 s),
    fingerprinted `["prowl", "main-window-surfacing", kind]`. The #428/#431 logic lives
    in `windowlessStallReportDecision` / `windowlessTimeoutReportDecision` returning
    `.report` / `.suppress` / `.resolveVisibleMainWindow`. A DEBUG-only launch stall can
    be injected via the `ProwlDebugLaunchStallSeconds` default.
- `supacode/App/MainWindowOpener.swift` — opener singleton; registered from
  `supacode/Commands/WindowCommands.swift` (command tree, works with zero windows) and
  from the main window content via `registersMainWindowOpener()` in
  `supacode/App/supacodeApp.swift`.
- `supacode/App/supacodeApp.swift` (app delegate) — starts the heartbeat and notes
  `launch` windowless state on launch; `applicationDidBecomeActive` and
  `applicationShouldHandleReopen` surface the main window when no visible main window
  exists; `applicationShouldTerminateAfterLastWindowClosed` returns `false`.
- `supacode/App/WindowTabbingDisabler.swift` — stamps `WindowID.main`, sets the frame
  autosave name, disables tabbing, and implements the close policy (amended by #523).
- `supacode/App/WindowTitle.swift` — title computation from `RepositoriesFeature.State`
  selection plus the selected terminal tab, with control-character sanitization.
- `supacode/Clients/AppLifecycle/AppLifecycleClient.swift` — `surfaceMainWindow` /
  `terminate` dependency; `AppFeature.requestQuit`
  (`supacode/Features/App/Reducer/AppFeature.swift`) surfaces the main window before the
  confirm-quit alert and honors the `confirmBeforeQuit` setting.
- CLI path: `supacode/CLIService/OpenCommandHandler.swift` calls
  `surfaceMainWindow()` when handling `prowl open`.
- Tests: `supacodeTests/WindowSurfacingTests.swift`,
  `supacodeTests/MainWindowOpenerTests.swift`, `supacodeTests/WindowTitleTests.swift`,
  `supacodeTests/AppFeatureQuitTests.swift`,
  `supacodeTests/WindowTabbingDisablerTests.swift`.

## Deviations from plan

- #353's original candidate search accepted non-panel helper windows as a fallback; #381
  reversed that within the same effort after Sentry evidence. Recorded as an in-frame
  correction, not a separate entry.
- Otherwise none known; #428/#431 narrowed diagnostics as planned once field data showed
  false positives.

## Open questions

- Root cause of fork issue #297 was never fully proven; #381 rated its own fix 65/100
  for the failure mode. Whether the Sentry event kinds have gone quiet since #428/#431
  cannot be verified from the repository.
- `WindowLifecycleDiagnostics.noteWindowless` is still called unconditionally from
  `surfaceMainWindow` when an opener is registered, relying on later rechecks
  (`noteMainWindowAppeared`, report-time decisions) to clear stale state — correct today
  but easy to regress if a new caller forgets the resolution path.
