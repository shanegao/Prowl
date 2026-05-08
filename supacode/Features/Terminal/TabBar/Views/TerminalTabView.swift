import AppKit
import SwiftUI

struct TerminalTabView: View {
  let tab: TerminalTabItem
  let isActive: Bool
  let isDragging: Bool
  let tabIndex: Int
  let fixedWidth: CGFloat?
  let hasNotification: Bool
  let onSelect: () -> Void
  let onClose: () -> Void
  let onRename: (String) -> Void
  @Binding var closeButtonGestureActive: Bool
  let isEditing: Bool
  let onBeginRename: () -> Void
  let onEndRename: () -> Void

  @State private var isHovering = false
  @State private var isHoveringClose = false
  @State private var isPressing = false
  @State private var editingTitle = ""
  @State private var initialEditingTitle = ""
  @State private var cancelOnExit = false
  @FocusState private var isFieldFocused: Bool
  @Environment(CommandKeyObserver.self) private var commandKeyObserver
  @Environment(\.resolvedKeybindings) private var resolvedKeybindings

  var body: some View {
    ZStack(alignment: .trailing) {
      Button(action: onSelect) {
        TerminalTabLabelView(
          tab: tab,
          isActive: isActive,
          isHoveringTab: isHovering,
          isHoveringClose: isHoveringClose,
          shortcutHint: shortcutHint,
          showsShortcutHint: showsShortcutHint
        )
      }
      .buttonStyle(TerminalTabButtonStyle(isPressing: $isPressing))
      .frame(
        minWidth: TerminalTabBarMetrics.tabMinWidth,
        maxWidth: TerminalTabBarMetrics.tabMaxWidth,
        minHeight: TerminalTabBarMetrics.tabHeight,
        maxHeight: TerminalTabBarMetrics.tabHeight
      )
      .frame(width: fixedWidth)
      .contentShape(.rect)
      .help("Open tab \(tab.displayTitle)")
      .accessibilityLabel(tab.displayTitle)
      .allowsHitTesting(!isEditing)
      .opacity(isEditing ? 0 : 1)

      ZStack {
        TabNotificationDot()
          .opacity(isShowingNotificationDot ? 1 : 0)
          .allowsHitTesting(false)
        TerminalTabCloseButton(
          isHoveringTab: isHovering,
          isDragging: isDragging,
          isShowingShortcutHint: showsShortcutHint,
          closeAction: onClose,
          closeButtonGestureActive: $closeButtonGestureActive,
          isHoveringClose: $isHoveringClose
        )
      }
      .animation(.easeInOut(duration: TerminalTabBarMetrics.hoverAnimationDuration), value: isHovering)
      .animation(.easeInOut(duration: 0.2), value: hasNotification)
      .padding(.trailing, TerminalTabBarMetrics.tabHorizontalPadding)
      .opacity(isEditing ? 0 : 1)
      .allowsHitTesting(!isEditing)
    }
    .overlay {
      if isEditing {
        TextField("", text: $editingTitle)
          .textFieldStyle(.plain)
          .font(.caption)
          .focused($isFieldFocused)
          .foregroundStyle(TerminalTabBarColors.activeText)
          .accessibilityLabel("Rename tab")
          .padding(.horizontal, TerminalTabBarMetrics.contentSpacing)
          .background(
            RoundedRectangle(
              cornerRadius: TerminalTabBarMetrics.renameFieldCornerRadius,
              style: .continuous
            )
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
              RoundedRectangle(
                cornerRadius: TerminalTabBarMetrics.renameFieldCornerRadius,
                style: .continuous
              )
              .strokeBorder(Color.accentColor, lineWidth: 1.5)
            )
          )
          .padding(.leading, TerminalTabBarMetrics.tabHorizontalPadding - TerminalTabBarMetrics.contentSpacing)
          .padding(.trailing, TerminalTabBarMetrics.closeButtonSize + TerminalTabBarMetrics.contentSpacing)
          .padding(.vertical, TerminalTabBarMetrics.renameFieldInset)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .onSubmit { onEndRename() }
          .onExitCommand {
            cancelOnExit = true
            onEndRename()
          }
          .onChange(of: isFieldFocused) { _, focused in
            guard !focused, isEditing else { return }
            onEndRename()
          }
      }
    }
    .background {
      TerminalTabBackground(
        isActive: isActive,
        isPressing: isPressing,
        isDragging: isDragging,
        isHovering: isHovering
      )
      .animation(.easeInOut(duration: TerminalTabBarMetrics.hoverAnimationDuration), value: isHovering)
    }
    .padding(.bottom, isActive ? TerminalTabBarMetrics.activeTabBottomPadding : 0)
    .offset(y: isActive ? TerminalTabBarMetrics.activeTabOffset : 0)
    .clipShape(.rect(cornerRadius: TerminalTabBarMetrics.tabCornerRadius))
    .contentShape(.rect)
    .onHover { hovering in
      isHovering = hovering
    }
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        guard !tab.isTitleLocked else { return }
        onBeginRename()
      }
    )
    .onChange(of: isEditing) { _, editing in
      if editing {
        editingTitle = tab.displayTitle
        initialEditingTitle = tab.displayTitle
        cancelOnExit = false
        isFieldFocused = true
        // The field editor only attaches after SwiftUI promotes the TextField
        // to first responder, so defer selectAll one hop to land on it.
        DispatchQueue.main.async {
          NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
      } else if cancelOnExit {
        cancelOnExit = false
      } else if editingTitle != initialEditingTitle {
        onRename(editingTitle)
      }
    }
    .zIndex(isActive ? 2 : (isDragging ? 3 : 0))
    .overlay {
      MiddleClickView(action: onClose)
    }
  }

  private var shortcutHint: String? {
    AppShortcuts.terminalTabSelectionDisplay(at: tabIndex, in: resolvedKeybindings)
  }

  private var showsShortcutHint: Bool {
    commandKeyObserver.isPressed && shortcutHint != nil
  }

  private var isShowingNotificationDot: Bool {
    hasNotification && !isHovering && !isHoveringClose && !isDragging && !showsShortcutHint
  }
}

private struct TabNotificationDot: View {
  var body: some View {
    Circle()
      .fill(.orange)
      .frame(width: 6, height: 6)
      .frame(width: TerminalTabBarMetrics.closeButtonSize, height: TerminalTabBarMetrics.closeButtonSize)
      .accessibilityLabel("Unread notifications")
  }
}

private struct MiddleClickView: NSViewRepresentable {
  let action: () -> Void

  func makeNSView(context: Context) -> MiddleClickNSView {
    MiddleClickNSView(action: action)
  }

  func updateNSView(_ nsView: MiddleClickNSView, context: Context) {
    nsView.action = action
  }
}

private final class MiddleClickNSView: NSView {
  var action: () -> Void

  init(action: @escaping () -> Void) {
    self.action = action
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let event = NSApp.currentEvent,
      event.type == .otherMouseDown || event.type == .otherMouseUp
    else { return nil }
    return super.hitTest(point)
  }

  override func otherMouseUp(with event: NSEvent) {
    if event.buttonNumber == 2 {
      action()
    } else {
      super.otherMouseUp(with: event)
    }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
