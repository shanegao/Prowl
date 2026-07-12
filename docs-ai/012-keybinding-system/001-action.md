# 012 — Keybinding System: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-27 | Default-shortcut alignment + conflict fallback: minimal remap (`⌃⌘S` sidebar, `⇧⌘U` updates, `⇧⌘Y` diff), custom shortcuts persist as user overrides with warning on conflict, terminal-critical combos released to Ghostty | PR #79 (issue #71) |
| 2026-03-28 | M1: versioned schema (`KeybindingSchemaDocument`), `KeybindingResolver` with appDefault → migratedLegacy → userOverride precedence, `LegacyCustomCommandShortcutMigration`, unit tests | PR #87 (issue #82) |
| 2026-03-29 | M2: menu display/registration, command palette labels, and Ghostty CLI keybind args all routed through resolver-backed helpers keyed by command ID | PR #88 (issue #83) |
| 2026-03-30 | M3: runtime sync + UI hints, table-style Shortcuts Settings, configurable local-interaction shortcuts. Accidentally merged to `main` as #95, reverted by #99, re-landed onto the integration base branch as #100 | PRs #95, #99, #100 (issue #84) |
| 2026-04-01 | M5 tests: 24-case behavior matrix (scope × policy × state: defaults, overrides, disable, migration precedence, conflict detection, cascading reset, persistence round-trip, edge cases) | PR #117 (issue #86) |
| 2026-04-01 | Umbrella merge of `feature/issue-72-keybinding-integration-base` into `main`: recorder UI, conflict alerts, cascading reset planner, custom commands UI revamp (M4, issue #85), agent architecture doc; 60 files, +5711/−668 | PR #118 (issues #72, #86) |
| 2026-05-08 | Ghostty key-equivalent ownership fix (upstream port) — see [002](002-ghostty-key-equivalent-ownership.md) | PR #255 |
| 2026-05-24 | Chained-binding shortcut-hint limitation identified as Ghostty reverse-map behavior; fallback PR closed unmerged — see [003](003-chained-binding-hint-limitation.md) | PR #334 (closed) |

## Outcome & current state (as of 2026-07-12)

All of the following verified against the working tree:

- `supacode/App/KeybindingSchema.swift` — `KeybindingSchemaDocument`,
  `KeybindingUserOverrideStore`, `KeybindingResolver`,
  `LegacyCustomCommandShortcutMigration`, and the `appDefaultsV1` bridge from
  `AppShortcuts.bindings`.
- `supacode/App/AppShortcuts.swift` — built-in command registry plus
  `ghosttyCLIKeybindArguments(from:)` generating unbind/bind args from a
  `ResolvedKeybindingMap`; display helpers for palette/menu hints.
- `supacode/Features/App/Reducer/AppFeature+Support.swift` — `resolvedKeybindings(...)`
  recompute: migrates legacy custom-command shortcuts, resolves, and lets custom
  commands win over conflicting app-level bindings.
- `supacode/App/ResolvedKeybindingsEnvironment.swift` — SwiftUI environment key.
- `supacode/App/supacodeApp.swift` — passes keybind args at Ghostty init and re-syncs
  on changes.
- `supacode/Features/Settings/Views/ShortcutsSettingsView.swift` — settings page and
  `NSEvent.addLocalMonitorForEvents`-based recorder. Note: `ShortcutResetPlanner` is an
  enum declared **inside this view file** (line ~742), not a separate file under
  `BusinessLogic/` as [architecture.md](architecture.md) currently claims.
- `supacode/Features/Settings/BusinessLogic/ShortcutConflictDetector.swift` and
  `ShortcutKeyTokenResolver.swift` — conflict detection and NSEvent → key-token mapping.
- `supacode/Features/Settings/Models/GlobalSettings.swift` — `keybindingUserOverrides`
  persisted via the shared settings file.
- Tests in `supacodeTests/`: `KeybindingSchemaTests.swift`,
  `KeybindingBehaviorMatrixTests.swift`, `ShortcutConflictDetectorTests.swift`,
  `ShortcutResetPlannerTests.swift`, `ShortcutKeyTokenResolverTests.swift`,
  `AppShortcutsTests.swift`, `GhosttySurfaceViewTests.swift`.
- User-facing shortcut table: `docs/reference/keyboard-shortcuts.md`.

## Deviations from plan

- The M1 design note (`doc-onevcat/keybinding-m1-design.md`, mentioned in PR #87's
  description) never landed on `main`; its substance survives only in the PR body and
  in [architecture.md](architecture.md).
- M3 landed twice due to the #95 mis-merge (reverted by #99, re-landed as #100); the
  final content is identical.
- Issue #72's framework research (KeyboardShortcuts/MASShortcut/HotKey) produced no
  adopted dependency; the recorder is self-built.

## Open questions

- [architecture.md](architecture.md) lists `ShortcutResetPlanner` at
  `supacode/Features/Settings/BusinessLogic/ShortcutResetPlanner.swift`, but the type
  is declared inside `supacode/Features/Settings/Views/ShortcutsSettingsView.swift`.
  The living doc should be corrected during migration (or the type extracted to match).
