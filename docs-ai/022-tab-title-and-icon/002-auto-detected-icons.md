# 022 — Amendment: Auto-Detected Command Icons (#234, #245)

## Context

After #215, changing a tab icon was possible but entirely manual. Multi-agent windows
still defaulted to the anonymous `terminal` glyph unless the user curated every tab.
#234 (merged 2026-04-22) made icons automatic: detect the running command from the
OSC 2 title and paint a per-command icon — branded artwork where available, SF Symbol
fallback otherwise. #245 (merged 2026-04-27) then fixed the precedence gap this opened
for Run Script and Custom Command tabs.

## Change

**#234 — detection pipeline and assets**

- Detection runs in `WorktreeTerminalState.noteTitleForCommandDetection` on every OSC 2
  title change. *Mapping-hit-equals-apply*: `CommandIconMap` looks up the first
  whitespace-delimited token; a hit applies immediately, a miss leaves the current icon
  alone. No debounce — the curated allow-list makes a hit trustworthy, which handles
  short-lived commands (`git status`) and TUIs that rewrite their title right away
  (`codex` → repo name).
- Idle-prompt suppression: a per-surface learned-idle set captures the first title after
  each `command_finished`, plus a shape heuristic (`isLikelyIdleTitleByShape`) for the
  bootstrap window before anything has been learned.
- Sticky semantics: the icon stays after the command exits, as a "what is this tab for"
  hint, until the next mapped command runs. Manual overrides (`isIconLocked` at the
  time) always win, and only the focused surface of a multi-split tab may drive the
  tab's icon.
- `TabIconSource` (required SF Symbol fallback + optional asset name), `@asset:<Name>`
  serialization parsed by `ResolvedTabIcon`, and a shared `TabIconImage` view used by
  both `TerminalTabLabelView` and `ShelfSpineView`. Shipped ~55 first-token mappings
  across 14 categories with 19 monochrome template brand SVGs
  (sources listed in `supacode/Assets.xcassets/CommandIcons/README.md`).
- DEBUG-only Debug Window with an Icon Catalog section rendering every map entry
  through `TabIconImage`, with a searchable filter.

**#245 — precedence pinning**

- New precedence level: auto-detected < script/Custom Command < user picker. Run Script
  tabs keep `play.fill` for the tab's lifetime (no single-frame flash before the
  command icon took over); Custom Commands carry their configured `systemImage` via a
  new `customCommandIcon` parameter on `TerminalClient.Command.createTabWithInput` /
  `createSplitWithInput`. The model's `"terminal"` placeholder and empty values count
  as "unset" so untouched commands still get full auto-detection.
- Within the same PR, the two lock booleans (`isIconLocked`, `isScriptIconActive`) were
  collapsed into a single `TerminalTabIconLock` enum (`auto`/`script`/`user`), commit
  `1826028c`. Resetting via the picker clears the lock back to `auto` so detection can
  take over again.

## Refs

- PR #234 (2026-04-22), PR #245 (2026-04-27, incl. `1826028c`)
- Cross-link: [002-custom-commands](../002-custom-commands/000-plan.md) for the Custom
  Command model that `customCommandIcon` reads from.

## Current state

All of the above is live; see the file inventory in [001-action.md](001-action.md).
The command map and artwork kept growing after #234 (about 66 tokens and 44 brand
imagesets as of 2026-07-12, e.g. Cline, Kimi).
