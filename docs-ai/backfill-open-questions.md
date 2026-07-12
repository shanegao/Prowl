# Backfill Open Questions (2026-07-12)

Aggregated follow-ups discovered while backfilling entries 001–045 by verifying PRs and
historical docs against the current tree. Each entry's full list lives in its own
`001-action.md` → *Open questions*; this file collects the ones worth acting on or
deciding. Living document: every actionable item is tracked by a GitHub issue (or was
fixed directly); strike items as they get resolved.

## Likely bugs / risky behavior

- ~~**`make bump-and-release` conflicts with the notarized-only release policy**~~
  ([001](001-fork-bootstrap-and-release-pipeline/001-action.md)) — **fixed: removed in
  PR #577** after auditing all 68 releases (never used; `bump-version` kept for `release.sh`).
- ~~**Sparkle channel picker is a no-op**~~ ([021](021-sparkle-update-ux/001-action.md)) —
  **fixed: the Stable/Tip setting and all `UpdateChannel` plumbing removed in PR #578.**
- **Shortening the archived-worktree retention window deletes immediately with no
  confirmation** ([018](018-archived-worktrees/001-action.md)) — silent-data-loss UX gap
  that issue #174's design notes had asked to guard. → **#560**
- **Line-diff timing tier never refreshes** ([037](037-line-diff-tracking/001-action.md)):
  `repositoryLineChangesTimings` fills only missing roots, so a repo crossing a size tier
  keeps its stale debounce tier until relaunch — diverges from the 2026-06-22 plan intent.
  → **#561**
- **Prefix-detection mismatch in branch-name suggestions**
  ([044](044-foundation-model-branch-names/001-action.md)): `buildPrompt` advertises any
  `/`-prefix found in branches but `BranchNameSanitizer.detectConventionPrefix` knows a
  fixed list (no `feat/`); `BranchNameSanitizer` also has no dedicated unit tests. → **#562**
- **`withExpectedGithubAccount` switch-execute-restore risk**
  ([039](039-gh-cli-hardening/001-action.md)): external `gh auth switch` or a crash inside
  the window leaves the host pinned to the override account; undocumented in docs/. → **#563**
- **SIGTERM'd long jobs never notify** ([008](008-terminal-notifications/001-action.md)):
  exit codes 130/143 are unconditionally treated as user-initiated. → **#564**

## Dead code / drift to clean up

- `SupacodePaths.originalLegacy*SettingsURL(for:)` unreferenced (repo-root legacy fallback
  dropped) — [004](004-prowl-rebrand/001-action.md). → **#565**
- `SidebarPresentation.showsListHeader(repositoryCount:)` ignores its parameter (leftover
  of the removed ">10 repos" rule) — [026](026-sidebar-container-refactor/001-action.md).
  → **#566**
- `AgentDetectionSchedule.observedAgent(now:)` ignores `now`; `idleAgentDetectionInterval`
  is a misnomer post-#441 — [030](030-agent-status-detection/001-action.md). → **#567**
- Stale `MaxRects-BSSF` doc comment on `arrangeCards()` in `CanvasView.swift` —
  [005](005-canvas-live-sessions/001-action.md). → **#568**
- `GHOSTTY_PROMPT_TITLE_SURFACE` carries an in-code "consider removing" note; decision
  never made — [007](007-ghostty-embedding-integration/001-action.md). → **#570**
- Close-confirmation copy hardcodes "at least 10 seconds" next to an injectable threshold —
  [035](035-protected-terminal-close/001-action.md). → **#569**
- `RepositoriesFeature+GithubIntegration.swift` re-crossed the 1,000-line ceiling that
  PR #403 established — [015](015-repositories-feature-refactor/001-action.md). → **#571**

## Docs / ledger corrections needed

- **Observability runbook drift** ([020](020-observability/runbook.md)): still documents
  the App-Hang machinery removed in #236/#241 (a drift warning is stamped at the top);
  needs an update pass. → **#572**
- ~~**Upstream ledger corrections**~~
  ([017](017-upstream-sync-process/upstream-ledger.md)) — **fixed 2026-07-12**: see the
  ledger's "Ledger corrections" entry (#265/#267 closed unmerged; #416/#417 commit
  attributions; upstream #225 deferred adoption marked never-executed; snapshot-cache row
  no longer "Pending upstream" — upstream #162 closed unmerged).
- **CLI contract drift** ([013](013-prowl-cli/001-action.md)): `contracts/send.md` still
  calls `--capture` future; `contracts/read.md` lacks `--wait-stable`; no contracts exist
  for `tab`/`pane`/`agents` despite shipped `v1` schema ids; architecture.md's planned
  JSON-Schema validation harness (M4) never landed. → **#559** (to be discussed before
  any writing)
- `restoreTerminalLayoutOnLaunch` still default-off "(experimental)" 3.5 months after
  shipping; no promote/retire decision — [014](014-terminal-layout-persistence/001-action.md).
  → **#573**
- Active Agents panel status-priority sorting (blocked→working→done→idle) was a #274
  follow-up, still unimplemented — [029](029-active-agents-panel/001-action.md). → **#574**

## Historical oddities (recorded, no action expected)

- PR #13 shows MERGED but its merge commit is not an ancestor of main; main was apparently
  reset on 2026-03-20 with no note — [006](006-startup-performance/001-action.md).
- #484 (foreground process-group detection fallback) was reverted the next day by direct
  commit `5b219791`; issue #495 (OSC 133;C) is the open successor — plain non-OSC-9;4
  commands still show no running spinner — [030](030-agent-status-detection/002-detection-scheduling.md).
- The docs/ manual (commit `49235800`) and a few early fixes landed as direct commits with
  no PR — [038](038-docs-agent-manual/001-action.md), [008](008-terminal-notifications/001-action.md).
- The outline used during backfill misattributed the 2026-05 UI refresh to Alex-ai-future;
  GitHub shows #326/#331 by abhi21git — docs follow GitHub — [033](033-ui-refresh-2026-05/001-action.md).
- The herdr "keep 3s hold" decision (2026-06-12/13) had no in-repo record before this
  backfill; it is now written down in [023](023-shelf-mode/000-plan.md) and
  [030](030-agent-status-detection/000-plan.md) from the maintainer's session notes.
- Release-shaped Makefile targets (`archive`, `install-release`) still depend on
  `build-ghostty-xcframework` rather than the artifact downloader (`ensure-ghostty`), so a
  cold machine source-builds (needs Xcode 26.3) instead of downloading —
  [041](041-ghosttykit-prebuilt-artifacts/001-action.md); unclear if deliberate. → **#576**
- CI runs `make lint` but never `make format-lint`, so the #503 failure class can recur —
  [016](016-dev-build-and-ci-workflow/001-action.md). → **#575**
