# 011 — Canvas Multi-Select & Broadcast Input: Action Log

All work landed in a single day through one PR (#53, merged 2026-03-25, branch
`feature/canvas-multiselect-broadcast`; it replaces #52, which was closed after a branch
rename). The commit chain maps cleanly onto the plan's three slices.

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-25 | Design doc committed alongside the work | `431fe890` |
| 2026-03-25 | Core feature: `CanvasSelectionState` + tests, CanvasView integration (z-order primary > selected > unselected), card visuals + selection shield, `MirroredTerminalKey` + tests, Ghostty broadcast hooks and follower APIs, tab-scoped fan-out on terminal state/manager | `ad587965` (PR #53) |
| 2026-03-25 | Polish: `Sendable` via raw modifier storage, safe `selectionState` capture in callbacks, canvas scroll-direction fix; debug logging removed | `057c3ecd`, `9325b1c3` |
| 2026-03-25 | Click behavior during broadcasting: per-card shield (`showsSelectionShield(for:)`), non-Cmd click on follower promotes it to primary, primary click passes through | `79bdd210` |
| 2026-03-25 | Whitelist `Cmd+Backspace` and `Cmd+Arrow` for broadcast (`commandAllowedKeyCodes`) | `b00fbabd` |
| 2026-03-25 | Select all cards with `Cmd+Opt+A` + toolbar button | `c993df57` |
| 2026-03-25 | Paste broadcast: Cmd+V hook, moved to `performKeyEquivalent` after Ghostty handles the binding; select-all reverted from an interim `Cmd+Shift+A` back to `Cmd+Opt+A`; context-menu paste also broadcasts via `paste(_ sender:)` | `8acfada0`, `93ed60e2`, `4480511b` |
| 2026-03-25 | Plan/design docs aligned with final implementation; PR #53 merged | `83d812fb`, `9f746c65` |

## Outcome & current state (as of 2026-07-12)

The feature works as designed and remains user-facing documented in
`docs/components/canvas.md` ("broadcast to every agent"). Key code, verified in the tree:

- `supacode/Features/Canvas/Models/CanvasSelectionState.swift` — the pure selection
  struct as planned. It has since gained `pruneAutoAdvancingPrimary(previousOrder:currentOrder:)`,
  which auto-focuses the nearest surviving neighbor when the primary card closes
  (PR #226, 2026-04-20 — part of [024-canvas-interaction-evolution](../024-canvas-interaction-evolution/000-plan.md)).
- `supacode/Features/Canvas/Views/CanvasView.swift` — selection `@State`, per-card
  `showsSelectionShield(for:)`, toolbar with Select All button (`checkmark.rectangle.stack`)
  and the "Broadcasting to N cards" badge, Escape/select-all key handling.
- `supacode/Features/Canvas/Views/CanvasView+Focus.swift` — broadcast wiring was later
  split out of `CanvasView.swift` into this extension: `handleSelectionShieldTap`,
  `syncBroadcastCallbacks` / `clearBroadcastCallbacks`.
- `supacode/Features/Canvas/Views/CanvasCardView.swift` — shield overlay plus terminal
  hit testing gated by `allowsHitTesting(isFocused && !showsSelectionShield)`.
- `supacode/Infrastructure/Ghostty/MirroredTerminalKey.swift` — normalized key model
  with the `commandAllowedKeyCodes` whitelist, unchanged in shape.
- `GhosttySurfaceView` was later split into extensions; the broadcast pieces now live in:
  `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift` (callback declarations),
  `GhosttySurfaceView+TextInput.swift` (`insertText` commit hook,
  `insertCommittedTextForBroadcast`, `applyMirroredKeyForBroadcast`), and
  `GhosttySurfaceView+Keyboard.swift` (`keyDown` mirror hook, Cmd+V pasteboard broadcast
  in `performKeyEquivalent`, and the `paste(_ sender:)` IBAction hook).
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` —
  `insertCommittedText(_:in tabId:)` / `applyMirroredKey(_:in:)`. A sibling overload
  `insertCommittedText(_:in surfaceID: UUID)` was added later and is used by the
  `prowl send` CLI path (`supacode/App/supacodeApp.swift`) — the broadcast insertion API
  became the CLI's text-injection primitive (see [013-prowl-cli](../013-prowl-cli/000-plan.md)).
- `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift` —
  `stateContaining(tabId:)`, `broadcastCommittedText`, `broadcastMirroredKey`.
- Select-all is no longer hardcoded: it resolves through the keybinding system
  (`AppShortcuts.CommandID.selectAllCanvasCards`, default `Cmd+Opt+A` in
  `supacode/App/AppShortcuts.swift`), so users can rebind it — see
  [012-keybinding-system](../012-keybinding-system/000-plan.md).
- Tests exist and grew with the feature: `supacodeTests/CanvasSelectionStateTests.swift`
  (15 tests, including auto-advance coverage) and
  `supacodeTests/MirroredTerminalKeyTests.swift` (8 tests).

## Deviations from plan

- **Select-all shortcut**: implemented mid-PR as `Cmd+Shift+A`, reverted to the designed
  `Cmd+Opt+A` before merge (`93ed60e2`); later made user-configurable via the keybinding
  system (entry 012).
- **Paste hook placement**: the design settled on firing `onCommittedText` from
  `performKeyEquivalent` (Cmd+V is intercepted by Ghostty's binding system before the
  responder chain's paste action). In the final code both paths fire the callback:
  `performKeyEquivalent` covers keyboard Cmd+V, and the `paste(_ sender:)` IBAction
  covers context-menu paste (`4480511b`) — the two entry points are disjoint, so no
  double broadcast for a single paste.
- Otherwise the implementation matches the plan closely; note the absorbed plan docs
  were themselves updated at merge time (`83d812fb`) to describe the final state.

## Open questions

- The original design doc contradicted itself on `paste(_ sender:)` (one section said
  the IBAction is unused because Ghostty intercepts Cmd+V, another said paste broadcast
  fires from `paste()`). Current code resolves this by hooking both paths, but the
  behavior was reconstructed from code reading, not runtime verification of the
  context-menu paste broadcast.
