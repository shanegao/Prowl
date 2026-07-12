# 032 — Amendment: June Upstream-Ported Performance Wave (2026-06-08)

## Context

The 2026-06-09 upstream review batch (post-v0.10.2, see
[017-upstream-sync-process](../017-upstream-sync-process/000-plan.md) and
`docs-ai/017-upstream-sync-process/upstream-ledger.md`) included several upstream
performance fixes targeting paths that Prowl's many-parallel-agents workload makes
near-constant hot: while agents stream output, the detail view re-renders on every OSC-9
progress tick. All four ports merged 2026-06-08 as fork-shaped implementations, not
cherry-picks.

## Change

| Fork PR | From upstream | Fix |
| --- | --- | --- |
| #414 | upstream #329 (FocusedAction slice) | Menu-bar commands published bare `() -> Void` closures via `focusedSceneValue`; closures are never equal, so every publisher body run rebuilt the system menu — flicker and collapsing submenus while an agent is busy. New `FocusedAction<Input>: Equatable` (`supacode/App/Models/FocusedAction.swift`) dedupes on `(isEnabled, token)`, where `token` projects captured state so commands never fire against a stale target. Fork keeps its disabled-as-`nil` convention. |
| #415 | upstream #347 | OSC-9 progress reports arrive far faster than the UI needs. `GhosttySurfaceBridge.ingestProgressReport(state:value:)` coalesces with a leading-edge-then-trailing flush (50ms throttle) plus a slow 1s/15s stale-watch replacing the per-report reset-task churn; `SET_TITLE` / `TerminalTabManager` title/dirty writes become idempotent; `GhosttySurfaceProgressBar` buckets percent to 5% steps and renders via `scaleEffect` instead of `GeometryReader` relayout. Only the bridge/tab-manager/progress-bar slices apply — the fork has no tab-stripe/shimmer. |
| #416 | upstream #376 (in spirit) | `WorktreeTerminalManager`'s unbounded `AsyncStream` grew without bound under agent tool storms (notably fork-specific `agentEntryChanged` re-emits). Cap the live stream at `.bufferingNewest(2048)` and `pendingEvents` at 1024; `TerminalEventCoalescer` drops exact-repeat "latest value wins" state events per slot, never coalescing lifecycle/notification events; dedup cache resets on resubscribe and forgets slots on `prune`. |
| #417 | upstream #332 (AnyView slice only) | `TerminalSplitTreeAXContainer` hosted `NSHostingView<AnyView>` with a fresh `AnyView` per `updateNSView`, defeating SwiftUI diffing so the whole split tree re-rendered per notification. Host the concrete `NSHostingView<TerminalSplitTreeView>` instead. Deliberately **not** ported: upstream's per-surface `@Observable` notification-dot mirror — the fork's `notifications` are observed (dot already accurate), so there was no correctness bug, and the invasive `toolbarNotificationGroups` move was skipped as regression risk without a bug behind it. |

Tests added with the wave: `FocusedActionTests`, `GhosttySurfaceBridgeTests`
(`TestClock`-driven coalescing cases), `GhosttySurfaceProgressBarTests`,
`TerminalEventCoalescerTests`. #417 shipped without a new test (type-erasure removal, no
logic change).

## Refs

PRs #414, #415, #416, #417 (all merged 2026-06-08); upstream #329, #347, #376, #332;
ledger batch "2026-06-09 — Review through post-v0.10.2".

## Current state (as of 2026-07-12)

Verified in the working tree:

- `supacode/App/Models/FocusedAction.swift`; `supacodeTests/FocusedActionTests.swift`.
- `supacode/Infrastructure/Ghostty/GhosttySurfaceBridge.swift` — `ingestProgressReport`;
  `supacode/Features/Terminal/Views/GhosttySurfaceProgressBar.swift` — `bucketedPercent`.
- `supacode/Features/Terminal/BusinessLogic/TerminalEventCoalescer.swift`;
  `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift` —
  `eventBufferCap = 2048`, `pendingEventCap = 1024`, `.bufferingNewest` policy.
- `supacode/Features/Terminal/Views/TerminalSplitTreeView.swift` —
  `TerminalSplitTreeAXContainer` holding `NSHostingView<TerminalSplitTreeView>`.
