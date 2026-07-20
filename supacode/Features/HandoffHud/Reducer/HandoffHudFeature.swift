import ComposableArchitecture
import Foundation

/// A row in the hand-off HUD's choose step.
struct HandoffTargetOption: Equatable, Identifiable, Sendable {
  enum Kind: Equatable, Hashable, Sendable {
    case agent(DetectedAgent)
    case briefOnly
  }

  let kind: Kind
  let title: String
  let subtitle: String
  /// The receiving agent equals the outgoing one (fresh-session restart).
  let isCurrentAgent: Bool

  var id: Kind { kind }

  var agent: DetectedAgent? {
    guard case .agent(let agent) = kind else { return nil }
    return agent
  }
}

/// The outgoing side of a hand-off, captured once when the HUD opens.
struct HandoffHudSource: Equatable, Sendable {
  /// Detected agent token, e.g. "codex".
  let agentToken: String
  let displayName: String
  /// Non-nil only for a resumable exact/high-confidence session.
  let preparationRequest: AgentResumeRequest?
  let sessionContext: HandoffStore.SessionContext?
  let observation: AgentLaunchObservation?
}

enum HandoffStage: Equatable, Sendable {
  case briefing
  case saving
  case archiving
  case launching
}

enum HandoffHudOutcome: Equatable, Sendable {
  case handedOff(agentDisplayName: String)
  case briefSaved
  case failed(message: String)
}

struct HandoffHudRun: Equatable, Sendable {
  let target: HandoffTargetOption
  let startedAt: Date
  /// Stages this run displays, in order (briefing only when resumable).
  let stages: [HandoffStage]
  var stage: HandoffStage
  var preparation: HandoffPreparationOutcome?
}

enum HandoffHudPhase: Equatable {
  case choosing
  case running(HandoffHudRun)
  case finished(HandoffHudOutcome)
}

/// The staged hand-off HUD (docs-ai 049): choose a receiving agent, then run
/// briefing → save → archive → launch with per-stage progress. Execution
/// state lives in this reducer — the HUD view is a projection, so a later
/// wave can dismiss the panel while a run continues.
///
/// The reducer drives `HandoffCoordinator` directly; the CLI handler shares
/// the same coordinator, so both entry points persist identical artifacts
/// and log lines.
@Reducer
struct HandoffHudFeature {
  @ObservableState
  struct State: Equatable {
    let worktree: Worktree
    let rootURL: URL
    let source: HandoffHudSource
    let targets: [HandoffTargetOption]
    var selectedIndex = 0
    var phase: HandoffHudPhase = .choosing

    var run: HandoffHudRun? {
      guard case .running(let run) = phase else { return nil }
      return run
    }

    var isChoosing: Bool { phase == .choosing }

    /// Build the HUD for a pane with a detected agent; nil without one — the
    /// no-source mechanical handoff stays CLI-only for now.
    static func make(worktree: Worktree, source: HandoffSourceContext?) -> State? {
      guard let sessionContext = source?.sessionContext, let agentToken = sessionContext.agent else {
        return nil
      }
      let sourceAgent = DetectedAgent(rawValue: agentToken)
      let preparationRequest = HandoffCommandHandler.preparationRequest(
        outgoingAgent: agentToken,
        session: source?.session,
        observation: source?.observation
      )
      var targets = AgentRuntimeAdapterRegistry.launchableAgents.map { agent in
        HandoffTargetOption(
          kind: .agent(agent),
          title: AgentRuntimeAdapterRegistry.displayName(for: agent),
          subtitle: Self.launchSubtitle(
            sourceAgent: sourceAgent,
            sourceDisplayName: sourceAgent?.displayName ?? agentToken,
            observation: source?.observation,
            destination: agent
          ),
          isCurrentAgent: agent == sourceAgent
        )
      }
      targets.append(
        HandoffTargetOption(
          kind: .briefOnly,
          title: "Only save progress, don't hand off",
          subtitle: "Saves the current state for a later hand-off",
          isCurrentAgent: false
        )
      )
      return State(
        worktree: worktree,
        rootURL: worktree.workingDirectory,
        source: HandoffHudSource(
          agentToken: agentToken,
          displayName: sourceAgent?.displayName ?? agentToken,
          preparationRequest: preparationRequest,
          sessionContext: sessionContext,
          observation: source?.observation
        ),
        targets: targets
      )
    }

