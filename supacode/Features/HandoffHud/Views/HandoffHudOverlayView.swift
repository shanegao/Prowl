import AppKit
import ComposableArchitecture
import SwiftUI

/// Command-palette-style overlay hosting the staged hand-off flow
/// (docs-ai 049). The panel is a projection of `HandoffHudFeature` state;
/// clicking outside dismisses only while choosing or finished — a running
/// hand-off keeps the panel up in this wave.
struct HandoffHudOverlayView: View {
  let store: StoreOf<HandoffHudFeature>

  var body: some View {
    ZStack {
      Color.clear
        .contentShape(.rect)
        .onTapGesture {
          switch store.phase {
          case .choosing:
            store.send(.cancelTapped)
          case .finished:
            store.send(.closeTapped)
          case .running:
            break
          }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Dismiss Hand Off")

      GeometryReader { geometry in
        VStack {
          HandoffHudCard(store: store)
            .zIndex(1)
          Spacer(minLength: 0)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        .padding(.top, max(0, geometry.size.height * 0.22))
      }
    }
  }
}

private struct HandoffHudCard: View {
  let store: StoreOf<HandoffHudFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      switch store.phase {
      case .choosing:
        HandoffHudChooseView(store: store)
      case .running(let run):
        HandoffHudRunView(run: run, sourceDisplayName: store.source.displayName) {
          store.send(.skipBriefingTapped)
        } onCancel: {
          store.send(.cancelTapped)
        }
      case .finished(let outcome):
        HandoffHudFinishedView(outcome: outcome) {
          store.send(.closeTapped)
        }
      }
    }
    .background {
      HandoffHudKeyCaptureView(
        onMove: { delta in store.send(.moveSelection(delta: delta)) },
        onConfirm: { confirmForCurrentPhase() },
        onEscape: { escapeForCurrentPhase() }
      )
    }
    .frame(maxWidth: 560)
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
    .shadow(radius: 32, x: 0, y: 12)
    .padding(16)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(headerTitle)
        .font(.headline)
      Text(headerSubtitle)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var headerTitle: String {
    switch store.phase {
    case .choosing:
      return "Hand Off"
    case .running(let run):
      switch run.target.kind {
      case .agent:
        return "Handing off to \(run.target.title)"
      case .briefOnly:
        return "Updating the brief"
      }
    case .finished(.handedOff(let name)):
      return "Handed off to \(name)"
    case .finished(.briefSaved):
      return "Brief updated"
    case .finished(.failed):
      return "Hand off failed"
    }
  }

  private var headerSubtitle: String {
    switch store.phase {
    case .choosing:
      if store.source.preparationRequest != nil {
        return "\(store.source.displayName) will brief the incoming agent first"
      }
      return "Hands this task to another agent in a new tab"
    case .running(let run):
      if run.stage == .briefing {
        return "\(store.source.displayName) is writing a brief for the next agent"
      }
      return "Preparing the hand-off…"
    case .finished(.handedOff):
      return "The receiving agent starts from the hand-off notes in a new tab"
    case .finished(.briefSaved):
      return "The current state is saved for a later hand-off"
    case .finished(.failed(let message)):
      return message
    }
  }

  private func confirmForCurrentPhase() {
    switch store.phase {
    case .choosing:
      store.send(.confirmSelection)
    case .finished:
      store.send(.closeTapped)
    case .running:
      break
    }
  }

  private func escapeForCurrentPhase() {
    switch store.phase {
    case .choosing, .running:
      store.send(.cancelTapped)
    case .finished:
      store.send(.closeTapped)
    }
  }
}

// MARK: - Choose step

private struct HandoffHudChooseView: View {
  let store: StoreOf<HandoffHudFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(spacing: 4) {
        ForEach(Array(store.targets.enumerated()), id: \.element.id) { index, target in
          HandoffTargetRow(
            target: target,
            isSelected: index == store.selectedIndex
          ) {
            store.send(.setSelectedIndex(index))
          }
        }
      }
      .padding(12)

      Divider()

      HStack {
        Spacer()
        Button("Cancel") {
          store.send(.cancelTapped)
        }
        .keyboardShortcut(.cancelAction)
        Button(continueTitle) {
          store.send(.confirmSelection)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
  }

  private var continueTitle: String {
    guard store.targets.indices.contains(store.selectedIndex) else { return "Continue" }
    let target = store.targets[store.selectedIndex]
    switch target.kind {
    case .agent:
      return "Hand Off to \(target.title)"
    case .briefOnly:
      return "Update Brief"
    }
  }
}

private struct HandoffTargetRow: View {
  let target: HandoffTargetOption
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      HStack(spacing: 10) {
        icon
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 6) {
            Text(target.title)
              .font(.body)
            if target.isCurrentAgent {
              Text("fresh session")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            }
          }
          Text(target.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
    )
    .help(rowHelp)
  }

