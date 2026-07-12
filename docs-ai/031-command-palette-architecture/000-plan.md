# 031 — Command Palette Architecture: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-16 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #291, #292, #293, #294, #296, #299, #300, #302 (+ #301/#303 in-frame fixes; #218/#287 precursors; #396/#421 see Amendments) |
| **Sources** | `doc-onevcat/plans/2026-05-16-command-palette-architecture-plan.md` (absorbed here; original removed in the docs-ai migration), PR descriptions #291–#303 |
| **Related** | [002-custom-commands](../002-custom-commands/000-plan.md), [003-diff-window](../003-diff-window/000-plan.md), [012-keybinding-system](../012-keybinding-system/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md), [027-split-pane-ux](../027-split-pane-ux/000-plan.md), `docs/components/command-palette.md` |

## Background

The command palette (`supacode/Features/CommandPalette/`) shipped ~24 commands and
the goal was 60–80: view toggles, navigation, worktree operations, and terminal
actions were reachable only via hotkeys or menu items. Two smaller fixes had already
landed — #218 (hide contextual actions like "Change Tab Icon…" from the empty-query
list) and #287 (replace the fragile SwiftUI `@FocusState` query focus with an
AppKit-backed field after macOS 26.5 broke the Cmd+P first-responder handoff) — but
before batch-adding commands, three architectural issues would have compounded at
scale:

1. **Confusing visibility model.** Two booleans (`isGlobal`, `isRootAction`)
   collapsed into one bit of meaningful state; the 8 app-level commands set both,
   so an empty Cmd+P showed a blank list in normal (no-PR) use.
2. **No keyword aliases.** The fuzzy scorer matched only `title` and `subtitle`;
   "Toggle Sidebar" could not be found by typing `sb`. At 60+ commands, short
   queries are load-bearing for discoverability.
3. **High cost-per-command.** Each addition touched `CommandPaletteItem.Kind`, the
   builder in `CommandPaletteFeature.commandPaletteItems`, delegate routing in
   `AppFeature`, and icon/badge rules in the overlay view, with no factory to
   compress the repetition.

## Goals

- Replace the two-flag visibility model with a single explicit
  `defaultSuggestion: Bool` plus a required `category` for section grouping.
- Make empty Cmd+P useful: a Recent/Suggested split capped at 8 rows, with section
  headers only on empty query (typing collapses to the flat fuzzy-ranked list).
- Keyword aliases that participate in fuzzy scoring but never display; highlight
  positions always come from the title so no synthetic offsets leak into the UI.
- Factories (`appShortcut`, `ghosttyCommand`) so batch additions become one-liners.
- Then batch-add commands by category: view toggles, navigation, worktree actions,
  terminal/tab/pane, shelf navigation.

**Non-goals**

- No registry pattern — the centralized builder stays; per-feature command
  contribution is a larger shift not justified at this scale.
- No frequency tracking on top of recency — the exponential-decay recency model
  (7-day half-life) is good enough.
- No declarative availability framework — context conditions stay as `if` branches
  in the builder.
- No list virtualization — SwiftUI `ForEach` handles ~80 rows fine on macOS 26+.

## Design / Approach

A four-stage PR sequence, foundations first:

1. **PR1 — model refactor (#291), no behavior change.** Add
   `Category` (`view` / `navigation` / `worktree` / `pullRequest` / `terminal` /
   `app` / DEBUG-only `debug`), `keywords: [String]`, and `defaultSuggestion: Bool`
   to `CommandPaletteItem`; delete `isGlobal` / `isRootAction`. A tagging table
   fixed `defaultSuggestion = isGlobal && !isRootAction` per kind so empty-query
   behavior stayed byte-identical.
2. **PR2 — search & empty-state UX (#292).** Recent (non-zero recency score, sorted
   by score) + Suggested (`defaultSuggestion` items not in Recent, sorted by
   `priorityTier` then declaration order), 8-row cap. Scorer scores `[title] +
   keywords` and takes the max. Flip the 8 app-level commands to
   `defaultSuggestion: true` with starter keywords (`preferences`, `update`,
   `cli`, …).
3. **PR3 — factories (#293).** `CommandPaletteItem.appShortcut(...)` for
   AppShortcut-backed commands and `.ghosttyCommand(_:)` for Ghostty-bridged
   terminal commands (`.terminal` category, search-only, priority +100).
4. **PR4+ — batch additions.** View toggles (#294), navigation (#296), worktree
   actions (#299), and a terminal/tab/pane batch that was expected to mostly pipe
   through Ghostty's existing `command-palette-entry` bridge.

**Contextuality lives in command construction**, not in the visibility flag: the
builder only constructs PR commands when an open PR exists, worktree commands when
a worktree is selected, etc. `defaultSuggestion` therefore stays a single uniform
bit — an item is suggested when the builder constructed it *and* the flag is true —
so the suggestion view is one filter + one sort with no PR-command special case.

## Alternatives & decisions

- **Single `defaultSuggestion` bit vs three-state enum**
  (`alwaysSuggest / onSearch / contextual`): rejected the enum because
  contextuality already lives in the builder; a bool is sufficient and uniform.
- **Keyword highlighting**: match positions are always computed against the title
  even when a keyword scored higher, so the UI never paints highlights at indexes
  that don't exist in the visible string.
- **`contextual(...)` factory** (planned third factory): deferred in #293 — it
  saved one line per call site and contextual commands vary too much in shape to
  share a signature. Never added since.
- **Terminal/tab/pane batch collapsed** (PR7 audit in #300): tab/pane switching and
  find were dropped (Ghostty's auto-bridged `command-palette-entry` items already
  cover font size, close tab/surface, new tab; ⌘F is intuitive). Shelf navigation
  and bulk-selection stretch items were dropped too. Only "Repo Settings" shipped
  from that batch, and a planned "New Tab" command was cut as a duplicate of
  Ghostty's own entry.

## Amendments

- Updated 2026-06-08: post-buildout fixes — Canvas card focus routing (#396) and
  first-open color-scheme flicker (#421) — see
  [002-post-buildout-fixes.md](002-post-buildout-fixes.md)
