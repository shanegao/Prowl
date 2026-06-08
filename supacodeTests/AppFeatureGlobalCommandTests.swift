import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Testing

@testable import supacode

@MainActor
struct AppFeatureGlobalCommandTests {
  @Test(.dependencies) func globalOnlyCommandDispatchesAtIndexZero() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Global Build",
        systemImage: "hammer.fill",
        command: "swift build",
        execution: .shellScript,
        shortcut: nil,
      )
    ]

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    #expect(
      sent.value == [
        .createTabWithInput(
          worktree,
          input: "swift build",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Global Build",
          customCommandIcon: "hammer.fill"
        )
      ]
    )
  }

  @Test(.dependencies) func mergedListPlacesGlobalsFirstAndIndexesIntoEither() async {
    let worktree = makeWorktree()
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let merged = EffectiveCommandsResolver.resolve(
      globalCommands: [
        UserCustomCommand(
          title: "Global Test",
          systemImage: "testtube.2",
          command: "swift test",
          execution: .shellScript,
          shortcut: nil
        )
      ],
      perRepoCommands: [
        UserCustomCommand(
          title: "Repo Deploy",
          systemImage: "paperplane",
          command: "./deploy.sh",
          execution: .shellScript,
          shortcut: nil
        )
      ]
    )
    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktree: worktree),
      settings: SettingsFeature.State()
    )
    state.selectedCustomCommands = merged

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in
        sent.withValue { $0.append(command) }
      }
    }

    // Index 0 should be the global command (globals-first ordering).
    await store.send(.runCustomCommand(0))
    // Index 1 should be the per-repo command.
    await store.send(.runCustomCommand(1))
    await store.finish()

    #expect(sent.value.count == 2)
    if sent.value.count >= 2 {
      #expect(
        sent.value[0]
          == .createTabWithInput(
            worktree,
            input: "swift test",
            runSetupScriptIfNew: false,
            autoCloseOnSuccess: false,
            customCommandName: "Global Test",
            customCommandIcon: "testtube.2"
          )
      )
      #expect(
        sent.value[1]
          == .createTabWithInput(
            worktree,
            input: "./deploy.sh",
            runSetupScriptIfNew: false,
            autoCloseOnSuccess: false,
            customCommandName: "Repo Deploy",
            customCommandIcon: "paperplane"
          )
      )
    }
  }

  @Test(.dependencies) func editingGlobalCommandsRemergesSelectedCommandsForActiveWorktree() async {
    // Drives the full reducer chain that's the most novel logic in this feature:
    // GlobalCommandsFeature.binding → SettingsFeature.commandsChanged → SettingsFeature.persist
    //   → AppFeature.settings(.delegate(.settingsChanged)) → re-merge selectedCustomCommands.
    let worktree = makeWorktree()
    let perRepoCommand = UserCustomCommand(
      title: "Repo Lint",
      systemImage: "checkmark",
      command: "swiftlint",
      execution: .shellScript,
      shortcut: nil
    )
    let newGlobalCommand = UserCustomCommand(
      title: "Global Build",
      systemImage: "hammer.fill",
      command: "swift build",
      execution: .shellScript,
      shortcut: nil
    )

    // The reducer's settingsChanged handler reads per-repo commands from
    // `@Shared(.userRepositorySettings(rootURL))`, NOT from
    // `state.selectedCustomCommands`. Seed the @Shared storage in-memory so
    // the merge has a per-repo source to combine with the new global.
    let store = withDependencies {
      $0.defaultFileStorage = .inMemory
    } operation: {
      @Shared(.userRepositorySettings(worktree.repositoryRootURL)) var userSettings
      $userSettings.withLock { $0.customCommands = [perRepoCommand] }

      var state = AppFeature.State(
        repositories: makeRepositoriesState(worktree: worktree),
        settings: SettingsFeature.State()
      )
      state.selectedCustomCommands = [perRepoCommand]
      return TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.send = { _ in }
      }
    }
    store.exhaustivity = .off  // tolerate the GitHub/notification fan-out from settingsChanged

    // Add a global command via the child reducer's binding action.
    await store.send(.settings(.globalCommands(.binding(.set(\.commands, [newGlobalCommand]))))) {
      $0.settings.globalCommands.commands = [newGlobalCommand]
    }
    await store.skipReceivedActions()
    await store.finish()

    // After the full chain, selectedCustomCommands should be the merged list:
    // [global Build, per-repo Lint] — globals first, per-repo unchanged.
    #expect(store.state.selectedCustomCommands.count == 2)
    if store.state.selectedCustomCommands.count >= 2 {
      #expect(store.state.selectedCustomCommands[0].title == "Global Build")
      #expect(store.state.selectedCustomCommands[1].title == "Repo Lint")
    }
  }

  @Test func resolverClearsGlobalShortcutWhenPerRepoConflicts() {
    // Companion to EffectiveCommandsResolverTests; double-check the contract holds with
    // the same UserCustomCommand shape AppFeature consumes.
    let merged = EffectiveCommandsResolver.resolve(
      globalCommands: [
        UserCustomCommand(
          title: "Build",
          systemImage: "hammer",
          command: "make",
          execution: .shellScript,
          shortcut: UserCustomShortcut(key: "b", modifiers: UserCustomShortcutModifiers(command: true))
        )
      ],
      perRepoCommands: [
        UserCustomCommand(
          title: "Repo Build",
          systemImage: "hammer.fill",
          command: "bun run build",
          execution: .shellScript,
          shortcut: UserCustomShortcut(key: "b", modifiers: UserCustomShortcutModifiers(command: true))
        )
      ]
    )
    #expect(merged.count == 2)
    #expect(merged[0].title == "Build")
    #expect(merged[0].shortcut == nil, "global ⌘B should be cleared because per-repo also binds ⌘B")
    #expect(merged[1].title == "Repo Build")
    #expect(merged[1].shortcut?.key == "b")
  }

  @Test func globalCommandsBindingScopedToCommandsKeyPathOnly() async {
    // The `.binding(\.commands)` arm is the only path that
    // re-normalizes and emits commandsChanged. Catch-all `.binding` would
    // misfire on any future bindable property.
    let cmd = UserCustomCommand(
      title: "Global Lint",
      systemImage: "checkmark",
      command: "swiftlint",
      execution: .shellScript,
      shortcut: nil
    )
    let store = TestStore(initialState: GlobalCommandsFeature.State()) {
      GlobalCommandsFeature()
    }

    await store.send(.binding(.set(\.commands, [cmd]))) {
      $0.commands = [cmd]
    }
    await store.receive(\.delegate.commandsChanged)
  }

  @Test(.dependencies) func settingsChangedWithoutWorktreeStillResolvesGlobalCommands() async {
    // Editing a global command with no worktree selected used
    // to silently skip the shortcut-registry sync (customCommandsRefreshed=false
    // branch). Now we always resolve from globals.
    let setShortcutsCalled = LockIsolated<Bool>(false)
    let globalCommand = UserCustomCommand(
      title: "Global X",
      systemImage: "circle",
      command: "echo x",
      execution: .shellScript,
      shortcut: nil
    )

    // Empty repositories — no selected worktree.
    let state = AppFeature.State(
      repositories: RepositoriesFeature.State(),
      settings: SettingsFeature.State()
    )

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { _ in }
      $0.customShortcutRegistryClient.setShortcuts = { _ in
        setShortcutsCalled.setValue(true)
      }
    }
    store.exhaustivity = .off

    await store.send(.settings(.globalCommands(.binding(.set(\.commands, [globalCommand]))))) {
      $0.settings.globalCommands.commands = [globalCommand]
    }
    await store.skipReceivedActions()
    await store.finish()

    #expect(store.state.selectedCustomCommands.count == 1)
    #expect(store.state.selectedCustomCommands.first?.title == "Global X")
    #expect(setShortcutsCalled.value, "setShortcuts must run even with no active worktree")
  }

  // MARK: - Helpers

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
