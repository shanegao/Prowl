import Foundation

public struct HandoffCommandPayload: Codable, Sendable, Equatable {
  public let action: HandoffAction
  public let artifactPath: String
  /// The agent detected in the target pane when the handoff ran (the "from" side).
  public let outgoingAgent: String?
  /// The receiving agent for `to`.
  public let toAgent: String?
  public let repos: [HandoffRepoPayload]
  public let changedFileCount: Int
  /// Archived copy of the previous artifact, relative to the handoff dir (for `to`).
  public let archivedPath: String?
  /// The pane the receiving agent was launched into (for `to` with launch).
  public let launchedPane: HandoffPanePayload?
  /// Whether `current.md` exists (for `status`).
  public let exists: Bool?
  /// Most recent handoff-log line (for `status`).
  public let lastLog: String?

  enum CodingKeys: String, CodingKey {
    case action
    case artifactPath = "artifact_path"
    case outgoingAgent = "outgoing_agent"
    case toAgent = "to_agent"
    case repos
    case changedFileCount = "changed_file_count"
    case archivedPath = "archived_path"
    case launchedPane = "launched_pane"
    case exists
    case lastLog = "last_log"
  }

  public init(
    action: HandoffAction,
    artifactPath: String,
    outgoingAgent: String? = nil,
    toAgent: String? = nil,
    repos: [HandoffRepoPayload] = [],
    changedFileCount: Int = 0,
    archivedPath: String? = nil,
    launchedPane: HandoffPanePayload? = nil,
    exists: Bool? = nil,
    lastLog: String? = nil
  ) {
    self.action = action
    self.artifactPath = artifactPath
    self.outgoingAgent = outgoingAgent
    self.toAgent = toAgent
    self.repos = repos
    self.changedFileCount = changedFileCount
    self.archivedPath = archivedPath
    self.launchedPane = launchedPane
    self.exists = exists
    self.lastLog = lastLog
  }
}

public struct HandoffRepoPayload: Codable, Sendable, Equatable {
  public let name: String
  public let branch: String?
  public let isGit: Bool
  public let changedFileCount: Int
  public let insertions: Int
  public let deletions: Int

  enum CodingKeys: String, CodingKey {
    case name
    case branch
    case isGit = "is_git"
    case changedFileCount = "changed_file_count"
    case insertions
    case deletions
  }

  public init(
    name: String,
    branch: String?,
    isGit: Bool,
    changedFileCount: Int,
    insertions: Int,
    deletions: Int
  ) {
    self.name = name
    self.branch = branch
    self.isGit = isGit
    self.changedFileCount = changedFileCount
    self.insertions = insertions
    self.deletions = deletions
  }
}

public struct HandoffPanePayload: Codable, Sendable, Equatable {
  public let worktreeID: String
  public let worktreeName: String
  public let tabID: String
  public let paneID: String
  public let paneTitle: String

  enum CodingKeys: String, CodingKey {
    case worktreeID = "worktree_id"
    case worktreeName = "worktree_name"
    case tabID = "tab_id"
    case paneID = "pane_id"
    case paneTitle = "pane_title"
  }

  public init(worktreeID: String, worktreeName: String, tabID: String, paneID: String, paneTitle: String) {
    self.worktreeID = worktreeID
    self.worktreeName = worktreeName
    self.tabID = tabID
    self.paneID = paneID
    self.paneTitle = paneTitle
  }
}
