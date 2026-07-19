# 002.006 — Command Visibility Gates and Scope Ordering: Plan

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-07-19 |
| **Primary PRs** | Pending |
| **Related** | [002 Custom Commands](000-plan.md), [012 Keybinding System](../012-keybinding-system/000-plan.md), `docs/components/custom-actions.md` |

## Background

Global commands currently appear in every repository unless a local command has a matching
trimmed, case-insensitive title. Neither scope can disable a command without deleting it, and
repository settings cannot show the effective command list that drives the toolbar.

## Goals

- Preserve commands, ordering, and shortcuts while allowing them to be disabled.
- Show both local and global commands, even when their titles match.
- Keep effective toolbar order deterministic: repository commands followed by global commands.
- Let each repository opt out of an enabled global command without editing its global definition.
- Remove disabled commands from every launch surface and shortcut dispatch.

## Design / Approach

- Add an `isEnabled` flag to `UserCustomCommand`, defaulting to `true` for legacy settings.
- Store only each repository's explicitly disabled global command IDs; an absent ID means enabled.
- Resolve both sources in repository-first order. A global command is effective only when its own
  `isEnabled` flag and its repository gate are both enabled; a local command has one gate.
- Build the app's toolbar, Worktrees menu, command palette, execution lookup, and keybinding
  registration from the effective list. Keep disabled commands and shortcuts persisted so
  re-enabling restores them.
- Extend the shared settings table with an Enabled column and explicit drag handle. The global
  editor owns global edits and reordering. Repository settings combine local and global rows:
  local rows remain editable and reorderable; global rows show a Global marker and expose only
  their This Repo gate. A globally disabled row remains configurable and says Disabled globally.
- Preserve existing local-over-global shortcut conflict precedence.

## Alternatives & decisions

- **Both matching titles remain visible**: title matching no longer suppresses global commands;
  source-qualified IDs make this safe.
- **Repository-first grouping instead of cross-scope ordering**: each scope owns its own stable
  order and drag interaction, avoiding a fragile per-repository ordering overlay for global IDs.
- **Persist only global opt-outs**: default-on global commands retain their expected all-repository
  behavior without serializing redundant `true` values.
- **One visible repository gate for Global rows**: the row reports a disabled global gate separately
  rather than conflating it with This Repo state.

## Verification

Logic tests cover decoding defaults, source/order resolution, visibility gates, and shortcut
registration. Reducer tests prove active-worktree refresh. A debug-app smoke test verifies the
settings table, source restrictions, drag order, overflow behavior, all command surfaces, and
shortcut restoration after re-enabling.

## Amendments

(append follow-up notes here)
