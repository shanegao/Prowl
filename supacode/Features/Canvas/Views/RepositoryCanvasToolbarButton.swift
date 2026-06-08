import SwiftUI

/// Toolbar button that opens a per-repository canvas, placed inside the
/// canvas-button group alongside the worktree- and active-agents-canvas
/// toggles. Rendered in the same three toolbars as `WorktreeCanvasToolbarButton`.
/// Active state means the repository is currently displayed in canvas mode;
/// tapping then exits back to the tab view.
struct RepositoryCanvasToolbarButton: View {
  let isActive: Bool
  let onToggle: () -> Void
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    Button {
      onToggle()
    } label: {
      Image(systemName: "square.grid.3x3")
        .symbolVariant(isActive ? .fill : .none)
        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
    }
    .help(
      AppShortcuts.helpText(
        title: isActive ? "Exit repo canvas" : "Open this repo in canvas",
        commandID: AppShortcuts.CommandID.toggleRepoCanvas,
        in: resolvedKeybindings
      )
    )
    .modifier(
      KeyboardShortcutModifier(
        shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.toggleRepoCanvas)
      )
    )
  }
}
