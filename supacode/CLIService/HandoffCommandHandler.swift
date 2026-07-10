// supacode/CLIService/HandoffCommandHandler.swift

import Foundation

/// A handoff target resolved on the main actor: the runnable root to store the
/// artifact under, plus the agent currently detected in that target's pane.
struct HandoffResolvedTarget: Sendable, Equatable {
  let worktreeID: String
  let worktreeName: String
  let rootPath: String
  let paneID: String
  let outgoingAgent: String?
  let sessionContext: HandoffStore.SessionContext?
}

/// The pane the receiving agent was launched into.
struct HandoffLaunchedPane: Sendable, Equatable {
  let worktreeID: String
  let worktreeName: String
  let tabID: String
  let paneID: String
  let paneTitle: String
}

@MainActor
final class HandoffCommandHandler: CommandHandler {
  typealias ResolveProvider = @MainActor (TargetSelector) -> Result<HandoffResolvedTarget, TargetResolverError>
  typealias LaunchProvider = @MainActor (HandoffResolvedTarget, String) -> HandoffLaunchedPane?

  /// Agents this command can launch (it injects an agent-specific kickoff command).
  static let supportedAgents = HandoffAgentSupport.launchableAgents

  private let resolveProvider: ResolveProvider
  private let launchProvider: LaunchProvider
  private let now: @Sendable () -> Date

  init(
    resolveProvider: @escaping ResolveProvider,
    launchProvider: @escaping LaunchProvider,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.resolveProvider = resolveProvider
    self.launchProvider = launchProvider
    self.now = now
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .handoff(let input) = envelope.command else {
      return errorResponse(code: CLIErrorCode.handoffFailed, message: "Invalid command.")
    }

    if input.action == .toAgent {
      guard let rawAgent = input.toAgent, let toAgent = HandoffAgentSupport.normalize(rawAgent) else {
        return errorResponse(
          code: CLIErrorCode.invalidArgument,
          message: "handoff to requires an agent of: \(HandoffAgentSupport.supportedAgentsDescription)."
        )
      }
      if input.launch, !HandoffAgentSupport.canLaunch(toAgent) {
        let launchable = HandoffAgentSupport.launchableAgentsDescription
        return errorResponse(
          code: CLIErrorCode.invalidArgument,
          message: "handoff can only launch: \(launchable). Use --no-launch for other agents."
        )
      }
    }

    let target: HandoffResolvedTarget
    switch resolveProvider(input.selector) {
    case .success(let resolved):
      target = resolved
    case .failure(let error):
      return mapResolverError(error)
    }

    let store = HandoffStore(rootURL: URL(fileURLWithPath: target.rootPath, isDirectory: true))
    let timestamp = now()

    switch input.action {
    case .save:
      return await handleSave(input: input, target: target, store: store, timestamp: timestamp)
    case .toAgent:
      return await handleTo(input: input, target: target, store: store, timestamp: timestamp)
    case .status:
      return await handleStatus(target: target, store: store)
    }
  }

  // MARK: - save

  private func handleSave(
    input: HandoffInput,
    target: HandoffResolvedTarget,
    store: HandoffStore,
    timestamp: Date
  ) async -> CommandResponse {
    let outgoing = target.outgoingAgent
    let note = input.note
    do {
      let result = try await Task.detached {
        let sessionContext = HandoffTranscriptResolver().resolve(
          sessionContext: target.sessionContext,
          rootURL: store.rootURL
        )
        return try store.save(
          outgoingAgent: outgoing,
          sessionContext: sessionContext,
          note: note,
          now: timestamp
        )
      }.value
      return success(payload: makePayload(action: .save, save: result))
    } catch {
      return errorResponse(
        code: CLIErrorCode.handoffFailed,
        message: "Failed to save handoff: \(String(describing: error))"
      )
    }
  }

  // MARK: - to

