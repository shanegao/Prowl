# 031 — Command Palette Architecture: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-20 | Precursor: hide contextual actions ("Change Tab Icon…", non-PR "Open Repository on Code Host") from the empty-query list; dedicated `openRepositoryOnCodeHost` Kind | PR #218 |
| 2026-05-14 | Precursor: AppKit-backed query field (`NSViewRepresentable`) replaces `@FocusState`; focus reasserted after open (macOS 26.5 Cmd+P path); terminal focus restored on dismiss, Canvas-aware via `canvasFocusedWorktreeID()` | PR #287 |
| 2026-05-16 | PR1: `category` + `keywords` + `defaultSuggestion` replace `isGlobal`/`isRootAction`; pure refactor, empty-query behavior byte-identical | PR #291 |
| 2026-05-16 | PR2: Recent/Suggested empty-query view (8-row cap, headers only on empty query), keyword aliases in fuzzy scoring, 8 app-level commands flipped to `defaultSuggestion: true`; new `CommandPaletteSuggestions` type + `suggestions(items:recencyByID:now:)` | PR #292 |
| 2026-05-16 | PR3: `appShortcut` + `ghosttyCommand` factories; `contextual(...)` factory deferred | PR #293 |
| 2026-05-17 | PR4: five view toggles (Sidebar ⌘⌃S, Active Agents ⌘⌥P, Canvas ⌘⌥↩, Shelf ⌘⇧↩, Show Diff ⌘⇧Y gated on worktree selection); `leftSidebarVisibility` lifted from `ContentView` `@State` into `AppFeature.State` | PR #294 |
| 2026-05-18 | PR5: navigation commands (Reveal in Finder, Copy Path, Reveal in Sidebar); focus-restore made default-on for all palette delegates via a deny list (`commandPaletteDelegateChangesActiveSelection`) instead of per-handler opt-in | PR #296 |
| 2026-05-18 | PR6+6.5: Run/Stop Script (state-dependent swap), Pin/Unpin, Delete Worktree, Rename Branch (via `pendingRenameBranchRequest` channel in `RepositoriesFeature`), per-repo custom commands as search-only items | PR #299 |
| 2026-05-18 | PR7 (scoped down after audit): Repo Settings command opening the Settings window at `SettingsSection.repository(repoID)`; rest of the planned terminal/tab/pane/shelf batch dropped | PR #300 |
| 2026-05-18 | Settings window: Cmd+W close shortcut + reveal selected repo row in sidebar | PR #301 |
| 2026-05-18 | Cleanup: Repo Settings handler funneled through the repositories pipeline; dead `copyPath` ⌘⇧C AppShortcut deleted (closed fork issue #295); dead `.removeWorktree`/`.archiveWorktree` Kinds deleted, delegate renamed `deleteWorktree` (−117 lines) | PR #302 |
| 2026-05-18 | Revert #301's `ScrollViewReader` auto-scroll in Settings sidebar (didn't feel right); Cmd+W close kept | PR #303 |
| 2026-06-05 | Canvas card focus routing — see [002-post-buildout-fixes.md](002-post-buildout-fixes.md) | PR #396 |
| 2026-06-08 | Color-scheme flicker fix — see [002-post-buildout-fixes.md](002-post-buildout-fixes.md) | PR #421 |

## Outcome & current state (as of 2026-07-12)

- `supacode/Features/CommandPalette/CommandPaletteItem.swift` — `CommandPaletteItem`
  with `category` / `keywords` / `defaultSuggestion`, the `Category` enum (six cases
  + DEBUG `debug`), and `CommandPaletteSuggestions` (`maxItems = 8`,
  `recent` + `suggested`, `allItems` flattener). The `Kind` enum has since grown
  beyond this entry's scope: `newWorkspace`
  ([042-project-workspaces](../042-project-workspaces/000-plan.md)), Canvas commands
  (`expandCanvasCard`, `arrangeCanvasCards`, `organizeCanvasCards`,
  `tileCanvasCards`, `selectAllCanvasCards` —
  [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md)
  and later canvas work), `runCustomCommand`, `debugLightDockNotificationDot`.
- `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift` — the
  builder `commandPaletteItems(from:customCommands:runScriptStatusByWorktreeID:actionTargetWorktreeID:ghosttyCommands:)`,
  `suggestions(items:recencyByID:now:)`, `filterItems` (empty query delegates to
  `suggestions(...).allItems`), `recencyRetentionIDs` pruning.
- `supacode/Features/CommandPalette/Reducer/CommandPaletteSupport.swift` — the
  `appShortcut` and `ghosttyCommand` factories, stable `CommandPaletteItemID`
  helpers (`openRepositorySettings(_:)`, `customCommand(_:)`),
  `commandPaletteRecencyScore` (7-day half-life, age capped at 30 days), and
  `delegateAction(for:)` kind→delegate mapping. The planned `contextual(...)`
  factory was never added (deferred in #293, no pain point since).
- `supacode/Features/CommandPalette/Reducer/CommandPaletteFuzzyScorer.swift` —
  `scoreItemForPiece(label:description:keywords:query:)` scores title and each
  keyword, taking the max; `doScoreFuzzy` unchanged underneath.
- `supacode/Features/CommandPalette/Views/CommandPaletteOverlayView.swift` — the
  AppKit `CommandPaletteQueryTextField` (`NSViewRepresentable`) from #287,
  sectioned rendering (`renderSectioned` with Recent/Suggested headers on empty
  query only).
- `supacode/Features/App/Reducer/AppFeature+CommandPalette.swift` — delegate
  routing. The helpers named in PR bodies (`navigationDelegateAction`,
  `viewDelegateAction` on the AppFeature side) were later reorganized into a
  `reduceCommandPalette*Delegate` family (`Navigation`, `Repository`, `Canvas`,
  `WorktreeFile`, `WorktreeAction`, `PullRequest`, `Debug`).
- `supacode/Features/App/Reducer/AppFeature+Support.swift` —
  `commandPaletteDelegateChangesActiveSelection` deny list currently:
  `selectWorktree`, `jumpToLatestUnread`, `viewArchivedWorktrees`, `newWorktree`,
  `toggleCanvas`, `renameBranch`. Everything else gets terminal focus restored
  after the delegate runs.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature.swift` —
  `pendingRenameBranchRequest` channel consumed by
  `supacode/Features/Repositories/Views/WorktreeDetailView.swift`, so the rename
  popover's `isPresented` stays view-local.
- `AppShortcuts.copyPath` no longer exists in `supacode/App/AppShortcuts.swift`
  (deleted in #302); the palette's Copy Path command (`Kind.copyPath`) remains,
  without a hotkey hint.
- User-facing behavior is documented in `docs/components/command-palette.md`.

## Deviations from plan

- The planned PR7 (terminal/tab/pane/find) and PR8 (shelf navigation) batches were
  almost entirely dropped after the #300 audit: Ghostty's auto-bridged
  `command-palette-entry` items already covered font size, close tab/surface, and
  new tab; tab/pane switching and find were judged unnecessary. Only Repo Settings
  shipped.
- Custom commands (per-repo, user-defined) were surfaced in #299 although the plan
  had not listed them; they are search-only (not default-suggested) with
  UUID-stable IDs so recency survives across sessions.
- The `contextual(...)` factory from the plan's PR3 was deferred and never added.
- Rename Branch required an unplanned TCA channel (`pendingRenameBranchRequest`,
  mirroring `pendingSidebarReveal`) because the popover's visibility is view-local
  `@State`; it also joined the focus-restore deny list so the popover's `TextField`
  keeps focus.
- #296 turned focus restore from per-handler opt-in (five sites patched in #287)
  into default-on with a deny list, after PR4's new handlers silently dropped the
  behavior — a structural fix the plan had not anticipated.

## Open questions

- PR #292 describes Recent as "anything used in the past month", but
  `commandPaletteRecencyScore` caps age at 30 days and returns a positive floor
  (~0.05) rather than 0, so an activated item stays in Recent indefinitely until
  its ID drops out of `recencyRetentionIDs`. Behavior is stable but the
  month-window description does not match the implementation.
