# 038 — docs/ Agent-Facing Manual: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-07 | Initial agent-facing manual under `docs/` (20 files, ~1900 lines: index, overview, concepts, `components/`, `reference/`) | commit `49235800` |
| 2026-06-07 | `AGENTS.md` change-time rule + `sync-docs` audit skill with committed baseline (initially `.claude/skills/sync-docs/baseline.md`, starting at `49235800`) | PR #408 |
| 2026-06-07 | Word-by-word accuracy audit of the manual against `supacode`/`ProwlCLI` sources; 13 files corrected (wrong behavior claims, config values like `dockBounceMode = continuous`, `⌥⌃` glyph order), 7 audited clean | PR #409 |
| 2026-06-07 | Baseline relocated to `docs/.sync-meta.json` (dotfile JSON: `last_synced_commit` / `last_synced_date` / `note`) | PR #410 |
| 2026-06-07 | `sync-docs` hooked into the release skill as its own step: clean-tree check → docs sync + commit → version bump → tag | PR #411 |
| 2026-06-07 | Docs bundled into the app (`embed-docs` Makefile target → `Contents/Resources/docs`), "Ask Agent About Prowl" help sheet (localized en/zh-Hans/zh-Hant/ja), copyable agent prompt in repo `README.md` | PR #412 |

## Outcome & current state (as of 2026-07-12)

- **Manual**: `docs/README.md` (index, states the agent-first framing),
  `docs/overview.md`, `docs/concepts.md`, 16 component manuals under
  `docs/components/` and `docs/reference/keyboard-shortcuts.md` +
  `docs/reference/settings-fields.md`. The set has grown per the change-time
  rule since creation (e.g. `docs/components/workspaces.md` added 2026-06-09).
- **Sync machinery**: `.claude/skills/sync-docs/SKILL.md` (diff-driven,
  conservative rules intact); baseline lives in `docs/.sync-meta.json` —
  currently `last_synced_commit: 168d8e9c…`, `last_synced_date: 2026-07-10`
  (release prep), showing the loop is actually exercised.
- **Rules**: the one-line docs rule is present in both `AGENTS.md` and
  `CLAUDE.md` (`## Rules`: update the matching `docs/` file when changing
  user-facing behavior; run `sync-docs` for a full audit).
- **Release hook**: `.claude/skills/release/SKILL.md` runs `sync-docs` against
  `docs/.sync-meta.json` before bump + tag, as designed. The release process
  itself is documented in
  `docs-ai/001-fork-bootstrap-and-release-pipeline/release-runbook.md`.
- **Bundling**: `Makefile` `embed-docs` target, wired into
  `build-app`/`archive`/`test`; runtime resolution in
  `supacode/Support/SupacodePaths.swift` (`bundledDocsURL`,
  `bundledDocsReadmePath`, `bundledDocsDirectoryPath`).
- **Help action**: `supacode/Features/Help/AskAgentHelpPresenter.swift`,
  `AskAgentHelpPrompt.swift` (system-locale → language key with
  Hans/Hant disambiguation), `AskAgentHelpView.swift`; wired in
  `supacode/App/supacodeApp.swift` (sheet + macOS Help menu item) and
  `supacode/Features/Repositories/Views/SidebarFooterView.swift` (sidebar Help
  menu). Tests: `supacodeTests/AskAgentHelpPromptTests.swift`.
- **README prompt**: repo `README.md` "Meet Prowl through your agent" section
  with a copyable prompt pointing at the raw GitHub `docs/README.md`, plus a
  pointer to Help → Ask Agent About Prowl for the bundled, localized variant.
- **Division of labor with this doc set**: `docs/` documents current behavior
  for users and their agents; `docs-ai/` (this system) records history and
  decisions — see [002-docs-ai-follow-on.md](002-docs-ai-follow-on.md).

## Deviations from plan

None known. The manual itself landed as a direct commit on `main`
(`49235800`) rather than via a PR; the five PRs the same day built the
maintenance, release, and distribution machinery around it.

## Open questions

None.
