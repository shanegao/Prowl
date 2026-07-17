# 011 — Canvas Multi-Select & Broadcast Input: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-25 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #53 (replaces #52, closed due to branch rename) |
| **Sources** | `doc-onevcat/plans/2026-03-25-canvas-multiselect-broadcast-design.md`, `doc-onevcat/plans/2026-03-25-canvas-multiselect-broadcast-implementation-plan.md` (absorbed here; originals removed in the docs-ai migration), PR #53 description |
| **Related** | [005-canvas-live-sessions](../005-canvas-live-sessions/000-plan.md), [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md), [012-keybinding-system](../012-keybinding-system/000-plan.md), `docs/components/canvas.md` |

## Background

Canvas (entry 005) was fundamentally a single-focus experience: `CanvasView` stored one
`focusedTabID`, only the focused card allowed terminal hit testing, and Canvas exit used
the focused card to decide which worktree/tab to restore. Two user scenarios motivated
multi-card input:

1. Open multiple cards backed by different agents and send the same prompt to compare
   results.
2. Operate multiple remote SSH sessions and apply the same command/configuration to all.

A constraint from existing code: terminal command routing was mostly worktree-scoped,
while Canvas cards are tab-scoped (`TerminalTabID`) — broadcast needed tab-level routing.

## Goals

- Natural multi-card selection on macOS: `Cmd+Click` anywhere on a card (terminal content
  included, not title-bar-only).
- Direct typing into the Canvas — no separate batch-input textbox.
- Correct non-English (IME) behavior: followers receive committed text, never phonetic
  composition keystrokes (`你好`, not `nihao`).
- Preserve existing single-card interaction when multi-select is not active.
- Select all (`Cmd+Opt+A` + toolbar button), `Escape` to clear broadcast selection.

### Non-goals (v1)

- Broadcasting mouse interactions, search UI, text selection, or context menus.
- Mirroring IME candidate/preedit UI to follower cards.
- Perfect behavior for all full-screen TUIs (`vim`, `fzf`, `top`, ...).
- Changing sidebar multi-selection or worktree detail selection outside Canvas.

## Design / Approach

**Selection model.** Focus and selection are distinct: *focus* decides where real
AppKit/Ghostty input originates; *selection* decides which cards receive mirrored input.
Exactly one selected card is the **primary** (real first responder, owns IME preedit,
source of mirrored input, decides Canvas-exit target); the rest are **followers**. A pure
value type `CanvasSelectionState` (`supacode/Features/Canvas/Models/CanvasSelectionState.swift`)
holds `mode` (`.idle`/`.selecting`), `selectedTabIDs`, `primaryTabID`, `selectionOrder`,
with mutations `focusSingle` / `toggleSelection` / `setPrimary` / `selectAll` /
`beginBroadcastInteractionIfNeeded` / `clear` / `prune`. It lives as Canvas-local
`@State` in `CanvasView` — deliberately not TCA reducer state, since the behavior is
Canvas-local and UI-driven; the pure struct keeps transitions testable without SwiftUI.

**Cmd+Click anywhere: selection shield.** The focused terminal would normally steal
clicks, so while `Cmd` is held or selection mode is active, a transparent hit-testing
shield overlays each card. During broadcasting (≥2 selected, mode back to `.idle`),
the shield is per-card: followers keep it (click promotes to primary), the primary drops
it (clicks pass through to the terminal). Because `CommandKeyObserver` has a 300 ms hold
delay (built for shortcut-hint UI), tap handlers read `NSEvent.modifierFlags` directly
for reliable Cmd detection; the observer only drives shield rendering.

**Broadcast fan-out, two categories:**

1. *Committed text* — English text, committed IME text, and pasted text. Taken from the
   primary card and inserted verbatim into each follower via `ghostty_surface_text`.
2. *Normalized special keys* — Enter, Backspace/Delete, arrows, Tab, Escape, control
   characters (Ctrl-C/D/L, ...), modeled as `MirroredTerminalKey` (Sendable; stores
   `modifierFlagsRawValue: UInt`). A static whitelist `commandAllowedKeyCodes` admits only
   `Cmd+Backspace` (51) and `Cmd+Arrow` (123–126); every other Cmd combination fails
   normalization so app shortcuts (`Cmd+C`, `Cmd+W`, `Cmd+Q`) never broadcast.

**IME rule (the most important one).** The primary card runs the full native IME
lifecycle (marked text, candidate window, commit, cancel). Followers render no preedit;
they receive only the final committed string when composition commits. Intentional
design, not degradation — it is the only safe way to keep multilingual input correct.

**Plumbing.** `GhosttySurfaceView` gains `onCommittedText` / `onMirroredKey` callbacks
(fired from `insertText()` and `keyDown()` on the primary) and safe follower APIs
`insertCommittedTextForBroadcast(_:)` / `applyMirroredKeyForBroadcast(_:)` that never
steal first responder. Tab-scoped helpers `insertCommittedText(_:in:)` /
`applyMirroredKey(_:in:)` on `WorktreeTerminalState` plus `stateContaining(tabId:)`,
`broadcastCommittedText`, `broadcastMirroredKey` on `WorktreeTerminalManager` do the
lookup and fan-out (failures logged via `SupaLogger`). Paste (Cmd+V) is broadcast by
reading `NSPasteboard.general` after Ghostty handles the paste binding.

**UX affordances.** Primary card: 2 pt accent ring; followers: 1.5 pt accent ring at 65%
opacity + background tint. A capsule badge "Broadcasting to N cards" appears in the
bottom-right toolbar next to a Select All button. Clicking blank canvas clears selection
(0-selection allowed); exiting Canvas returns to the primary card's worktree/tab.

Delivery was planned in three slices: (1) selection state + shield + styling,
(2) tab-scoped helpers + committed-text/special-key broadcast, (3) IME hardening, paste,
Cmd whitelist, select-all/Escape, per-card shield polish.

## Alternatives & decisions

- **Rejected: title-bar-only multi-select** — in Canvas the card is the object; users
  must be able to Cmd+Click the terminal area too. Led to the shield design.
- **Rejected: dedicated batch-input textbox** — makes broadcast feel indirect and unlike
  a terminal; direct typing into the primary card is the intended interaction.
- **Rejected: full raw-event mirroring for IME** — would propagate phonetic composition
  keys (`nihao`, romaji). Commit-text mirroring chosen; correct multilingual output beats
  perfect preedit mirroring.
- **Rejected: separate `onPasteText` callback** — paste reuses `onCommittedText`
  plumbing instead of adding a parallel callback.
- **Selection state stays in the view, not TCA** — no reducer involvement for v1; the
  pure struct provides testability without the ceremony.
- **Select-all shortcut wobble** — during implementation select-all briefly shipped as
  `Cmd+Shift+A`, then was reverted to the designed `Cmd+Opt+A` before merge
  (commit 93ed60e2).

## Amendments

None. Later Canvas-wide evolution that touched this machinery (primary auto-advance on
card close, keybinding-system integration) is recorded in
[001-action.md](001-action.md) under current state and belongs to entries 024 and 012.
