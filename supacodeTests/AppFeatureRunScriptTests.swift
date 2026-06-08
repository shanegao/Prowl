import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

@MainActor
struct AppFeatureRunScriptTests {
  @Test(.dependencies) func runScriptWithoutConfiguredScriptPresentsPrompt() async {
    let worktree = makeWorktree()
    let repositories = makeRepositoriesState(worktree: worktree)
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositories,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.runScript) {
      $0.runScriptDraft = ""
      $0.isRunScriptPromptPresented = true
    }
  }

  @Test(.dependencies) func saveRunScriptAndRunPersistsAndExecutesScript() async {
    let worktree = makeWorktree()
    let repositories = makeRepositoriesState(worktree: worktree)
    let storage = SettingsTestStorage()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(
        initialState: AppFeature.State(
          repositories: repositories,
          settings: SettingsFeature.State()
        )
      ) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.send = { command in
          sent.withValue { $0.append(command) }
        }
      }
    }

    await store.send(.runScript) {
      $0.runScriptDraft = ""
      $0.isRunScriptPromptPresented = true
    }
    await store.send(.runScriptDraftChanged("npm run dev")) {
      $0.runScriptDraft = "npm run dev"
    }
    await store.send(.saveRunScriptAndRun) {
      $0.selectedRunScript = "npm run dev"
      $0.runScriptDraft = ""
      $0.isRunScriptPromptPresented = false
    }
    await store.receive(\.runScript)
    await store.finish()

    #expect(sent.value == [.runScript(worktree, script: "npm run dev")])

    let savedRunScript = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.repositorySettings(worktree.repositoryRootURL)) var repositorySettings
      return repositorySettings.runScript
    }
    #expect(savedRunScript == "npm run dev")
  }

  @Test(.dependencies) func runScriptDoesNotOverwriteDraftWhenPromptAlreadyPresented() async {
    let worktree = makeWorktree()
    let repositories = makeRepositoriesState(worktree: worktree)
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositories,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    }

    await store.send(.runScript) {
      $0.runScriptDraft = ""
      $0.isRunScriptPromptPresented = true
    }
    await store.send(.runScriptDraftChanged("pnpm dev")) {
      $0.runScriptDraft = "pnpm dev"
    }
    await store.send(.runScript)
    #expect(store.state.runScriptDraft == "pnpm dev")
    #expect(store.state.isRunScriptPromptPresented)
  }

  @Test(.dependencies) func runScriptUsesCanvasFocusedWorktree() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])

    // In canvas mode, `actionTargetContext` reads the script from
    // `@Shared(.repositorySettings(rootURL))`, not from `state.selectedRunScript`.
    // Seed the shared store under .inMemory so the test exercises the same
    // path the live app would.
    let store = withDependencies {
      $0.defaultFileStorage = .inMemory
    } operation: {
      @Shared(.repositorySettings(worktree.repositoryRootURL)) var repoSettings
      $repoSettings.withLock { $0.runScript = "npm test" }

      var repositories = makeRepositoriesState(worktree: worktree)
      repositories.selection = .canvas(.overall)
      var state = AppFeature.State(
        repositories: repositories,
        settings: SettingsFeature.State()
      )
      state.selectedRunScript = "npm test"

      return TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { worktree.id }
        $0.terminalClient.send = { command in
          sent.withValue { $0.append(command) }
        }
      }
    }
    store.exhaustivity = .off

    await store.send(.runScript)
    await store.finish()

    #expect(sent.value == [.runScript(worktree, script: "npm test")])
  }

  @Test(.dependencies) func newTerminalUsesCanvasFocusedWorktree() async {
    let worktree = makeWorktree()
    var repositories = makeRepositoriesState(worktree: worktree)
    repositories.selection = .canvas(.overall)
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositories,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { worktree.id }
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.newTerminal)
    await store.finish()

    #expect(sent.value == [.createTab(worktree, runSetupScriptIfNew: false)])
  }

  private func makeWorktree() -> Worktree {
    Worktree(
      id: "/tmp/repo/wt-1",
      name: "wt-1",
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
      repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
    )
  }

  private func makeRepositoriesState(worktree: Worktree) -> RepositoriesFeature.State {
    let repository = Repository(
      id: "/tmp/repo",
      rootURL: URL(fileURLWithPath: "/tmp/repo"),
      name: "repo",
      worktrees: [worktree]
    )
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    repositoriesState.selection = .worktree(worktree.id)
    return repositoriesState
  }
}
