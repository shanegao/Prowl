# 2026-07-06 Upstream Sync Batch — Investigation Record & Decisions

> Historical record of entry 017. Kept verbatim from `doc-onevcat/plans/2026-07-06-upstream-sync-batch.md` (migrated 2026-07-12).

Scope: upstream `supabitapp/supacode` commits after baseline `1d888dbc` (2026-06-05, post-v0.10.2)
through `bcbc4059` (2026-07-06), spanning v0.10.3 → v0.10.5. 70 commits total.

This document records the per-commit verdicts from the 2026-07-06 investigation round and the
resulting fork actions. Each "port" theme lands as its own PR referencing this plan. The
`docs-ai/017-upstream-sync-process/upstream-ledger.md` baseline should be advanced to `bcbc4059` only after the PRs from this
batch have merged.

## Verdict: already fixed / already present in fork (no action)

| Upstream | Fork equivalent | Notes |
| --- | --- | --- |
| `84be657a` #517 duplicate WorktreeID crash | fork `fa187be4` (2026-06-30) | 1:1 functional equivalent incl. same-named test in `WorktreeInfoWatcherManagerTests` |
| `0494b1bf` #480 refuse repo with duplicate worktree paths | fork `06c0bd0d` (2026-05-25) | Fork dedupes at `GitClient.worktrees` boundary (first-wins) instead of refusing; no crash exposure. Upstream's stricter "surface corruption" UX noted as possible future feature |
| `03dd26f4` #566 terminal focus after command palette closes | fork `52786b1d`, `6b7f6884` | Fork restores terminal focus on all three dismissal paths via `restoreCommandPaletteTerminalFocusEffect`; upstream's NSPanel restructure unnecessary. Bundled feature (⌘1–9 tab switching while sidebar focused) noted as optional future item — would conflict with palette's ⌘1–5 quick-activate |
| `3be32880` #524 Clone Repository to Local Folder | fork PR #520 (2026-06-27) | Fork-native clone flow predates upstream's. Missing-vs-upstream polish (streamed progress %, branch/depth options, File-menu entry) = optional enhancements, not a port |
| `7e7b04d9` #454 memoize terminal zoom | fork PRs #81/#121 (2026-03/04) | Fork syncs per keypress via stock `ghostty_surface_inherited_config` — no ghostty patch needed; strictly more robust than upstream's switch/quit sampling |
| `a8cab19e` #409 Dismiss All not clearing popover | n/a | Bug mechanism (stale TCA projection mirror) doesn't exist — fork popover reads `@Observable` state directly |
| `5ac547ca` #513 build warnings | n/a | None of the five warning sites exist in the fork |
| `e409e81a` GoLand, `bca5441e` Rider, `bcbc4059` PhpStorm | fork `e423d2d8` (2026-06-13) | Same bundle ids; already mapped in `WorktreeProjectKind` project detection |

## Verdict: port (PRs in this batch)

| Theme | Upstream refs | Fork PR | Notes |
| --- | --- | --- | --- |
| gh detection & login-shell hardening | `70786d2d` #410, `82c101c1` #460, `4e0aeb54` #482, `ad4db32a` #535 | onevcat/Prowl#541 | All four defects present verbatim in fork's `ShellClient` / `GithubCLIExecutableResolver` |
| Editor additions | `3886a052` Zed Preview #447, `c135b9d6` IDEA EAP #496, `566bf4c4` Nova #506 | onevcat/Prowl#542 | Only these 3 missing. Added to fork's `OpenWorktreeAction` shape (upstream's `c38c325d` OpenTarget refactor NOT adopted — see skips). IDEA EAP joins android/java `preferredActions` |
| TERM_PROGRAM override | `7a5c9ab1` #458 | onevcat/Prowl#543 | Fork emits `TERM_PROGRAM=prowl` + `TERM_PROGRAM_VERSION` via a static runtime-override conf loaded in both `loadConfig()` and `applyRuntimeOverridesIfNeeded()` (fork has no upstream-style bundled-overrides file) |
| Preserve symlinked JSON config on write | `99d27826` #478 | onevcat/Prowl#544 | Fork's `SettingsFilePersistence` + `RepositoryLocalSettingsPersistence` both use `.atomic` writes that replace symlinks. Fork decision: also route repo-local `~/.prowl/repo/**` files through the symlink-preserving writer (upstream's untrusted-repo exception doesn't apply — fork stores them under `~/.prowl`, user-owned). Write-only port; dropped upstream's unused `moveAside` |
| Notification sound picker | `ce03d3c3` #511 | onevcat/Prowl#545 | Adapted to fork single-target layout. Decision: default & legacy-`true` migration → `.supacodeClassic` (keeps current notification.wav behavior) instead of upstream's `.hero`. Raw values kept byte-identical to upstream for sync compat |
| Mute notifications for viewed surface | `f15420ce` #562 | onevcat/Prowl#546 | Real gap: fork posts banner/sound/bounce regardless of whether the originating surface is focused & visible. Ported with adaptation (`isViewed` threaded through the event pipeline, `muteNotificationsForActiveSurface` default-on). **Stacked on #545** (retargets to main when #545 merges) |
| Searchable base-ref filter | `e37bebad` #387/#411 | **deferred → Linear CLAW-99** | Fork already has flat base-ref `Picker`s so upstream's original nested-menu pain is avoided; upstream's full widget needs tree infra (`BranchMenuNode`/`GitBranchInventory`) the fork lacks and a bespoke windowed list that wants interactive UI iteration. Recommended fork approach (pure filter helper + inline result list) captured in the issue |

## Verdict: skipped this round (decision recorded)

