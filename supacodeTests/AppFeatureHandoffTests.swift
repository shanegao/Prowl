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

    #expect(ids.contains(CommandPaletteItemID.handoffToAgent("claude")))
    #expect(ids.contains(CommandPaletteItemID.handoffToAgent("codex")))
  }

  @Test func regularGitWorktreeShowsHandoffCommands() {
    let repositories = makeGitWorktreeState(
      repositoryRoot: URL(fileURLWithPath: "/tmp/repo"),
      worktreeRoot: URL(fileURLWithPath: "/tmp/repo-feature")
    )

    let items = CommandPaletteFeature.commandPaletteItems(from: repositories)
    let ids = items.map(\.id)

    #expect(ids.contains(CommandPaletteItemID.handoffToAgent("claude")))
    #expect(ids.contains(CommandPaletteItemID.handoffToAgent("codex")))
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

    #expect(ids.contains(CommandPaletteItemID.handoffToAgent("claude")))
    #expect(ids.contains(CommandPaletteItemID.handoffToAgent("codex")))
  }

  // MARK: - Delegate launches the receiving agent

  @Test(.dependencies) func handoffDelegateLaunchesAgentTab() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }

    let state = AppFeature.State(
      repositories: makeWorkspaceState(root: root),
      settings: SettingsFeature.State()
    )
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.commandPalette(.delegate(.handoffToAgent("claude"))))
    await store.finish()

    #expect(sent.value.count == 1)
    guard
      case .createTabWithInput(
        _,
        input: let input,
        runSetupScriptIfNew: let runSetup,
        autoCloseOnSuccess: let autoClose,
        customCommandName: let name,
        customCommandIcon: let icon
      )? = sent.value.first
    else {
      Issue.record("Expected createTabWithInput, got \(sent.value)")
      return
    }
    #expect(input == HandoffCommandHandler.kickoff(for: "claude"))
    #expect(runSetup == false)
    #expect(autoClose == false)
    #expect(name == "Hand off → claude")
    #expect(icon == nil)

    // The handoff artifact was materialized in the workspace root.
    let store2 = HandoffStore(rootURL: root)
    #expect(FileManager.default.fileExists(atPath: store2.currentURL.path(percentEncoded: false)))
    let log = try String(contentsOf: store2.logURL, encoding: .utf8)
    #expect(log.contains("launch=requested"))
    #expect(!log.contains("agent → claude  (command palette)"))
  }

  @Test(.dependencies) func handoffDelegateDoesNotLaunchWhenArtifactPreparationFails() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let repositories = makeWorkspaceState(root: root)
    try FileManager.default.removeItem(at: root)
    try "not a directory".write(to: root, atomically: true, encoding: .utf8)

    let state = AppFeature.State(
      repositories: repositories,
      settings: SettingsFeature.State()
    )
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }
    store.exhaustivity = .off

    await store.send(.commandPalette(.delegate(.handoffToAgent("claude"))))
    await store.receive(\.repositories.showToast) {
      guard case .warning(let message) = $0.repositories.statusToast else {
        Issue.record("Expected warning toast")
        return
      }
      #expect(message.hasPrefix("Hand off failed:"))
    }

    #expect(sent.value.isEmpty)
  }

  @Test(.dependencies) func handoffDelegateAttributesFocusedAgent() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let codexSurfaceID = uuid(3)
    let claudeSurfaceID = uuid(4)
    var repositories = makeWorkspaceState(root: root)
    repositories.activeAgents.entries = [
      activeAgentEntry(
        id: codexSurfaceID,
        worktreeID: root.path(percentEncoded: false),
        surfaceID: codexSurfaceID,
        displayState: .working,
        agent: .codex
      ),
      activeAgentEntry(
        id: claudeSurfaceID,
        worktreeID: root.path(percentEncoded: false),
        surfaceID: claudeSurfaceID,
        displayState: .working,
        agent: .claude
      ),
    ]
    let state = AppFeature.State(
      repositories: repositories,
      settings: SettingsFeature.State()
    )
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.handoffSessionContext = { _ in
        HandoffStore.SessionContext(
          agent: "claude",
          paneID: claudeSurfaceID.uuidString,
          paneTitle: "claude",
          source: "terminal-scrollback",
          confidence: "fallback",
          excerptText: "focused claude context"
        )
      }
    }
    store.exhaustivity = .off

    await store.send(.commandPalette(.delegate(.handoffToAgent("codex"))))
    await store.finish()

    let context = try String(contentsOf: HandoffStore(rootURL: root).contextURL, encoding: .utf8)
    #expect(context.contains("Outgoing agent (detected): claude"))
    #expect(!context.contains("Outgoing agent (detected): codex"))
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
