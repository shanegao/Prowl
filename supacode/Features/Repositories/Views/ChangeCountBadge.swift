import SwiftUI

/// `+added −removed` capsule badge for a worktree's diff size. Shared by the
/// sidebar worktree row and the toolbar's no-PR status item so both render the
/// change counts identically. `strokeStyle` lets the host tune the capsule
/// outline (the sidebar dims it when the row is selected); `font` lets the host
/// size it (the popover floors it at 14pt; the compact sidebar keeps `.caption`).
struct ChangeCountBadge: View {
  let addedLines: Int
  let removedLines: Int
  var strokeStyle: AnyShapeStyle = AnyShapeStyle(.tertiary)
  var font: Font = .caption

  var body: some View {
    HStack(spacing: 4) {
      Text("+\(addedLines)")
        .foregroundStyle(.green)
      Text("-\(removedLines)")
        .foregroundStyle(.red)
        .baselineOffset(-1)
    }
    .font(font)
    .lineLimit(1)
    .padding(.horizontal, 4)
    .fixedSize(horizontal: true, vertical: false)
    .overlay {
      Capsule().stroke(strokeStyle, lineWidth: 1)
    }
    .monospacedDigit()
  }
}
