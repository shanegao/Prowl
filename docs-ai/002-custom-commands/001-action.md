# 002 — Custom Commands: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-02-27 | Initial feature: repo-scoped custom command buttons (icon/title/command/execution mode, up to 3 per repo) in worktree toolbar + Worktrees menu; per-command shortcut overrides routed past Ghostty via a shortcut registry; shortcut editor layout polish | commits `76046bc0`, `b5c58e4d` |
| 2026-02-27 | Terminal-input commands execute via synthesized Return key events (`submitLine()`, keyCode 36) instead of pasted text only | commit `562042fc` |
| 2026-03-27 | `Onevcat*` type prefix renamed to `User*` (`UserRepositorySettings`, `UserCustomShortcutRegistry`) during shortcut-conflict work | commits `3ef622c7`, `f3f62a4e` (PR #79, see [012](../012-keybinding-system/000-plan.md)) |
| 2026-03-31 | UI revamp: editable command table, 3-command cap removed, toolbar overflow menu, SF Symbol preset picker, shortcut recording with repo-local conflict handling (keybinding milestone M4, fork issue #85) — see [002-ui-revamp-and-keybinding-unification.md](002-ui-revamp-and-keybinding-unification.md) | PR #101 |
| 2026-04-17 | New Split execution target (per-command direction) + Close on success toggle; 800 ms auto-close delay; success toast — see [003-split-target-and-close-on-success.md](003-split-target-and-close-on-success.md) | PR #205 |
| 2026-04-27 | Custom command icons pinned over command auto-detection for the run's lifetime; the model's `"terminal"` placeholder treated as "unset" so untouched commands keep auto-detection | PR #245 (owned by [022](../022-tab-title-and-icon/000-plan.md)) |
| 2026-05-18 | Custom commands surfaced in the command palette (typed-query only, stable UUID-based item IDs, per-command recency) | PR #299 (owned by [031](../031-command-palette-architecture/000-plan.md)) |
| 2026-05-28 | Canvas custom actions: Run/Stop Script and Custom Commands routed through the focused Canvas card; toolbar cluster kept as a single `ToolbarItem` to avoid card-switch jumps (community #358 by vince-hz + refinements) | PR #362 (owned by [024](../024-canvas-interaction-evolution/000-plan.md)) |
| 2026-06-07 | Settings UI split into dedicated files (`RepositorySettingsCustomCommandsView.swift`, `RepositorySettingsSupportingViews.swift`) as part of the large-file refactor | PR #403 (owned by [015](../015-repositories-feature-refactor/000-plan.md)) |

## Outcome & current state (as of 2026-07-12)

- **Model** — `supacode/Features/Settings/Models/UserRepositorySettings.swift`:
  `UserCustomCommand` (id, title, `systemImage`, command, execution, `splitDirection`,
  `closeOnSuccess`, optional `shortcut`), `UserCustomCommandExecution`
  (`.shellScript` "New Tab" / `.terminalInput` "In Place" / `.split`),
  `UserCustomShortcut` + `UserCustomShortcutModifiers`. `init(from:)` uses
  `decodeIfPresent` with defaults so pre-#205 settings files keep decoding. No command
  count cap remains.
- **Storage** — `supacode/Support/SupacodePaths.swift`: `prowl.onevcat.json` under
  `~/.prowl/repo/<repo-last-path>/`, with legacy fallbacks for `supacode.onevcat.json`
  (both the pre-rename directory file and the original repo-root location).
- **Execution** — `supacode/Features/App/Reducer/AppFeature.swift`
  (`.runCustomCommand(index:)`): dispatches `terminalClient.send(.createTabWithInput)` /
  `.createSplitWithInput` / `.insertText` per mode; treats an empty or `"terminal"`
  `systemImage` as no icon so tab auto-detection still applies.
  `supacode/Clients/Terminal/TerminalClient.swift` carries `autoCloseOnSuccess` and
  `customCommandIcon` on both create commands.
- **Terminal input** — `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`:
  `focusAndRunCommand(_:)` inserts the text into the focused surface then calls
  `GhosttySurfaceView.submitLine()` (synthesized `\r` keyDown/keyUp, keyCode 36) in
  `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`.
- **Close on success / toast** —
  `supacode/Features/Terminal/Models/WorktreeTerminalState+Notifications.swift`:
  `handleCommandFinished` consumes `autoCloseSurfaceIds` one-shot, schedules the delayed
  auto-close on exit 0, and fires `onCustomCommandSucceeded` (success toast callback wired
  in `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`).
- **Toolbar** — `supacode/Features/Repositories/Views/WorktreeDetailView.swift` +
  `WorktreeDetailToolbarViews.swift`: `UserCustomCommandToolbarButton` for the first
  commands, `CustomCommandOverflowButton` popover for the rest; shortcut labels resolved
  via `store.resolvedKeybindings.keyboardShortcut(for:)`. The Canvas toolbar path renders
  the same cluster (`supacode/Commands/WorktreeCommands.swift` provides the menu items).
- **Shortcuts** — `supacode/App/KeybindingSchema.swift`:
  `LegacyCustomCommandShortcutMigration.migrate(commands:)` converts each per-command
  `UserCustomShortcut` into a keybinding override; `appResolverSchema(customCommands:)`
  injects per-command schema entries (scope `.customCommand`). The precedence hook
  survives as `supacode/Infrastructure/Ghostty/UserCustomShortcutRegistry.swift`,
  consulted in `supacode/Infrastructure/Ghostty/GhosttySurfaceView+Keyboard.swift` and fed
  through `supacode/Clients/Shortcuts/CustomShortcutRegistryClient.swift`.
- **Palette** — `supacode/Features/CommandPalette/Reducer/CommandPaletteFeature.swift`:
  `customCommandItems(_:)`, `CommandPaletteItemID.customCommand`, subtitle
  "Custom command in this repo · …" including execution mode and split direction.
- **Settings UI** —
  `supacode/Features/Settings/Views/RepositorySettingsCustomCommandsView.swift` (+
  `RepositorySettingsSupportingViews.swift`, `RepositorySettingsView.swift`).
- **Tests** — `supacodeTests/AppFeatureCustomCommandTests.swift`,
  `RepositorySettingsFeatureTests.swift`, `UserRepositorySettingsKeyTests.swift`.
- **User docs** — `docs/components/custom-actions.md` describes behavior and hotkey
  precedence.

## Deviations from plan

- The original `Onevcat*` naming and the standalone shortcut model did not survive as
  designed: types were renamed to `User*` (2026-03-27), and the per-command `shortcut`
  field is now primarily a legacy carrier migrated into the config-driven keybinding
  system ([012](../012-keybinding-system/000-plan.md)) rather than the source of truth for
  display/resolution.
- The 3-command cap was an explicit part of the original design and was removed in #101.
- "Close on success" as merged in #205 closed immediately on exit 0; an 800 ms delay was
  added in the same PR branch (`5d2c2836`) so the final output stays briefly visible.

## Open questions

- None.
