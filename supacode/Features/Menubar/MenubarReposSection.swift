import AppKit
import ComposableArchitecture
import SwiftUI

/// Repos section of the menubar dropdown. Git repos use `Menu(_:primaryAction:)`
/// so tapping the parent row opens the first worktree and hovering reveals the
/// full worktree submenu; plain-folder repos are a single button.
struct MenubarReposSection: View {
  @Bindable var store: StoreOf<AppFeature>

  var body: some View {
    Section("Repos") {
      let orderedRepos = store.repositories.orderedRepositoryIDs()
        .compactMap { store.repositories.repositories[id: $0] }
      if orderedRepos.isEmpty {
        Button("No repositories") {}
          .disabled(true)
      } else {
        ForEach(orderedRepos) { repoRow($0) }
      }
    }
  }

  @ViewBuilder
  private func repoRow(_ repo: Repository) -> some View {
    let title = store.repositories.repositoryName(for: repo.id) ?? repo.name
    if repo.kind == .plain {
      Button(title) {
        selectRepository(repo.id)
      }
    } else {
      let rows = store.repositories.worktreeRows(in: repo)
      Menu(title) {
        ForEach(rows) { row in
          Button(row.name) {
            selectWorktree(row.id)
          }
        }
      } primaryAction: {
        // Tap on the parent row itself → open the first worktree by default,
        // matching the sidebar's "select repo" affordance.
        if let first = rows.first {
          selectWorktree(first.id)
        }
      }
    }
  }

  /// `focusTerminal: true` diverges from `WorktreeCommands.worktreeMenuButton`
  /// (which defaults to `false`): the menubar is invoked from outside Prowl, so
  /// the user expects keyboard focus to land in the terminal immediately rather
  /// than just on the sidebar row. `surfaceMainWindow()` brings the window
  /// forward for the same reason — TCA actions alone change selection silently.
  private func selectWorktree(_ id: Worktree.ID) {
    store.send(.repositories(.selectWorktree(id, focusTerminal: true, recordHistory: true)))
    NSApplication.shared.surfaceMainWindow()
  }

  private func selectRepository(_ id: Repository.ID) {
    store.send(.repositories(.selectRepository(id)))
    NSApplication.shared.surfaceMainWindow()
  }
}
