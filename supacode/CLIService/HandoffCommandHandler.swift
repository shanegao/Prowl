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
  let outgoingLaunchObservation: AgentLaunchObservation?
  let outgoingSession: AgentSession?
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
  typealias LaunchProvider = @MainActor (HandoffResolvedTarget, AgentStartRequest) -> HandoffLaunchedPane?
  /// Resumes the source session headlessly and returns its reply text; the
  /// handler validates the reply and transcribes it into `current.md`.
  typealias PreparationProvider = @Sendable (AgentResumeRequest, URL) async throws -> String

  /// Agents this command can launch (it injects an agent-specific kickoff command).
  static let supportedAgents = HandoffAgentSupport.launchableAgents

  private let resolveProvider: ResolveProvider
  private let launchProvider: LaunchProvider
  private let preparationProvider: PreparationProvider
  private let now: @Sendable () -> Date

  init(
    resolveProvider: @escaping ResolveProvider,
    launchProvider: @escaping LaunchProvider,
    preparationProvider: @escaping PreparationProvider,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.resolveProvider = resolveProvider
    self.launchProvider = launchProvider
    self.preparationProvider = preparationProvider
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
    let coordinator = makeCoordinator(store: store)
    do {
      let (result, preparation) = try await coordinator.save(
        outgoingAgent: outgoing,
        sessionContext: target.sessionContext,
        note: note,
        preparationRequest: preparationRequest(input: input, target: target),
        now: timestamp
      )
      return success(payload: makePayload(action: .save, save: result, preparation: preparation))
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
    guard let destinationAgent = DetectedAgent(rawValue: toAgent) else {
      return errorResponse(code: CLIErrorCode.invalidArgument, message: "Unknown handoff agent: \(toAgent).")
    }
    let coordinator = makeCoordinator(store: store)

    let artifacts: HandoffCoordinator.TransitionArtifacts
    do {
      // Prepare, refresh the appendix, then archive before launching.
      artifacts = try await coordinator.makeTransitionArtifacts(
        outgoingAgent: outgoing,
        toAgent: toAgent,
        sessionContext: target.sessionContext,
        preparationRequest: preparationRequest(input: input, target: target),
        now: timestamp
      )
    } catch {
      return errorResponse(
        code: CLIErrorCode.handoffFailed,
        message: "Failed to prepare handoff: \(String(describing: error))"
      )
    }

    let configuration: AgentLaunchConfiguration
    if let sourceAgent = outgoing.flatMap(DetectedAgent.init(rawValue:)) {
      configuration = AgentRuntimeAdapterRegistry.inheritedConfiguration(
        from: sourceAgent,
        observation: target.outgoingLaunchObservation,
        to: destinationAgent
      )
    } else {
      configuration = .init()
    }
    var launched: HandoffLaunchedPane?
    if input.launch {
      launched = launchProvider(
        target,
        AgentStartRequest(
          agent: destinationAgent,
          prompt: Self.kickoffPrompt(),
          configuration: configuration
        )
      )
      if launched == nil {
        await coordinator.logTransition(
          from: from,
          toAgent: toAgent,
          disposition: .failed,
          preparation: artifacts.preparation,
          archivedPath: artifacts.archivedPath,
          note: input.note,
          now: timestamp
        )
        return errorResponse(code: CLIErrorCode.handoffFailed, message: "Failed to launch \(toAgent).")
      }
    }

    await coordinator.logTransition(
      from: from,
      toAgent: toAgent,
      disposition: launched.map { .pane($0.paneID) } ?? .skipped,
      preparation: artifacts.preparation,
      note: input.note,
      now: timestamp
    )

    return success(
      payload: makePayload(
        action: .toAgent,
        save: artifacts.save,
        toAgent: toAgent,
        archivedPath: artifacts.archivedPath,
        launched: launched,
        preparation: artifacts.preparation
      )
    )
  }

  private func makeCoordinator(store: HandoffStore) -> HandoffCoordinator {
    HandoffCoordinator(store: store, resume: preparationProvider)
  }

  /// The safe source-preparation request, or nil when `--no-prepare` was
  /// passed or no exact/high-confidence resumable session exists.
  private func preparationRequest(input: HandoffInput, target: HandoffResolvedTarget) -> AgentResumeRequest? {
    guard input.prepare else { return nil }
    return Self.preparationRequest(
      outgoingAgent: target.outgoingAgent,
      session: target.outgoingSession,
      observation: target.outgoingLaunchObservation
    )
  }

  // MARK: - status

  private func handleStatus(target: HandoffResolvedTarget, store: HandoffStore) async -> CommandResponse {
    let (status, sessionContext) = await Task.detached {
      (store.readStatus(), target.sessionContext)
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

  nonisolated static func kickoffPrompt() -> String {
    "Take over this Prowl workspace task. Read .prowl/handoff/current.md (agent notes), "
      + ".prowl/handoff/context.md (generated state), and .prowl/workspace.json (repo layout, if present), "
      + "then continue from Next Steps. If context.md lists a Session Context excerpt, read it before changing code. "
      + "Ask before any commit/push or destructive git."
  }

  nonisolated static func preparationRequest(
    outgoingAgent: String?,
    session: AgentSession?,
    observation: AgentLaunchObservation?
  ) -> AgentResumeRequest? {
    guard
      let outgoingAgent,
      let agent = DetectedAgent(rawValue: outgoingAgent),
      let session,
      session.confidence == .exact || session.confidence == .high,
      AgentRuntimeAdapterRegistry.canResume(agent)
    else {
      return nil
    }
    return AgentResumeRequest(
      agent: agent,
      session: session,
      prompt: preparationPrompt(),
      model: observation?.model
    )
  }

  nonisolated static func preparationPrompt() -> String {
    "Prowl handoff preparation. Reply with the complete updated contents of .prowl/handoff/current.md "
      + "and nothing else: a markdown document titled \"# Handoff\" with the sections \"## Objective\", "
      + "\"## Current State\", \"## What Has Been Done\", \"## Open Questions\", \"## Risks / Watch Out\", "
      + "\"## Next Steps\", and \"## Suggested Prompt For Next Agent\". Carry forward still-relevant notes "
      + "from the existing file. Base the update on what you already know from this session; do not run "
      + "commands, read extra files, or edit anything — Prowl writes the file from your reply. "
      + "Be concise and answer in a single reply."
  }

  // MARK: - Payload

  private func makePayload(
    action: HandoffAction,
    save: HandoffStore.SaveResult,
    toAgent: String? = nil,
    archivedPath: String? = nil,
    launched: HandoffLaunchedPane? = nil,
    preparation: HandoffPreparationOutcome? = nil
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
      preparation: preparation?.rawValue,
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
