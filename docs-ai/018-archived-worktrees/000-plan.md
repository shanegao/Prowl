# 018 — Archived Worktrees: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-09 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #187, #191 (amendment: #512) |
| **Sources** | Fork issues #181 and #174, PR #187/#191/#512 descriptions, change-list 2026-04-08 review batch (see [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md)) |
| **Related** | [019-worktree-creation-and-lifecycle](../019-worktree-creation-and-lifecycle/000-plan.md), [012-keybinding-system](../012-keybinding-system/000-plan.md), [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md), `docs/components/repositories-and-worktrees.md` |

## Background

Worktree archiving (hide a worktree from the sidebar without deleting it, with an
Archived Worktrees panel reachable from Menu Bar > Worktrees) is inherited from upstream
Supacode. By early April 2026 two pains had accumulated in daily use:

1. **Discoverability** (issue #181): the confirmation alert shown when archiving never
   said where archived worktrees go. Users archived a worktree and then could not find
   it again; the only entry points were a menu item and a sidebar footer button.
2. **Unbounded growth** (issue #174): archived worktrees were tracked as a flat
   `[Worktree.ID]` list with no timestamps and no cleanup. Power users ended up with a
   long archived list requiring manual deletion.

The 2026-04-08 upstream review batch had just surfaced that upstream shipped its own
auto-delete for archived worktrees (upstream #214, `666d440d`). Fork issue #174 was
filed the same day; the fork implemented its own version on top of its already-diverged
archived-worktree persistence rather than porting the upstream commit (which is not in
the fork's ancestry).

## Goals

- Tell the user, at the moment of archiving, where archived worktrees can be found —
  including the actual keyboard shortcut, not a hardcoded one.
- Add a "View Archived Worktrees" command palette entry.
- Auto-delete archived worktrees after a configurable retention period (1/3/7/14/30
  days, or never), which requires recording *when* each worktree was archived.
- Migrate the legacy flat ID list to the timestamped model without losing data.

### Non-goals

- Changing archive semantics themselves (archive scripts, archive-on-merge behavior,
  what can be archived) — that evolution belongs to
  [019-worktree-creation-and-lifecycle](../019-worktree-creation-and-lifecycle/000-plan.md).

## Design / Approach

**Discoverability (#187).** Extend the single and bulk archive confirmation alerts with
"Find … later in Menu Bar > Worktrees > Archived Worktrees (⌃⌘A)", where the shortcut
string is resolved at runtime from `AppShortcuts.archivedWorktrees.display` so the copy
tracks rebinding (012-keybinding-system). Add a `viewArchivedWorktrees` command palette
item (archivebox icon) that dispatches the existing
`RepositoriesFeature.Action.selectArchivedWorktrees` and maps to
`AppShortcuts.CommandID.archivedWorktrees` so the palette row shows the shortcut hint.

**Auto-delete with retention (#191).** Replace the flat `[Worktree.ID]` archived list
with a domain struct `ArchivedWorktree { id, archivedAt }`. Add an `AutoDeletePeriod`
enum whose raw value is the number of days (1/3/7/14/30, plus a DEBUG-only
`immediately = 0` for testing); `nil` means never. The setting lives in
`GlobalSettings.archivedAutoDeletePeriod` (settings file) and is wired
`GlobalSettings` → `SettingsFeature` → `RepositoriesFeature`. The sweep
(`autoDeleteExpiredArchivedWorktrees`) runs on repository load and whenever the setting
changes; expired entries are routed through the existing confirmed-delete lifecycle path
(`worktreeLifecycle(.deleteWorktreeConfirmed)`), skipping main worktrees and worktrees
already being deleted, with branch deletion following the global
`deleteBranchOnDeleteWorktree` flag and only for Prowl-created worktrees. Persistence
moves to a new `archivedWorktrees` app-storage key with a one-time migration from the
legacy `archivedWorktreeIDs` key (migrated entries are stamped with the migration date).

## Alternatives & decisions

- **Fork-native implementation over porting upstream's.** Upstream's auto-delete
  (`666d440d`, upstream #214) predates #191 by a week and was reviewed in the
  2026-04-08 batch, but the fork's archived persistence had already diverged; #191 was
  implemented on a fork branch and the upstream commit was never merged.
- **`[ArchivedWorktree]` array instead of the `[Worktree.ID: Date]` dictionary**
  sketched in issue #174 — an `Identifiable` struct list codecs cleanly through
  `@Shared(.appStorage)` and reads better in tests.
- **Reuse the confirmed-delete path** for expired entries instead of a separate bulk
  deletion routine, so auto-delete inherits all lifecycle safeguards for free.
- **DEBUG-only "Immediately" period** so retention can be exercised without waiting a
  day.
- Issue #174's design notes sketched a confirmation alert when shortening the retention
  window would immediately delete existing archived worktrees; this was **not
  implemented** — changing the setting triggers the sweep directly (see 001-action.md
  deviations).

## Amendments

- Updated 2026-06-26: the sidebar archived-worktrees button became a toggle with an
  explicit exit affordance (#512) — see
  [002-archived-button-toggle.md](002-archived-button-toggle.md)
