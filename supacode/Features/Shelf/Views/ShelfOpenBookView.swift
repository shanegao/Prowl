import AppKit
import SwiftUI

/// Renders the terminal content for the currently open book.
///
/// Mirrors the terminal-content slice of `WorktreeTerminalTabsView` without
/// the horizontal tab bar: in Shelf the tab bar lives on the book's spine,
/// so we only render the content stack (plus icon picker sheet + focus
/// observer) here.
struct ShelfOpenBookView: View {
  let worktree: Worktree
  let manager: WorktreeTerminalManager
  let shouldRunSetupScript: Bool

  @State private var windowActivity = WindowActivityState.inactive

  var body: some View {
    let state = manager.state(for: worktree) { shouldRunSetupScript }
    Group {
      if let selectedId = state.tabManager.selectedTabId {
        TerminalTabContentStack(tabs: state.tabManager.tabs, selectedTabId: selectedId) { tabId in
          TerminalSplitTreeAXContainer(tree: state.splitTree(for: tabId)) { operation in
            state.performSplitOperation(operation, in: tabId)
          }
        }
      } else {
        EmptyTerminalPaneView(message: "No terminals open")
      }
    }
    .sheet(
      item: Binding(
        get: { state.iconPickerTabId },
        set: { state.iconPickerTabId = $0 }
      )
    ) { tabId in
      let currentIcon = state.tabManager.tabs.first(where: { $0.id == tabId })?.icon
      TabIconPickerView(
        initialIcon: currentIcon,
        defaultIcon: state.defaultIcon(for: tabId),
        onApply: { newIcon in
          state.applyIconChange(tabId, icon: newIcon)
          state.dismissIconPicker()
        },
        onCancel: {
          state.dismissIconPicker()
        }
      )
    }
    .background(
      WindowFocusObserverView { activity in
        windowActivity = activity
        state.syncFocus(windowIsKey: activity.isKeyWindow, windowIsVisible: activity.isVisible)
      }
    )
  }
}
