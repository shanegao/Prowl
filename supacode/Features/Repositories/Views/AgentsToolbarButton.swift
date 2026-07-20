import SwiftUI

/// What the Agents capsule shows for the selected pane's detected agent.
/// nil means no agent: the capsule renders its generic, disabled form
/// (reserved for the future quick launcher — docs-ai 049).
struct AgentsCapsuleState: Equatable {
  let displayName: String
  let iconToken: String
  let displayState: AgentDisplayState
  /// Behavior preview shown as the menu's read-only first line.
  let infoLine: String
}

/// Toolbar entry point for agent-scoped actions, left of the branch title.
/// The capsule itself is a passive status indicator for the selected pane;
/// its menu currently carries the hand-off entry.
struct AgentsToolbarButton: View {
  let capsule: AgentsCapsuleState?
  let onHandOff: () -> Void

  var body: some View {
    Menu {
      if let capsule {
        Text(capsule.infoLine)
        Divider()
        Button("Hand Off…") {
          onHandOff()
        }
      }
    } label: {
      label
    }
    .menuIndicator(.hidden)
    .disabled(capsule == nil)
    .help(helpText)
    .accessibilityLabel(accessibilityText)
  }

  @ViewBuilder
  private var label: some View {
    HStack(spacing: 5) {
      if let capsule {
        agentIcon(capsule)
        Text(capsule.displayName)
          .font(.callout.weight(.medium))
          .monospaced()
        Circle()
          .fill(capsule.displayState.foregroundStyle)
          .frame(width: 6, height: 6)
          .accessibilityHidden(true)
      } else {
        Image(systemName: "person.2")
          .accessibilityHidden(true)
        Text("Agents")
          .font(.callout.weight(.medium))
      }
    }
  }

  @ViewBuilder
  private func agentIcon(_ capsule: AgentsCapsuleState) -> some View {
    if let source = CommandIconMap.iconForFirstToken(capsule.iconToken) {
      TabIconImage(rawName: source.storageString, pointSize: 13)
    } else {
      Image(systemName: "sparkle")
        .accessibilityHidden(true)
    }
  }

  private var helpText: String {
    guard let capsule else {
      return "No agent detected in the selected pane"
    }
    return "\(capsule.displayName) · \(capsule.displayState.label) — agent actions for this pane"
  }

  private var accessibilityText: String {
    guard let capsule else { return "Agents (no agent detected)" }
    return "Agents: \(capsule.displayName), \(capsule.displayState.label)"
  }
}
