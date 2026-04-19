import SwiftUI

/// Toolbar button that opens a per-worktree canvas, placed next to the branch
/// name in `WorktreeToolbarContent`. Active state indicates the worktree is
/// currently displayed in canvas mode; tapping then exits back to the tab view.
struct WorktreeCanvasToolbarButton: View {
  let isActive: Bool
  let onToggle: () -> Void
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    Button {
      onToggle()
    } label: {
      Image(systemName: "square.grid.2x2")
        .symbolVariant(isActive ? .fill : .none)
        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
    }
    .help(
      AppShortcuts.helpText(
        title: isActive ? "Exit worktree canvas" : "Open this worktree in canvas",
        commandID: AppShortcuts.CommandID.toggleWorktreeCanvas,
        in: resolvedKeybindings
      )
    )
    .modifier(
      KeyboardShortcutModifier(
        shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.toggleWorktreeCanvas)
      )
    )
  }
}
