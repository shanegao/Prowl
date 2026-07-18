import AppKit
import ComposableArchitecture

extension AppFeature {
  func reduceCommandPaletteAction(
    _ action: CommandPaletteFeature.Action,
    state: inout State
  ) -> Effect<Action> {
    switch action {
    case .setPresented(false):
      guard state.commandPalette.isPresented else { return .none }
      return restoreCommandPaletteTerminalFocusEffect(repositories: state.repositories)

    case .togglePresented:
      guard state.commandPalette.isPresented else { return .none }
      return restoreCommandPaletteTerminalFocusEffect(repositories: state.repositories)

    case .delegate(let delegate):
      return reduceCommandPaletteDelegate(delegate, state: &state)

    default:
      return .none
    }
  }

  func reduceCommandPaletteDelegate(
    _ delegate: CommandPaletteFeature.Delegate,
    state: inout State
  ) -> Effect<Action> {
    if let effect = reduceCommandPaletteNavigationDelegate(delegate, state: &state) {
      return effect
    }
    if let effect = reduceCommandPaletteRepositoryDelegate(delegate) {
      return effect
    }
    if let effect = reduceCommandPaletteCanvasDelegate(delegate) {
      return effect
    }
    if let effect = reduceCommandPaletteWorktreeFileDelegate(delegate, state: &state) {
      return effect
    }
    if let effect = reduceCommandPaletteWorktreeActionDelegate(delegate, state: &state) {
      return effect
    }
    if let effect = reduceCommandPaletteHandoffDelegate(delegate, state: &state) {
      return effect
    }
    if let effect = reduceCommandPalettePullRequestDelegate(delegate) {
      return effect
    }
    #if DEBUG
      if let effect = reduceCommandPaletteDebugDelegate(delegate) {
        return effect
      }
    #endif
    return .none
  }

  func reduceCommandPaletteNavigationDelegate(
    _ delegate: CommandPaletteFeature.Delegate,
    state: inout State
  ) -> Effect<Action>? {
    switch delegate {
    case .selectWorktree(let worktreeID):
      if state.repositories.isShowingCanvas {
        if state.repositories.worktree(for: worktreeID) == nil,
          state.repositories.repositories[id: worktreeID]?.kind == .plain
        {
          return .send(.repositories(.focusCanvasRepository(worktreeID)))
        }
        return .send(.repositories(.focusCanvasWorktree(worktreeID)))
      }
      return .send(.repositories(.selectWorktree(worktreeID)))

    case .checkForUpdates:
      return .send(.updates(.checkForUpdates))

    case .openSettings:
      return .merge(
        .send(.settings(.setSelection(.general))),
        .run { _ in
          await settingsWindowClient.show()
        }
      )

    case .newWorktree:
      return .send(.repositories(.worktreeCreation(.createRandomWorktree)))

    case .deleteWorktree(let worktreeID, let repositoryID):
      return .send(.repositories(.worktreeLifecycle(.requestDeleteWorktree(worktreeID, repositoryID))))

    case .viewArchivedWorktrees:
      return .send(.repositories(.selectArchivedWorktrees))

    case .refreshWorktrees:
      return .send(.repositories(.refreshWorktrees))

    case .jumpToLatestUnread:
      return .send(.jumpToLatestUnread)

    case .installCLI:
      return .send(.settings(.installCLIButtonTapped(showAlert: false)))

    case .toggleLeftSidebar:
      return .send(.toggleLeftSidebar)

    case .toggleActiveAgentsPanel:
      return .send(.repositories(.activeAgents(.togglePanelVisibility)))

    default:
      return nil
    }
  }

  func reduceCommandPaletteRepositoryDelegate(
    _ delegate: CommandPaletteFeature.Delegate
  ) -> Effect<Action>? {
    switch delegate {
    case .openRepository:
      return .send(.repositories(.setOpenPanelPresented(true)))

    case .newWorkspace:
      return .send(.repositories(.workspaceCreation(.promptRequested)))

    default:
      return nil
    }
  }

  func reduceCommandPaletteCanvasDelegate(
    _ delegate: CommandPaletteFeature.Delegate
  ) -> Effect<Action>? {
    switch delegate {
    case .toggleCanvas:
      return .send(.repositories(.toggleCanvas))

    case .expandCanvasCard:
      return .send(.repositories(.requestCanvasCommand(.toggleExpand)))

    case .arrangeCanvasCards:
      return .send(.repositories(.requestCanvasCommand(.arrange)))

    case .organizeCanvasCards:
      return .send(.repositories(.requestCanvasCommand(.organize)))

    case .tileCanvasCards:
      return .send(.repositories(.requestCanvasCommand(.tile)))

    case .selectAllCanvasCards:
      return .send(.repositories(.requestCanvasCommand(.selectAll)))

    case .toggleShelf:
      return .send(.repositories(.toggleShelf))

    default:
      return nil
    }
  }

