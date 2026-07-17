# 033 — UI Refresh 2026-05: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-05-24 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #331 + #332 (anchor); #326, #343 (same wave); #168, #169 (precursors); #467 (amendment) |
| **Sources** | PR descriptions #168/#169/#326/#331/#332/#343/#467; `feat/ui-enhancements` branch commit messages (`13fc410d..5cfad79c`); fork issues #311/#315/#317 |
| **Related** | [025-repo-identity-appearance](../025-repo-identity-appearance/000-plan.md) (repo color feeds the chrome tint; `.custom` color added here), [026-sidebar-container-refactor](../026-sidebar-container-refactor/000-plan.md) (sidebar structure this refresh built on), [023-shelf-mode](../023-shelf-mode/000-plan.md) (spine tint preferences), [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md) (palette the refresh polished), [029-active-agents-panel](../029-active-agents-panel/000-plan.md) (agent rows touched by #331), `docs/components/settings.md`, `docs/reference/settings-fields.md` |

## Background

This is the fork's first large community contribution. In May 2026, GitHub user
**abhi21git** (Abhishek Maurya) first fixed the toolbar title hover layout shift (#326,
superseding the closed fork attempt #324), then opened #331 "Major UI Enhancements": a
single-commit, 20-file pass over the terminal tab bar, sidebar, find overlay, command
palette, Active Agents rows, and the agent loading indicator. It addressed three open
fork issues — tab visual differentiation (#311), sidebar background color mismatch
(#315), and inconsistent Shelf/Canvas mode toggling (#317).

Two earlier fork fixes are the precursors for the "chrome tint" theme: on macOS 26,
non-opaque windows render a white-biased glass, so with Ghostty `background-opacity < 1`
the titlebar looked light even in dark mode. #168 tinted `window.backgroundColor` by
appearance (dark ⇒ black at 0.7 alpha) to counteract the bias, and #169 gave the sidebar
footer a material background under transparency. The 05 refresh generalized this ad-hoc
tinting into a deliberate window-chrome design.

## Goals

- Land the community refresh without losing fork identity: keep what improves the UI,
  revert what regresses deliberate fork behavior, and credit the contributor.
- Terminal tab bar: clear visual differentiation of active/hovered/inactive tabs
  (issue #311), floating glass look, stable layout (no hover-induced shifts).
- Sidebar: consistent background (#315), a fixed view-mode switcher top bar with
  consistent Shelf/Canvas toggling (#317).
- A first-class **window chrome tint**: one setting that tints the nav band and toolbar
  band across Normal / Shelf / Canvas view modes, driven by the active repo's color or
  a custom color.
- Assorted polish: zero-repository empty state, settings window minimum width,
  fullscreen-safe toolbar rendering (#343).

**Non-goals**

- No change to per-repo identity semantics ([025](../025-repo-identity-appearance/000-plan.md))
  beyond adding a free custom color; the tint *consumes* the existing repo color.

## Design / Approach

The distinctive process decision: instead of iterating inside the contributor's PR, the
fork took #331's commit (`13fc410d`) verbatim as the base of a review branch
`feat/ui-enhancements`, then layered 21 review/revert/extension commits on top and merged
the whole branch as #332. GitHub marked #331 merged the moment its commit landed on
`main`, so contributor attribution is preserved in history while every #331 change got
line-level review.

On that branch, the design settled as:

- **Tab bar**: keep #331's floating-glass direction but revert its structural reshape
  (`d027ea7a`); adopt instead the adaptive brightness ladder from the fork's own closed
  PR #327 — in dark mode `controlBackgroundColor` is *darker* than
  `windowBackgroundColor`, so selection is conveyed by a `labelColor`-tint ladder
  (bar < inactive < hovered < active), while light mode keeps the native white-tab look.
  Centered titles, full-width tabs, hover close circle, close button on the leading
  edge, a tab/terminal gap, and the bar tint extended across the bottom gap.
- **Window chrome tint** (`51af064e`): a `WindowTintMode` setting
  (`none` / `repositoryColor` / `custom`) with unified color logic in a
  `WindowChromeTint` domain enum. The tint is "driven from the detail side": the nav
  band and toolbar band are overlays on full-bleed detail content, painted as one
  continuous "L". Shelf chrome tints with the open book's repo color; Canvas tints the
  nav only, leaving the toolbar untinted so floating cards don't sit on a colored band
  (`5cfad79c`).
- **Custom repository color** (`8dc41bc3`): `.custom(TintColor)` added to
  `RepositoryColorChoice` so the tint isn't limited to the fixed preset palette
  (domain type owned by [025](../025-repo-identity-appearance/000-plan.md)).
- **Sidebar**: view-mode switcher reworked into a fixed top bar (`85067862`); restore
  the Expand/Collapse All header controls #331 had dropped (`b47be417`); brighten the
  nav picker track to match the tab bar; keep the repo color dot solid on focus loss.
- **Fork identity kept**: restore the bagua-glyph working indicator that #331 had
  replaced (`b6e8d3f2`, tests fixed in `7e558ef0`).
- **Fullscreen fallback** (#343, one day later): in macOS fullscreen the AppKit toolbar
  stops sampling the tinted content behind it, so an explicit toolbar background is
  enabled only for fullscreen enter/steady/exit, resolved from Prowl's own Light/Dark
  appearance (not the system appearance captured at launch), and held stable across
  SwiftUI toolbar host detach/reattach cycles to avoid flicker.

## Alternatives & decisions

- **Review branch over in-PR iteration** (#331→#332): the fork rebased review commits
  on top of the contributor's commit rather than requesting changes, keeping merge
  attribution while enabling aggressive reverts. Both PRs merged together on
  2026-05-24.
- **Adopt #327's brightness ladder, revert #331's tab reshape** (`d027ea7a`): #327 had
  been closed unmerged, but its dark-mode analysis (selection sinking into the bar) was
  the accepted fix for issue #311.
- **Keep the bagua indicator** (`b6e8d3f2`): #331's replacement loading indicator was
  rejected; the glyph is a deliberate fork trait.
- **Canvas toolbar stays untinted** (`5cfad79c`): a colored band behind floating cards
  hurt readability, so Canvas only tints the nav.
- **Fullscreen fallback is scoped, not a rewrite** (#343): outside fullscreen the
  original hidden-toolbar-background rendering path is preserved untouched; the
  explicit background is a best-effort fallback only while fullscreen is involved.

## Amendments

- Updated 2026-06-17: toolbar icon hover fix by second community contributor
  Alex-ai-future (#467) — see [002-toolbar-icon-fixes.md](002-toolbar-icon-fixes.md)
