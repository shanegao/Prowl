# 012 — Amendment: Chained-Binding Shortcut-Hint Limitation (2026-05-24)

## Context

Shortcut hints for Ghostty-native actions (e.g. `new_split:right`) are resolved by
reverse lookup: `GhosttyRuntime.keyboardShortcut(for:)` calls `ghostty_config_trigger`
to map an action string back to its trigger. In May 2026 the split-creation hints in
the tab bar showed empty even though the keys worked inside the surface.

## Finding

**Known limitation:** Ghostty deliberately excludes chained (`chain=`), sequence
(`a>b`), and `performable:` triggers from its reverse map (the `track_reverse` handling
in `ThirdParty/ghostty/src/input/Binding.zig`), because such triggers cannot be
expressed as a single GUI menu accelerator. `ghostty_config_trigger` therefore returns
an empty trigger for any action bound *only* through such a trigger — so Prowl's
shortcut hints show empty for it. Plain (non-chained) custom rebinds resolve fine.

The observed case was user config, not a Prowl bug: the local Ghostty config chained
`equalize_splits` onto `super+d=new_split:right` / `super+shift+d=new_split:down`,
which removed those bindings from the reverse map. A probe against the default Ghostty
config confirmed split actions resolve normally when unchained.

## Decision

- PR #334 ("Show split shortcut hints when bindings are chained", a hardcoded-fallback
  approach) was **closed unmerged** on 2026-05-24 once the root cause was understood;
  the user config was fixed instead.
- The limitation is accepted: reading a chained trigger would require a new
  forward-search C API in the Ghostty fork (searching the forward binding map including
  chained leaves) plus an xcframework rebuild — not undertaken.

## Refs

- PR #334 (closed 2026-05-24, unmerged).
- `ThirdParty/ghostty/src/input/Binding.zig` (reverse-map exclusion).

## Current state

`supacode/Infrastructure/Ghostty/GhosttyRuntime.swift` (`keyboardShortcut(for:)`) and
`supacode/Infrastructure/Ghostty/GhosttyShortcutManager.swift` still resolve hints via
`ghostty_config_trigger`; actions bound only through chained/sequence/performable
triggers continue to show no shortcut hint.
