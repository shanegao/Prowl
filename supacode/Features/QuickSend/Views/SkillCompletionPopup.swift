import AppKit
import SwiftUI

struct QuickSendCompletionItem: Equatable, Sendable {
  let id: String
  let title: String
  let subtitle: String?
  let insertionText: String
  let systemImage: String
}

/// A floating, caret-anchored autocomplete popup for Quick Send composer tokens.
/// Hosted in a borderless, non-activating child window so the composer text view
/// keeps first-responder — the popup is driven entirely from the text view (which
/// forwards ↑/↓/Return/Tab) and never becomes key itself. Styled to sit on the same
/// `.regularMaterial` surface family as the Quick Send panel.
@MainActor
final class SkillCompletionController {
  private enum Constants {
    /// Most matches shown at once; the rest are summarised as "+N more" and reached
    /// by typing more of the query — keeps the popup compact without a scroll region.
    static let maxVisible = 8
    /// Fixed popup width; kept narrower than the panel's 340pt width floor
    /// (`QuickSendPanelManager.Layout.minSize`) so it fits within the composer.
    static let width: CGFloat = 280
    /// Vertical gap between the caret and the popup's nearest edge.
    static let gap: CGFloat = 4
  }

  private var window: NSPanel?
  private var hosting: NSHostingView<SkillCompletionListView>?
  private var matches: [QuickSendCompletionItem] = []
  private var overflow = 0
  /// Always a valid index into `matches` (or 0 when empty); maintained by `show`,
  /// `moveSelection`, and `hide`, and read only through `selectedCompletion`.
  private var selectedIndex = 0

  var isVisible: Bool { window?.isVisible ?? false }

  /// The item the user would insert right now, or nil when there are no matches.
  var selectedCompletion: QuickSendCompletionItem? {
    matches.indices.contains(selectedIndex) ? matches[selectedIndex] : nil
  }

  /// Show or update the popup with `allMatches`, anchored just below `anchor` (the
  /// token's rect in screen coordinates), attached to `parent`.
  func show(matches allMatches: [QuickSendCompletionItem], below anchor: NSRect, parent: NSWindow) {
    let visible = Array(allMatches.prefix(Constants.maxVisible))
    guard !visible.isEmpty else {
      hide()
      return
    }
    // Reset the highlight to the top whenever the candidate set changes (i.e. as the
    // query narrows), so the first match is always pre-selected for a quick Return.
    if visible != matches { selectedIndex = 0 }
    matches = visible
    // Keep the cursor valid even if the set shrank without changing its prefix.
    selectedIndex = min(selectedIndex, matches.count - 1)
    overflow = allMatches.count - visible.count

    let panel = window ?? makeWindow()
    hosting?.rootView = listView()
    layout(panel, below: anchor)
    if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
    panel.orderFront(nil)
  }

  /// Move the highlight by `delta` rows, clamped to the visible matches.
  func moveSelection(by delta: Int) {
    guard !matches.isEmpty else { return }
    selectedIndex = max(0, min(matches.count - 1, selectedIndex + delta))
    hosting?.rootView = listView()
  }

  func hide() {
    guard let panel = window else { return }
    panel.parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    matches = []
    overflow = 0
    selectedIndex = 0
  }

  private func listView() -> SkillCompletionListView {
    SkillCompletionListView(
      matches: matches, selectedIndex: selectedIndex, overflow: overflow, width: Constants.width)
  }

  private func makeWindow() -> NSPanel {
    let view = NSHostingView(rootView: listView())
    view.sizingOptions = [.intrinsicContentSize]
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: Constants.width, height: 44),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    panel.level = .popUpMenu
    panel.isFloatingPanel = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.contentView = view
    window = panel
    hosting = view
    return panel
  }

  private func layout(_ panel: NSPanel, below anchor: NSRect) {
    guard let hosting else { return }
    hosting.layoutSubtreeIfNeeded()
    let size = hosting.fittingSize
    panel.setContentSize(size)
    // `anchor` is in screen coordinates (origin bottom-left). Prefer dropping the
    // popup just below the token, left-aligned to its trigger; if that would clip
    // the bottom of the caret's screen, flip it above so it stays fully visible.
    let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.minX, y: anchor.minY)) }
    let bottomLimit = screen?.visibleFrame.minY ?? -.greatestFiniteMagnitude
    let belowTop = anchor.minY - Constants.gap
    let topY =
      belowTop - size.height >= bottomLimit ? belowTop : anchor.maxY + size.height + Constants.gap
    panel.setFrameTopLeftPoint(NSPoint(x: anchor.minX, y: topY))
  }
}

/// The styled list rendered inside the completion popup. Pure presentation — the
/// owning text view drives `selectedIndex` from the keyboard.
struct SkillCompletionListView: View {
  let matches: [QuickSendCompletionItem]
  let selectedIndex: Int
  var overflow = 0
  let width: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
        row(item: item, isSelected: index == selectedIndex)
      }
      if overflow > 0 {
        Text("+\(overflow) more — keep typing to narrow")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
      }
    }
    .padding(6)
    .frame(width: width, alignment: .leading)
    .background(.regularMaterial, in: .rect(cornerRadius: 10))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
  }

  // Mirrors the agent-switcher row styling in `QuickSendView` (accent fill + white
  // text when selected) so the two pickers read as the same component family.
  private func row(item: QuickSendCompletionItem, isSelected: Bool) -> some View {
    HStack(spacing: 7) {
      Image(systemName: item.systemImage)
        .font(.caption2)
        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title)
          .font(.system(.body, design: .monospaced))
          .foregroundStyle(isSelected ? Color.white : Color.primary)
          .lineLimit(1)
          .truncationMode(.middle)
        if let subtitle = item.subtitle {
          Text(subtitle)
            .font(.caption2)
            .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 6))
  }
}
