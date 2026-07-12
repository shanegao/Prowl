# 040 — Automatic Open In: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-19 | Code-host opening fallback: generic `GitRemoteWebInfo` parsing, open PR when present else repository homepage, `supportsCodeHost` capability split from PR support (commits `d62827e6`, `9822ae62`, `ed1d2f69`) | PR #217 |
| 2026-04-20 | Code-host actions labeled with the detected host's display name ("Open on GitLab", falling back to "Open on Code Host") | commit `afdda3e0` (direct to main) |
| 2026-05-08 | Android Studio open action via the JetBrains CLI-arguments path (`com.google.android.studio`); port of upstream #262 from the 2026-05-08 review batch | PR #264 |
| 2026-06-13 | Project-aware Automatic Open In: `WorktreeProjectKind` detection, specialist-first resolution, new apps (iTerm2, Sublime Text, Tower, Rider, GoLand, CLion, PhpStorm, RubyMine), menu-icon caching, "Automatic" menu entry to clear a pinned app (commits `e423d2d8`, `2940a94e`, `e8d8ff48`, `3a24efce`) | PR #439 |
| 2026-07-08 | Zed Preview, IntelliJ IDEA EAP, Nova ported from upstream; IDEA EAP joins android/java project-kind fallbacks | PR #542 — see [002-upstream-editor-ports.md](002-upstream-editor-ports.md) |

## Outcome & current state (as of 2026-07-12)

**Open-app model.** `supacode/Domain/OpenWorktreeAction.swift` is a 39-case enum
covering editors, terminals, git clients, Finder, Xcode, and `$EDITOR`. Ordering lives
in `editorPriority` / `terminalPriority` / `gitClientPriority`, composed into
`defaultPriority` (resolution order) and `menuOrder` (dropdown order, filtered by
`isInstalled`). JetBrains-family apps (androidStudio, clion, goland, intellij,
intellijEAP, phpstorm, pycharm, rider, rubymine, rustrover, webstorm) open via
`NSWorkspace.OpenConfiguration.arguments`; the rest via
`open(_:withApplicationAt:configuration:)`. Menu icons are pre-resized to 16×16 and
cached in a `@MainActor` hit-only cache keyed by bundle identifier.

**Project detection.** `supacode/Domain/WorktreeProjectKind.swift` defines 11 kinds
with `detect(at:fileManager:)` (single shallow listing, most-specific marker first,
`package.json` last) and `preferredActions` (apple → Xcode; android → Android Studio,
IntelliJ, IDEA EAP; dotnet → Rider; java → IntelliJ, IDEA EAP; golang → GoLand; rust →
RustRover; cpp → CLion; php → PhpStorm; ruby → RubyMine; python → PyCharm; web →
WebStorm). `OpenWorktreeAction.preferredDefault(for:isInstalled:)` prepends these to
`defaultPriority`; final fallback is Finder.

**Reducer wiring.** `fromSettingsID(_:defaultEditorID:workingDirectory:)` is called
from three sites: `supacode/Features/App/Reducer/AppFeature+Support.swift` (shared
helper used by `worktreeSettingsLoaded` and the Canvas focus path) and two sites in
`supacode/Features/App/Reducer/AppFeature.swift` (including `settingsChanged`).
`openActionResetToAutomatic` clears a pinned per-repo selection; the toolbar UI lives in
`supacode/Features/Repositories/Views/WorktreeDetailView.swift`,
`WorktreeDetailToolbarViews.swift`, and `OpenWorktreeActionMenuLabelView.swift` (no
per-render icon resize).

**Code host.** `supacode/Clients/Git/GitRemoteWebInfo.swift` and
`GitClient.parseRepositoryWebInfo` in `supacode/Clients/Git/GitClient.swift` handle
GitHub/GitLab/SSH-with-port remote shapes; `Repository.Capabilities.supportsCodeHost`
(`supacode/Domain/Repository.swift`) gates the action; the open-PR-or-homepage fallback
is in `supacode/Features/Repositories/Reducer/RepositoriesFeature+GithubIntegration.swift`
via `supacode/Clients/Workspace/OpenURLClient.swift`.

**Tests.** `supacodeTests/WorktreeProjectKindTests.swift` (marker→kind matrix,
precedence, nil cases against real temp directories),
`supacodeTests/OpenWorktreeActionTests.swift` (bundle IDs, menu order covers all cases,
heuristic resolution with injected `isInstalled`),
`supacodeTests/AppFeatureDefaultEditorTests.swift` (end-to-end reducer resolution),
`supacodeTests/GitRemoteInfoTests.swift` (remote parsing).

**Docs.** Behavior documented in `docs/components/repositories-and-worktrees.md`
(Automatic selection, pinning, detection) and `docs/reference/settings-fields.md`
(`defaultEditorID` / `openActionID`, `auto` semantics).

## Deviations from plan

None known. Note for provenance: many editor cases (Windsurf, VSCodium, Antigravity,
VS Code Insiders, Warp, WebStorm, PyCharm, IntelliJ, RustRover) predate this entry —
they were inherited from upstream before/alongside the fork and are not part of this
entry's PRs.

## Open questions

- `WorktreeProjectKind` classifies any Gradle project as `android`, so a pure JVM
  Gradle project on a machine with Android Studio installed resolves to Android Studio
  rather than IntelliJ. The fallback chain covers machines without Android Studio, but
  the kind name and mapping conflate "Gradle" with "Android" by design.
