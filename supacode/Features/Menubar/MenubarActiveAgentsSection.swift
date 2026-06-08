import AppKit
import ComposableArchitecture
import SwiftUI

/// Active Agents section of the menubar dropdown. Sorts blocked agents first
/// (the only `.needs-your-attention` state), then by recency. Top `inlineLimit`
/// inline, rest in a "More" submenu; hidden entirely when no agents are active.
struct MenubarActiveAgentsSection: View {
  @Bindable var store: StoreOf<AppFeature>

  /// Cap on inline rows before remaining agents are folded into a "More"
  /// submenu — keeps the menubar from growing unbounded when many agents run.
  private static let inlineLimit = 5

  var body: some View {
    let sorted = sortedEntries
    if !sorted.isEmpty {
      Section("Active Agents") {
        let inline = sorted.prefix(Self.inlineLimit)
        let overflow = Array(sorted.dropFirst(Self.inlineLimit))
        ForEach(inline) { entry in
          agentRow(entry)
        }
        if !overflow.isEmpty {
          Menu("More") {
            ForEach(overflow) { entry in
              agentRow(entry)
            }
          }
        }
      }
    }
  }

  private var sortedEntries: [ActiveAgentEntry] {
    store.repositories.activeAgents.entries.sorted { lhs, rhs in
      let lhsBlocked = lhs.displayState == .blocked
      let rhsBlocked = rhs.displayState == .blocked
      if lhsBlocked != rhsBlocked { return lhsBlocked }
      return lhs.lastChangedAt > rhs.lastChangedAt
    }
  }

  @ViewBuilder
  private func agentRow(_ entry: ActiveAgentEntry) -> some View {
    Button {
      store.send(.repositories(.activeAgents(.entryTapped(entry.id))))
      NSApplication.shared.surfaceMainWindow()
    } label: {
      Label {
        Text("[\(entry.displayState.label)] \(entry.worktreeName)")
      } icon: {
        AgentIconImage(entry: entry)
      }
    }
  }
}
