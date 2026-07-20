import SwiftUI

/// What the Agents capsule shows for the selected pane's detected agent.
/// nil means no agent: the capsule renders its generic, disabled form
/// (reserved for the future quick launcher — docs-ai 049).
struct AgentsCapsuleState: Equatable {
  let displayName: String
  /// Resolved branded icon; nil falls back to a generic symbol. Resolved by
  /// the assembler with the same two-step token fallback the Active Agents
  /// panel uses, so a wrapper process name never loses the brand icon.
  let iconSource: TabIconSource?
  let displayState: AgentDisplayState
  /// Behavior preview shown as the popover's read-only first line.
  let infoLine: String
}

/// Toolbar entry point for agent-scoped actions, left of the branch title.
/// The capsule is a passive status indicator for the selected pane; clicking
/// it opens a popover that hosts the agent actions — hand-off today, more
/// later (docs-ai 049). A `Menu` cannot host this control: macOS toolbars
/// flatten custom menu labels to their text, dropping the badge and status
/// dot, so the popover is the durable container for this surface.
struct AgentsToolbarButton: View {
  let capsule: AgentsCapsuleState?
  let onHandOff: () -> Void
  @State private var isPopoverPresented = false

  var body: some View {
    Button {
      isPopoverPresented.toggle()
    } label: {
      label
    }
    .disabled(capsule == nil)
    .help(helpText)
    .accessibilityLabel(accessibilityText)
    .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
      if let capsule {
        AgentsPopoverContent(
          capsule: capsule,
          onHandOff: {
            isPopoverPresented = false
            onHandOff()
          }
        )
      }
    }
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
    if let source = capsule.iconSource {
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
    return "Agent actions — \(capsule.displayName) · \(capsule.displayState.label)"
  }

  private var accessibilityText: String {
    guard let capsule else { return "Agents (no agent detected)" }
    return "Agents: \(capsule.displayName), \(capsule.displayState.label)"
  }
}

/// The agent-actions popover: a read-only behavior preview line and the
/// action list. Rows follow menu conventions (full-width highlight on
/// hover) so future actions slot in as additional rows.
private struct AgentsPopoverContent: View {
  let capsule: AgentsCapsuleState
  let onHandOff: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(capsule.infoLine)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 10)

      Divider()
        .padding(.horizontal, 6)

      AgentsPopoverRow(
        title: "Hand Off…",
        systemImage: "arrow.left.arrow.right",
        action: onHandOff
      )
      .padding(.horizontal, 6)
      .padding(.bottom, 6)
    }
    .frame(width: 260, alignment: .leading)
  }
}

private struct AgentsPopoverRow: View {
  let title: String
  let systemImage: String
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .frame(width: 16)
          .accessibilityHidden(true)
        Text(title)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(isHovered ? Color.accentColor.opacity(0.2) : Color.clear)
    )
    .onHover { isHovered = $0 }
  }
}
