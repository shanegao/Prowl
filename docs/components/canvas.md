# Canvas View

> A zoomable board where every agent is a live, interactive terminal card —
> watch them all at once, and broadcast one command to every selected agent.

**Keywords:** canvas, board, cards, grid, zoom, pan, broadcast, multi-select, select all, arrange, organize, tile, fill, expand card, bird's-eye, overview of agents

**Related:** [view-modes](view-modes.md) · [shelf](shelf.md) · [terminal](terminal.md) · [active-agents](active-agents.md) · [keyboard-shortcuts](../reference/keyboard-shortcuts.md)

## What it is

Canvas turns every open terminal tab into a **card** floating on an infinite,
zoomable board. Each card is a **live, fully interactive terminal** — not a
screenshot — so you can watch several agents work simultaneously, then click into
any card to type. A card whose task just finished **lights up** so you can see at
a glance who's done.

**Toggle Canvas:** `⌘⌥↩` (`toggle_canvas`), or the **Overall** canvas button in the
window toolbar (alongside the worktree-, repository-, and active-agents-canvas
toggles). Toggling has no effect if no worktrees are open.

## The signature feature: broadcast to every agent

Canvas lets you **type a command once and send it to many agents at once**:

1. **Select multiple cards.** `⌘`-click cards to add them to the selection, or
   press **`⌘⌥A` (Select All Cards)**. With two or more selected, Canvas enters
   **broadcasting** mode (the toolbar shows "Broadcasting to N cards").
2. **Type into the primary (focused) card.** What you type — text and submitted
   commands — is **mirrored to every selected card**.
3. Great for "run the tests", "commit", "`/clear`", "continue", etc. across a
   whole fleet of agents in one keystroke.

Selection controls:
- `⌘`-click a card body → toggle it in/out of the selection.
- **Click (without `⌘`)** an already-selected card → make it the **primary** (the
  one you type into) without deselecting the rest. (`⌘`-clicking a selected card
  instead *removes* it from the selection.)
- Click empty canvas → clear the selection. **Esc** also clears it while
  broadcasting (two or more cards selected).

## Working with cards

| Operation | How |
|-----------|-----|
| Focus (enter) a card | Single-click its body |
| Navigate between cards | `⌘⌃↑` / `⌘⌃↓` / `⌘⌃←` / `⌘⌃→` — jump to the nearest card in that direction (spatial, based on card positions) |
| Move a card | Drag its title bar |
| Resize a card | Drag its edges/corners |
| Expand / restore a card | `⌘⌥E`, double-click the title bar, or the title-bar expand button — fills the viewport with that card; click the dimmed background or `⌘⌥E` again to restore |
| Close a card (its tab) | The **×** in the card title bar |
| Right-click a card's title bar | Context menu: Rename Tab, Change Icon, Close Tab, Close Other/All Tabs in This Worktree |
| Pan the board | Drag empty space (or middle-drag) |
| Zoom | `⌘` + scroll, or pinch (≈0.25×–2×) |

## Arranging the board

- **`⌘⌥A` Select All Cards** — select every card (entering broadcast).
- **`⌘⌥R` Arrange Cards** — bin-pack the existing cards to fit the viewport's
  aspect ratio, preserving each card's size, then fit-to-view.
- **`⌘⌥G` Organize Cards** — reset every card to a uniform grid (≈√N columns) at a
  default size and center them.
- **`⌘⌥T` Tile Cards** — resize every card to tile and fill the viewport, like an
  automatic window manager. Cards form a balanced grid whose orientation follows
  the window: a wide window spreads them into rows (2 cards → left/right, 5 →
  top 2 / bottom 3), a tall window stacks them into columns. Each line fills its
  full extent, so the cards use as much area as possible. The zoom adapts to card
  count: a few cards stay at native scale (large, detailed), while many cards zoom
  out so each keeps a readable terminal surface (more rows/columns at smaller text
  — enough to follow what each agent is doing).

These also appear as toolbar buttons. There's a `?` help popover (bottom-left)
explaining pan/zoom/expand — hover the button to reveal it, move away to dismiss,
or click to pin it open.

## Toolbar actions

The main toolbar tracks the focused card. Its center status area shows the same
PR/check summary, toast, or time hint as Normal view, and the right-side Run
Script / Custom Command buttons run against the focused card's worktree. `⌘⌃G`
(`open_pull_request`, "Open on Code Host") opens that card's PR when it has one,
or the repository page otherwise.

## Visual cues

- **Focused card:** bright accent border. **Selected (multi-select):** medium
  accent border. **Unselected:** faint border.
- **Finished/unread task:** the card title bar turns orange.
- During selection/broadcast, non-focused cards get a subtle shield overlay so you
  don't accidentally type into the wrong one.
- The left nav band is tinted with the focused card's repository color
  (`windowTintMode`).

## Layout & sizing

- Default card size adapts to screen width (roughly 800×550 on a 14", larger on a
  27"). Cards have generous min/max bounds and snap-animate on resize.
- On first entry, cards auto-arrange into a balanced grid. Positions, sizes, and
  z-order are persisted across launches (in `UserDefaults`) and restored when you
  return to Canvas.
- Closing a card's last tab prunes it; focus advances to a neighbor.

## Many agents at once

Canvas is built for scale: the grid grows with the number of cards, Arrange packs
them to your viewport, and you can zoom out to see everything then zoom into a
region. Cards are real terminals, so the ones off-screen are occlusion-managed for
performance.

## Settings that affect Canvas

- `defaultViewMode` — launch directly into Canvas.
- `canvasDefaultLayout` — how cards are first laid out when you open Canvas:
  `uniform` (same-size cards packed to fit) or `tile` (resize cards to fill the
  screen, the default). Only the initial auto-layout is affected; saved card
  positions are always restored.
- `windowTintMode` / repository colors — card and nav tinting.
- `showRunButtonInToolbar` — whether the Run button appears in the Canvas toolbar.

## Keyboard card navigation

`⌘⌃↑` / `⌘⌃↓` / `⌘⌃←` / `⌘⌃→` move focus to the **nearest card** in
that direction, based on the 2D card positions on the board. If the target card
is partially off-screen, the canvas pans smoothly to reveal it without changing
the zoom level. These are the same key combos used for worktree/book navigation
in Normal and Shelf views — in Canvas they switch to spatial navigation
automatically.

## When to recommend Canvas vs Shelf

- **Canvas** = spatial, see-everything, broadcast to many. Best when you're
  supervising a fleet or fanning the same command out.
- **Shelf** = linear, keyboard-fast triage of many worktrees one at a time.

See [view-modes](view-modes.md) for the comparison.

## Gotchas for agents

- Broadcasting requires **≥2 selected cards**; it mirrors what's typed into the
  **primary** card.
- Toggling Canvas with nothing open is a no-op.
- A "card" maps to a **tab**, identified by `tab.id` — the same ID the
  [`prowl` CLI](cli.md) uses.
