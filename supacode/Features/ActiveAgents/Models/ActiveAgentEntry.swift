import Foundation

struct ActiveAgentEntry: Identifiable, Equatable, Sendable {
  let id: UUID
  let worktreeID: Worktree.ID
  let worktreeName: String
  let tabID: TerminalTabID
  let tabTitle: String
  let surfaceID: UUID
  let paneIndex: Int
  let agent: DetectedAgent
  let rawState: AgentRawState
  let displayState: AgentDisplayState
  let lastChangedAt: Date
}

extension ActiveAgentEntry {
  static func sorted(_ entries: [ActiveAgentEntry]) -> [ActiveAgentEntry] {
    entries.sorted { left, right in
      let leftRank = left.displayState.sortRank
      let rightRank = right.displayState.sortRank
      if leftRank != rightRank {
        return leftRank < rightRank
      }
      if left.lastChangedAt != right.lastChangedAt {
        return left.lastChangedAt > right.lastChangedAt
      }
      return left.id.uuidString < right.id.uuidString
    }
  }
}

extension AgentDisplayState {
  fileprivate var sortRank: Int {
    switch self {
    case .blocked:
      return 0
    case .working:
      return 1
    case .done:
      return 2
    case .idle:
      return 3
    }
  }
}
