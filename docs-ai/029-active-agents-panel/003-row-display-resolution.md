# 029 — Amendment: Row Display Resolution (2026-05-28 / 2026-06-04)

## Context

Each agent row labels which repository/branch the agent belongs to. Originally the
label came from the worktree owning the agent's terminal **tab**, so an agent launched
after `cd`-ing into a different repo inside a tab showed the wrong repo/branch.
Separately, users who identify panes by tab title (rather than branch) had no way to
see titles in the panel.

## Change

**Repo/branch from the agent's cwd (PR #363, 2026-05-28).** `ActiveAgentEntry` gained
`workingDirectory: URL?`, captured from the surface's inherited config when the entry
is emitted (`WorktreeTerminalState.activeAgentEntry`). Display resolution is a
three-tier lookup in `SidebarListView`:

1. cwd inside a known repo/worktree → use that worktree as the display key (name and
   live branch label via the existing metadata path);
2. cwd known but outside every repo → derive a name from the last path component;
3. cwd unknown → fall back to the surface's owning worktree (previous behavior).

`ActiveAgentEntry.worktreeID` is deliberately left untouched: it also drives
`focusSurface`/`selectWorktree`, and the surface physically lives in the tab's
worktree, so the cwd resolution is display-only.

**Tab-title display setting (PR #386, 2026-06-04, refs #385).** A persisted setting
(`showActiveAgentTabTitles` in `GlobalSettings`, default off) swaps the row
subtitle/tooltip between branch name (default) and tab title.

## Refs

- PR #363 (merged 2026-05-28), PR #386 (merged 2026-06-04)
- Tests: `RepositorySectionViewTests` (all three cwd tiers, nested-worktree deepest
  match, nil-cwd fallback), `SettingsFeatureTests`, `AppFeatureSettingsChangedTests`,
  `ActiveAgentsFeatureTests` (subtitle/help behavior)

## Current state

Resolution helpers `activeAgentRowDisplays` / `activeAgentRowDisplay` /
`resolveWorktreeID(forWorkingDirectory:in:)` live in
`supacode/Features/Repositories/Views/SidebarListView.swift` as static pure functions;
`ActiveAgentsPanel` consumes precomputed per-entry displays plus a `showTabTitles`
flag. The setting is wired through `supacode/Features/Settings/Models/GlobalSettings.swift`
and `supacode/Features/Settings/Reducer/SettingsFeature.swift`.
