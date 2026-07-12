# 015 — Amendment: Repo-wide Large Swift File Split (PR #403)

## Context

Two months of feature work after the #131 decomposition, several other source files
had grown to the same unmanageable size the original `RepositoriesFeature.swift` once had
(`WorktreeTerminalState.swift` ~1,850 lines, `GhosttySurfaceView.swift` ~1,900 lines,
`RepositoriesFeature.swift` itself back near 2,500 lines of remaining core logic). PR #403
(merged 2026-06-07) applied the same discipline repo-wide: non-test sources stay under
1,000 lines, split along behavior-preserving extension/helper boundaries.

## Change

50 files changed (+11,822/−11,466); pure code motion plus lint cleanup of the
`AppFeature` helper switches the split introduced. The major splits:

| Area | Extracted files |
| --- | --- |
| Repositories reducer | `RepositoriesFeature+CoreReducer.swift`, `+RepositoryLoading.swift`, `+Selection.swift`, `+StateQueries.swift`, `+WorktreeState.swift` |
| App reducer | `AppFeature+CommandPalette.swift`, `+Support.swift`, `+TerminalEvents.swift` |
| Command palette | `CommandPaletteFuzzyScorer.swift`, `CommandPaletteSupport.swift` |
| Terminal state | `WorktreeTerminalState+AgentDetection.swift`, `+CLI.swift`, `+LayoutSnapshot.swift`, `+Notifications.swift`, `+Surfaces.swift`, `+TabIcons.swift` |
| Ghostty runtime/surface | `GhosttyRuntime+Callbacks.swift`, `+ThemeFallback.swift`, `GhosttyRuntimeSupport.swift`, `GhosttySurfaceView+Accessibility/…/+TextInput.swift`, `GhosttySurfaceScrollView.swift`, `CLIKeySpec.swift` |
| Canvas | `CanvasSupportViews.swift`, `CanvasView+Focus.swift` |
| Settings | `RepositorySettingsCustomCommandsView.swift`, `RepositorySettingsSupportingViews.swift` |
| Git/GitHub clients | `GitClientShellHelpers.swift`, `GitClientTypes.swift`, `GithubCLIExecutableResolver.swift`, `GithubCLIModels.swift` |

For this entry's feature specifically, `RepositoriesFeature.swift` shed another ~2,460
lines: the residual root switch became `reduceCore` in
`RepositoriesFeature+CoreReducer.swift`, and loading/selection/state-query helpers moved
into their own extensions.

## Refs

- PR #403 (merge `50327959`, 2026-06-07)

## Current state

All extracted files listed above exist in the working tree. The extraction of
`GitClientTypes.swift` in this PR is what gave #426 its landing spot for
`GitWorktreeCreateRequest` the following day.
