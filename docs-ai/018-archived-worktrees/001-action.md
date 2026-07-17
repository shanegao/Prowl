# 018 — Archived Worktrees: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-09 | Discoverability: archive alerts name the menu location + live shortcut; "View Archived Worktrees" palette command | PR #187 (closes #181) |
| 2026-04-09 | Auto-delete with retention: `ArchivedWorktree` model, `AutoDeletePeriod` setting + Worktree settings picker, sweep on load/setting change, legacy persistence migration | PR #191 (closes #174) |
| 2026-06-26 | Archived-worktrees button becomes a toggle with exit affordance (community PR, Alex-ai-future) | PR #512 — see [002-archived-button-toggle.md](002-archived-button-toggle.md) |

## Outcome & current state (as of 2026-07-12)

- `supacode/Domain/ArchivedWorktree.swift` — `ArchivedWorktree { id: Worktree.ID,
  archivedAt: Date }`, `Codable`/`Identifiable`.
- `supacode/Features/Settings/Models/AutoDeletePeriod.swift` — raw-value-in-days enum
  (`oneDay = 1` … `thirtyDays = 30`), `Comparable`, with DEBUG-only
  `immediately = 0` ("Immediately (debug)").
- `supacode/Features/Settings/Models/GlobalSettings.swift` — optional
  `archivedAutoDeletePeriod`, encoded as the raw day count; `nil` = never (default).
  Picker ("Never" + all periods) in
  `supacode/Features/Settings/Views/WorktreeSettingsView.swift`, under the Cleanup
  grouping.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+CoreReducer.swift` —
  `setArchivedAutoDeletePeriod` stores the period and immediately sends
  `autoDeleteExpiredArchivedWorktrees`; the same action is also appended to the
  repositories-loaded effects when a period is set. The sweep computes
  `cutoff = now - days` and dispatches
  `worktreeLifecycle(.deleteWorktreeConfirmed(...))` per expired entry, skipping main
  worktrees and IDs in `deletingWorktreeIDs`; `deleteBranch` is true only when
  `deleteBranchOnDeleteWorktree` is on and the worktree is in
  `prowlCreatedWorktreeIDs`.
- `supacode/Clients/Repositories/RepositoryPersistenceClient.swift` — loads/saves the
  `archivedWorktrees` app-storage key; on first load with an empty new key it migrates
  legacy `archivedWorktreeIDs` (stamping `archivedAt` with the migration date) and
  clears the legacy key.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeLifecycle.swift` —
  `archiveWorktreeAlertMessage(for:)` / `archiveWorktreesAlertMessage()` build the
  "Find … later in Menu Bar > Worktrees > Archived Worktrees (…)" copy from
  `AppShortcuts.archivedWorktrees.display`.
- `supacode/Features/CommandPalette/CommandPaletteItem.swift` — `.viewArchivedWorktrees`
  maps to `AppShortcuts.CommandID.archivedWorktrees` (action id `archived_worktrees`,
  default ⌘⌃A in `supacode/App/AppShortcuts.swift`).
- Archived view UI: `supacode/Features/Repositories/Views/ArchivedWorktreesDetailView.swift`
  (grouped by repo, Unarchive + Delete Selected) and `ArchivedWorktreeRowView.swift`.
- Toggle behavior from #512: `preArchivedWorktreeID` in `RepositoriesFeature.State`,
  toggle logic in `selectArchivedWorktrees`, icon/label switching in
  `supacode/Features/Repositories/Views/SidebarFooterView.swift` and
  `supacode/Commands/WorktreeCommands.swift` — details in
  [002-archived-button-toggle.md](002-archived-button-toggle.md).

User-facing behavior is documented in
`docs/components/repositories-and-worktrees.md` ("Archiving a worktree"),
`docs/reference/keyboard-shortcuts.md`, and `docs/reference/settings-fields.md`.

## Deviations from plan

- Issue #174 sketched a `[Worktree.ID: Date]` dictionary; the implementation used a
  `[ArchivedWorktree]` struct array (decided during #191, reflected in its PR body).
- Issue #174's confirmation alert for retention-window shortening (warn when a shorter
  period would immediately delete existing archived worktrees) was not implemented;
  changing the setting runs the sweep at once. The DEBUG-only "Immediately" option
  makes this observable in debug builds.

## Open questions

- Upstream later added "re-surface archived worktrees in the sidebar while their delete
  script runs" (upstream #346, `b69ce38e`), reviewed 2026-06-09 and left in the
  "not yet ported — re-evaluate" bucket; the fork still lacks that affordance during
  slow archive-delete scripts.
- Shortening the retention period silently deletes newly-expired archived worktrees
  without confirmation (see deviations). Deliberate simplification as far as the
  sources show, but worth revisiting if auto-delete complaints appear.
