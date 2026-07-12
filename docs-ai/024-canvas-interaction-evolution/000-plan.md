# 024 — Canvas Interaction Evolution: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-04-25 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #226, #229, #238, #329, #337, #362, #393, #394, #395, #396, #400, #401, #402, #457, #507, #509, #514 |
| **Sources** | PR descriptions; fork issues #197, #225, #228, #328, #357, #392, #453; community PR #358 (vince-hz) |
| **Related** | [005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md), [011-canvas-multiselect-broadcast](../011-canvas-multiselect-broadcast/000-plan.md), [043-canvas-tile-layout](../043-canvas-tile-layout/000-plan.md), [002-custom-commands](../002-custom-commands/000-plan.md), [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md), `docs/components/canvas.md`, `docs/components/view-modes.md` |

## Background

Canvas v1 ([005](../005-canvas-live-sessions/000-plan.md)) shipped the free-form
live-card view in March 2026. Once it became the daily driver for watching multiple
agents, friction accumulated against the Normal view: navigation was trackpad-only
(pinch zoom, two-finger pan), acting on a card required focusing it first, card layout
was lost across launches, the toolbar/palette/sidebar all silently kicked the user back
to Normal view, and keyboard coverage was near zero.

There was never a single master plan. The work arrived as a three-month stream of
user-filed fork issues and PR-level designs (2026-04-20 → 2026-06-27), all pushing one
theme: **Canvas should be a first-class primary view — anything you can do in Normal
view should work without leaving Canvas.** This entry records that program, anchored at
the April pointer-interaction wave; the later waves are amendments. Layout-algorithm
work is out of frame ([043](../043-canvas-tile-layout/000-plan.md)), as is multi-select
broadcast ([011](../011-canvas-multiselect-broadcast/000-plan.md)).

## Goals

- Mouse-first navigation parity: zoom and pan without a trackpad (fork issue #197).
- Act on a card (close, expand) without focusing it first (fork issue #225).
- Never steal scroll events from TUIs that speak the mouse protocol (fork issue #228).
- Card layout and z-order survive relaunch (fork issue #328); Canvas can be the boot
  view.
- App actions — new tab, Run Script, custom commands, code-host/PR actions,
  sidebar/palette selection — resolve against the *focused Canvas card* instead of
  forcing an exit to Normal view.
- Keyboard coverage: arrange/organize, expand a card, spatial card-to-card navigation.

**Non-goals**: changing the packing algorithms (Waterfall/MaxRects stayed as v1 built
them until [043](../043-canvas-tile-layout/000-plan.md)'s Tile layout), and broadcast
semantics.

## Design / Approach (anchor wave, April 2026)

- **Cmd+wheel zoom** (#238): held Cmd routes wheel events to
  `CanvasScrollCoordinator.handleZoom`; the math lives in `CanvasZoomMath`, extracted
  from the existing `MagnifyGesture` anchor-preserving formula, with sensitivity tuned
  per `NSEvent.hasPreciseScrollingDeltas` (mouse wheel vs trackpad). The Cmd+scroll
  path is wired into the existing pan-momentum monitor so flipping Cmd mid-gesture
  switches behavior immediately.
- **Middle-click pan** (#238): a window-scoped `NSEvent` local monitor installed by
  `CanvasScrollContainerView` while it is in a window intercepts
  `otherMouseDown/Dragged/Up` with `buttonNumber == 2`, drives the canvas offset
  directly, and swallows the events so focused Ghostty surfaces never see them. The
  monitor tears down with the view, so it has no effect outside Canvas.
- **Hover card actions** (#226): per-card close/expand buttons fade in on title-bar
  hover. Closing the highlighted card auto-advances selection to the nearest surviving
  neighbor in the pre-close tab order, matching the terminal's own focus handoff.
- **Scroll ownership rule** (#229): the canvas must never claim wheel events the
  terminal wants. #204's "no-scrollback passthrough" (forward scroll to the canvas when
  Ghostty reports empty scrollback) was reverted because TUIs (pagers, editors) drive
  their own mouse scroll protocol with an empty scrollbar.

## Program-level design theme (later waves)

Two mechanisms carry almost all subsequent work:

- **Focused-card action routing**: `AppFeature` resolves an action-target worktree that
  falls back from the Normal selection to the Canvas-focused card
  (`actionTargetWorktree` → `canvasFocusedTerminalWorktree` in
  `supacode/Features/App/Reducer/AppFeature+Support.swift`). New tab (#394), custom
  actions (#362), and code-host/PR actions (#509) all ride this.
- **One-shot reducer→view requests**: Canvas operations that are view-local (focus a
  card, expand, arrange) are triggered from reducers via `CanvasFocusRequest` /
  `CanvasCommandRequest` values that `CanvasView` observes and consumes exactly once
  (#395, #396, #402).

## Alternatives & decisions

- **#229 partial revert**: of #204's three scroll optimizations, only the
  no-scrollback passthrough branch was dropped; gesture continuity and the 0.3 s bounce
  window were kept.
- **#226 deferred the context-menu variant** deliberately; it landed later as #457.
- **#393 keybinding choice**: the proposed `Cmd+Shift+R` was rejected (taken by
  `refreshWorktrees`); Arrange/Organize joined the existing Canvas `⌘⌥` family as
  `⌘⌥R` / `⌘⌥G`, user-rebindable via the Shortcuts recorder.
- **#362 single-item toolbar cluster**: the Run + Custom Command cluster renders as one
  `ToolbarItem { HStack }` — an intentional divergence from the Normal toolbar — because
  on Canvas the host view stays mounted and NSToolbar animated per-item insert/remove
  when switching between cards with different command counts.
- **#401 adaptive default card size** replaced the fixed 1000×680 card with clamped
  linear interpolation on host-screen width (800×550 at ≤1512 pt), so small screens get
  a higher fit-to-view scale and readable text.
- **#402 expand-in-place** replaced #226's expand-to-tab-view stopgap. The animation is
  driven by an `Animatable` container (`AnimatedExpandableCard`) so size/center/scale
  interpolate from one progress value per frame; the canvas transform is never mutated,
  which is what keeps the background frozen. Earlier attempts using implicit
  per-modifier interpolation or plain `@State` progress did not animate correctly.
- **#514 spatial navigation** uses weighted distance (primary axis + 2× cross axis) to
  prefer directly aligned neighbors over diagonal ones; in the reducer, the `⌘⌃`-arrow
  worktree-selection actions are redirected into Canvas navigate commands while Canvas
  is active, so the keys no longer force a view-mode switch.

## Amendments

- Updated 2026-05-28: Canvas becomes a first-class view — layout persistence, Default
  View option, focused-card custom actions — see
  [002-first-class-canvas.md](002-first-class-canvas.md)
- Updated 2026-06-06: keyboard & layout wave — shortcuts, in-canvas navigation
  routing, resize animation, adaptive sizing, expand-in-place — see
  [003-keyboard-and-layout-wave.md](003-keyboard-and-layout-wave.md)
- Updated 2026-06-27: completeness wave — card tab context menu, hover help, code-host
  toolbar actions, spatial card navigation — see
  [004-completeness-wave.md](004-completeness-wave.md)
