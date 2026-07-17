# 036 — Window Management Hardening: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-26 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #261, #353, #381, #428, #431 (amendments: #494, #523) |
| **Sources** | PR descriptions #261/#353/#381/#428/#431/#494/#523; fork issues #297, #490; upstream review ledger → `docs-ai/017-upstream-sync-process/upstream-ledger.md` |
| **Related** | [013-prowl-cli](../013-prowl-cli/000-plan.md), [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md), [020-observability](../020-observability/000-plan.md), [035-protected-terminal-close](../035-protected-terminal-close/000-plan.md) |

## Background

Prowl's main window is a singleton SwiftUI `Window(_:id:)` scene. SwiftUI tears the
backing `NSWindow` down when the window closes, and on a macOS restart-relaunch
(loginwindow "reopen windows at login") the scene is often not recreated at all — the
process launches with zero windows. A bare `NSApp.activate(ignoringOtherApps:)` cannot
bring back a torn-down scene; only `openWindow(id:)` rebuilds it, and before this work
that only happened implicitly when `applicationShouldHandleReopen` fired (Dock icon
click). Activation paths that do not trigger reopen — Cmd-Tab, Mission Control, CLI
`prowl open`, menu commands — left the app stuck windowless and apparently unresponsive.

Fork issue #297 reported exactly this: Prowl unresponsive after a macOS restart with
window restoration, and intermittently unresponsive when re-activating after all windows
had been closed. A stackshot existed but did not conclusively prove the trigger path, so
the effort was framed as a targeted mitigation plus field observability rather than a
proven root-cause fix.

Groundwork predating the anchor: PR #261 (2026-05-09, adaptation of upstream #297/#298
from the post-v0.8.5 review batch) added dynamic main-window titles, centralized
main-window surfacing so app reopen / CLI open / Window menu / quit confirmation all
target the real main window instead of Settings or panels, and routed quit termination
through an injectable `AppLifecycleClient` so confirmation behavior is testable.

## Goals

- Recreate the main window from **every** activation path, including relaunches that
  start with zero windows, by bridging AppKit lifecycle code to SwiftUI's
  `openWindow(id:)`.
- Identify the main window strictly (visible window with identifier `WindowID.main`)
  instead of guessing among AppKit helper windows.
- Ship diagnostics (structured logs + narrow Sentry events) that can confirm or refute
  the mitigation in the field, and keep those diagnostics free of false positives
  (inactive/background launches, stale windowless state).
- Keep quit confirmation anchored to the real main window.

### Non-goals

- Proving the exact root cause of issue #297 (PR #381 self-assessed 65/100 confidence;
  observability was the compensating investment).
- Auxiliary window behavior (Diff/Settings/Debug) — handled later as amendments.

## Design / Approach

- **Window identity** — `WindowID.main` (`supacode/App/WindowSurfacing.swift`) is stamped
  onto the main `NSWindow` by `WindowTabbingDisabler`
  (`supacode/App/WindowTabbingDisabler.swift`), which also disables native tabbing and
  persists the window frame.
- **Opener bridge** — `MainWindowOpener` (`supacode/App/MainWindowOpener.swift`) holds a
  registered `openWindow(id: WindowID.main)` closure. It is registered from two places:
  the app command tree (`supacode/Commands/WindowCommands.swift`), which is built even
  when no window exists — essential for zero-window relaunches — and the main window
  content (`registersMainWindowOpener()`), which refreshes registration on appearance.
- **Surfacing** — `NSApplication.surfaceMainWindow()` finds a main-window candidate and
  deminiaturizes/orders it front; when no candidate exists it requests a new window via
  the registered opener, falling back to activation-only when no opener is registered
  yet. All callers (app delegate reopen/activation hooks, Window menu, CLI open handler,
  quit flow) go through this one entry point.
- **Diagnostics** — `WindowLifecycleDiagnostics` (same file) tracks windowless periods,
  logs via `SupaLogger`, runs a main-thread heartbeat, and captures two narrow Sentry
  event kinds in release builds: `main_window_timeout` (windowless ≥ 10 s) and
  `windowless_main_thread_stall` (heartbeat lag ≥ 5 s while windowless), tagged with
  main/visible window counts and opener registration state.
- **Quit** — `AppFeature.requestQuit` surfaces the main window before presenting the
  confirmation alert; termination goes through `AppLifecycleClient`
  (`supacode/Clients/AppLifecycle/AppLifecycleClient.swift`).

## Alternatives & decisions

- **Disk lifecycle logging vs SupaLogger + Sentry** — #353 replaced temporary on-disk
  lifecycle logs with SupaLogger-only diagnostics plus narrow Sentry events; disk logging
  was a debugging scaffold, not a shippable mechanism.
- **Helper-window fallback removed** — #353 initially allowed surfacing arbitrary
  non-panel AppKit windows when no identified main window was found. Sentry evidence
  showed helper windows being counted as the main window, so #381 tightened the rule to
  "visible `WindowID.main` only" and deleted the fallback.
- **Diagnostics ordering** — #381 moved the windowless note before `openWindow(id:)` to
  stop stale windowless reports racing a successfully recreated window.
- **Report only when actionable** — #428/#431 decided that stall/timeout Sentry reports
  are only meaningful for active sessions with genuinely no visible main window; both
  paths re-check window state at report time and resolve stale tracking instead of
  reporting (driven by Sentry issues PROWL-MACOS-AW / PROWL-MACOS-AV being dominated by
  background-launch and stale-state samples).
- **Mitigation over closure** — the team explicitly accepted a mitigation-plus-telemetry
  posture (#381: "targeted mitigation plus better observability rather than a fully
  proven root-cause closure").

## Amendments

- Updated 2026-06-23: auxiliary windows (Diff/Settings/Debug) invisible in fullscreen
  Spaces — see [002-fullscreen-auxiliary-windows.md](002-fullscreen-auxiliary-windows.md)
- Updated 2026-06-28: Close Window in fullscreen no longer hides the window (black-screen
  fix) — see [003-fullscreen-close-black-screen.md](003-fullscreen-close-black-screen.md)
