# 014 — Terminal Layout Persistence: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-31 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #112, #113, #116 (umbrella for fork issue #76) |
| **Sources** | Fork issue #76, PR #77/#81/#112/#113/#116/#120–#125/#186/#380/#459 descriptions, change-list 2026-04-08 and 2026-06-09 review batches (ledger lives on as `docs-ai/017-upstream-sync-process/upstream-ledger.md`) |
| **Related** | [010-plain-folder-support](../010-plain-folder-support/000-plan.md), [022-tab-title-and-icon](../022-tab-title-and-icon/000-plan.md), [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md), `docs/components/terminal.md`, `docs/components/settings.md`, `docs/reference/settings-fields.md` |

## Background

Prowl lost all terminal arrangement on every restart: tab and split layouts were rebuilt
from scratch and font-size adjustments (Cmd+/-) reverted to the Ghostty config default.
Fork issue #76 asked for both to persist across launches — a real pain for the
many-worktrees, many-splits workflow the app is built around.

Persisting layout is riskier than it sounds: the snapshot is read at boot, before the
repository list is live, and a corrupted or stale snapshot could poison startup (the
adjacent repository-snapshot cache from 006-startup-performance had the same exposure).
The work was therefore split into a safety phase and a restore phase.

## Goals

- Persist the per-worktree tab/split tree (pane working directories, focused pane,
  selected worktree) and restore it on launch.
- Persist the user's terminal font-size override independently of Ghostty's config file.
- Fail closed: an invalid, oversized, or unrestorable snapshot must be discarded (and
  surfaced to the user) rather than half-applied.
- Keep the feature opt-in behind a setting (`restoreTerminalLayoutOnLaunch`, default
  `false`, labeled experimental) with a manual "Clear saved terminal layout" escape hatch.

### Non-goals

- Persisting live shell sessions (scrollback, running processes). Restore recreates
  fresh shells in the saved working directories; this is a layout snapshot, not a
  terminal multiplexer.

## Design / Approach

Reconstructed from the phase PRs (#112, #113) and the umbrella #116.

**Font size first (#77, #81).** The font-size override became a Prowl-local setting
(`GlobalSettings.terminalFontSize`) instead of a Ghostty config write. The value is
normalized against Ghostty's default `font-size` (reset-to-default clears the override),
synced from surface cell-size/config-change callbacks, and injected into
`WorktreeTerminalManager` as `preferredFontSize` at boot so new surfaces inherit it.

**Phase A — persistence safety (#112).** Guardrails before any restore logic:

- Snapshot storage moved from `~/.prowl` to
  `~/Library/Application Support/com.onevcat.prowl/cache/` (both
  `repository-snapshot.json` and the new `terminal-layout-snapshot.json`), with legacy
  migration.
- `PathPolicy` centralizes path normalization + containment checks used by persistence
  keys and worktree-cleanup safety.
- `snapshotPersistencePhase` (`idle`/`restoring`/`active`) in `RepositoriesFeature`
  blocks snapshot writeback while boot-time restore is in flight.
- Fail-closed "fuses": limits on snapshot file size, repository count, and worktrees per
  repository; anything over the limit is rejected and reset.
- Settings plumbing: the `restoreTerminalLayoutOnLaunch` toggle, the clear-layout action,
  and a stub `TerminalLayoutPersistenceClient`.

**Phase B — restore pipeline (#113, assembled in #116).**

- `TerminalLayoutSnapshotPayload`: a versioned Codable model
  (worktrees → tabs → recursive split nodes) with its own validity fuses
  (`maxWorktrees`, `maxSplitNodesPerTab`, `maxSplitDepth`) and migration support.
- `TerminalLayoutPersistenceClient` does snapshot I/O (`loadSnapshot` / `saveSnapshot` /
  `clearSnapshot`), rejecting invalid or oversized files.
- `WorktreeTerminalManager` orchestrates: build the payload from live terminal states on
  save; on restore, match snapshot worktrees against the loaded repository list, rebuild
  each `WorktreeTerminalState` tab/split tree, and clear the snapshot if anything fails.
- `LaunchRestoreMode` (`lastFocusedWorktree` vs `restoreLayout`) unifies the two startup
  paths in `AppFeature`; restore fires once, when repositories are loaded and the
  persistence phase is active.
- Save points: scene phase going inactive/background (async) and
  `applicationWillTerminate` (synchronous), the latter because macOS termination does not
  wait for async effects.

## Alternatives & decisions

- **Snapshot-and-rebuild over a session multiplexer.** The fork restores *layout* and
  spawns fresh shells; it never attempted process-level session survival. Upstream later
  went the other way, bundling a `zmx` multiplexer for terminal-session persistence
  (upstream #334/#356/#357/#360/#361/#368/#369). The 2026-06-09 upstream review batch
  deliberately skipped that entire track: the fork keeps its own terminal-layout
  persistence and takes no `zmx` dependency. Recorded in the upstream ledger
  (`docs-ai/017-upstream-sync-process/upstream-ledger.md`).
- **Kept over upstream's own layout persistence.** Upstream also shipped a
  layout-persistence feature (`771e4aab`), reviewed in the 2026-04-08 v0.8.0 batch. The
  fork's implementation had already merged a week earlier (#116, 2026-04-01) and was not
  replaced.
- **Opt-in, fail-closed.** Because restore runs at boot, every failure path clears the
  snapshot and falls back to a clean launch (later also warning via toast, #125), and the
  toggle shipped default-off/experimental. It still is today.
- **Font size as a Prowl setting, not a Ghostty config edit** — keeps the user's Ghostty
  config file untouched and lets the override travel with Prowl's own settings (#77).

## Amendments

- Updated 2026-06-16: two launch-ordering races fixed months later — Default View
  restoration hang (#380) and a scenePhase save that cleared the snapshot before restore
  could read it (#459) — see [002-launch-restore-races.md](002-launch-restore-races.md)
