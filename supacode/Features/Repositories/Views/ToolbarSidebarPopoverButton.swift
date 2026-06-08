import ComposableArchitecture
import SwiftUI

/// Quick-navigation popover button that complements the macOS-provided sidebar
/// toggle. Click toggles the sidebar (same dispatch as the system button);
/// hover presents a popover with the full `SidebarView` so the user can pick
/// a different worktree without first opening the sidebar.
///
/// Visibility is gated by the **parent** — this view should only be added to
/// the toolbar when the sidebar is collapsed. Hover lifecycle (150 ms debounce
/// close when the cursor leaves both button and popover) mirrors
/// `ToolbarNotificationsPopoverButton`.
struct ToolbarSidebarPopoverButton: View {
  @Bindable var store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @State private var isPresented = false
  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var closeTask: Task<Void, Never>?
  /// Stable identity used by `PopoverPresentationCoordinator` to track
  /// which popover button currently holds presentation. Created once per
  /// view-instance via `@State`, distinct from sibling popover buttons.
  @State private var popoverOwnerID = UUID()
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings
  @Environment(PopoverPresentationCoordinator.self) private var popoverCoordinator

  var body: some View {
    Button {
      store.send(.toggleLeftSidebar)
    } label: {
      Image(systemName: "rectangle.stack.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(.orange, .secondary)
        .accessibilityHidden(true)
    }
    .help(
      AppShortcuts.helpText(
        title: "Show Sidebar",
        commandID: AppShortcuts.CommandID.toggleLeftSidebar,
        in: resolvedKeybindings
      )
    )
    .accessibilityLabel("Show Sidebar")
    .onHover { hovering in
      isHoveringButton = hovering
      updatePresentation()
    }
    .popover(isPresented: $isPresented) {
      SidebarView(
        store: store.scope(state: \.repositories, action: \.repositories),
        terminalManager: terminalManager,
        showsHeaderChrome: false
      )
      // SidebarView's `.navigationSplitViewColumnWidth(min: 220, ideal: 260,
      // max: 320)` is silently ignored outside `NavigationSplitView`, so the
      // popover would otherwise collapse to a narrow `List` default. These
      // hints match the docked sidebar's column-width ideal.
      .frame(idealWidth: 320, idealHeight: 560)
      .onHover { hovering in
        isHoveringPopover = hovering
        updatePresentation()
      }
      .onDisappear {
        isHoveringPopover = false
      }
    }
    // Coordinate with sibling toolbar popover buttons so only one is
    // presented at a time. See `PopoverPresentationCoordinator` for the
    // race-condition this prevents (fast cursor sweep freezing the app).
    .onChange(of: isPresented) { _, isOpen in
      if isOpen {
        popoverCoordinator.claim(owner: popoverOwnerID) {
          isPresented = false
        }
      } else {
        popoverCoordinator.release(owner: popoverOwnerID)
      }
    }
    .onDisappear {
      closeTask?.cancel()
      popoverCoordinator.release(owner: popoverOwnerID)
    }
  }

  private func updatePresentation() {
    if isHoveringButton || isHoveringPopover {
      closeTask?.cancel()
      isPresented = true
      return
    }
    closeTask?.cancel()
    closeTask = Task { @MainActor in
      try? await ContinuousClock().sleep(for: .milliseconds(150))
      if !Task.isCancelled {
        isPresented = false
      }
    }
  }
}
