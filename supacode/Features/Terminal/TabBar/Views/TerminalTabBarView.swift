import SwiftUI

struct TerminalTabBarView: View {
  @Bindable var manager: TerminalTabManager
  let createTab: () -> Void
  let splitHorizontally: () -> Void
  let splitVertically: () -> Void
  let canSplit: Bool
  let renameTab: (TerminalTabID) -> Void
  let changeIcon: (TerminalTabID) -> Void
  let closeTab: (TerminalTabID) -> Void
  let closeOthers: (TerminalTabID) -> Void
  let closeToRight: (TerminalTabID) -> Void
  let closeAll: () -> Void
  let hasNotification: (TerminalTabID) -> Bool
  @Environment(\.controlActiveState)
  private var activeState

  var body: some View {
    HStack(spacing: 0) {
      TerminalTabsView(
        manager: manager,
        renameTab: renameTab,
        changeIcon: changeIcon,
        closeTab: closeTab,
        closeOthers: closeOthers,
        closeToRight: closeToRight,
        closeAll: closeAll,
        hasNotification: hasNotification
      )
      // Background wraps only the tabs; the trailing accessories (+ / splits)
      // sit outside it on the bare bar chrome.
      .background(TerminalTabBarBackground())
      Spacer(minLength: 0)
      TerminalTabBarTrailingAccessories(
        createTab: createTab,
        splitHorizontally: splitHorizontally,
        splitVertically: splitVertically,
        canSplit: canSplit
      )
    }
    .frame(height: TerminalTabBarMetrics.barHeight)
    .saturation(activeState == .inactive ? 0 : 1)
    .clipped()
  }
}

// MARK: - Previews

#if DEBUG
  @MainActor
  private struct TerminalTabBarPreviewRow: View {
    let title: String
    @State private var manager: TerminalTabManager

    init(title: String, tabCount: Int) {
      self.title = title
      let manager = TerminalTabManager()
      for index in 0..<tabCount {
        _ = manager.createTab(title: Self.sampleTitles[index % Self.sampleTitles.count], icon: nil)
      }
      manager.selectedTabId = manager.tabs.first?.id
      _manager = State(initialValue: manager)
    }

    private static let sampleTitles = [
      "zsh", "npm run dev", "git status", "vim README.md", "claude",
      "docker compose -h this is a long title", "tail -f log", "python main.py", "ssh prod", "htop",
      "make build", "swift test", "node server", "redis-cli", "psql",
    ]

    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        TerminalTabBarView(
          manager: manager,
          createTab: {},
          splitHorizontally: {},
          splitVertically: {},
          canSplit: true,
          renameTab: { _ in },
          changeIcon: { _ in },
          closeTab: { manager.closeTab($0) },
          closeOthers: { manager.closeOthers(keeping: $0) },
          closeToRight: { manager.closeToRight(of: $0) },
          closeAll: { manager.closeAll() },
          hasNotification: { _ in false }
        )
      }
    }
  }

  #Preview("Terminal Tab Bar States") {
    VStack(alignment: .leading, spacing: 16) {
      TerminalTabBarPreviewRow(title: "0 tabs", tabCount: 0)
      TerminalTabBarPreviewRow(title: "1 tab", tabCount: 1)
      TerminalTabBarPreviewRow(title: "2 tabs", tabCount: 2)
      TerminalTabBarPreviewRow(title: "15 tabs (scrollable)", tabCount: 15)
    }
    .padding()
    .frame(width: 720)
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(CommandKeyObserver())
    .environment(GhosttyShortcutManager(preview: ()))
  }
#endif
