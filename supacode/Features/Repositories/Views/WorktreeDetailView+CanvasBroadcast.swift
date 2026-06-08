import ComposableArchitecture
import SwiftUI

// Supplementary toolbar content for `WorktreeDetailView`, kept in a feature-owned
// extension so the upstream-shared toolbar bodies (`worktreeToolbarContent`,
// `canvasToolbarContent`, `makeFocusedActions`) carry only one-line calls into the
// helpers below — mirroring the existing `canvasButtonGroup` wiring so future
// upstream merges stay conflict-free. Contains:
//   • the sidebar quick-nav + active-agents hover-popover buttons, and
//   • repo/overall-canvas multi-card BROADCAST — fan a global command out to every
//     selected card, with single-target shortcuts (⌘R/⌘O/⌘T/⌘F) gated off while
//     broadcasting so a stale focused card isn't targeted.
extension WorktreeDetailView {

  // MARK: - Sidebar + active-agents popover buttons

  /// Sidebar quick-nav popover + active-agents hover-popover buttons, in their
  /// own trailing group rendered adjacent to the notifications popover. The
  /// sidebar button shows only when the sidebar is collapsed (`.detailOnly`);
  /// `ToolbarSidebarPopoverButton` has no internal visibility gate and relies on
  /// this parent check (see its own doc comment).
  @ToolbarContentBuilder
  func popoverButtonsGroup() -> some ToolbarContent {
    // Break the toolbar capsule so these popover buttons — and the
    // notifications/update group that immediately follows them — render as one
    // capsule separate from the preceding canvas-mode buttons, instead of all
    // merging into a single pill.
    ToolbarSpacer(.fixed)
    ToolbarItemGroup(placement: .primaryAction) {
      if store.leftSidebarVisibility == .detailOnly {
        ToolbarSidebarPopoverButton(store: store, terminalManager: terminalManager)
      }
      ToolbarActiveAgentsPopoverButton(store: store, terminalManager: terminalManager)
    }
  }

  // MARK: - Canvas broadcast (multi-card command fan-out)

  /// Distinct worktree IDs behind the cards currently multi-selected in canvas,
  /// derived from `terminalManager.canvasSelectedTabIDs` (mirrored from
  /// CanvasView's `CanvasSelectionState`). Empty outside canvas; 2+ entries means
  /// the user is broadcasting across worktrees.
  func canvasSelectedWorktreeIDs() -> Set<Worktree.ID> {
    let tabIDs = terminalManager.canvasSelectedTabIDs
    guard !tabIDs.isEmpty else { return [] }
    return Set(
      tabIDs.compactMap { tabID in
        terminalManager.activeWorktreeStates
          .first(where: { $0.surfaceView(for: tabID) != nil })?
          .worktreeID
      }
    )
  }

  /// True while 2+ worktrees' cards are multi-selected in canvas. Drives both the
  /// broadcast command toolbar and the suppression of single-target shortcuts
  /// (⌘R/⌘O/⌘T/⌘F) so a stale focused card isn't targeted mid-broadcast.
  func isCanvasBroadcasting() -> Bool {
    canvasSelectedWorktreeIDs().count > 1
  }

  // MARK: - Scoped canvas navigation title

  /// Window-proxy / Window-menu / accessibility title for the detail pane. In a
  /// per-worktree or per-repository canvas it reads "Canvas · <name>" so the
  /// scope is identifiable; everything else defers to `WindowTitle.compute`. The
  /// on-screen title bar is hidden in canvas via `.toolbar(removing:)`, so this
  /// only affects the off-screen title surfaces.
  func detailNavigationTitle(repositories: RepositoriesFeature.State) -> String {
    if let worktreeID = repositories.scopedCanvasWorktreeID,
      let worktree = repositories.worktree(for: worktreeID)
    {
      return "Canvas · \(worktree.name)"
    }
    if let repositoryID = repositories.scopedCanvasRepositoryID,
      let repository = repositories.repositories[id: repositoryID]
    {
      return "Canvas · \(repository.name)"
    }
    return WindowTitle.compute(repositories: repositories, terminalManager: terminalManager)
  }

  /// Slim global-command buttons shown in repo/overall canvas while broadcasting;
  /// each fans the command out to every selected worktree via the reducer's
  /// `runCustomCommandOnWorktrees`. `globalCommands` is injected from the call
  /// site because `@Shared(.settingsFile)` is private to `WorktreeDetailView`.
  @ToolbarContentBuilder
  func broadcastCommandsToolbar(
    globalCommands: [UserCustomCommand],
    targets: Set<Worktree.ID>
  ) -> some ToolbarContent {
    // Broadcast shows only runnable globals (filtered before slicing), unlike the
    // per-card toolbar which also lists non-runnable commands but disabled — a
    // per-target "disabled" state isn't meaningful when fanning out to N worktrees.
    let runnable = globalCommands.filter(\.hasRunnableCommand)
    let inline = Array(runnable.prefix(3))
    let overflow = Array(runnable.dropFirst(3))
    if !inline.isEmpty {
      ToolbarSpacer(.fixed)
      ToolbarItemGroup(placement: .primaryAction) {
        ForEach(inline, id: \.id) { command in
          UserCustomCommandToolbarButton(
            title: command.resolvedTitle,
            systemImage: command.resolvedSystemImage,
            shortcut: nil,
            isEnabled: true,
            action: {
              guard !targets.isEmpty else { return }
              store.send(.runCustomCommandOnWorktrees(command, targets))
            }
          )
        }
      }
    }
    if !overflow.isEmpty {
      ToolbarItem(placement: .primaryAction) {
        CustomCommandOverflowButton(
          entries: overflow.enumerated().map { (index: $0.offset, command: $0.element) },
          shortcutDisplay: { _ in nil },
          onRunCustomCommand: { offset in
            guard overflow.indices.contains(offset) else { return }
            store.send(.runCustomCommandOnWorktrees(overflow[offset], targets))
          }
        )
      }
    }
  }
}