  private func handleTo(
    input: HandoffInput,
    target: HandoffResolvedTarget,
    store: HandoffStore,
    timestamp: Date
  ) async -> CommandResponse {
    guard let rawAgent = input.toAgent, let toAgent = HandoffAgentSupport.normalize(rawAgent) else {
      return errorResponse(code: CLIErrorCode.invalidArgument, message: "handoff to requires an agent.")
    }
    let outgoing = target.outgoingAgent
    let from = outgoing ?? "agent"

    let saveResult: HandoffStore.SaveResult
    let archivedPath: String?
    do {
      // Refresh the appendix, then archive the current artifact before launching.
      saveResult = try await Task.detached {
        let sessionContext = HandoffTranscriptResolver().resolve(
          sessionContext: target.sessionContext,
          rootURL: store.rootURL
        )
        return try store.save(
          outgoingAgent: outgoing,
          sessionContext: sessionContext,
          note: nil,
          now: timestamp
        )
      }.value
      archivedPath = try await Task.detached {
        try store.archiveCurrent(from: from, toAgent: toAgent, now: timestamp)
      }.value
    } catch {
      return errorResponse(
        code: CLIErrorCode.handoffFailed,
        message: "Failed to prepare handoff: \(String(describing: error))"
      )
    }

    var launched: HandoffLaunchedPane?
    if input.launch {
      launched = launchProvider(target, Self.kickoff(for: toAgent))
      if launched == nil {
        let archiveSuffix = archivedPath.map { "  archive=\($0)" } ?? ""
        let noteSuffix = input.note.map { "  note=\"\($0.replacing("\n", with: " "))\"" } ?? ""
        try? await Task.detached {
          try store.appendLog(
            "\(from) → \(toAgent)  launch=failed\(archiveSuffix)\(noteSuffix)",
            now: timestamp
          )
        }.value
        return errorResponse(code: CLIErrorCode.handoffFailed, message: "Failed to launch \(toAgent).")
      }
    }

    let note = input.note
    let paneSuffix = launched.map { "  pane=\($0.paneID)" } ?? "  (no launch)"
    let noteSuffix = note.map { "  note=\"\($0.replacing("\n", with: " "))\"" } ?? ""
    try? await Task.detached {
      try store.appendLog("\(from) → \(toAgent)\(paneSuffix)\(noteSuffix)", now: timestamp)
    }.value

    return success(
      payload: makePayload(
        action: .toAgent,
        save: saveResult,
        toAgent: toAgent,
        archivedPath: archivedPath,
        launched: launched
      )
    )
  }

  // MARK: - status

  private func handleStatus(target: HandoffResolvedTarget, store: HandoffStore) async -> CommandResponse {
    let (status, sessionContext) = await Task.detached {
      let sessionContext = HandoffTranscriptResolver().resolve(
        sessionContext: target.sessionContext,
        rootURL: store.rootURL
      )
      return (store.readStatus(), sessionContext)
    }.value
    return success(
      payload: HandoffCommandPayload(
        action: .status,
        artifactPath: status.artifactPath,
        outgoingAgent: target.outgoingAgent,
        sessionContext: sessionContext.map {
          HandoffSessionPayload(
            agent: $0.agent,
            sessionID: $0.sessionID,
            paneID: $0.paneID,
            paneTitle: $0.paneTitle,
            source: $0.source,
            confidence: $0.confidence,
            transcriptPath: $0.transcriptPath
          )
        },
        exists: status.exists,
        lastLog: status.lastLogLine
      )
    )
  }

  // MARK: - Kickoff prompt

  nonisolated static func kickoff(for agent: String) -> String {
    let instruction =
      "Take over this Prowl workspace task. Read .prowl/handoff/current.md (the full handoff) "
      + "and .prowl/workspace.json (repo layout, if present), then continue from Next Steps. "
      + "If current.md lists a Session Context excerpt, read that file before changing code. "
      + "Ask before any commit/push or destructive git."
    return "\(agent) \"\(instruction)\""
  }

  // MARK: - Payload

  private func makePayload(
    action: HandoffAction,
    save: HandoffStore.SaveResult,
    toAgent: String? = nil,
    archivedPath: String? = nil,
    launched: HandoffLaunchedPane? = nil
  ) -> HandoffCommandPayload {
    HandoffCommandPayload(
      action: action,
      artifactPath: save.artifactPath,
      outgoingAgent: save.outgoingAgent,
      toAgent: toAgent,
      repos: save.repos.map {
        HandoffRepoPayload(
          name: $0.name,
          branch: $0.branch,
          isGit: $0.isGit,
          changedFileCount: $0.changedFileCount,
          insertions: $0.insertions,
          deletions: $0.deletions
        )
      },
      changedFileCount: save.totalChangedFiles,
      archivedPath: archivedPath,
      sessionContext: save.sessionContext,
      launchedPane: launched.map {
        HandoffPanePayload(
          worktreeID: $0.worktreeID,
          worktreeName: $0.worktreeName,
          tabID: $0.tabID,
          paneID: $0.paneID,
          paneTitle: $0.paneTitle
        )
      }
    )
  }

  // MARK: - Response helpers

  private func success(payload: HandoffCommandPayload) -> CommandResponse {
    do {
      return try CommandResponse(
        ok: true,
        command: "handoff",
        schemaVersion: "prowl.cli.handoff.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      return errorResponse(code: CLIErrorCode.handoffFailed, message: "Failed to encode response.")
    }
  }

  private func mapResolverError(_ error: TargetResolverError) -> CommandResponse {
    switch error {
    case .notFound(let message):
      return errorResponse(code: CLIErrorCode.targetNotFound, message: message)
    case .notUnique(let message):
      return errorResponse(code: CLIErrorCode.targetNotUnique, message: message)
    }
  }

  private func errorResponse(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: "handoff",
      schemaVersion: "prowl.cli.handoff.v1",
      error: CommandError(code: code, message: message)
    )
  }
}
