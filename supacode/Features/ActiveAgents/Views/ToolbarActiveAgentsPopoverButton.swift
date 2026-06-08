import ComposableArchitecture
import Sharing
import SwiftUI

struct ToolbarActiveAgentsPopoverButton: View {
  @Bindable var store: StoreOf<AppFeature>
  let terminalManager: WorktreeTerminalManager
  @State private var isPresented = false
  @State private var isPinnedOpen = false
  @State private var isHoveringButton = false
  @State private var isHoveringPopover = false
  @State private var closeTask: Task<Void, Never>?
  /// Stable identity used by `PopoverPresentationCoordinator` to track
  /// which popover button currently holds presentation.
  @State private var popoverOwnerID = UUID()
  @Shared(.repositoryAppearances) private var repositoryAppearances
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @Environment(PopoverPresentationCoordinator.self) private var popoverCoordinator

  private var agentCount: Int {
    store.repositories.activeAgents.entries.count
  }

  private var worktreeMetadata: ActiveAgentWorktreeMetadata {
    SidebarListView.activeAgentWorktreeMetadata(
      repositories: store.repositories.repositories,
      customTitles: store.repositories.repositoryCustomTitles,
      repositoryAppearances: repositoryAppearances
    )
  }

  /// Per-entry repository/branch/color labels resolved here so the panel stays
  /// presentational — the resolution rule (workingDirectory-first, fallback to
  /// the owning worktree) lives in `SidebarListView.activeAgentRowDisplay`.
  private var rowDisplays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay] {
    SidebarListView.activeAgentRowDisplays(
      entries: store.repositories.activeAgents.entries,
      repositories: store.repositories.repositories,
      metadata: worktreeMetadata
    )
  }

  private var selectedSurfaceID: UUID? {
    store.repositories.selectedWorktreeID.flatMap { worktreeID in
      terminalManager.stateIfExists(for: worktreeID)?.activeSurfaceID
    }
  }

  /// Merged "⌥⌃↑↓" hint shown only while Cmd is held; `nil` otherwise. Resolved
  /// here (the popover's owner) so `ActiveAgentsPanel` stays presentational.
  private var navigationShortcutHint: String? {
    commandKeyObserver.isPressed
      ? AppShortcuts.activeAgentsNavigationDisplay(in: resolvedKeybindings)
      : nil
  }

  var body: some View {
    Button {
      togglePresentation()
    } label: {
      HStack(spacing: 6) {
        Image(systemName: agentCount > 0 ? "wand.and.stars.inverse" : "wand.and.stars")
          .foregroundStyle(agentCount > 0 ? .orange : .secondary)
          .accessibilityHidden(true)
        if agentCount > 0 {
          Text(agentCount, format: .number)
            .font(.caption.monospacedDigit())
        }
      }
    }
    .help(
      AppShortcuts.helpText(
        title: "Active Agents",
        commandID: AppShortcuts.CommandID.toggleActiveAgentsPanel,
        in: resolvedKeybindings
      )
    )
    .accessibilityLabel("Active Agents")
    .onHover { hovering in
      isHoveringButton = hovering
      updatePresentation()
    }
    .popover(isPresented: $isPresented) {
      ActiveAgentsPanel(
        store: store.scope(state: \.repositories.activeAgents, action: \.repositories.activeAgents),
        rowDisplays: rowDisplays,
        selectedSurfaceID: selectedSurfaceID,
        navigationShortcutHint: navigationShortcutHint,
        showTabTitles: store.repositories.showActiveAgentTabTitles,
        onEntrySelected: { closePopover() }
      )
      .onHover { hovering in
        isHoveringPopover = hovering
        updatePresentation()
      }
      .onDisappear {
        isHoveringPopover = false
        isPinnedOpen = false
      }
    }
    // Coordinate with sibling toolbar popover buttons so only one is
    // presented at a time. See `PopoverPresentationCoordinator` for the
    // race-condition this prevents (fast cursor sweep freezing the app).
    .onChange(of: isPresented) { _, isOpen in
      if isOpen {
        popoverCoordinator.claim(owner: popoverOwnerID) {
          closePopover()
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

  private func togglePresentation() {
    if isPinnedOpen {
      closePopover()
      return
    }
    closeTask?.cancel()
    isPinnedOpen = true
    isPresented = true
  }

  private func updatePresentation() {
    if isPinnedOpen || isHoveringButton || isHoveringPopover {
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

  private func closePopover() {
    closeTask?.cancel()
    isPinnedOpen = false
    isPresented = false
  }
}
