import SwiftUI

/// Vertical spine rendering for a single book on the Shelf.
///
/// Phase 2 scope: geometry (one-line-text width), rotated header
/// (name/branch), and a fixed-width selection background. Tab slots,
/// notification badges, ⌘-overlay digits, and bottom controls are added
/// in later phases.
struct ShelfSpineView: View {
  let book: ShelfBook
  let isOpen: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .center, spacing: 4) {
        ShelfSpineHeader(book: book)
          .padding(.top, 8)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .frame(width: ShelfMetrics.spineWidth)
    .background(spineBackground)
    .overlay(alignment: .trailing) {
      if !isOpen {
        Divider()
          .opacity(0.4)
      }
    }
    .help("\(book.displayName)")
  }

  @ViewBuilder
  private var spineBackground: some View {
    if isOpen {
      Color.accentColor.opacity(0.12)
    } else {
      Color.clear
    }
  }
}

private struct ShelfSpineHeader: View {
  let book: ShelfBook

  var body: some View {
    VStack(spacing: 6) {
      Text(book.displayName)
        .font(.callout.weight(.semibold))
        .lineLimit(1)
        .truncationMode(.tail)
        .fixedSize()
        .rotationEffect(.degrees(90))
        .frame(width: ShelfMetrics.spineWidth, alignment: .center)
      if let branchName = book.branchName, branchName != book.displayName {
        Text(branchName)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .fixedSize()
          .rotationEffect(.degrees(90))
          .frame(width: ShelfMetrics.spineWidth, alignment: .center)
      }
    }
    .padding(.top, 36)
    .padding(.bottom, 8)
  }
}

/// Shared metrics for the Shelf layout so the three segments stay in sync.
enum ShelfMetrics {
  /// Width of a single spine (roughly one line of text).
  static let spineWidth: CGFloat = 26
}
