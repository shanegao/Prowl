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
    return url
  }

  private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private func makeWorkspaceState(root: URL) -> RepositoriesFeature.State {
    let workspace = ProjectWorkspace(id: root.path, title: "Checkout Flow")
    let repo = Repository(
      id: root.path,
      rootURL: root,
      name: "Checkout Flow",
      worktrees: IdentifiedArray(uniqueElements: []),
      workspace: workspace
    )
    var state = RepositoriesFeature.State()
    state.repositories = [repo]
    state.selection = .repository(repo.id)
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

  @Test func nonWorkspaceHidesHandoffCommands() {
    let rootURL = URL(fileURLWithPath: "/tmp/plain-repo")
    let repo = Repository(
      id: rootURL.path,
      rootURL: rootURL,
      name: "Plain",
      kind: .git,
      worktrees: IdentifiedArray(uniqueElements: [])
    )
    var repositories = RepositoriesFeature.State()
    repositories.repositories = [repo]
    repositories.selection = .repository(repo.id)

    let items = CommandPaletteFeature.commandPaletteItems(from: repositories)
    let ids = items.map(\.id)

    #expect(!ids.contains(CommandPaletteItemID.handoffToAgent("claude")))
    #expect(!ids.contains(CommandPaletteItemID.handoffToAgent("codex")))
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
  }
}
