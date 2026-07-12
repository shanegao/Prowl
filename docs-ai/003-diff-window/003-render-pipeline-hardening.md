# 003 — Amendment: Render Pipeline Hardening (2026-07-03)

## Context

Three problems accumulated in `DiffWindowState` as the window saw heavier use:

1. A cancelled diff-load task could still write stale cache/selection data
   after a refresh or worktree switch (cancellation was checked after the
   write, not before).
2. Rapidly flicking through files (A → B → C) sent a render request for every
   pass-through file, causing visible flash/jump; meanwhile the WebView-backed
   `DiffView` can take 1–2 s to diff/paint large files even when the
   Swift-side cache hit is instant, with no feedback.
3. After a YiTong `didFail` render event, the error overlay could never be
   dismissed for the same file: YiTong skips value-equal documents, and
   re-selecting the same file was a no-op.

## Change

Three PRs in one day, each building on the previous:

**PR #529 — stale writes, testability, spinner, debounce**

- Check `Task.isCancelled` *before* cache/selection writes.
- `DiffWindowState` made unit-testable: git access injected as constructor
  closures; cache eviction and selection reconciliation extracted into pure
  statics (`evictedCache`, `resolvedSelection`).
- `isRenderingDiff` + a centered loading indicator driven by YiTong's
  `didRender`/`didFail` events.
- 150 ms `selectFile` debounce backed by an injectable `Clock`.

**PR #536 — error recovery, leading-edge debounce**

- Retry after `.didFail` works by bumping `renderGeneration`, which the view
  uses as `.id()` on the `DiffView` — recreating the view forces a fresh
  render (verified against YiTong 0.2.0 source: `DiffViewController.update`
  skips value-equal documents, so merely clearing the error would leave a
  stuck spinner). Retry gestures: refresh, or re-selecting the failed file.
- Debounce became leading-edge: a deliberate single click applies immediately
  and opens the coalescing window; only rapid follow-ups within the window are
  deferred.
- Behavior documented in `docs/components/diff-view.md`.

**PR #537 — shared `Debouncer`, `RenderState` enum**

- The cancel-previous + sleep + cancellation-check pattern was hand-rolled in
  six places across three stores; extracted into `Debouncer`/`KeyedDebouncer`
  (`supacode/Support/Debouncer.swift`) and migrated `DiffWindowState`,
  `WorktreeInfoWatcherManager`, and `PullRequestRefreshCoordinator` onto them.
- The migration fixed a latent bug outside the diff window:
  `scheduleBranchChanged`/`scheduleRestart` swallowed `CancellationError` with
  `try? await sleep(...)`, so a cancelled debounce fired immediately instead
  of never.
- `isRenderingDiff: Bool` + `renderError` folded into one `RenderState` enum
  (`idle`/`rendering`/`failed`), making "spinner and error at once"
  unrepresentable.

## Refs

- PRs #529, #536, #537.
- Tests: `supacodeTests/DiffWindowStateTests.swift` (cache eviction, selection
  reconciliation, render state, leading-edge debounce via `TestClock`),
  `supacodeTests/DebouncerTests.swift`.

## Current state

All three changes are live in the working tree as of 2026-07-12; see
[001-action.md](001-action.md) "Outcome & current state" for file-level detail.
