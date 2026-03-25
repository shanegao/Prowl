# Canvas Multi-Select Broadcast Implementation Plan

**Goal:** Implement Canvas multi-card selection with direct broadcast input, including committed-text IME fan-out, while preserving current single-card behavior when multi-select is inactive.

**Scope:**
- In:
  - Canvas-local multi-selection state and transitions
  - Cmd+Click selection across full card area
  - Primary vs follower selected styling
  - Broadcast of committed text plus a small set of normalized special keys
  - IME-safe follower behavior using committed text only
  - Tests for selection state transitions and input normalization/filtering
- Out:
  - Mouse broadcast
  - Full TUI parity for all applications
  - Follower-side IME candidate/preedit UI

**Architecture:**
- Keep selection state local to Canvas, but extract transition logic into a pure helper for tests.
- Add a transparent selection shield so Cmd+Click works across the whole card, including terminal content.
- Keep one primary card as the real first responder; mirror input from it to follower cards.
- Introduce small normalized mirrored-key APIs instead of replaying arbitrary AppKit events everywhere.
- Treat IME specially: only committed text fans out; preedit stays primary-only.

**Acceptance / Verification:**
- Cmd+Click anywhere on a card toggles selection.
- Non-Cmd click exits selection mode and returns to single-card interaction.
- Clicking blank canvas clears selection and focus.
- Multiple selected cards receive mirrored committed text.
- Followers receive committed Chinese/Japanese text, not phonetic intermediate input.
- Build passes and targeted tests pass.

## Task 1: Add pure Canvas selection state machine

**Files:**
- Create: `supacode/Features/Canvas/Models/CanvasSelectionState.swift`
- Create: `supacodeTests/CanvasSelectionStateTests.swift`

**Steps:**
1. Add a pure selection model that stores selection mode, selected tab IDs, primary tab ID, and selection order.
2. Write tests for Cmd+Click enter/toggle/remove, non-Cmd click exit, and blank-canvas clear.
3. Run the new test file and confirm green.

## Task 2: Integrate selection model into CanvasView

**Files:**
- Modify: `supacode/Features/Canvas/Views/CanvasView.swift`

**Steps:**
1. Replace single-focus-only state with primary focus + selected tabs + selection mode.
2. Preserve current initial focus / canvas exit behavior by mapping it to primary focus.
3. Update z-order and unfocus logic to respect 0-selection and multi-selection.
4. Build and fix compile errors before moving on.

## Task 3: Add selected/follower visuals and selection shield hooks

**Files:**
- Modify: `supacode/Features/Canvas/Views/CanvasCardView.swift`

**Steps:**
1. Add separate styling for primary focused card vs follower selected cards.
2. Add an overlay/shield path that can intercept clicks across the full card when selection mode or Cmd is active.
3. Ensure normal single-card terminal interaction still works outside selection mode.
4. Build and verify the view compiles.

## Task 4: Wire Cmd+Click anywhere on card

**Files:**
- Modify: `supacode/Features/Canvas/Views/CanvasView.swift`
- Modify: `supacode/Features/Canvas/Views/CanvasCardView.swift`

**Steps:**
1. Use `CommandKeyObserver` from the environment in Canvas.
2. Make Cmd+Click on card shield toggle selection.
3. Make non-Cmd click on a card exit selection mode and focus that one card.
4. Make blank-canvas click clear selection and focus.
5. Run selection tests if they need updates.

## Task 5: Add normalized mirrored-key model

**Files:**
- Create: `supacode/Infrastructure/Ghostty/MirroredTerminalKey.swift`
- Create: `supacodeTests/MirroredTerminalKeyTests.swift`
- Modify: `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`

**Steps:**
1. Define a small mirrored-key type for Enter, backspace, arrows, tab, escape, and control-character input.
2. Add normalization helpers/tests for filtering out Command shortcuts.
3. Run the new tests.

## Task 6: Add Ghostty broadcast hooks and safe follower APIs

**Files:**
- Modify: `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`
- Modify: `supacodeTests/GhosttySurfaceViewTests.swift`

**Steps:**
1. Add callbacks for committed text and mirrored special keys.
2. Add follower-safe APIs that can insert committed text and replay normalized keys without stealing first responder.
3. Keep IME preedit local to the primary card.
4. Add focused unit tests for new pure helper behavior where practical.

## Task 7: Add tab-scoped terminal broadcast helpers

**Files:**
- Modify: `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- Modify: `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`
- Modify: `supacodeTests/WorktreeTerminalManagerTests.swift` (if practical)

**Steps:**
1. Add tab-scoped lookup and broadcast helper methods.
2. Add a manager-level helper to fan out input from primary to followers.
3. Keep primary as the real responder; do not refocus followers.
4. Add tests for pure/observable behavior if practical.

## Task 8: Connect primary-card input to follower broadcast

**Files:**
- Modify: `supacode/Features/Canvas/Views/CanvasView.swift`
- Modify: `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
- Modify: `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift`

**Steps:**
1. Subscribe primary-card surface callbacks only when multi-selection is active.
2. Broadcast committed text to followers.
3. Broadcast normalized special keys to followers.
4. Keep IME committed-text behavior correct.
5. Build and run targeted tests.

## Task 9: Add lightweight Canvas broadcast status UI

**Files:**
- Modify: `supacode/Features/Canvas/Views/CanvasView.swift`

**Steps:**
1. Show `Broadcasting to N cards` when `selectedTabIDs.count > 1`.
2. Make the hint subtle and consistent with existing canvas chrome.
3. Build and verify layout visually if possible.

## Task 10: Run verification and ship

**Files:**
- Modify: plan docs if scope changed materially

**Steps:**
1. Run targeted tests for new selection and mirrored-key logic.
2. Run `make build-app`.
3. If feasible, run broader test coverage (`make test` or a well-scoped subset) and capture any unrelated failures.
4. Review diff.
5. Commit only the feature changes.
6. Push branch and open PR against `onevcat/Prowl`.
