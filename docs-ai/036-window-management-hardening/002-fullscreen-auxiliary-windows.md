# 036 — Amendment: Auxiliary Windows Invisible in Fullscreen

## Context

With the main window in native fullscreen (an exclusive macOS Space), opening an
auxiliary window — Diff, Settings, or Debug — created the `NSWindow` on a background
Space instead of the fullscreen Space. The window existed but never appeared, so
clicking the corresponding buttons looked like a no-op. Root cause: windows configured
only with `tabbingMode = .disallowed` do not automatically join the active Space.

## Change

Set `collectionBehavior = [.moveToActiveSpace]` on the windows created by all three
auxiliary window managers so macOS moves them onto the current (including fullscreen)
Space:

- `supacode/Features/DiffView/DiffWindowManager.swift`
- `supacode/Features/Settings/BusinessLogic/SettingsWindowManager.swift`
- `supacode/Features/Debug/BusinessLogic/DebugWindowManager.swift`

## Refs

- PR #494 (merged 2026-06-23)
- Related: [003-diff-window](../003-diff-window/000-plan.md) (Diff window manager)

## Current state

All three managers still set `[.moveToActiveSpace]` at window creation (verified
2026-07-12 in the files above).