- **Window appearance rewrite** `35f84d87` #570 (per-surface backgrounds, terminal-driven window
  appearance) + **status inspector** `a9b35a6b` #577 — the fork is satisfied with its current window
  appearance and has its own PR-state tri-state work; both rewrites conflict with fork-only chrome
  (`chromeBackgroundColor`) and notification/PR UI. Decision: skip; do not revisit unless upstream
  builds must-have features on top of these.
- **Keybinding conflict zone** `dccf58fe` #459 + `cb5670f8` #461 (terminal bindings vs non-remappable
  macOS menu built-ins), `7fbeac56` #416 (worktree-selection chord overrides) — touches
  `GhosttySurfaceView.performKeyEquivalent`, where the fork has custom routing. No fork-reported bug
  today. Skip; revisit if users hit ⌘W/⌘Q/chord conflicts.
- **OSC 3008 agent presence track** `548609ab` #390, `0e26cbfe` #392, `23ae4ac6` #394 — upstream
  moved agent presence onto a patched-ghostty OSC 3008 channel. Fork's task status already rides
  Ghostty's progress OSC with its own patched-ghostty fork. Architecture watch item only.
- **Toolchain self-diagnosis** `23f8b19d` #468 — fork ships prebuilt GhosttyKit vendor downloads
  (2026-06-14 plan) and intends to track libghostty upstream commits later; not needed.
- **zmx track** `558d4d81`/`4a7ddd01` (zmx fork pin), `50350b4b` #453 (zmx client recovery),
  `39e4b9f4` #457 (blocking-script profile skip) — fork has no zmx; consistent with earlier rounds.
- **Hook-driven agent integrations** `7fa190f9` Hermes #537, `0d77e858` Kimi #512, `ed69392b`
  Copilot CLI #455, `05eadd95` OpenCode #412, `73a2e616` #557 — rely on upstream settings/hook
  modules the fork doesn't carry.
- **Upstream CLI** `b3dcf973` #556 (completion-based socket acks) — fork has its own `prowl` CLI
  transport.
- **Release/CI housekeeping** — v0.10.3–v0.10.5 bumps, `185d2fce` #486, `62807127`/`b1cd23c5`
  telemetry xcconfig, `52e52c4b` parallel Actions, `2df2b75a` #393 CI restructure,
  `74d95921`/`7eb572f2`/`d6de7e3f` checksums, `4473474c` agents.md — fork uses local notarized
  date-based releases.
- **`c38c325d` #423 generalize worktree open targets** — upstream refactor (OpenTarget/OpenBehavior,
  editors moved to shared module, Xcode workspace-file search, Zed bundled-CLI open). Parallel
  evolution: fork's `WorktreeProjectKind` detection is a capability upstream lacks. Skip the refactor;
  editor cases added in fork shape. Upstream's Xcode `.xcworkspace` preference and Zed CLI open noted
  as possible future enhancements.
- **UI polish not carried this round**: `a40c01a5` #539 hover help (fork already tooltips its
  controls; sidebar status icons can gain `.help` opportunistically), `a10e1158`/`87341e9a` glyph
  opacity, `22d315eb` #525 light-mode selector, `7a878d87` #433 hit targets, `67a3c5b5` #427 badge
  tint, `2f3a105b` #565 Settings window Space, `faa679c4` #456 hoisted-worktree grouping (depends on
  upstream sidebar sections the fork skipped), `ce03d3c3`-adjacent `f15420ce` handled above. These are
  low-risk cherry candidates for a future polish pass if symptoms are observed in the fork's UI.

## Remote SSH track (architecture decision ①)

`88e50398` #407 + `adb02054` #415, `ef255697` #452, `8696d619` #462, `a04597d4` #463,
`73cc6a4b` #502, `b61bbe0e` #574. Total ≈ +12k/−3.7k lines (~45% tests).

Key findings: zmx is a **soft** dependency (bare-ssh degradation paths exist; the #574 reconnect loop
is plain `/bin/sh`); the #462 `SidebarPersistenceMigrator` targets files the fork doesn't have, so the
fork could adopt the final self-descriptive id format (`[user@]host[:port]/path`) from day one with
zero user-facing migration. The real cost is hand-translating upstream's monolithic
`RepositoriesFeature` changes (4,680 lines in one file) into the fork's 10+ extension files plus the
branded `RepositoryID`/`WorktreeID` identity refactor. Difficulty: **L** (XL with full branded-id +
zmx resilience). Decision: not now; tracked as **Linear CLAW-98** (CLAW team, project Prowl) with
staged adoption options (MVP → editors → reconnect loop).

## PR checklist for this batch

1. onevcat/Prowl#541 — gh detection & login-shell hardening ✅ opened
2. onevcat/Prowl#542 — editor additions (Zed Preview, IDEA EAP, Nova) + project-detection mapping ✅ opened
3. onevcat/Prowl#543 — TERM_PROGRAM=prowl override ✅ opened
4. onevcat/Prowl#544 — symlink-preserving settings writes ✅ opened
5. onevcat/Prowl#545 — notification sound picker ✅ opened
6. onevcat/Prowl#546 — mute notifications for the viewed surface (stacked on #545) ✅ opened
7. Searchable base-ref filter → deferred to **Linear CLAW-99**
8. Remote SSH track → deferred to **Linear CLAW-98**
9. This plan document (its own docs PR)

After all PRs merge: advance `docs-ai/017-upstream-sync-process/upstream-ledger.md` baseline to `bcbc4059` (2026-07-06) with a
new dated entry summarizing this round (ported PRs, skipped tracks, and the two Linear follow-ups).
