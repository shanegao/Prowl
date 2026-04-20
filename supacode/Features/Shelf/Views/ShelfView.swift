import ComposableArchitecture
import SwiftUI

/// Root view for Shelf presentation mode.
///
/// Phase 2 layout: three horizontal segments — a left stack of passed
/// spines, the currently open book's terminal area, and a right stack of
/// upcoming spines. Subsequent phases layer in tab slots, animations,
/// notification badges, the bottom controls, and context menus described
/// in `doc-onevcat/shelf-view.md`.
struct ShelfView: View {
  let store: StoreOf<RepositoriesFeature>
  let terminalManager: WorktreeTerminalManager

  var body: some View {
    let state = store.state
    let books = state.orderedShelfBooks()
    let openBookID = state.openShelfBookID
    let openIndex = openBookID.flatMap { id in
      books.firstIndex(where: { $0.id == id })
    }

    HStack(spacing: 0) {
      if let openIndex {
        spineStack(books: Array(books[0...openIndex]), openIndex: openIndex, isLeftStack: true)
        openBookArea(for: books[openIndex], state: state)
        let rightStart = openIndex + 1
        if rightStart < books.count {
          spineStack(
            books: Array(books[rightStart..<books.count]),
            openIndex: openIndex,
            isLeftStack: false
          )
        }
      } else {
        spineStack(books: books, openIndex: nil, isLeftStack: true)
        emptyOpenArea()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background)
  }

  @ViewBuilder
  private func spineStack(books: [ShelfBook], openIndex: Int?, isLeftStack: Bool) -> some View {
    HStack(spacing: 0) {
      ForEach(Array(books.enumerated()), id: \.element.id) { _, book in
        ShelfSpineView(
          book: book,
          isOpen: isOpen(book),
          onTap: { handleSpineTap(book) }
        )
      }
    }
  }

  private func isOpen(_ book: ShelfBook) -> Bool {
    store.state.openShelfBookID == book.id
  }

  @ViewBuilder
  private func openBookArea(for book: ShelfBook, state: RepositoriesFeature.State) -> some View {
    if let worktree = state.selectedTerminalWorktree, worktree.id == book.id {
      ShelfOpenBookView(
        worktree: worktree,
        manager: terminalManager,
        shouldRunSetupScript: state.pendingSetupScriptWorktreeIDs.contains(worktree.id)
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .id(worktree.id)
    } else {
      emptyOpenArea()
    }
  }

  @ViewBuilder
  private func emptyOpenArea() -> some View {
    VStack(spacing: 10) {
      Image(systemName: "books.vertical")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text("No book selected")
        .font(.headline)
      Text("Click a spine to open a book.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func handleSpineTap(_ book: ShelfBook) {
    switch book.kind {
    case .worktree:
      store.send(.selectWorktree(book.id, focusTerminal: true))
    case .plainFolder:
      store.send(.selectRepository(book.repositoryID))
    }
  }
}
