# 010 — Plain Folder Support: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-24 | Full implementation in one PR: `Repository.Kind` + capabilities, `PersistedRepositoryEntry` migration, plain-folder add/reload/upgrade/downgrade, repository-level selection, folder toolbar title, capability-gated settings/palette, Canvas round-trip for plain folders; ~2.7k lines incl. tests | PR #48 (`0db1a91c`) |
| 2026-03-27 | Repo header tab count fixed for plain folders: count terminal state keyed by `repository.id`, extracted `RepositorySectionView.openTabCount` + tests | PR #80 |
| 2026-04-01 | Terminal layout restore fixed for plain folders (part of the layout-persistence work) | PR #120 → [014-terminal-layout-persistence](../014-terminal-layout-persistence/000-plan.md) |
| 2026-05-25 | Active Agents selection fixed for plain folders | PR #344 → [029-active-agents-panel](../029-active-agents-panel/000-plan.md) |
| 2026-07-08 | Contributor PR: watch `.plain` roots for `.git` creation so `git init` updates the sidebar immediately (closed unmerged; commit retained in #553) | PR #548 |
| 2026-07-11 | Upgrade watchers merged + hardened (failure isolation, injectable monitors, edge-triggered detection) | PR #553 — see [002-plain-upgrade-watchers.md](002-plain-upgrade-watchers.md) |

## Outcome & current state (as of 2026-07-12)

- `supacode/Domain/Repository.swift` — `Repository.Kind` (`.git`/`.plain`) and nested
  `Repository.Capabilities` with `.git`/`.plain` presets, derived from `kind` via the
  `capabilities` computed property. Since 042-project-workspaces, `Repository` also
  carries `workspace: ProjectWorkspace?` and the initializer forces `kind = .plain`
  whenever a workspace payload is present.
- `supacode/Domain/PersistedRepositoryEntry.swift` — `{ path, kind }` as planned.
- `supacode/Clients/Repositories/RepositoryPersistenceClient.swift` — decodes legacy
  `[String]` roots as `.git` entries; `RepositorySnapshotCachePayload`
  (`currentVersion = 2`) persists `kind` per `SnapshotRepository` and restores
  zero-worktree repositories. Storage keys live in
  `supacode/Features/Settings/BusinessLogic/RepositoryPersistenceKeys.swift`.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+RepositoryLoading.swift` —
  `upgradedRepositoryEntriesIfNeeded` normalizes paths, detects workspaces (forced
  `.plain`), upgrades `.plain` → `.git` when the path is its own repo root, and
  downgrades `.git` → `.plain` only on a definitive "not a git repository" error while
  the path still exists.
- Selection: `supacode/Features/Repositories/Views/SidebarSelection.swift` has a
  first-class `.repository(Repository.ID)` case next to `.worktree`;
  `RepositoriesFeature.Action.selectRepository` drives it
  (`supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`). Shelf and
  Default View dispatch `.selectRepository` for plain folders and `.selectWorktree` for
  worktrees (`RepositoriesFeature+Selection.swift`, `AppFeature+Support.swift`).
- Terminal: plain folders reuse the worktree-keyed terminal infrastructure —
  `WorktreeTerminalManager` state is keyed by `repository.id` (both `Worktree.ID` and
  `Repository.ID` are path-derived `String`s). `RepositorySectionView.openTabCount`
  (used by `RepoHeaderRow`) counts worktree tabs for git repos and the
  repository-keyed state for plain folders (#80).
- Toolbar: `supacode/Features/Repositories/Views/DetailToolbarTitle.swift` renders
  `.folder(name:)` with the `folder` SF Symbol for `.plain` repositories (a
  `.workspace` case was added later by 042).
- Settings: `supacode/Features/RepositorySettings/Reducer/RepositorySettingsFeature.swift`
  keeps `Repository.Capabilities` in state, hides worktree/diff/PR sections by
  capability, and skips git loading unless `supportsRepositoryGitSettings`.
- Watchers: `plainRepositoryRootsForInfoWatcher()` in
  `RepositoriesFeature+StateQueries.swift` feeds `.plain` non-workspace roots to
  `WorktreeInfoWatcherManager`, which upgrades entries live on `git init` (see
  [002-plain-upgrade-watchers.md](002-plain-upgrade-watchers.md)).
- CLI: `supacode/CLIService/Shared/ListCommandPayload.swift` exposes `kind`
  (`git`/`plain`) per target in `prowl list`.

User-facing behavior is documented in `docs/concepts.md` and
`docs/components/repositories-and-worktrees.md`.

## Deviations from plan

- The capabilities type is nested (`Repository.Capabilities`), not a standalone
  `RepositoryCapabilities`, and gained a `supportsCodeHost` flag beyond the planned set.
- The plan suggested repository rows should "likely" become selectable for git
  repositories too; #48 deliberately kept the git repo header as an expand/collapse
  control (its manual acceptance tests assert this), so only plain folders select at the
  repository level.
- "Avoid fake worktrees" holds at the domain level (no synthetic `Worktree` values), but
  the terminal layer reuses the `Worktree.ID` key space with the repository ID rather
  than introducing a separate keying concept — a pragmatic reuse the plan did not spell
  out.
- Immediate reaction to `git init` was not part of the original plan (upgrade only ran on
  load/reload); it arrived 3.5 months later via #548/#553.

## Open questions

- None.
