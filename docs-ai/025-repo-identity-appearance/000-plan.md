# 025 — Repo Identity & Appearance: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-27 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #240, #243 (anchor); #247, #276 (follow-ups) |
| **Sources** | PR descriptions #240/#243/#247/#276; upstream review ledger decisions 2026-05-08 and 2026-06-09 (→ `docs-ai/017-upstream-sync-process/upstream-ledger.md`) |
| **Related** | [022-tab-title-and-icon](../022-tab-title-and-icon/000-plan.md) (per-*tab* identity), [023-shelf-mode](../023-shelf-mode/000-plan.md) (spine tint preference), [026-sidebar-container-refactor](../026-sidebar-container-refactor/000-plan.md), [033-ui-refresh-2026-05](../033-ui-refresh-2026-05/000-plan.md) (custom color, chrome tint), [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md), `docs/components/repositories-and-worktrees.md` |

## Background

With many repositories open at once, the sidebar, the shelf spine, and the canvas card
title bar all rendered every repo the same way: a plain folder-derived name. Repos were
hard to tell apart at a glance, and repos sharing a generic folder name (several `src`
checkouts) were literally indistinguishable. The idea: a one-time, per-repo visual
identity — icon, color, and optionally a display title — that pays off across every
surface where the repo shows up.

## Goals

- Per-repo **icon** (curated SF Symbol presets + free-form symbol name, or a
  user-provided PNG/SVG) and **color** (fixed palette of system colors: Finder's 7 plus
  mint/cyan/pink), independently optional; repos without an entry render exactly as
  before (#240).
- Surface the identity in all three render sites: sidebar row (icon before name,
  Finder-style trailing color dot), shelf spine (proximity tint switches from
  `accentColor` to the repo color, plus a header icon), canvas card title bar (icon +
  always-on color strip) (#240).
- Small papercuts: open the icon image picker directly at the repo's working directory
  (#243); let the user override the displayed repo title (#247); animate the sidebar
  color dot on hover instead of snapping (#276).

**Non-goals**

- Per-*worktree* title or color. Identity is deliberately repo-level; per-worktree
  visual distinction stays at the tab layer (custom tab titles/icons,
  [022](../022-tab-title-and-icon/000-plan.md)). This scoping later became the anchor
  for a standing divergence from upstream — see
  [002-upstream-divergence.md](002-upstream-divergence.md).

## Design / Approach

As designed in #240:

- **Data model**: `RepositoryAppearance` (optional `RepositoryIconSource` + optional
  `RepositoryColorChoice`), held in a single global
  `@Shared([Repository.ID: RepositoryAppearance])` dictionary persisted at
  `~/.prowl/repository-appearances.json`. Sidebar, shelf, and canvas read it directly
  via `@Shared` — no per-call client layer. One global file rather than per-repo
  settings so the sidebar (which renders every row) gets every appearance in a single
  read.
- **Icon storage**: a single storage string with marker prefixes (`@asset:` for bundled
  assets, `@file:` for user images, bare string = SF Symbol), mirroring the existing
  `TabIconSource` convention. User-imported PNG/SVG files live in the per-repo settings
  directory (`~/.prowl/repo/<name>/icons/<uuid>.<ext>`), persisted as bare filenames so
  the JSON stays portable and the files are cleaned up together with the rest of the
  per-repo settings directory on repo removal.
- **Rendering**: `RepositoryIconImage` is the single rendering site so tinting rules
  (SF Symbols/SVGs tint with the repo color; PNGs keep their own colors) and fallback
  behavior stay consistent across the three surfaces.
- **Mutation**: everything goes through explicit `RepositorySettingsFeature` reducer
  actions (`setAppearanceColor`, `setAppearanceIcon`, `importUserImage`,
  `resetAppearance`, ...) — no direct `store.appearance.* = ...` writes in views,
  keeping the custom SwiftLint rule clean.
- **Picker at repo dir** (#243): switch from SwiftUI `.fileImporter()` (no
  initial-directory API) to `NSOpenPanel` with `directoryURL = store.rootURL`, using
  `panel.begin` (non-blocking) rather than `runModal`.
- **Custom title** (#247): an optional `customTitle` field on the per-repo
  `RepositorySettings` file, surfaced as a "Display Name" section in Repo Settings.
  Whitespace-only input normalizes to `nil` so the folder-derived `Repository.name`
  remains the fallback.
- **Hover polish** (#276): wrap the sidebar header `isHovering` toggle in
  `withAnimation(.easeOut(duration: 0.15))` so the color dot slides when the row's
  hover buttons appear; skip the animation under `accessibilityReduceMotion`.

## Alternatives & decisions

- **One global appearance dictionary, not nested in `Repository` or per-repo settings**
  (#240): all three surfaces need O(1) cross-repo lookups during render; per-repo files
  would force one file load per sidebar row at startup.
- **Canvas tint above the `.bar` material, not below** (#240 mid-flight decision): the
  bar's 0.9 opacity would dilute a base-layer tint to invisibility. Existing
  notification/selected-unfocused tints stay in their original position so repos
  without an appearance look unchanged.
- **Fixed system colors only** (#240): named presets stay semantic system colors so
  they adapt to light/dark mode. Later relaxed with an explicit `.custom(TintColor)`
  opt-out (#332, [033](../033-ui-refresh-2026-05/000-plan.md)); preset persistence kept
  the legacy bare-string encoding.
- **`customTitle` lives in `RepositorySettings`, not in the appearance dictionary**
  (#247): the title is per-repo configuration alongside scripts and base-ref defaults,
  while icon/color stay in the render-hot global dict.
- **Repo-level model kept against upstream's per-repo and later per-worktree
  title/color** — the standing divergence decision, recorded in
  [002-upstream-divergence.md](002-upstream-divergence.md).

## Amendments

- Updated 2026-06-09: upstream per-repo (upstream #276) and per-worktree (upstream
  #308/#367) title/color reviewed and skipped; fork keeps its richer repo-level
  appearance model — see [002-upstream-divergence.md](002-upstream-divergence.md)
