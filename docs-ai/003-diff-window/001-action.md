# 003 — Diff Window: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-06 | Git operations for diff (name-status, untracked paths, show file at HEAD); diff window with file tree + YiTong `DiffView`; diff badge click, `Cmd+]` shortcut, Show Diff menu item; preload all file contents on open; toolbar (sidebar toggle, split/unified picker), `Cmd+W` close, frame persistence | PR #1 (commits `0d03848`, `09194c4`, `59dc4f6`, `5850576`, `8985fc2`) |
| 2026-03-19 | Unicode/Chinese filenames: pass `-c core.quotePath=false` to `git diff --name-status` and `git ls-files --others`; unit tests | PR #10 (commit `1b32a26`, fork issue #9) |
| 2026-03-23 | YiTong pinned to 0.2.0 (`upToNextMajorVersion`), optimized web bundle: −6.6 MB bundle, −7 MB .app | PR #45 |
| 2026-06-14 | Configurable external diff tools (Built-in / Hunk / FileMerge / Kaleidoscope / Custom Command) behind one launcher | PR #449 → [002](002-external-diff-tools.md) |
| 2026-07-03 | Fix stale cache writes after cancellation; testable `DiffWindowState` (injected git closures, pure reconciliation statics); render spinner; 150 ms select debounce | PR #529 → [003](003-render-pipeline-hardening.md) |
| 2026-07-03 | Render-failure recovery via `renderGeneration` view identity; leading-edge debounce (first click immediate) | PR #536 → [003](003-render-pipeline-hardening.md) |
| 2026-07-03 | Shared `Debouncer`/`KeyedDebouncer` helpers; render phase folded into `RenderState` enum | PR #537 → [003](003-render-pipeline-hardening.md) |
| 2026-07-08 | Diff window follows the app's appearance setting instead of the system appearance | PR #540 → [004](004-appearance-follows-app.md) |

## Outcome & current state (as of 2026-07-12)

The feature lives in `supacode/Features/DiffView/`:

- `DiffWindowState.swift` — `@Observable @MainActor` store: changed-file list,
  per-file `DiffDocument` cache, `RenderState` enum (`idle`/`rendering`/
  `failed`), `renderGeneration` retry counter, leading-edge select debounce via
  an injected `Debouncer`, and pure static reconciliation helpers
  (`evictedCache`, `resolvedSelection`). Git access is injected as closures
  (live implementations use `GitClient`).
- `DiffWindowManager.swift` — singleton `NSWindow` host:
  `setFrameAutosaveName("DiffWindow")`, local `keyDown` monitor for `Cmd+W`,
  refresh-on-focus, and `NSAppearance.from(_:)` applied from the app's
  appearance setting.
- `DiffWindowContentView.swift` — `NavigationSplitView` (file list sidebar +
  YiTong `DiffView`), `@AppStorage("diffViewStyle")` split/unified picker,
  sidebar toggle (toolbar button + `focusedSceneAction`), render
  spinner/error overlay, `.id(state.renderGeneration)` on the `DiffView`, and
  `WindowAppearanceSetter` for live appearance updates.
- `DiffChangedFile.swift` — name-status parsing model.

Supporting pieces:

- `supacode/Clients/Git/GitClient.swift` — `diffNameStatus(at:)`,
  `untrackedFilePaths(at:)`, `showFileAtHEAD(_:in:)`, all with
  `-c core.quotePath=false`.
- `supacode/Domain/ExternalDiffTool.swift` and
  `supacode/Clients/ExternalDiff/` (`ExternalDiffToolClient.swift`,
  `ExternalDiffSnapshotClient.swift`) — the tool setting and launcher; the
  Built-in branch calls `DiffWindowManager.shared.show(...)`.
- `supacode/Support/Debouncer.swift` — `Debouncer` + `KeyedDebouncer`, shared
  with `WorktreeInfoWatcherManager` and `PullRequestRefreshCoordinator`.
- YiTong is pinned `upToNextMajorVersion: 0.2.0` in `supacode.xcodeproj`
  (resolved at 0.2.0).
- Tests: `supacodeTests/DiffWindowStateTests.swift`,
  `DebouncerTests.swift`, `ExternalDiffToolTests.swift`,
  `GitClientDiffPathEncodingTests.swift`.
- User-facing behavior is documented in `docs/components/diff-view.md`.

## Deviations from plan

- The original `Cmd+]` shortcut no longer exists. Show Diff is a config-driven
  keybinding (`show_diff` in `supacode/App/AppShortcuts.swift`, default `⌘⇧Y`)
  after the keybinding system landed
  ([012-keybinding-system](../012-keybinding-system/000-plan.md)).
- "Preload all on open" was refined by the July wave: the cache now survives
  `refresh()` (with eviction of disappeared files) instead of being rebuilt
  from scratch, and per-file documents stream into the cache as they complete.
- The diff badge / Show Diff entry points no longer open the window directly;
  they route through `ExternalDiffToolClient`, which dispatches to the built-in
  window or an external tool (amendment 002).

## Open questions

None.
