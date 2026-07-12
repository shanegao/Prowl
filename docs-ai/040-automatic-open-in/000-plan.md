# 040 — Automatic Open In: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-06-13 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #439 (anchor), precursors #217, #264; later port #542 |
| **Sources** | PR #217/#264/#439/#542 descriptions, change-list 2026-05-08 and 2026-07-09 review batches (now `../017-upstream-sync-process/upstream-ledger.md`) |
| **Related** | [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md), [028-pr-status-tracking](../028-pr-status-tracking/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md) (#509 canvas toolbar code-host actions), `docs/components/repositories-and-worktrees.md`, `docs/reference/settings-fields.md` |

## Background

This entry covers how a worktree is opened *outside* Prowl — in an editor, terminal,
git client, or the repository's code host in the browser.

Two precursor gaps were fixed before the anchor work:

- **Code host was PR-gated and GitHub-only** (#217, 2026-04-19). The "open on GitHub"
  shortcut assumed a pull request existed and a GitHub-shaped remote; with no PR the
  action silently did nothing, and GitLab-style remotes could not open anything.
- **Android Studio was missing** from the open-app list (#264, 2026-05-08, port of
  upstream #262 `6fff0218` from the 2026-05-08 review batch).

The anchor problem (#439): the toolbar **Open In** control's *Automatic* mode simply
picked the first installed app from a fixed priority list (Cursor → Zed → VS Code → …)
regardless of what the repository contained — a Swift package opened in Cursor even when
Xcode was the obvious choice. Several mainstream apps (iTerm2, Sublime Text, Tower, most
of the JetBrains family) were also unsupported, and toolbar redraws paid a repeated
app-icon rasterization cost.

## Goals

- Make the `auto` open action project-aware: detect the project ecosystem from the
  worktree's contents and prefer a specialist app, falling back to the generic priority.
- Keep explicit selections untouched: a per-repo `openActionID` or global
  `defaultEditorID` must be respected exactly as before; project awareness applies only
  to the `auto` path.
- Expand the supported app set (JetBrains family, iTerm2, Sublime Text, Tower).
- Fix the measured per-render icon cost in the toolbar without adding caches that hide
  newly installed apps.
- (Precursor #217) make the code-host action host-generic and PR-optional: open the PR
  when one exists, otherwise the repository homepage.

### Non-goals

- PR management actions stay GitHub-only (#217 broadened only the *open in browser*
  action to generic hosts).
- No persisted detection cache; project detection is recomputed from a single shallow
  directory listing at resolution time.

## Design / Approach

Reconstructed from the PR #439 description.

**Project detection.** New `WorktreeProjectKind` (`supacode/Domain/WorktreeProjectKind.swift`)
detects the project type from one shallow listing of the worktree's top-level entries,
ordered from most to least specific marker: `.xcodeproj`/`.xcworkspace`/`Package.swift`/
`Project.swift` → **apple**, Gradle files → **android**, `.sln`/`.csproj` → **dotnet**,
`pom.xml` → **java**, `go.mod` → **golang**, `Cargo.toml` → **rust**, `CMakeLists.txt` →
**cpp**, `composer.json` → **php**, `Gemfile` → **ruby**, Python manifests → **python**,
and `package.json` deliberately last → **web** (almost any repo carries one for tooling).

**Specialist-first resolution.** Each kind maps to `preferredActions` tried before the
generic `OpenWorktreeAction.defaultPriority` (apple → Xcode; android → Android Studio,
then IntelliJ; dotnet → Rider; golang → GoLand; rust → RustRover; web → WebStorm; …),
falling back seamlessly when the specialist is not installed. The worktree's
`workingDirectory` is threaded through all three reducer resolution sites
(`worktreeSettingsLoaded`, Canvas focus, `settingsChanged`) into
`OpenWorktreeAction.fromSettingsID(_:defaultEditorID:workingDirectory:)`. Picking an app
from the dropdown still pins it for the repo; an **Automatic** menu entry (added inside
the PR, commit `e8d8ff48`) clears the pin back to project-aware selection.

**New apps.** iTerm2, Sublime Text, Tower, plus the remaining JetBrains IDEs — Rider,
GoLand, CLion, PhpStorm, RubyMine — opened via the existing JetBrains CLI-arguments path
(`NSWorkspace.OpenConfiguration.arguments`) rather than Apple Events.

**Icon performance (measure first).** Benchmarks showed
`urlForApplication(withBundleIdentifier:)` at ~3.5µs warm — not a bottleneck, left
uncached so newly installed apps appear immediately. The real waste was
`icon(forFile:)` (~1.1ms cold) plus a `lockFocus` rasterizing resize on every toolbar
redraw. Menu icons are now pre-resized once and cached (cache stores hits only), and the
per-render resize was removed from `OpenWorktreeActionMenuLabelView`.

**Code-host fallback (#217).** Generic remote parsing
(`GitClient.parseRepositoryWebInfo` → `GitRemoteWebInfo` with host, repository path, and
optional port) replaces GitHub-specific parsing; the action opens the PR when one exists
and otherwise the repository homepage. A dedicated `supportsCodeHost` capability was
split from `supportsPullRequests` so non-GitHub remotes surface the browser action
without implying PR support.

## Alternatives & decisions

- **Heuristic detection over configuration.** Project kind is inferred from marker
  files rather than a new setting; explicit per-repo/global selections remain the
  configuration surface and always win over the heuristic.
- **No LaunchServices caching.** Installed-app lookups were measured cheap and left
  uncached so a newly installed editor shows up without invalidation; only resolved
  icons are cached.
- **Upstream `c38c325d` #423 OpenTarget/OpenBehavior refactor rejected** (2026-07-09
  review batch): new editors are added as cases in the fork's existing enum shape
  instead of adopting upstream's restructure — see [002-upstream-editor-ports.md](002-upstream-editor-ports.md).
- **`settingsID` raw values follow upstream literals** (`zed-preview`, `intellijEAP`,
  `nova`) so persisted selections stay portable across syncs; `intellijEAP` knowingly
  breaks the fork's kebab-case convention.
- **Host-generic open, GitHub-only PR management** (#217): broadening stopped at the
  browser action; PR state tracking stayed GitHub-scoped (see 028).

## Amendments

- Updated 2026-07-08: Zed Preview / IntelliJ IDEA EAP / Nova ported from upstream, with
  fork-specific project-kind integration — see [002-upstream-editor-ports.md](002-upstream-editor-ports.md)
