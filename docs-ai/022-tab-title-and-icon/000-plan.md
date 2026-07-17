# 022 — Tab Title and Icon: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-18 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #214, #215 (anchor); #234, #245, #259 (later waves); #186 (groundwork) |
| **Sources** | PR descriptions #186/#214/#215/#234/#245/#259; fork issues #172, #194; upstream review ledger entry for upstream #269 |
| **Related** | [014-terminal-layout-persistence](../014-terminal-layout-persistence/000-plan.md) (#186 persists title/icon in the snapshot), [002-custom-commands](../002-custom-commands/000-plan.md) (#245 pins Custom Command icons), `docs/components/terminal.md` |

## Background

Every terminal tab in Prowl looked the same: the icon was hardcoded to `terminal` and the
title was whatever the shell last emitted via OSC 2. With many worktrees × many tabs
(often several coding agents running in parallel), multi-tab windows were visually
indistinguishable — nothing told you at a glance what a tab was *for*.

Two pieces of groundwork already existed by the anchor date:

- #186 (2026-04-08, fork issue #172) had added optional `title` / `icon` fields to
  `SnapshotTab` in the terminal layout snapshot, so per-tab identity could round-trip
  across app relaunches. That persistence work is documented in
  [014-terminal-layout-persistence](../014-terminal-layout-persistence/001-action.md);
  this entry covers the identity features built on top of it.
- A `promptTabTitle` NSAlert flow existed (backing Ghostty's `prompt_title` action), but
  was not reachable from the tab context menu.

Fork issue #194 then asked for the missing half: a UI to change the tab icon, noting the
snapshot layer already supported saving/restoring one.

## Goals

- Let the user rename a tab from the tab's right-click menu (#214).
- Let the user pick a custom tab icon — preset grid plus free-form SF Symbol name — from
  the context menu and the command palette (#215).
- Make chosen titles/icons survive relaunch via the existing layout snapshot.
- (Later waves) Make icons useful without manual work: auto-detect an icon from the
  running command (#234), with a sane precedence order against script/user choices
  (#245); make custom titles first-class and persistent, separate from live shell titles
  (#259).

**Non-goals**

- Per-tab tint color: fork issue #172 also mentioned persisting a tint color, but no
  per-tab tint was ever built (repo-level color identity came separately, see
  entry 025).

## Design / Approach

As planned at the anchor (from #214/#215 PR descriptions):

- **Title change** (#214): add a "Change Tab Title..." entry at the top of the terminal
  tab context menu, reusing the existing `promptTabTitle` NSAlert flow via a new
  `WorktreeTerminalState.promptChangeTabTitle(_:)`. Empty input clears the override,
  matching Ghostty `prompt_title` semantics. A `changeTitle` closure threads
  `TerminalTabBarView` → `TerminalTabsView` → `TerminalTabsRowView` →
  `TerminalTabContextMenu`.
- **Icon change** (#215): a SwiftUI picker (`TabIconPickerView`) with a curated
  40-symbol preset grid, a free-form SF Symbol name field with live preview (Done
  disabled until the name resolves to a real system symbol), an "Open SF Symbols"
  shortcut, and "Reset to Default". Reachable from the tab context menu and from the
  command palette (`CommandPaletteItem.Kind.changeFocusedTabIcon` →
  `TerminalClient.Command.presentTabIconPicker`).
- **Lock model**: the tab model gains `isIconLocked`, and `TerminalTabManager` exposes
  `overrideIcon` / `clearIconOverride` / `updateIcon`, mirroring the existing
  title-lock pattern (`isTitleLocked`, used by the RUN SCRIPT tab).
- **Persistence contract**: snapshot capture writes `tab.icon` only when the user has
  overridden it; restore re-derives the lock from the snapshot so a chosen icon
  round-trips without being silently overwritten by defaults.

The auto-detection design (#234) and the title persistence redesign (#259) came later
and are described in the amendments.

## Alternatives & decisions

- **Sticky icons over reset-on-exit** (#234): an auto-detected icon deliberately stays
  after the command exits — "a tab that ran `claude` keeps the Claude icon as a
  'what is this tab for' hint until the next mapped command runs".
- **Allow-list over debounce** (#234): icon detection is *mapping-hit-equals-apply* on
  the first whitespace-delimited token of each OSC 2 title, with no debounce. A curated
  allow-list hit is by definition brandable; this fixed short-lived commands
  (`git status`) and TUIs that immediately overwrite their `preexec` title (`codex`),
  both of which slipped past an earlier debounce-based detector idea. Idle shell
  prompts are suppressed by a per-surface learned-idle set plus a shape heuristic.
- **Explicit precedence order** (#245): auto-detected < Run Script / Custom Command
  icon < user picker. Initially two booleans; collapsed into a single
  `TerminalTabIconLock` enum (`auto` / `script` / `user`) inside the same PR.
- **Custom title as separate field, not frozen live title** (#259, adapting upstream
  #269): user titles moved from "override the single `title` string" to a dedicated
  `customTitle` with `displayTitle = customTitle ?? title`, so the live shell title
  keeps flowing underneath and a snapshot no longer freezes a stale shell title.
- **String-typed icon storage** (#234): `tab.icon` stays `String?` for back-compat with
  the picker and persistence; bundled brand artwork serializes as `@asset:<Name>` and
  is parsed by `ResolvedTabIcon`.

## Amendments

- Updated 2026-04-27: auto-detected command icons + precedence pinning (#234, #245) —
  see [002-auto-detected-icons.md](002-auto-detected-icons.md)
- Updated 2026-05-08: persistent custom tab titles and inline rename (#259) —
  see [003-persistent-custom-titles.md](003-persistent-custom-titles.md)
