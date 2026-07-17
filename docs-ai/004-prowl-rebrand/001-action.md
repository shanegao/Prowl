# 004 — Prowl Rebrand: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-02-28 | Groundwork: per-repo settings files moved from repo roots into `~/.supacode/repo/<name>/` with legacy migration | commit `ea9259f8` |
| 2026-03-17 | User-facing rebrand: display strings, bundle ID `com.onevcat.prowl`, UTType `com.onevcat.prowl.ghosttySurfaceId`, `~/.supacode`→`~/.prowl` migration (move), `supacode.json`→`prowl.json` fallback chain, upstream Sparkle feed + EdDSA key removed | PR #3 (`5f7d84ae`) |
| 2026-03-17 | AGENTS.md rule: PRs always target the fork, never upstream | commit `962ba621` |
| 2026-03-17 | PreToolUse hook blocking `gh pr create` without an explicit fork `--repo` | commit `99705600` |
| 2026-03-17 | New Prowl cat app icon (all AppIcon sizes) + test assertions updated to `prowl.json` | commit `dfd04ef7` |
| 2026-03-17 | `PRODUCT_NAME` renamed `supacode`→`Prowl`; then `TEST_HOST` fixed to `Prowl.app`, explicit `PRODUCT_MODULE_NAME = supacode`, shared xcscheme added | commits `83113df6`, `5676418d` |
| 2026-03-18 | Hook updated to also accept `onevcat/Prowl` (GitHub repo renamed from `onevcat/supacode`) | commit `3d72fb7c` |
| 2026-03-20 | Migration changed from `moveItem` to `copyItem` to preserve `~/.supacode` (fork issue #16) | PR #19 — see [002](002-migration-copy-not-move.md) |
| 2026-04-13 | Hook and AGENTS.md drop the old `onevcat/supacode` name; `onevcat/Prowl` is the only valid PR target | commit `fd637b14` |

## Outcome & current state (as of 2026-07-12)

- **Identity**: `supacode.xcodeproj/project.pbxproj` has
  `PRODUCT_BUNDLE_IDENTIFIER = com.onevcat.prowl`, `PRODUCT_NAME = Prowl`, and
  `PRODUCT_MODULE_NAME = supacode` for the Release configuration. Debug builds later
  gained a distinct identity (`com.onevcat.prowl.debug`, `PRODUCT_NAME = "Prowl Debug"`)
  so a dev build can run alongside the installed app — that is entry
  [016](../016-dev-build-and-ci-workflow/000-plan.md) work, not part of this rebrand.
  The main window title and menu strings use "Prowl" (`supacode/App/supacodeApp.swift`).
- **Paths**: `supacode/Support/SupacodePaths.swift` — `baseDirectory` copy-migrates
  `~/.supacode` → `~/.prowl` on first access (`copyItem`, per #19);
  `appSupportDirectory` is `~/Library/Application Support/com.onevcat.prowl`.
- **Settings files**: `repositorySettingsURL` → `prowl.json`,
  `userRepositorySettingsURL` → `prowl.onevcat.json`, with legacy fallbacks
  `supacode.json` / `supacode.onevcat.json` still honored (and rewritten to the new name
  on load) in `supacode/Features/Settings/BusinessLogic/RepositorySettingsKey.swift` and
  `UserRepositorySettingsKey.swift` (the latter renamed from
  `OnevcatRepositorySettingsKey.swift` in later refactoring).
- **Logging subsystem**: `supacode/Support/SupaLogger.swift` uses
  `Bundle.main.bundleIdentifier ?? "com.onevcat.prowl"`; `make log-stream` filters on
  `com.onevcat.prowl`.
- **Sparkle**: `supacode/Info.plist` again contains `SUFeedURL` — now pointing at the
  fork's own appcast (`https://github.com/onevcat/Prowl/releases/latest/download/appcast.xml`)
  with the fork's `SUPublicEDKey`. The rebrand removed the upstream feed; the fork feed
  was restored by the release pipeline
  ([001](../001-fork-bootstrap-and-release-pipeline/000-plan.md)).
- **Guard hook**: `.claude/hooks/block-upstream-pr.sh` is active via the `PreToolUse`
  Bash matcher in `.claude/settings.json`; it blocks any `gh pr create` that does not
  explicitly pass `--repo`/`-R` `onevcat/Prowl`. `AGENTS.md` carries the matching prose
  rule ("PRs must target `onevcat/Prowl` … never the upstream `supabitapp/supacode`").
- **Module naming**: source directory, scheme, and module remain `supacode` — paths like
  `supacode/App/...` are correct and intentional.

## Deviations from plan

- The migration strategy described in #3 (move `~/.supacode` wholesale) survived only
  three days; #19 replaced it with copy after fork issue #16. Documented as amendment
  [002](002-migration-copy-not-move.md).
- #3 described the bundle ID change as complete, but a distinct Debug bundle ID was
  introduced much later (entry 016); at rebrand time Debug and Release shared
  `com.onevcat.prowl`.

## Open questions

- `SupacodePaths.originalLegacyRepositorySettingsURL(for:)` and
  `originalLegacyUserRepositorySettingsURL(for:)` (repo-root `supacode.json` /
  `supacode.onevcat.json` locations, `supacode/Support/SupacodePaths.swift:290-297`) are
  defined but referenced nowhere in the app, CLI, or tests — the repo-root fallback read
  appears to have been dropped from the load chain at some point, leaving these as dead
  code. Candidates for removal.
- `Info.plist` sets `SUEnableAutomaticChecks` to `false` even though the fork feed is
  configured; whether background update checks are driven elsewhere is a question for
  entry [021](../021-sparkle-update-ux/000-plan.md), noted here only because the key
  originates in this file.
