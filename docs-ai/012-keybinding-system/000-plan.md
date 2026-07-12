# 012 — Keybinding System: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-27 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #79, #87, #88, #100 (re-land of #95), #117, #118, #255 |
| **Sources** | Fork issues #55, #71, #72 (milestones #82–#86), PR descriptions; [architecture.md](architecture.md) (living architecture reference kept in this folder) |
| **Related** | [002-custom-commands](../002-custom-commands/000-plan.md), [007-ghostty-embedding-integration](../007-ghostty-embedding-integration/000-plan.md), [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md), `docs/reference/keyboard-shortcuts.md` |

## Background

Before this work, app shortcuts were hard-coded in `AppShortcuts`, custom command
shortcuts lived in a separate ad-hoc registry, and three consumers — menu items, the
command palette, and the Ghostty `--keybind` CLI arguments — each read bindings from
their own hard-coded path. Users could not rebind anything, and several defaults
collided with terminal muscle memory (`⌘[`/`⌘]`, and the contested role of `⌘B` —
discussion in fork issue #55). Issue #55 was split into two planning issues:

- **#71** — default-shortcut alignment and conflict precedence rules.
- **#72** — a config-driven keybinding system with a recorder UI, including research
  into third-party frameworks (KeyboardShortcuts, MASShortcut, HotKey).

## Goals

- A versioned keybinding schema covering every command, with scope, overridability, and
  conflict-policy metadata (four scopes: `configurableAppAction`, `systemFixedAppAction`,
  `localInteraction`, `customCommand`).
- Deterministic resolution with layered precedence: `appDefault` → `migratedLegacy` →
  `userOverride`; non-overridable commands ignore overrides entirely.
- One resolver output (`ResolvedKeybindingMap`) feeding all consumers: menus, command
  palette labels, SwiftUI environment, and Ghostty CLI keybind arguments.
- Shortcuts Settings page with an inline key recorder, conflict detection/replacement,
  and cascading reset back to defaults.
- Automatic migration of legacy custom-command shortcuts into the new override store.
- Minimal default remap per #71, and releasing terminal-critical combinations to Ghostty.

### Non-goals

- Hard-blocking conflicting user shortcuts: conflicts warn and prefer the user override
  (decision in #71/#79), rather than refusing to save.
- Managing Ghostty-native bindings (splits, terminal actions bound in the user's Ghostty
  config): those stay owned by Ghostty; Prowl only unbinds/binds what it needs.

## Design / Approach

The work was milestone-split under umbrella issue #72 and integrated on a dedicated
branch (`feature/issue-72-keybinding-integration-base`) that merged into `main` as one
reviewed unit (#118):

- **M1 (#82 → PR #87)** — data layer: `KeybindingSchemaDocument` (versioned schema),
  `KeybindingResolver` (precedence merge), `LegacyCustomCommandShortcutMigration`
  (old `UserCustomCommand.shortcut` → override entries), plus schema/resolver tests.
- **M2 (#83 → PR #88)** — routing: menu shortcut display/registration, command palette
  labels, and Ghostty CLI argument generation all read from resolver-backed helpers
  keyed by command ID, replacing three separate hard-coded paths.
- **M3 (#84 → PR #95/#100)** — runtime sync + UI: Shortcuts Settings table layout,
  resolved-binding hints across the UI, configurable local-interaction shortcuts.
- **M4 (#85, landed inside #118)** — custom commands UI revamp sharing the same
  recorder and conflict engine.
- **M5 (#86 → PR #117 + docs in #118)** — behavior matrix tests (scope × policy ×
  state) and the agent-facing architecture reference (now [architecture.md](architecture.md)).

Ghostty integration generates two kinds of CLI args from the resolved map: `=unbind`
for app-owned shortcuts (so Ghostty does not intercept them) and bind args for
terminal actions (e.g. `goto_tab:N`), re-synced whenever bindings change. The full
mechanics (scopes, policies, storage, reset cascade) are documented in
[architecture.md](architecture.md) — not duplicated here.

## Alternatives & decisions

- **Minimal default remap** (#71 owner plan, implemented in #79): `⌃⌘S` Toggle Sidebar
  (was `⌘[`), `⇧⌘U` Check for Updates (was `⌘U`), `⇧⌘Y` Show Diff (was `⌘]`); `⌘B` left
  unassigned for build/custom-command semantics.
- **Warn, don't block** (#79): a custom shortcut conflicting with an app default is
  persisted and wins (`result=customOverride` warning log), instead of hard rejection.
- **Release terminal-critical combos** (#79): `⌘[`/`⌘]`, `⇧⌘[`/`⇧⌘]`, `⌘D`/`⇧⌘D` are no
  longer unbound from Ghostty, preserving native tab/split behavior.
- **Self-built recorder over third-party frameworks**: #72 planned framework research;
  the shipped implementation uses a plain `NSEvent.addLocalMonitorForEvents` recorder
  with `ShortcutKeyTokenResolver`, and no third-party shortcut dependency exists in the
  tree.
- **Integration-base branch flow**: milestones merged into a feature base branch and
  reviewed once at #118. The M3 PR #95 was accidentally merged to `main`, reverted by
  #99, and re-landed as #100 against the base branch.

## Amendments

- Updated 2026-05-08: Ghostty key-equivalent ownership fix (#255, upstream port) — see
  [002-ghostty-key-equivalent-ownership.md](002-ghostty-key-equivalent-ownership.md)
- Updated 2026-05-24: chained/sequence/performable bindings invisible to shortcut-hint
  reverse lookup; fallback PR #334 closed as unnecessary — see
  [003-chained-binding-hint-limitation.md](003-chained-binding-hint-limitation.md)
