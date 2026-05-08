import AppKit
import SwiftUI

struct WorktreeTerminalTabsView: View {
  let worktree: Worktree
  let manager: WorktreeTerminalManager
  let shouldRunSetupScript: Bool
  let forceAutoFocus: Bool
  let createTab: () -> Void
  @State private var windowActivity = WindowActivityState.inactive
  @State private var configReloadCounter = 0

  var body: some View {
    let state = manager.state(for: worktree) { shouldRunSetupScript }
    let _ = configReloadCounter
    let unfocusedSplitOverlay = manager.unfocusedSplitOverlay()
    VStack(spacing: 0) {
      TerminalTabBarView(
        manager: state.tabManager,
        createTab: createTab,
        splitHorizontally: {
          _ = state.performBindingActionOnFocusedSurface("new_split:down")
        },
        splitVertically: {
          _ = state.performBindingActionOnFocusedSurface("new_split:right")
        },
        canSplit: state.tabManager.selectedTabId != nil,
        renameTab: { tabId in
          state.tabManager.beginTabRename(tabId)
        },
        changeIcon: { tabId in
          state.presentIconPicker(for: tabId)
        },
        closeTab: { tabId in
          state.closeTab(tabId)
        },
        closeOthers: { tabId in
          state.closeOtherTabs(keeping: tabId)
        },
        closeToRight: { tabId in
          state.closeTabsToRight(of: tabId)
        },
        closeAll: {
          state.closeAllTabs()
        },
        hasNotification: { tabId in
          state.hasUnseenNotification(for: tabId)
        }
      )
      if let selectedId = state.tabManager.selectedTabId {
        TerminalTabContentStack(tabs: state.tabManager.tabs, selectedTabId: selectedId) { tabId in
          TerminalSplitTreeAXContainer(
            tree: state.splitTree(for: tabId),
            activeSurfaceID: state.activeSurfaceID(for: tabId),
            unfocusedSplitOverlay: unfocusedSplitOverlay,
            hasNotification: { surfaceID in
              state.hasUnseenNotification(forSurfaceID: surfaceID)
            },
            action: { operation in
              state.performSplitOperation(operation, in: tabId)
            }
          )
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
    .onAppear {
      state.ensureInitialTab(focusing: false)
      if shouldAutoFocusTerminal {
        state.focusSelectedTab()
      }
      let activity = resolvedWindowActivity
      state.syncFocus(windowIsKey: activity.isKeyWindow, windowIsVisible: activity.isVisible)
    }
    .onChange(of: state.tabManager.selectedTabId) { _, _ in
      if shouldAutoFocusTerminal {
        state.focusSelectedTab()
      }
      let activity = resolvedWindowActivity
      state.syncFocus(windowIsKey: activity.isKeyWindow, windowIsVisible: activity.isVisible)
    }
    .onReceive(NotificationCenter.default.publisher(for: .ghosttyRuntimeConfigDidChange)) { _ in
      configReloadCounter &+= 1
    }
  }

  private var shouldAutoFocusTerminal: Bool {
    if forceAutoFocus {
      return true
    }
    guard let responder = NSApp.keyWindow?.firstResponder else { return true }
    return !(responder is NSTableView) && !(responder is NSOutlineView)
  }

  private var resolvedWindowActivity: WindowActivityState {
    if let keyWindow = NSApp.keyWindow {
      return WindowActivityState(
        isKeyWindow: keyWindow.isKeyWindow,
        isVisible: keyWindow.occlusionState.contains(.visible)
      )
    }
    return windowActivity
  }
}
