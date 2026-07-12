# 012 — Amendment: Ghostty Key Equivalent Ownership (2026-05-08)

## Context

Since M2/M3, `GhosttySurfaceView.performKeyEquivalent` routes keys bound in Ghostty to
the surface first, and only lets unbound keys fall through to the app. Upstream
identified two edge cases in this routing (upstream #259 `6c807c63`, upstream #264
`539c0feb`): a surface could consume key equivalents while not actually being the first
responder, and Ghostty-bound or custom shortcuts were forwarded to the main menu even
when no menu item carried that exact shortcut.

## Change

Ported to the fork as #255 during the 2026-05-08 upstream review batch (see
[../017-upstream-sync-process/upstream-ledger.md](../017-upstream-sync-process/upstream-ledger.md)):

- Require the Ghostty surface to be the actual first responder before it handles key
  equivalents.
- Forward Ghostty-bound or user-custom shortcuts to the main menu only when an exact
  menu item shortcut exists.
- Regression coverage for shifted menu-shortcut matching and focus ownership.

## Refs

- PR #255 (fork port); upstream #259, #264.
- Upstream ledger entry 2026-05-08 ("Review through post-v0.8.5").

## Current state

`supacode/Infrastructure/Ghostty/GhosttySurfaceView+Keyboard.swift` implements the
`performKeyEquivalent` routing; tests live in
`supacodeTests/GhosttySurfaceViewTests.swift`.
