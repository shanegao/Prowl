# 002 — Amendment: UI Revamp & Keybinding Unification (#101)

## Context

By late March 2026 the original three-command settings form had outgrown itself, and the
config-driven keybinding system ([012-keybinding-system](../012-keybinding-system/000-plan.md))
had landed its resolver and recorder milestones (M1–M3). Fork issue #85 ("[M4] Unify
custom commands UI with shared recorder and conflict engine") scheduled custom commands as
the keybinding project's fourth milestone: stop hand-rolling shortcut entry and conflict
checks in the repo settings form, and lift the arbitrary command cap.

## Change

PR #101 (merged 2026-03-31, "Issue #85: revamp repo custom commands UI and remove
3-command cap"):

- Replaced the repository custom commands settings with a table + detail editor UX
  (iterated during the branch into an inline-editable, scrollable lazy stack).
- Removed the legacy 3-command cap (`maxCustomCommands`).
- Shortcut recording now uses the shared recorder with **repo-local conflict handling
  only** (Replace / Cancel between the repo's own commands); app-level conflict warning
  noise was removed — resolution against app bindings happens in the keybinding resolver,
  where repo custom command shortcuts take priority over app bindings (branch commit
  `1e225271`).
- Resolved keybinding displays shown both in repository settings and on the terminal
  toolbar custom command buttons.
- Toolbar overflow menu: the first 3 commands stay as buttons; the rest go into a
  scrollable popover (max 10 visible rows).
- SF Symbol preset picker popover (expanded to 30 presets during the branch) while keeping
  manual symbol input.
- Execution mode labels renamed to "New Tab" / "In Place" (`1401ff27`).

## Refs

- PR #101, fork issue #85 (closed).
- Branch commits: `83243acb`, `22713fe3`, `1e225271`, `bdf6e8d0`, `1401ff27`.

## Current state

The table/editor lives in
`supacode/Features/Settings/Views/RepositorySettingsCustomCommandsView.swift` (split out
of `RepositorySettingsView.swift` in PR #403). Overflow rendering is
`CustomCommandOverflowButton` in
`supacode/Features/Repositories/Views/WorktreeDetailToolbarViews.swift`. Shortcut
migration/resolution is `LegacyCustomCommandShortcutMigration` and
`appResolverSchema(customCommands:)` in `supacode/App/KeybindingSchema.swift`.
