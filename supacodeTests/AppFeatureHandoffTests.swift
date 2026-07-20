import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct AppFeatureHandoffTests {
  private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "handoff-app-tests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL
  }

  private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private func uuid(_ value: UInt8) -> UUID {
    UUID(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  }

  private func makeWorkspaceState(root: URL) -> RepositoriesFeature.State {
    let root = root.standardizedFileURL
    let workspace = ProjectWorkspace(id: root.path(percentEncoded: false), title: "Checkout Flow")
    let repo = Repository(
      id: root.path(percentEncoded: false),
      rootURL: root,
      name: "Checkout Flow",
      worktrees: IdentifiedArray(uniqueElements: []),
      workspace: workspace
    )
    var state = RepositoriesFeature.State()
    state.repositories = [repo]
    state.repositoryRoots = [root]
    state.selection = .repository(repo.id)
    return state
  }

  private func makeGitWorktreeState(repositoryRoot: URL, worktreeRoot: URL) -> RepositoriesFeature.State {
    let repositoryRoot = repositoryRoot.standardizedFileURL
    let worktreeRoot = worktreeRoot.standardizedFileURL
    let worktree = Worktree(
      id: worktreeRoot.path(percentEncoded: false),
      name: "feature-handoff",
      detail: "feature-handoff",
      workingDirectory: worktreeRoot,
      repositoryRootURL: repositoryRoot
    )
    let repository = Repository(
      id: repositoryRoot.path(percentEncoded: false),
      rootURL: repositoryRoot,
      name: "App",
      worktrees: [worktree]
    )
    var state = RepositoriesFeature.State()
    state.repositories = [repository]
    state.repositoryRoots = [repositoryRoot]
    state.selection = .worktree(worktree.id)
    return state
  }

  // MARK: - Command palette item presence

  @Test func workspaceShowsHandoffCommands() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let repositories = makeWorkspaceState(root: root)

    let items = CommandPaletteFeature.commandPaletteItems(from: repositories)
    let ids = items.map(\.id)

    #expect(ids.contains(CommandPaletteItemID.handOff))
  }

  @Test func regularGitWorktreeShowsHandoffCommands() {
    let repositories = makeGitWorktreeState(
      repositoryRoot: URL(fileURLWithPath: "/tmp/repo"),
      worktreeRoot: URL(fileURLWithPath: "/tmp/repo-feature")
    )

    let items = CommandPaletteFeature.commandPaletteItems(from: repositories)
    let ids = items.map(\.id)

    #expect(ids.contains(CommandPaletteItemID.handOff))
  }

  @Test func plainFolderShowsHandoffCommands() {
    let rootURL = URL(fileURLWithPath: "/tmp/plain-folder")
    let repo = Repository(
      id: rootURL.path,
      rootURL: rootURL,
      name: "Plain",
      kind: .plain,
      worktrees: IdentifiedArray(uniqueElements: [])
    )
    var repositories = RepositoriesFeature.State()
    repositories.repositories = [repo]
    repositories.selection = .repository(repo.id)

    let items = CommandPaletteFeature.commandPaletteItems(from: repositories)
    let ids = items.map(\.id)

    #expect(ids.contains(CommandPaletteItemID.handOff))
  }

  // MARK: - HUD presentation

  @Test(.dependencies) func openHandoffHudPresentsForDetectedAgent() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let state = AppFeature.State(
      repositories: makeWorkspaceState(root: root),
      settings: SettingsFeature.State()
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.handoffSourceContext = { _ in
        HandoffSourceContext(
          sessionContext: HandoffStore.SessionContext(
            agent: "codex",
            paneID: "pane-0",
            paneTitle: "codex",
            source: "terminal-scrollback",
            confidence: "fallback",
            excerptText: nil
          ),
          observation: nil,
          session: nil
        )
      }
    }
    store.exhaustivity = .off

    await store.send(.openHandoffHud) {
      let hud = try #require($0.handoffHud)
      #expect(hud.source.agentToken == "codex")
      #expect(hud.source.preparationRequest == nil)
      #expect(hud.phase == .choosing)
    }

    await store.send(.handoffHud(.presented(.delegate(.dismiss)))) {
      $0.handoffHud = nil
    }
  }

  @Test(.dependencies) func openHandoffHudWarnsWithoutDetectedAgent() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let state = AppFeature.State(
      repositories: makeWorkspaceState(root: root),
      settings: SettingsFeature.State()
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.handoffSourceContext = { _ in nil }
    }
    store.exhaustivity = .off

    await store.send(.openHandoffHud)
    await store.receive(\.repositories.showToast) {
      guard case .warning(let message) = $0.repositories.statusToast else {
        Issue.record("Expected warning toast")
        return
      }
      #expect(message.contains("No agent detected"))
    }
    #expect(store.state.handoffHud == nil)
  }

  // MARK: - Palette delegate opens the HUD; the HUD runs the hand-off

  @Test(.dependencies) func paletteHandOffRunsThroughHud() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }

    let state = AppFeature.State(
      repositories: makeWorkspaceState(root: root),
      settings: SettingsFeature.State()
    )
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let resumed = LockIsolated<AgentResumeRequest?>(nil)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
      $0.terminalClient.handoffSourceContext = { _ in
        HandoffSourceContext(
          sessionContext: HandoffStore.SessionContext(
            agent: "codex",
            paneID: "pane-0",
            paneTitle: "codex",
            source: "terminal-scrollback",
            confidence: "fallback",
            excerptText: ""
          ),
          observation: AgentLaunchObservation(model: "gpt-5.4", executionMode: .unrestricted),
          session: AgentSession(
            id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
            transcriptPath: nil,
            source: .openFile,
            confidence: .exact
          )
        )
      }
      $0.agentRuntimeClient = AgentRuntimeClient(
        resume: { request, _ in
          resumed.setValue(request)
          return """
            # Handoff

            ## Objective
            Palette source status.

            ## Current State
            Ready to hand off.

            ## Next Steps
            1. Continue in claude.
            """
        }
      )
    }
    store.exhaustivity = .off

    await store.send(.commandPalette(.delegate(.handOff)))
    let hud = try #require(store.state.handoffHud)
    #expect(hud.source.agentToken == "codex")
    let claudeIndex = try #require(hud.targets.firstIndex { $0.agent == .claude })

    await store.send(.handoffHud(.presented(.setSelectedIndex(claudeIndex))))
    await store.send(.handoffHud(.presented(.confirmSelection)))
    await store.receive(\.handoffHud.presented.launchFinished)
    await store.finish()

    guard case .finished(.handedOff(let name))? = store.state.handoffHud?.phase else {
      Issue.record("Expected handed-off outcome, got \(String(describing: store.state.handoffHud?.phase))")
      return
    }
    #expect(name == "Claude Code")

    #expect(sent.value.count == 1)
    expectClaudeLaunchCommand(sent.value.first, root: root)

    // The handoff artifact was materialized in the workspace root.
    let store2 = HandoffStore(rootURL: root)
    let log = try String(contentsOf: store2.logURL, encoding: .utf8)
    #expect(log.contains("codex → claude"))
    #expect(log.contains("launch=requested"))
    #expect(log.contains("preparation=completed"))
    #expect(log.contains("source=agents-hud"))
    #expect(resumed.value?.agent == .codex)
    #expect(resumed.value?.model == "gpt-5.4")
    // Prowl transcribed the source reply into current.md.
    let current = try String(contentsOf: store2.currentURL, encoding: .utf8)
    #expect(current.hasPrefix("# Handoff"))
    #expect(current.contains("Palette source status."))
  }

  private func expectClaudeLaunchCommand(_ command: TerminalClient.Command?, root: URL) {
    guard
      case .createTabWithInput(
        _,
        input: let input,
        workingDirectory: let workingDirectory,
        runSetupScriptIfNew: let runSetup,
        autoCloseOnSuccess: let autoClose,
        customCommandName: let commandName,
        customCommandIcon: let icon
      )? = command
    else {
      Issue.record("Expected createTabWithInput, got \(String(describing: command))")
      return
    }
    #expect(input.contains("'claude'"))
    #expect(input.contains("'--dangerously-skip-permissions'"))
    #expect(!input.contains("gpt-5.4"))
    #expect(input.contains(HandoffCommandHandler.kickoffPrompt()))
    #expect(runSetup == false)
    #expect(autoClose == false)
    #expect(commandName == "Hand off → Claude Code")
    #expect(icon == nil)
    #expect(workingDirectory == root)
  }

  @Test(.dependencies) func paletteHandOffAttributesFocusedAgent() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let claudeSurfaceID = uuid(4)
    let state = AppFeature.State(
      repositories: makeWorkspaceState(root: root),
      settings: SettingsFeature.State()
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.handoffSourceContext = { _ in
        HandoffSourceContext(
          sessionContext: HandoffStore.SessionContext(
            agent: "claude",
            paneID: claudeSurfaceID.uuidString,
            paneTitle: "claude",
            source: "terminal-scrollback",
            confidence: "fallback",
            excerptText: "focused claude context"
          ),
          observation: nil,
          session: nil
        )
      }
    }
    store.exhaustivity = .off

    // The HUD source is the focused pane's agent, not any sibling pane.
    await store.send(.commandPalette(.delegate(.handOff)))
    let hud = try #require(store.state.handoffHud)
    #expect(hud.source.agentToken == "claude")
    #expect(hud.source.sessionContext?.excerptText == "focused claude context")
    let claudeTarget = try #require(hud.targets.first { $0.agent == .claude })
    #expect(claudeTarget.isCurrentAgent)
  }

  @Test(.dependencies) func agentDoneAutoSavesExistingHandoffArtifact() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handoffStore = HandoffStore(rootURL: root)
    try handoffStore.ensureScaffold()

    let surfaceID = uuid(7)
    let tabID = TerminalTabID(rawValue: uuid(8))
    var state = AppFeature.State(
      repositories: makeWorkspaceState(root: root),
      settings: SettingsFeature.State()
    )
    state.settings.autoShowActiveAgentsPanel = false

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0.terminalClient.handoffSessionContextForSurface = { _, _ in
        HandoffStore.SessionContext(
          agent: "codex",
          sessionID: "session-1",
          paneID: surfaceID.uuidString,
          paneTitle: "codex",
          source: "terminal-scrollback",
          confidence: "fallback",
          transcriptPath: "/tmp/codex.jsonl",
          excerptText: "finished implementation"
        )
      }
    }
    store.exhaustivity = .off

    let working = activeAgentEntry(
      id: surfaceID,
      worktreeID: root.path(percentEncoded: false),
      tabID: tabID,
      surfaceID: surfaceID,
      displayState: .working
    )
    let done = activeAgentEntry(
      id: surfaceID,
      worktreeID: root.path(percentEncoded: false),
      tabID: tabID,
      surfaceID: surfaceID,
      displayState: .done
    )

    await store.send(.terminalEvent(.agentEntryChanged(working)))
    #expect(store.state.handoffAutoSaveDisplayStates[surfaceID] == .working)

    await store.send(.terminalEvent(.agentEntryChanged(done)))
    #expect(store.state.handoffAutoSaveDisplayStates[surfaceID] == .done)
    #expect(store.state.handoffAutoSaveLastSavedAt[surfaceID] == Date(timeIntervalSince1970: 1_760_000_000))
    await store.finish()

    let context = try String(contentsOf: handoffStore.contextURL, encoding: .utf8)
    #expect(context.contains("Session ID: session-1"))
    #expect(context.contains(".prowl/handoff/sessions/"))
    let sessionFiles = try FileManager.default.contentsOfDirectory(
      at: handoffStore.sessionDirectory,
      includingPropertiesForKeys: nil
    )
    let sessionFile = try #require(sessionFiles.first)
    let session = try String(contentsOf: sessionFile, encoding: .utf8)
    #expect(session.contains("finished implementation"))
    let log = try String(contentsOf: handoffStore.logURL, encoding: .utf8)
    #expect(log.contains("auto-save: codex done"))
  }

  @Test(.dependencies) func agentDoneDoesNotCreateHandoffArtifact() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handoffStore = HandoffStore(rootURL: root)

    let surfaceID = uuid(9)
    let state = AppFeature.State(
      repositories: makeWorkspaceState(root: root),
      settings: SettingsFeature.State()
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    }
    store.exhaustivity = .off

    let working = activeAgentEntry(
      id: surfaceID,
      worktreeID: root.path(percentEncoded: false),
      surfaceID: surfaceID,
      displayState: .working
    )
    let done = activeAgentEntry(
      id: surfaceID,
      worktreeID: root.path(percentEncoded: false),
      surfaceID: surfaceID,
      displayState: .done
    )

    await store.send(.terminalEvent(.agentEntryChanged(working)))
    #expect(store.state.handoffAutoSaveDisplayStates[surfaceID] == .working)

    await store.send(.terminalEvent(.agentEntryChanged(done)))
    #expect(store.state.handoffAutoSaveDisplayStates[surfaceID] == .done)
    await store.finish()

    #expect(handoffStore.hasCurrentArtifact == false)
  }

  @Test(.dependencies) func agentDoneAutoSavesToNonMainWorktreeRoot() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let repositoryRoot = root.appending(path: "main", directoryHint: .isDirectory)
    let worktreeRoot = root.appending(path: "feature", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
    let worktreeStore = HandoffStore(rootURL: worktreeRoot)
    try worktreeStore.ensureScaffold()

    let surfaceID = uuid(10)
    var state = AppFeature.State(
      repositories: makeGitWorktreeState(repositoryRoot: repositoryRoot, worktreeRoot: worktreeRoot),
      settings: SettingsFeature.State()
    )
    state.settings.autoShowActiveAgentsPanel = false
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
    }
    store.exhaustivity = .off

    let working = activeAgentEntry(
      id: surfaceID,
      worktreeID: worktreeRoot.path(percentEncoded: false),
      surfaceID: surfaceID,
      displayState: .working
    )
    let done = activeAgentEntry(
      id: surfaceID,
      worktreeID: worktreeRoot.path(percentEncoded: false),
      surfaceID: surfaceID,
      displayState: .done
    )

    await store.send(.terminalEvent(.agentEntryChanged(working)))
    await store.send(.terminalEvent(.agentEntryChanged(done)))
    await store.finish()

    let context = try String(contentsOf: worktreeStore.contextURL, encoding: .utf8)
    #expect(context.contains("Outgoing agent (detected): codex"))
    #expect(HandoffStore(rootURL: repositoryRoot).hasCurrentArtifact == false)
  }

  private func activeAgentEntry(
    id: UUID,
    worktreeID: Worktree.ID,
    tabID: TerminalTabID = TerminalTabID(rawValue: UUID()),
    surfaceID: UUID,
    displayState: AgentDisplayState,
    agent: DetectedAgent = .codex
  ) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: id,
      worktreeID: worktreeID,
      worktreeName: "Checkout Flow",
      workingDirectory: nil,
      tabID: tabID,
      paneTitle: agent.rawValue,
      surfaceID: surfaceID,
      paneIndex: 1,
      iconLookupToken: agent.iconLookupToken,
      agent: agent,
      rawState: displayState == .working ? .working : .idle,
      displayState: displayState,
      lastChangedAt: Date(timeIntervalSince1970: 1_760_000_000)
    )
  }
}
