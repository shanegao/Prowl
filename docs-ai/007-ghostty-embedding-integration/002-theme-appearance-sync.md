# 007 — Amendment: Theme / Appearance Sync (2026-04-24 → 2026-05-26)

## Context

Prowl has its own appearance setting (System / Light / Dark) while Ghostty renders with
the user's Ghostty theme. Two mismatches surfaced (fork issue #223, later #351):

1. A user with a **single** Ghostty theme (e.g. a dark theme) got a dark terminal inside
   a Light-mode Prowl window — Ghostty only adapts when the user configured a
   `light:X,dark:Y` pair. The same applies with **no** theme at all: Ghostty's no-theme
   default is a fixed dark background (`#282C34`) that ignores appearance entirely.
2. During startup, restored terminal surfaces could be created **before** SwiftUI
   propagated `.preferredColorScheme`, so Ghostty picked the system Light/Dark branch
   instead of the app-selected one.

Constraint carried through all three PRs: never mutate the user's Ghostty config file;
any adaptation must be runtime-only and reversible.

## Change

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-24 | Single-theme mismatch fallback: probe `ghostty +show-config` for `theme`/`background`, classify the background tone, and when a single theme's tone contradicts the app appearance, apply a runtime-only override in Ghostty's dual form (`theme = light:…,dark:…`); cleared as soon as tones re-align; parser tests added | PR #237 |
| 2026-04-27 | Initial color-scheme sync: `GhosttyRuntime(initialColorScheme:)` seeds the persisted appearance mode before any restored surface exists; `GhosttyColorSchemeSyncView` anchors to the explicit Light/Dark preference and only follows the environment in System mode | PR #242 |
| 2026-05-26 | Respect explicit same-name dual themes (`theme = light:X,dark:X` — collapsed to a single theme by `+show-config`, so the theme mode is re-derived from the **raw** user config) and fold the no-theme case into the fallback via `GhosttyThemeMode.allowsMismatchFallback`; `.dual` is always respected | PR #352 |

The override is applied by writing the fallback line to a temp file
(`prowl-ghostty-theme-overrides.conf`) and rebuilding the Ghostty config with that file
loaded last — the same mechanism used for Prowl's keybind overrides.

## Refs

- PRs #237, #242, #352; fork issues #223, #351.

## Current state (as of 2026-07-12)

- `supacode/Infrastructure/Ghostty/GhosttyRuntime+ThemeFallback.swift` —
  `reconcileThemeFallback(for:)` (off-main probe, short-circuited under test),
  `applyResolvedThemeFallback`, `setThemeFallbackOverride`,
  `applyRuntimeOverridesIfNeeded` (temp-file override loading), raw-config re-derivation
  (`rawUserThemeMode`, `preferredGhosttyConfigURL` mirroring Ghostty's macOS config
  selection; `config-file` includes are not resolved — documented limitation).
- `supacode/Infrastructure/Ghostty/GhosttyRuntimeSupport.swift` — `GhosttyThemeMode`
  (`none`/`single`/`dual`, `allowsMismatchFallback`), `GhosttyTerminalTone`,
  `GhosttyUserConfigSnapshot.parse(showConfigOutput:)`, `rawThemeSpec(fromConfig:)`
  (last-wins, comment-aware), `classifyBackgroundTone` (luminance-only — #237's PR body
  describes a strict saturation gate, but it was already dropped within #237's own review
  cycle because tinted dark themes like Dracula/Nord were misclassified as `unknown`).
- `supacode/App/GhosttyColorSchemeSyncView.swift` + `GhosttyRuntime.init(initialColorScheme:)`
  (seeded from persisted settings in `supacode/App/supacodeApp.swift`).
- Reload path: `GhosttyRuntime+Callbacks.swift` re-runs `reconcileThemeFallback` on
  `GHOSTTY_ACTION_CONFIG_CHANGE`, so editing the Ghostty config re-evaluates the fallback.
- Tests: `supacodeTests/GhosttyUserConfigSnapshotTests.swift`,
  `supacodeTests/GhosttyRuntimeColorSchemeTests.swift`.
