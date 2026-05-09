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