  func reduceCommandPaletteWorktreeFileDelegate(
    _ delegate: CommandPaletteFeature.Delegate,
    state: inout State
  ) -> Effect<Action>? {
    switch delegate {
    case .showDiff:
      return openSelectedWorktreeDiffEffect(state: state)

    case .revealInFinder:
      return .send(.openWorktree(.finder))

    case .copyPath:
      guard let worktree = state.repositories.selectedTerminalWorktree else {
        return .none
      }
      let path = worktree.workingDirectory.path
      return .run { _ in
        await MainActor.run {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(path, forType: .string)
        }
      }

    case .revealInSidebar:
      guard state.repositories.selectedWorktreeID != nil else { return .none }
      return .merge(
        .send(.showLeftSidebar),
        .send(.repositories(.revealSelectedWorktreeInSidebar))
      )

    default:
      return nil
    }
  }

  func openDiffEffect(
    worktree: Worktree,
    resolvedKeybindings: ResolvedKeybindingMap
  ) -> Effect<Action> {
    @Shared(.settingsFile) var settingsFile
    let settings = ExternalDiffSettings(
      toolID: settingsFile.global.externalDiffToolID,
      customCommand: settingsFile.global.externalDiffCustomCommand
    )
    return .run { send in
      await externalDiffToolClient.open(settings, worktree, resolvedKeybindings) { error in
        send(.openWorktreeFailed(error))
      }
    }
  }

  func openSelectedWorktreeDiffEffect(state: State) -> Effect<Action> {
    guard let worktreeID = state.repositories.selectedWorktreeID,
      let worktree = state.repositories.worktree(for: worktreeID)
    else {
      return .none
    }
    return openDiffEffect(worktree: worktree, resolvedKeybindings: state.resolvedKeybindings)
  }

  func reduceCommandPaletteWorktreeActionDelegate(
    _ delegate: CommandPaletteFeature.Delegate,
    state: inout State
  ) -> Effect<Action>? {
    switch delegate {
    case .runScript:
      return .send(.runScript)

    case .stopRunScript:
      return .send(.stopRunScript)

    case .renameBranch:
      guard let worktreeID = state.repositories.selectedWorktreeID else { return .none }
      return .send(.repositories(.requestRenameBranchPrompt(worktreeID)))

    case .openRepositorySettings(let repositoryID):
      // Reuse the existing repo-side flow so the repo-existence guard and
      // settingsWindowClient.show() live in one place.
      return .send(.repositories(.repositoryManagement(.openRepositorySettings(repositoryID))))

    case .togglePinWorktree(let worktreeID, let isCurrentlyPinned):
      if isCurrentlyPinned {
        return .send(.repositories(.worktreeOrdering(.unpinWorktree(worktreeID))))
      }
      return .send(.repositories(.worktreeOrdering(.pinWorktree(worktreeID))))

    case .runCustomCommand(let index):
      return .send(.runCustomCommand(index))

    case .ghosttyCommand(let action):
      guard let worktree = actionTargetWorktree(repositories: state.repositories) else {
        return .none
      }
      // Capture the target surface synchronously: the async effect below races
      // AppKit's post-dismiss focus reshuffle, which can hand first responder
      // to a different pane before the binding action runs.
      let command: TerminalClient.Command
      if let surfaceID = terminalClient.selectedSurfaceID(worktree.id) {
        command = .performBindingActionOnSurface(worktree, surfaceID: surfaceID, action: action)
      } else {
        command = .performBindingAction(worktree, action: action)
      }
      return .run { _ in
        await terminalClient.send(command)
      }

    case .changeFocusedTabIcon(let worktreeID):
      guard let worktree = state.repositories.selectedTerminalWorktree,
        worktree.id == worktreeID
      else {
        return .none
      }
      return .run { _ in
        await terminalClient.send(.presentTabIconPicker(worktree))
      }

    default:
      return nil
    }
  }

