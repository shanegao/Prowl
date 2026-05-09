import ComposableArchitecture
import SwiftUI

struct ActiveAgentRow: View {
  let entry: ActiveAgentEntry

  var body: some View {
    HStack(spacing: 8) {
      agentIcon
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.agent.displayName)
          .font(.body.monospaced())
          .lineLimit(1)
        Text(entry.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 8)
      statusPill
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .contentShape(.rect)
  }

  private var agentIcon: some View {
    Group {
      if let icon = CommandIconMap.iconForFirstToken(entry.agent.iconLookupToken) {
        TabIconImage(rawName: icon.storageString, pointSize: 16)
      } else {
        Image(systemName: "sparkle")
      }
    }
    .frame(width: 20, height: 20)
    .accessibilityHidden(true)
  }

  private var statusPill: some View {
    HStack(spacing: 4) {
      if entry.displayState == .working {
        ProgressView()
          .controlSize(.small)
          .frame(width: 10, height: 10)
      }
      Text(entry.displayState.label)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
    }
    .foregroundStyle(entry.displayState.foregroundStyle)
  }
}

extension AgentDisplayState {
  fileprivate var label: String {
    switch self {
    case .working:
      return "Working"
    case .blocked:
      return "Blocked"
    case .done:
      return "Done"
    case .idle:
      return "Idle"
    }
  }

  fileprivate var foregroundStyle: Color {
    switch self {
    case .working:
      return .orange
    case .blocked:
      return .red
    case .done:
      return .blue
    case .idle:
      return .secondary
    }
  }
}