    /// Read-only launch-configuration facts; the HUD never offers options.
    private static func launchSubtitle(
      sourceAgent: DetectedAgent?,
      sourceDisplayName: String,
      observation: AgentLaunchObservation?,
      destination: DetectedAgent
    ) -> String {
      let standard = "Launches with its default setup"
      guard let sourceAgent else { return standard }
      let configuration = AgentRuntimeAdapterRegistry.inheritedConfiguration(
        from: sourceAgent,
        observation: observation,
        to: destination
      )
      if configuration.executionMode == .unrestricted, observation?.executionMode == .unrestricted {
        return "Will bypass permissions (carried over from \(sourceDisplayName))"
      }
      return standard
    }
  }

  enum Action: Equatable {
    case moveSelection(delta: Int)
    case setSelectedIndex(Int)
    case confirmSelection
    case skipBriefingTapped
    case cancelTapped
    case closeTapped
    case briefingReplyReceived(HandoffPreparationReply)
    case briefingFinished(HandoffPreparationOutcome)
    case savingFinished
    case archivingFinished
    case launchFinished
    case runFailed(message: String)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case dismiss
  }

  private nonisolated struct BriefingCancelID: Hashable {
    let worktreeID: Worktree.ID
  }

  @Dependency(AgentRuntimeClient.self) private var agentRuntimeClient
  @Dependency(TerminalClient.self) private var terminalClient
  @Dependency(\.date.now) private var now

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .moveSelection(let delta):
        guard state.isChoosing, !state.targets.isEmpty else { return .none }
        let count = state.targets.count
        state.selectedIndex = (state.selectedIndex + delta + count) % count
        return .none

      case .setSelectedIndex(let index):
        guard state.isChoosing, state.targets.indices.contains(index) else { return .none }
        state.selectedIndex = index
        return .none

      case .confirmSelection:
        guard state.isChoosing, state.targets.indices.contains(state.selectedIndex) else { return .none }
        return startRun(&state, target: state.targets[state.selectedIndex])

      case .briefingReplyReceived(let reply):
        guard var run = state.run, run.stage == .briefing else { return .none }
        switch reply {
        case .reply:
          // Leaving briefing is the reducer's commit decision. A late reply
          // after Skip or Cancel is ignored before it reaches the filesystem.
          run.stage = .saving
          state.phase = .running(run)
          let coordinator = makeCoordinator(state)
          let timestamp = run.startedAt
          return .run { send in
            let outcome = coordinator.applyPreparation(reply, now: timestamp)
            await send(.briefingFinished(outcome))
          }
          .cancellable(id: BriefingCancelID(worktreeID: state.worktree.id), cancelInFlight: true)

        case .skipped:
          run.preparation = .skipped
        case .failed:
          run.preparation = .failed
        }
        return advance(&state, run: run, to: .saving)

      case .briefingFinished(let outcome):
        guard var run = state.run, run.stage == .saving else { return .none }
        run.preparation = outcome
        return advance(&state, run: run, to: .saving)
      case .savingFinished:
        guard let run = state.run, run.stage == .saving else { return .none }
        if run.target.kind == .briefOnly {
          state.phase = .finished(.briefSaved)
          return .none
        }
        return advance(&state, run: run, to: .archiving)

      case .archivingFinished:
        guard let run = state.run, run.stage == .archiving else { return .none }
        return advance(&state, run: run, to: .launching)

      case .launchFinished:
        guard let run = state.run, run.stage == .launching else { return .none }
        state.phase = .finished(.handedOff(agentDisplayName: run.target.title))
        return .none

      case .runFailed(let message):
        guard state.run != nil else { return .none }
        state.phase = .finished(.failed(message: message))
        return .none

      case .skipBriefingTapped:
        guard var run = state.run, run.stage == .briefing else { return .none }
        run.preparation = .skipped
        return .merge(
          .cancel(id: BriefingCancelID(worktreeID: state.worktree.id)),
          advance(&state, run: run, to: .saving)
        )

      case .cancelTapped:
        switch state.phase {
        case .choosing:
          return .send(.delegate(.dismiss))
        case .running(let run) where run.stage == .briefing:
          // Abort entirely: the artifact is untouched and no log line is
          // written — parity with Ctrl-C on the CLI path.
          return .merge(
            .cancel(id: BriefingCancelID(worktreeID: state.worktree.id)),
            .send(.delegate(.dismiss))
          )
        case .running, .finished:
          return .none
        }