  @ViewBuilder
  private var icon: some View {
    switch target.kind {
    case .agent(let agent):
      if let source = CommandIconMap.iconForFirstToken(agent.iconLookupToken) {
        TabIconImage(rawName: source.storageString, pointSize: 18)
      } else {
        Image(systemName: "sparkle")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    case .briefOnly:
      Image(systemName: "square.and.pencil")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
  }

  private var rowHelp: String {
    switch target.kind {
    case .agent:
      return "Hand this task to \(target.title) in a new tab"
    case .briefOnly:
      return "Update the hand-off notes without launching another agent"
    }
  }
}

// MARK: - Run step

private struct HandoffHudRunView: View {
  let run: HandoffHudRun
  let sourceDisplayName: String
  let onSkip: () -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(run.stages.enumerated()), id: \.element) { index, stage in
          stageRow(stage: stage, index: index)
        }
      }
      .padding(16)

      Divider()

      HStack {
        if run.stage == .briefing {
          Text("This can take a moment while \(sourceDisplayName) writes its brief.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if run.stage == .briefing {
          Button("Cancel") {
            onCancel()
          }
          .keyboardShortcut(.cancelAction)
          .help("Stop this hand-off; nothing is changed")
        }
      }
      .padding(12)
    }
  }

  @ViewBuilder
  private func stageRow(stage: HandoffStage, index: Int) -> some View {
    let currentIndex = run.stages.firstIndex(of: run.stage) ?? 0
    HStack(spacing: 8) {
      stageIndicator(stage: stage, index: index, currentIndex: currentIndex)
      Text(stageTitle(stage))
        .font(.body)
        .foregroundStyle(index <= currentIndex ? .primary : .secondary)
      Spacer(minLength: 0)
      if stage == .briefing, run.stage == .briefing {
        Button("Skip") {
          onSkip()
        }
        .controlSize(.small)
        .help("Hand off now with the current summary and repo state")
      }
    }
  }

  @ViewBuilder
  private func stageIndicator(stage: HandoffStage, index: Int, currentIndex: Int) -> some View {
    if index < currentIndex {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .accessibilityLabel("Completed")
    } else if index == currentIndex {
      ProgressView()
        .controlSize(.small)
    } else {
      Image(systemName: "circle")
        .foregroundStyle(.quaternary)
        .accessibilityLabel("Pending")
    }
  }

  private func stageTitle(_ stage: HandoffStage) -> String {
    switch stage {
    case .briefing:
      return "Collect brief from \(sourceDisplayName)"
    case .saving:
      return "Save context"
    case .archiving:
      return "Archive"
    case .launching:
      switch run.target.kind {
      case .agent:
        return "Launch \(run.target.title)"
      case .briefOnly:
        return "Launch"
      }
    }
  }
}

// MARK: - Finished step

private struct HandoffHudFinishedView: View {
  let outcome: HandoffHudOutcome
  let onClose: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        icon
        Text(message)
          .font(.body)
        Spacer(minLength: 0)
      }
      .padding(16)

      Divider()

      HStack {
        Spacer()
        Button("Close") {
          onClose()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
  }

  @ViewBuilder
  private var icon: some View {
    switch outcome {
    case .handedOff, .briefSaved:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.title2)
        .accessibilityLabel("Success")
    case .failed:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
        .font(.title2)
        .accessibilityLabel("Failure")
    }
  }

  private var message: String {
    switch outcome {
    case .handedOff(let name):
      return "New tab opened with \(name)"
    case .briefSaved:
      return "Hand-off notes are up to date"
    case .failed:
      return "Nothing was launched"
    }
  }
}

// MARK: - Key capture

/// Grabs first-responder status while the HUD is visible so arrow keys,
/// Return, and Escape drive the panel instead of leaking into the focused
/// terminal surface (where they would reach a live agent session).
private struct HandoffHudKeyCaptureView: NSViewRepresentable {
  let onMove: (Int) -> Void
  let onConfirm: () -> Void
  let onEscape: () -> Void

  func makeNSView(context: Context) -> KeyCaptureNSView {
    let view = KeyCaptureNSView()
    view.onMove = onMove
    view.onConfirm = onConfirm
    view.onEscape = onEscape
    return view
  }

  func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
    nsView.onMove = onMove
    nsView.onConfirm = onConfirm
    nsView.onEscape = onEscape
    nsView.grabFocusIfNeeded()
  }

  final class KeyCaptureNSView: NSView {
    var onMove: ((Int) -> Void)?
    var onConfirm: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      grabFocusIfNeeded()
    }

    func grabFocusIfNeeded() {
      guard let window, window.firstResponder !== self else { return }
      window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
      switch event.keyCode {
      case 126:  // up arrow
        onMove?(-1)
      case 125:  // down arrow
        onMove?(1)
      case 36, 76:  // return, keypad enter
        onConfirm?()
      case 53:  // escape
        onEscape?()
      default:
        // Swallow everything else: keys must never leak into the terminal
        // behind the panel.
        break
      }
    }
  }
}
