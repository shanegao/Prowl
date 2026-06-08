import AppKit
import ComposableArchitecture
import SwiftUI

/// Always-available macOS status-bar dropdown for switching worktrees and
/// surfacing active agents. Sibling to the main `Window` scene in
/// `SupacodeApp.body`; activation policy stays `.regular` so the Dock icon
/// also remains.
struct MenubarScene: Scene {
  @Bindable var store: StoreOf<AppFeature>

  var body: some Scene {
    MenuBarExtra("Prowl", systemImage: "square.split.bottomrightquarter") {
      MenubarReposSection(store: store)
      Divider()
      MenubarActiveAgentsSection(store: store)
      Divider()
      Button("Open Prowl Window") {
        NSApplication.shared.surfaceMainWindow()
      }
      Button("Quit Prowl") {
        store.send(.requestQuit)
      }
    }
    .menuBarExtraStyle(.menu)
  }
}