      case .closeTapped:
        guard case .finished = state.phase else { return .none }
        return .send(.delegate(.dismiss))

      case .delegate:
        return .none
      }
    }
  }

  // MARK: - Run orchestration

  private func makeCoordinator(_ state: State) -> HandoffCoordinator {
    let client = agentRuntimeClient
    return HandoffCoordinator(
      store: HandoffStore(rootURL: state.rootURL),
      resume: { request, workingDirectory in
        try await client.resume(request, in: workingDirectory)
      }
    )
  }

  private func startRun(_ state: inout State, target: HandoffTargetOption) -> Effect<Action> {
    let stages: [HandoffStage] =
      (state.source.preparationRequest == nil ? [] : [.briefing])
      + [.saving]
      + (target.kind == .briefOnly ? [] : [.archiving, .launching])
    var run = HandoffHudRun(
      target: target,
      startedAt: now,
      stages: stages,
      stage: stages[0]
    )
    guard let request = state.source.preparationRequest else {
      run.preparation = .skipped
      return advance(&state, run: run, to: .saving)
    }
    state.phase = .running(run)
    let coordinator = makeCoordinator(state)
    return .run { send in
      let reply = await coordinator.collectPreparation(request)
      await send(.briefingReplyReceived(reply))
    }
    .cancellable(id: BriefingCancelID(worktreeID: state.worktree.id), cancelInFlight: true)
  }

  private func advance(_ state: inout State, run: HandoffHudRun, to stage: HandoffStage) -> Effect<Action> {
    var run = run
    run.stage = stage
    state.phase = .running(run)
    let coordinator = makeCoordinator(state)
    let timestamp = run.startedAt
    let source = state.source
    let worktree = state.worktree
    let rootURL = state.rootURL

    switch stage {
    case .briefing:
      return .none

    case .saving:
      let preparation = run.target.kind == .briefOnly ? run.preparation : nil
      return .run { send in
        _ = try await coordinator.saveArtifact(
          outgoingAgent: source.agentToken,
          sessionContext: source.sessionContext,
          note: nil,
          preparation: preparation,
          now: timestamp
        )
        await send(.savingFinished)
      } catch: { error, send in
        await send(.runFailed(message: error.localizedDescription))
      }

    case .archiving:
      guard let toAgent = run.target.agent else { return .none }
      return .run { send in
        _ = try await coordinator.archive(from: source.agentToken, toAgent: toAgent.rawValue, now: timestamp)
        await send(.archivingFinished)
      } catch: { error, send in
        await send(.runFailed(message: error.localizedDescription))
      }

    case .launching:
      guard let destination = run.target.agent else { return .none }
      let configuration = inheritedConfiguration(source: source, destination: destination)
      let preparation = run.preparation ?? .skipped
      let targetTitle = run.target.title
      let client = terminalClient
      return .run { send in
        let request = AgentStartRequest(
          agent: destination,
          prompt: HandoffCommandHandler.kickoffPrompt(),
          configuration: configuration
        )
        let kickoff = try AgentRuntimeAdapterRegistry.makeStartInvocation(request).terminalInput
        await coordinator.logTransition(
          from: source.agentToken,
          toAgent: destination.rawValue,
          disposition: .requested,
          preparation: preparation,
          source: "agents-hud",
          now: timestamp
        )
        await client.send(
          .createTabWithInput(
            worktree,
            input: kickoff,
            workingDirectory: rootURL,
            runSetupScriptIfNew: false,
            autoCloseOnSuccess: false,
            customCommandName: "Hand off → \(targetTitle)",
            customCommandIcon: nil
          )
        )
        await send(.launchFinished)
      } catch: { error, send in
        await send(.runFailed(message: error.localizedDescription))
      }
    }
  }

  private func inheritedConfiguration(
    source: HandoffHudSource,
    destination: DetectedAgent
  ) -> AgentLaunchConfiguration {
    guard let sourceAgent = DetectedAgent(rawValue: source.agentToken) else {
      return AgentLaunchConfiguration()
    }
    return AgentRuntimeAdapterRegistry.inheritedConfiguration(
      from: sourceAgent,
      observation: source.observation,
      to: destination
    )
  }
}
