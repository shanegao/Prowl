# 040 — Amendment: Upstream Editor Ports (Zed Preview, IDEA EAP, Nova)

## Context

The 2026-07-09 upstream review batch (post-v0.10.5, see
[017-upstream-sync-process](../017-upstream-sync-process/000-plan.md)) found six recent
editor additions upstream. Three were already present in the fork with identical bundle
ids — GoLand / Rider / PhpStorm landed via `e423d2d8` (#439) on 2026-06-13. The
remaining three were ported as PR #542 (merged 2026-07-08, commit `9a13c42d`).

## Change

| Editor | Upstream | Bundle id | Placement |
| --- | --- | --- | --- |
| Zed Preview | upstream #447 | `dev.zed.Zed-Preview` | right after Zed in `editorPriority` (channel-variant convention) |
| IntelliJ IDEA EAP | upstream #496 | `com.jetbrains.intellij-EAP` | right after IntelliJ; JetBrains CLI-args open path |
| Nova | upstream #506 | `com.panic.Nova` | after Sublime Text among Mac-native generic editors |

Fork-specific integration: IDEA EAP participates in the fork's project-type detection —
`WorktreeProjectKind.preferredActions` for `android` and `java` ends with IDEA EAP as
the IntelliJ fallback — which upstream does not have.

Decisions carried from the sync batch:

- Upstream's `c38c325d` #423 OpenTarget/OpenBehavior refactor was deliberately NOT
  adopted; the three editors are additive cases in the fork's existing
  `OpenWorktreeAction` enum shape.
- `settingsID` raw values match upstream exactly (`zed-preview`, `intellijEAP`, `nova`)
  so persisted selections stay portable across future syncs; `intellijEAP` breaks the
  fork's kebab-case convention on purpose.

Tests added: bundle-id assertions, `editorPriority` membership,
`channelVariantsFollowTheirStableEditors` (pins Zed Preview / IDEA EAP directly after
their stable channels), updated android/java `preferredActions` expectations, and
`preferredDefaultPicksIntellijEAPWhenOnlyEAPInstalled` for Automatic-mode fallback.
`docs/components/repositories-and-worktrees.md` was updated in the same change.

## Refs

- PR #542 (merged 2026-07-08)
- Upstream #447 / #496 / #506; ledger entry: 2026-07-09 batch in
  `../017-upstream-sync-process/upstream-ledger.md`

## Current state

Verified in `supacode/Domain/OpenWorktreeAction.swift`: `zedPreview` follows `zed` and
`intellijEAP` follows `intellij` in `editorPriority`; `nova` sits after `sublimeText`;
all three bundle ids and `settingsID` literals match the table above. IDEA EAP is
present in `supacode/Domain/WorktreeProjectKind.swift` `preferredActions` for `android`
and `java`.
