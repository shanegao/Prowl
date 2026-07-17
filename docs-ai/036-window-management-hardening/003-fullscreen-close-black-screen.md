# 036 — Amendment: Fullscreen Close-Window Black Screen

## Context

Outside fullscreen, Close Window intentionally hides the main window instead of closing
it: `WindowTabbingDisabler`'s window delegate intercepts `windowShouldClose`, calls
`orderOut(nil)`, and returns `false`, so the SwiftUI scene survives and can be
resurfaced. In fullscreen this policy backfired: once the last terminal tab was closed,
another `Cmd+W` fell through from tab-close to the window-close command, and
`orderOut(nil)` on a fullscreen window left the re-shown Ghostty area black (fork issue
#490 describes the black screen where `EmptyTerminalPaneView` should appear).

## Change

Make the hide-on-close policy conditional on fullscreen state:
`WindowTabbingDisabler.WindowTabbingView.windowShouldClose` only calls `orderOut(nil)`
when `shouldOrderOutOnClose(styleMask:)` is true, i.e. when the window's style mask does
not contain `.fullScreen`. The non-fullscreen hide behavior is unchanged, and the
delegate still returns `false` so the window is never actually closed. Focused tests
cover the fullscreen vs non-fullscreen policy.

## Refs

- PR #523 (merged 2026-06-28), fixes fork issue #490
- Related: [035-protected-terminal-close](../035-protected-terminal-close/000-plan.md)
  (the `Cmd+W` tab-close path this falls through from)

## Current state

`supacode/App/WindowTabbingDisabler.swift` implements
`shouldOrderOutOnClose(styleMask:)` as `!styleMask.contains(.fullScreen)`; tests in
`supacodeTests/WindowTabbingDisablerTests.swift` (verified 2026-07-12).
