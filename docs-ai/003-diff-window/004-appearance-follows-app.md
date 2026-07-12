# 003 — Amendment: Diff Window Follows App Appearance (2026-07-08)

## Context

The diff window followed the **system** appearance instead of the app's
`appearanceMode` setting: with the system in Light and the app set to Dark, the
diff window rendered with a Light background.

Root cause traces back to the 000-plan design decision to host the window as a
standalone `NSWindow` (`DiffWindowManager`) rather than a SwiftUI `WindowGroup`
scene: it never read `appearanceMode` from `settingsFile`, so
`.preferredColorScheme()` had no effect. Additionally YiTong's `DiffView`
(WKWebView-backed) used `.automatic` appearance, which resolves
`view.effectiveAppearance` in `viewDidLoad()` — before the view enters the
window hierarchy — returning the system default on first render.

## Change

PR #540 (merged 2026-07-08) applies the app's appearance at three levels:

- **Window chrome** — `DiffWindowManager.show(...)` takes a `colorScheme`
  parameter and sets `window.appearance` (via an `NSAppearance.from(_:)`
  helper) before `makeKeyAndOrderFront`, for both new and reused windows.
- **Live updates** — `DiffWindowContentView` reads `@Shared(.settingsFile)`
  and installs a `WindowAppearanceSetter` in `.background`, the same pattern
  as `SettingsView`/`DebugView`, so changing the setting updates the open
  window.
- **WKWebView content** — an explicit `appearance` is passed to YiTong's
  `DiffConfiguration` instead of `.automatic`, bypassing the too-early
  `effectiveAppearance` read.

`ExternalDiffToolClient` threads the resolved color scheme into
`DiffWindowManager.show()` for the Built-in tool path.

## Refs

- PR #540. Files: `supacode/Features/DiffView/DiffWindowManager.swift`,
  `supacode/Features/DiffView/DiffWindowContentView.swift`,
  `supacode/Clients/ExternalDiff/ExternalDiffToolClient.swift`.

## Current state

Verified in the working tree 2026-07-12: `NSAppearance.from(_:)` and the
pre-`makeKeyAndOrderFront` appearance assignment exist in `DiffWindowManager`,
and `DiffWindowContentView` carries `@Shared(.settingsFile)` +
`WindowAppearanceSetter` and passes an explicit appearance to
`DiffConfiguration`.
