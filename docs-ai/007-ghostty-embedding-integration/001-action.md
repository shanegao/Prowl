# 007 — Ghostty Embedding Integration: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-21 | `prompt_surface_title` / `prompt_tab_title` → `NSAlert` rename dialogs (tab titles get `overrideTitle`/`clearTitleOverride` lock semantics on `TerminalTabManager`); `open_config` opens the resolved Ghostty config path | PR #26 |
| 2026-03-21 | `toggle_fullscreen` (native), `toggle_maximize` (`NSWindow.zoom`), `toggle_background_opacity` implemented in `GhosttySurfaceBridge.handleAppAction`; `toggle_window_decorations` explicitly excluded | PR #27 |
| 2026-03-21 | Filter `check_for_updates` from Ghostty palette items (native Sparkle updater is the real implementation) | PR #29 |
| 2026-03-21 | `quit` + `close_window` routed at `GhosttyRuntime` level; within the same PR, quit rerouted from `NSApp.terminate` to TCA `AppFeature.requestQuit` for confirm-before-quit | PR #31 |
| 2026-03-21 | Filter unsupported actions from palette: `new_window`, `close_all_windows`, `goto_window`, `toggle_tab_overview`, `inspector`, `show_gtk_inspector`, `show_on_screen_keyboard` | PR #32 |
| 2026-03-21 | Add `toggle_window_decorations` to the filter set (closes fork issue #21 together with #26/#27/#31) | PR #33 |
| 2026-04-24 → 2026-05-26 | Theme/appearance sync wave (#237, #242, #352) — see [002-theme-appearance-sync.md](002-theme-appearance-sync.md) | PRs #237, #242, #352 |
| 2026-05-09 | `onevcat/ghostty` fork branch `release/v1.3.1-patched` created (first patch: `ghostty_surface_pid`, for [030-agent-status-detection](../030-agent-status-detection/000-plan.md)); becomes the carrier for this entry's later ABI backport | ledger 2026-05-09 |
| 2026-05-13 → 2026-05-30 | Text & key-event safety wave (#286, #348, #374) — see [003-text-and-key-event-safety.md](003-text-and-key-event-safety.md) | PRs #286, #348, #374 |

## Outcome & current state (as of 2026-07-12)

- `supacode/Infrastructure/Ghostty/GhosttyRuntime+Callbacks.swift` — app-level action
  interception in `handleAction`: `GHOSTTY_ACTION_OPEN_CONFIG` (target `GHOSTTY_TARGET_APP`)
  → `openGhosttyConfig()` (path from `ghostty_config_open_path()`, opened via
  `/usr/bin/open -t`); `GHOSTTY_ACTION_QUIT` → `runtime.onQuit?()`;
  `GHOSTTY_ACTION_CLOSE_WINDOW` → `closeWindow(target:)` closing the originating surface's
  window (app-target is a no-op). Everything else falls through to the surface bridge.
- `supacode/App/supacodeApp.swift` wires `runtime.onQuit = { appStore?.send(.requestQuit) }`;
  `requestQuit` lives in `supacode/Features/App/Reducer/AppFeature.swift`.
- `supacode/Infrastructure/Ghostty/GhosttySurfaceBridge.swift` — `handleAppAction`
  implements `GHOSTTY_ACTION_TOGGLE_FULLSCREEN` / `TOGGLE_MAXIMIZE` /
  `TOGGLE_BACKGROUND_OPACITY` (the latter via `GhosttySurfaceView.toggleBackgroundOpacity()`);
  `GHOSTTY_ACTION_PROMPT_TITLE` invokes the `onPromptTitle` callback.
- `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift` —
  `handlePromptTitle(_:tabId:)` maps **both** `GHOSTTY_PROMPT_TITLE_SURFACE` and
  `GHOSTTY_PROMPT_TITLE_TAB` to the tab-title prompt (`promptTabTitle`), with an inline
  comment noting Prowl's single-window model and suggesting the surface variant could be
  dropped.
- `supacode/Features/CommandPalette/Reducer/CommandPaletteSupport.swift` —
  `filteredGhosttyActionKeys` (9 keys: `check_for_updates`, `new_window`,
  `close_all_windows`, `goto_window`, `toggle_tab_overview`, `toggle_window_decorations`,
  `inspector`, `show_gtk_inspector`, `show_on_screen_keyboard`), applied by
  `ghosttyCommandItems(_:)`. The palette itself was later rebuilt
  ([031-command-palette-architecture](../031-command-palette-architecture/000-plan.md));
  the filter survived the rebuild.
- Theme/appearance and text-safety state is detailed in the two amendment files; key
  files: `supacode/Infrastructure/Ghostty/GhosttyRuntime+ThemeFallback.swift`,
  `GhosttyRuntimeSupport.swift`, `supacode/App/GhosttyColorSchemeSyncView.swift`,
  `GhosttySurfaceView.swift` (`GhosttyEventText`, `stringFromGhosttyText`),
  `GhosttySurfaceView+EventTranslation.swift`, `MirroredTerminalKey.swift`.
- `ThirdParty/ghostty` submodule sits at `48365577c` on `release/v1.3.1-patched`
  (v1.3.1 + 4 fork patches); branch model and upgrade procedure:
  [ghostty-fork-sync.md](ghostty-fork-sync.md).

## Deviations from plan

- #26 shipped an `onOpenConfig` bridge callback; today `open_config` is handled entirely
  at the `GhosttyRuntime` level and the bridge's `GHOSTTY_ACTION_OPEN_CONFIG` case is a
  documented no-op ("Handled at app level"). The bridge callback no longer exists.
- #26 described distinct surface-title vs tab-title prompt flows; the current code
  collapses both prompt variants into the tab-title prompt (see above).
- #31's PR body describes `NSApp.terminate` routing, but its final commit
  (`4732780f`, "Route quit action through TCA requestQuit for confirm-before-quit")
  already replaced that with the TCA path — the body was not updated.
- #32 and #33 carry near-identical descriptions; #33's actual diff only added
  `toggle_window_decorations` to the filter set.

## Open questions

- `GHOSTTY_PROMPT_TITLE_SURFACE` support is marked in-code as a candidate for removal
  ("Consider removing GHOSTTY_PROMPT_TITLE_SURFACE support entirely") but the decision was
  never made; both variants still funnel into the tab prompt.
- The text-free-ABI fork patch (#286) is documented as droppable once the submodule
  reaches an upstream tag containing upstream commit `4803d58`; as of 2026-07-12 the
  submodule is still on v1.3.1-patched, so the patch remains load-bearing.
