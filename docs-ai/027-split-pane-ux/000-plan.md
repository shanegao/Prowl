# 027 — Split Pane UX: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-04 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #253, #258, #279 (+ #435, see Amendments) |
| **Sources** | PR descriptions #253/#258/#279/#435, fork issues #278/#369, upstream review ledger (`docs-ai/017-upstream-sync-process/upstream-ledger.md`) |
| **Related** | [012-keybinding-system](../012-keybinding-system/000-plan.md), [023-shelf-mode](../023-shelf-mode/000-plan.md), [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md), `docs/components/terminal.md` |

## Background

Prowl runs several agent panes side by side inside split layouts (normal tabs,
Shelf, Canvas cards). With more than one pane per tab it was hard to tell at a
glance which split pane had keyboard focus: every surface rendered at full
brightness, and the split divider was a hardcoded `.secondary`-styled line that
user themes could not restyle. Ghostty.app already solves the focus-visibility
problem with `unfocused-split-fill` / `unfocused-split-opacity`, and exposes
`split-divider-color`, so users coming from Ghostty expected their existing
config to carry over. Fork issue #278 explicitly requested divider color/width
customization through the Ghostty config pipeline.

## Goals

- Make the focused pane obvious in any multi-split layout by dimming unfocused
  panes, in all three hosts (tab view, Shelf open-book, Canvas cards).
- Respect the user's Ghostty theming: source the dim tint and the divider color
  from Ghostty runtime config rather than hardcoding values.
- Give users an off switch (`Settings → Appearance → Splits`) and a divider
  width control.
- Keep the Ghostty fork patch set minimal — no new patched config keys.

**Non-goals**

- Split zoom / focus mode (requested later in issue #369; handled as a separate
  wave — see Amendments).

## Design / Approach

Three steps, each a PR:

1. **Dim overlay (#253)** — a translucent tint layered on top of each
   unfocused terminal surface in `TerminalSplitTreeView`'s `LeafView`, kept
   below the progress/search/drag-handle overlays. Initially a black tint with
   scheme-adaptive strength (0.30 dark / 0.12 light). Controlled by a new
   `dimUnfocusedSplits` toggle in `GlobalSettings` (default on). Requires
   plumbing `focusedSurfaceID` through `TerminalSplitTreeView` / `SubtreeView`
   / `LeafView` (and the AX container) from all three call sites:
   `WorktreeTerminalTabsView`, `ShelfOpenBookView`, `CanvasView`. Single-pane
   (no-split) terminals are never dimmed.
2. **Ghostty config alignment (#258)** — replace the hardcoded tint with values
   read from Ghostty runtime config: `unfocused-split-fill` (falling back to
   `background`) and `unfocused-split-opacity` (inverted into an overlay
   opacity). Route click focus and explicit split focus through a shared
   active-surface path, and refresh the overlays in all three hosts when the
   Ghostty runtime config reloads. Upstream reference:
   upstream #260 (supabitapp/supacode@4d19b068).
3. **Divider color + width (#279)** — read Ghostty's existing
   `split-divider-color` via `ghostty_config_get` (fallback
   `NSColor.separatorColor`). Ghostty hardcodes the visible divider size, so
   width is a fork-only `prowl-split-divider-width = N` directive parsed
   directly from the primary Ghostty config file
   (`ghostty_config_open_path()`), clamped to 0…32 pt; the invisible hit area
   is unchanged. Both values flow through
   `WorktreeTerminalManager.splitDividerAppearance()` into
   `TerminalSplitTreeView` and a new `dividerVisibleSize` argument on
   `SplitView`.

## Alternatives & decisions

- **Own implementation vs upstream port**: upstream shipped its own inactive
  split dimming (upstream #260) in the same window. The fork kept its own
  settings-toggle-based overlay from #253 (the upstream ledger records upstream
  #260 as "already covered / intentionally different") but aligned the tint
  source with Ghostty config in #258, citing upstream #260 as reference.
- **Divider width mechanism**: adding a real Ghostty config key would mean
  another patch on the Ghostty submodule fork. Decided instead to parse a
  Prowl-namespaced directive (`prowl-split-divider-width`) from the user's
  existing Ghostty config file, keeping the Ghostty patch set minimal (PR #279;
  answers issue #278's request to reuse the same pipeline as the dim effect).
- **Settings surface**: only the on/off dim toggle lives in Prowl settings;
  colors and width stay Ghostty-config-driven so one theme file styles both
  apps.

## Amendments

- Updated 2026-06-10: split-zoom UX — per-pane zoom buttons, `⌘⌥⇧F` binding,
  palette focus-race fix (#435) — see [002-split-zoom-ux.md](002-split-zoom-ux.md)
