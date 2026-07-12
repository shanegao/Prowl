# 034 — Amendment: Duplicate Watcher Crash (#528)

## Context

Sentry issue `PROWL-MACOS-D6`: crashes in `WorktreeInfoWatcherManager.setWorktrees`
while building a lookup with `Dictionary(uniqueKeysWithValues:)`, which traps on
duplicate keys. The watcher receives the flat-mapped worktrees of *all* repositories
(`worktreesForInfoWatcher()`), and base-directory collisions can enumerate the same
worktree path more than once — the per-repository discovery dedup from #346 does not
cover cross-repository duplicates.

Provenance: the trapping call was introduced upstream in `c6d14452` (2026-01-27, the
original worktree info watcher). Upstream fixed the same crash class in `84be657a`
(upstream #517, 2026-06-29), but the fork's `prowl@2026.6.27` release did not include
that commit, so the fork shipped its own fix.

## Change

- `setWorktrees` builds `worktreesByID` with an explicit first-wins loop and configures
  watchers only for the deduplicated worktree list.
- Regression test `buildsWorktreeLookupWithoutTrappingOnDuplicateID()` in
  `supacodeTests/WorktreeInfoWatcherManagerTests.swift`.
- New SwiftLint custom rule `dictionary_unique_keys_with_values` (severity error)
  blocks `Dictionary(uniqueKeysWithValues:)` repo-wide; existing call sites were
  converted to explicit duplicate handling (`Dictionary(_, uniquingKeysWith:)` /
  `IdentifiedArray(_, uniquingIDsWith:)`), so the crash class cannot re-enter.

## Refs

- PR #528 — "Fix duplicate worktree watcher crash" (merged 2026-06-30)
- Sentry issue `PROWL-MACOS-D6`; upstream #517 (`84be657a`)

## Current state

Verified: the first-wins loop in `setWorktrees` in
`supacode/Features/Repositories/BusinessLogic/WorktreeInfoWatcherManager.swift`; the
`dictionary_unique_keys_with_values` rule in `.swiftlint.yml`; no
`Dictionary(uniqueKeysWithValues:)` call sites remain outside the lint rule definition.
