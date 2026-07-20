import ComposableArchitecture
import Foundation

extension AppFeature {
  /// Open the hand-off HUD for the selected runnable target. Requires a
  /// detected agent on the selected pane — the no-source mechanical handoff
  /// stays CLI-only (docs-ai 049).
  func openHandoffHud(state: inout State) -> Effect<Action> {
    guard state.handoffHud == nil else { return .none }
    guard let worktree = state.repositories.selectedTerminalWorktree else { return .none }
    let source = terminalClient.handoffSourceContext(worktree.id)
    guard let hudState = HandoffHudFeature.State.make(worktree: worktree, source: source) else {
      return .send(.repositories(.showToast(.warning("No agent detected in the current pane"))))
    }
    state.handoffHud = hudState
    return .none
  }
}
