# 023 — Amendment: Book-Switch Jank Investigation (2026-04-29)

## Context

A week after launch, quickly switching Shelf books — especially via keyboard shortcuts —
showed visible frame drops. Early Instruments captures included multi-second main-thread
hangs and hundreds of thousands of SwiftUI update/cause edges per short recording. The
reducer and Ghostty bridge signposts were consistently sub-millisecond: the cost was
SwiftUI invalidation, layout, responder, and display-list work.

The full investigation — trace methodology (`xctrace` exports, hitches normalized per
`reducer.selectWorktree` signpost), the run-by-run table, and the rejected experiments —
is kept verbatim in this folder as [jank-investigation.md](jank-investigation.md). This
amendment records only the outcome.

## Change

Retained fixes (PR #246, plus `0fe682cb` from the investigation branch):

- Sidebar tab-count reads moved into a leaf view (`RepoHeaderTabCountBadge`) so unrelated
  terminal activity stops invalidating every repository section — the single largest win.
- `orderedShelfBooks()` rewritten without per-body `Dictionary`/`Set`/row-model churn.
- Shelf-originated switches stop sending a redundant TCA animation transaction on top of
  the view-level `.animation(value: openBookID)`.
- `CommandKeyObserver` enters shortcut-hint mode only for bare ⌘ or bare ⌃, not for every
  chord containing them.
- Sidebar type-through `.onKeyPress` forwarding not installed while Shelf is active.
- Spines rendered from a single `ForEach`, removing the cross-stack
  `matchedGeometryEffect` from the original two-stack layout.
- Open-book `.transition(.opacity)` removed (small win, no observed UX cost).
- Permanent signposts under `com.onevcat.prowl` / PointsOfInterest for future regressions.

Rejected (tried, measured, reverted — do not re-try without a new trace): removing the
outer `.id(worktree.id)`, disabling/isolating the spine animation, rendering the terminal
in a final-position overlay (black-edge artifact), and conditionally removing closed-spine
context menus (worse traces *and* worse UX).

## Refs

- PR #246 (2026-04-29), commit `0fe682cb`
- [jank-investigation.md](jank-investigation.md) — full trace record, methodology, and
  future structural directions (custom spine layout, virtualized spines, …)

## Current state

The single-`ForEach` layout and the bare-⌘/⌃ hint gate are still in place
(`supacode/Features/Shelf/Views/ShelfView.swift`, `supacode/App/CommandKeyObserver.swift`).
The Shelf-only `.onKeyPress` gate is gone because the sidebar type-through forwarding was
removed entirely the same day (commit `9030147d`, "refocus terminal on single selection"),
which also removes the fix's behavior trade-off (typed characters not forwarded while
Shelf was active).