  func reduceCommandPaletteHandoffDelegate(
    _ delegate: CommandPaletteFeature.Delegate,
    state: inout State
  ) -> Effect<Action>? {
    guard case .handoffToAgent(let agent) = delegate else { return nil }
    // Hand off the current workspace task to the other agent: refresh + archive
    // the handoff artifact, then launch the receiving agent in a new tab whose
    // kickoff points at `.prowl/handoff/current.md`. Mirrors `prowl handoff to`.
    guard let worktree = state.repositories.selectedTerminalWorktree else {
      return .none
    }
    guard let destinationAgent = DetectedAgent(rawValue: agent) else { return .none }
    let rootURL = worktree.workingDirectory
    let sessionContext = terminalClient.handoffSessionContext(worktree.id)
    let outgoing = sessionContext?.agent
    let observation = terminalClient.handoffLaunchObservation(worktree.id)
    let preparationRequest = HandoffCommandHandler.preparationRequest(
      outgoingAgent: outgoing,
      session: terminalClient.handoffAgentSession(worktree.id),
      observation: observation
    )
    let configuration: AgentLaunchConfiguration
    if let sourceAgent = outgoing.flatMap(DetectedAgent.init(rawValue:)) {
      configuration = AgentRuntimeAdapterRegistry.inheritedConfiguration(
        from: sourceAgent,
        observation: observation,
        to: destinationAgent
      )
    } else {
      configuration = .init()
    }
    let request = AgentStartRequest(
      agent: destinationAgent,
      prompt: HandoffCommandHandler.kickoffPrompt(),
      configuration: configuration
    )
    guard let kickoff = try? AgentRuntimeAdapterRegistry.makeStartInvocation(request).terminalInput else {
      return .none
    }
    return .run { send in
      let store = HandoffStore(rootURL: rootURL)
      let now = Date()
      let preparation: HandoffPreparationOutcome
      if let preparationRequest {
        await send(.repositories(.showToast(.inProgress("Preparing handoff from \(outgoing ?? "agent")…"))))
        preparation = await Self.prepareHandoffSource(
          request: preparationRequest,
          store: store,
          rootURL: rootURL,
          runtimeClient: agentRuntimeClient,
          now: now
        )
      } else {
        preparation = .skipped
      }
      do {
        try await Task.detached {
          _ = try store.save(
            outgoingAgent: outgoing,
            sessionContext: sessionContext,
            note: nil,
            now: now
          )
          _ = try store.archiveCurrent(from: outgoing ?? "agent", toAgent: agent, now: now)
          try store.appendLog(
            "handoff prepared  from=\(outgoing ?? "agent")  to=\(agent)  preparation=\(preparation.rawValue)  "
              + "launch=requested  source=command-palette",
            now: now
          )
        }.value
      } catch {
        await MainActor.run {
          appLogger.warning("[Handoff] command palette failed for \(rootURL.path(percentEncoded: false)): \(error)")
        }
        await send(.repositories(.showToast(.warning("Hand off failed: \(error.localizedDescription)"))))
        return
      }
      await terminalClient.send(
        .createTabWithInput(
          worktree,
          input: kickoff,
          workingDirectory: rootURL,
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Hand off → \(agent)",
          customCommandIcon: nil
        )
      )
      if preparationRequest != nil {
        if preparation == .completed {
          await send(.repositories(.dismissToast))
        } else {
          await send(
            .repositories(.showToast(.warning("Handed off with existing notes (source preparation failed)")))
          )
        }
      }
    }
  }

  /// Resumes the outgoing session read-only, then validates and transcribes its
  /// reply into `current.md`. Mirrors `HandoffCommandHandler`'s CLI-side flow.
  private static func prepareHandoffSource(
    request: AgentResumeRequest,
    store: HandoffStore,
    rootURL: URL,
    runtimeClient: AgentRuntimeClient,
    now: Date
  ) async -> HandoffPreparationOutcome {
    do {
      let reply = try await runtimeClient.resume(request, in: rootURL)
      return await Task.detached {
        store.applyPreparationReply(reply, now: now) ? HandoffPreparationOutcome.completed : .failed
      }.value
    } catch {
      return .failed
    }
  }

  func reduceCommandPalettePullRequestDelegate(
    _ delegate: CommandPaletteFeature.Delegate
  ) -> Effect<Action>? {
    switch delegate {
    case .openPullRequest(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .openOnCodeHost))))

    case .markPullRequestReady(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .markReadyForReview))))

    case .mergePullRequest(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .merge))))

    case .closePullRequest(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .close))))

    case .copyFailingJobURL(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .copyFailingJobURL))))

    case .copyCiFailureLogs(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .copyCiFailureLogs))))

    case .rerunFailedJobs(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .rerunFailedJobs))))

    case .openFailingCheckDetails(let worktreeID):
      return .send(.repositories(.githubIntegration(.pullRequestAction(worktreeID, .openFailingCheckDetails))))

    default:
      return nil
    }
  }

  #if DEBUG
    func reduceCommandPaletteDebugDelegate(
      _ delegate: CommandPaletteFeature.Delegate
    ) -> Effect<Action>? {
      switch delegate {
      case .debugTestToast(let toast):
        return .send(.repositories(.showToast(toast)))

      case .debugSimulateUpdateFound:
        return .send(.updates(.debugSimulateUpdateFound))

      case .debugLightDockNotificationDot:
        return .run { _ in await dockClient.setNotificationBadge(1) }

      default:
        return nil
      }
    }
  #endif
}
