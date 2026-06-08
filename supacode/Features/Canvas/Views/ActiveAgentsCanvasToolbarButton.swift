import SwiftUI

/// Toolbar button that opens the global active-agents canvas — a board of every
/// tab currently running an agent, across all worktrees. Active state means the
/// agent canvas is showing; tapping then exits back to the previous worktree.
///
/// Placed inside the canvas-button group alongside the worktree- and
/// repository-canvas toggles (all three switch the detail pane between canvas
/// scopes), and shown only when at least one agent is active or the agent
/// canvas is already open, so the button never opens an empty board.
struct ActiveAgentsCanvasToolbarButton: View {
  let isActive: Bool
  let onToggle: () -> Void

  var body: some View {
    Button {
      onToggle()
    } label: {
      Image(systemName: "sparkles.rectangle.stack")
        .symbolVariant(isActive ? .fill : .none)
        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
    }
    .help(isActive ? "Exit active-agents canvas" : "Show all active agents in canvas")
  }
}
