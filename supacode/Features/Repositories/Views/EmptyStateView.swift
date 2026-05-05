import ComposableArchitecture
import SwiftUI

struct EmptyStateView: View {
  let store: StoreOf<RepositoriesFeature>
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    let shortcutDisplay = AppShortcuts.display(for: AppShortcuts.CommandID.openRepository, in: resolvedKeybindings)
    VStack(spacing: 16) {
      Image(systemName: "tray")
        .font(.title2)
        .accessibilityHidden(true)
        .padding(.bottom, 4)
      Text("Open a repository or folder")
        .font(.headline)
      Text(promptText(shortcutDisplay: shortcutDisplay))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button("Add Repository...") {
        store.send(.setOpenPanelPresented(true))
      }
      .padding(.top, 4)
      .modifier(
        KeyboardShortcutModifier(
          shortcut: resolvedKeybindings.keyboardShortcut(for: AppShortcuts.CommandID.openRepository)
        )
      )
      .help(
        AppShortcuts.helpText(
          title: "Add Repository",
          commandID: AppShortcuts.CommandID.openRepository,
          in: resolvedKeybindings
        ))
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
    .multilineTextAlignment(.center)
  }

  private func promptText(shortcutDisplay: String?) -> String {
    if let shortcutDisplay {
      return "Press \(shortcutDisplay) or click Add Repository to add one."
    }
    return "Click Add Repository to add one."
  }
}
