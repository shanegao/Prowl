# 025 — Repo Identity & Appearance: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-27 | Per-repo icon + color identity across sidebar / shelf spine / canvas card: `RepositoryAppearance` model, global `@Shared` dict persisted to `~/.prowl/repository-appearances.json`, `RepositoryIconImage` render site, picker UI in Repo Settings, 30+ tests. In-PR fixes: seed appearance synchronously into `RepositorySettingsFeature.State` (fixes a race where clicking a color before the async load wiped the saved icon) and curate the SF Symbol preset list | PR #240 |
| 2026-04-27 | "Choose Image..." opens at the repo's working directory via `NSOpenPanel` with `directoryURL = store.rootURL` (replacing `.fileImporter()`) | PR #243 |
| 2026-04-29 | Optional `customTitle` on `RepositorySettings` ("Display Name" in Repo Settings); whitespace-only normalizes to `nil`; surfaced across sidebar, shelf, canvas, toolbar/window title, and the Settings repo list. Mid-PR, the display mechanism switched from a per-row leaf-view `@Shared` subscription to a reducer-held title cache | PR #247 |
| 2026-05-11 | Sidebar color dot glides on hover (`withAnimation(.easeOut(duration: 0.15))`) instead of snapping when the hover buttons appear; animation skipped under Reduce Motion | PR #276 |
| 2026-05-08 / 2026-06-09 | Upstream's per-repo, then per-worktree title/color reviewed and skipped — divergence decision | [002-upstream-divergence.md](002-upstream-divergence.md) |

## Outcome & current state (as of 2026-07-12)

Domain and persistence:

- `supacode/Domain/RepositoryAppearance.swift` — optional `icon` + `color`, `.empty`
  baseline.
- `supacode/Domain/RepositoryIconSource.swift` — `.sfSymbol` / `.bundledAsset`
  (`@asset:`) / `.userImage` (`@file:`), storage-string convention shared with
  `TabIconSource`.
- `supacode/Domain/RepositoryColorChoice.swift` — 10 named presets **plus a
  `.custom(TintColor)` case added later** (#332,
  [033](../033-ui-refresh-2026-05/000-plan.md)); presets still encode as legacy bare
  strings so pre-existing user JSON decodes unchanged.
- `supacode/Domain/RepositoryIconPresets.swift` — curated SF Symbol presets (currently
  40 entries; the #240 PR body's "32" predates the in-PR curation commit).
- `supacode/Clients/Repositories/RepositoryAppearancesKey.swift` — `SharedKey` behind
  `@Shared(.repositoryAppearances)`, file at `SupacodePaths.repositoryAppearancesURL`
  (`~/.prowl/repository-appearances.json`).
- `supacode/Clients/Repositories/RepositoryIconAssetStore.swift` — imports/removes user
  images under `SupacodePaths.repositoryIconsDirectory(for:)`
  (`~/.prowl/repo/<name>/icons/`), bare filenames in JSON.

Feature and render sites:

- `supacode/Features/RepositorySettings/Reducer/RepositorySettingsFeature.swift` —
  `setAppearanceColor` / `setAppearanceIcon` / `importUserImage` / `resetAppearance`
  actions and `customTitle` normalization.
- `supacode/Features/RepositorySettings/Views/RepositoryAppearancePickerView.swift` —
  picker UI; the #243 `NSOpenPanel` + `directoryURL` behavior is still in place.
- `supacode/Features/Repositories/Views/RepositoryIconImage.swift` — the single icon
  render site; used by `RepoHeaderRow.swift`, `ShelfSpineView.swift`,
  `CanvasCardView.swift`, and the appearance picker.
- `supacode/Features/Repositories/Views/RepositorySectionView.swift` — sidebar header:
  appearance lookup, trailing color dot, and the #276 hover animation with the
  `accessibilityReduceMotion` opt-out.
- `supacode/Features/Shelf/Views/ShelfSpineView.swift` and
  `supacode/Features/Canvas/Views/CanvasView+Focus.swift` /
  `CanvasCardView.swift` — shelf and canvas render sites.

Custom title plumbing (current shape):

- `supacode/Features/Settings/Models/RepositorySettings.swift` — `customTitle: String?`
  (`decodeIfPresent`, schema-compatible).
- `RepositoriesFeature.State.repositoryCustomTitles` (`supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`)
  is the display cache; `RepositoriesFeature+CoreReducer.swift` handles
  `refreshCustomTitle` / `customTitlesLoaded` / `customTitleUpdated`, and `AppFeature`
  refreshes the cache on every repo-settings change. Read sites include the sidebar
  (`RepositorySectionView` → `RepoHeaderRow`), `supacode/App/WindowTitle.swift`, the
  Settings repo list, and workspace naming
  (`RepositoriesFeature+WorkspaceCreation.swift`).

Since the anchor, the repo color grew extra consumers outside this entry's scope:
window-chrome tint (`windowTintMode = repositoryColor`,
[033](../033-ui-refresh-2026-05/000-plan.md)) and the shelf spine tint preference
(`shelfSpineTintFollowsRepositoryColor`, #356,
[023](../023-shelf-mode/000-plan.md)). Workspaces
([042](../042-project-workspaces/000-plan.md)) default to a `folder` icon when no
appearance is set. User-facing behavior is documented in
`docs/components/repositories-and-worktrees.md` ("Repository appearance (icon & color)").

## Deviations from plan

- **#247's leaf-view design was superseded inside the same PR.** The PR body describes
  a `RepoHeaderTitleTextResolved` leaf view subscribing to
  `@Shared(.repositorySettings(rootURL))` per row; the PR's final commits replaced this
  with the reducer-held `repositoryCustomTitles` cache, and the leaf view no longer
  exists. Displayed titles now flow through `RepositoriesFeature` state.
- **Color palette is no longer "10 fixed colors only"** — `.custom(TintColor)` was
  added in #332 (owned by [033](../033-ui-refresh-2026-05/000-plan.md)); noted here
  because it changed this entry's domain type.
- **Preset count**: 40 curated presets in the tree vs "32" in the #240 body (curation
  happened in an in-PR fix commit, `d8a85b60`).

## Open questions

- PR #240 references a local-only decision record (`.agents/repo-icon-color-decisions.md`)
  that was never committed; apart from the canvas tint-layer decision summarized in the
  body, its remaining mid-flight decisions are unrecoverable.
