import SwiftUI

/// Toolbar button that opens the app-wide **overall** canvas — a board of every
/// open terminal across all repositories. Placed inside the canvas-button group
/// after the worktree- and repository-canvas toggles (it's the broadest scope)
/// and before the cross-cutting active-agents toggle. Active state means the
/// overall canvas is showing; tapping then exits back to a worktree.
///
/// Unlike its sibling toggles it carries **no** `KeyboardShortcutModifier`: the
/// overall-canvas hotkey is registered once as the global "Canvas" menu command
/// in `SidebarCommands`, so binding it here too would double-register `⌘⌥↩`. The
/// help text still surfaces the shortcut for discoverability.
struct OverallCanvasToolbarButton: View {
  let isActive: Bool
  let onToggle: () -> Void
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    Button {
      onToggle()
    } label: {
      Image(systemName: "square.stack")
        .symbolVariant(isActive ? .fill : .none)
        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
    }
    .help(
      AppShortcuts.helpText(
        title: isActive ? "Exit overall canvas" : "Open overall canvas",
        commandID: AppShortcuts.CommandID.toggleCanvas,
        in: resolvedKeybindings
      )
    )
  }
}
