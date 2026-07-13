# 002.005 — Global Custom Commands: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-13 | Added global command storage, resolution, settings UI, source-qualified routing, tests, and manual documentation. | `f481db26` |

## Outcome & current state (as of 2026-07-13)

- `UserGlobalSettings` persists `customCommands` in `~/.prowl/global.onevcat.json` through
  `UserGlobalSettingsKey`.
- `EffectiveCustomCommand` resolves local commands before global commands and suppresses a
  global command when a trimmed, case-insensitive local title matches.
- `AppFeature`, `WorktreeCommands`, `WorktreeDetailView`, and `CommandPaletteFeature` use
  source-qualified command identity. Local bindings retain `custom_command.<uuid>` and
  global bindings use `custom_command.global.<uuid>`; a local shortcut collision disables
  the global binding.
- Settings → Custom Commands edits the global list. The toolbar marks global entries and
  the overflow menu receives the source-qualified commands.

## Deviations from plan

The global editor is intentionally compact rather than extracting the existing
repository editor into a shared view. It supports the same persisted command fields while
keeping the repository editor unchanged.

## Open questions

None.
