import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import Sharing
import Testing

@testable import supacode

/// Canvas-vs-sidebar dispatch coverage for `AppFeature.actionTargetContext` —
/// the helper that resolves which worktree (and which repo's settings/commands)
/// the user-driven action handlers should act on.
///
/// **Invariants under test**:
/// 1. `.canvas(.worktree(id))` scope (per-worktree canvas): the scope itself
///    names the target. `canvasFocusedWorktreeID` is not required because only
///    one card is rendered — there's nothing to mis-route to.
/// 2. `.canvas(.repository(_))` / `.canvas(.overall)` scope (multi-card canvas):
///    `canvasFocusedWorktreeID` is authoritative. If it's nil or doesn't
///    resolve, the helper returns nil rather than silently retargeting the
///    sidebar selection.
/// 3. Canvas not showing: sidebar selection wins regardless of any stale
///    `canvasFocusedWorktreeID`.
///
/// Each test pins one branch of the helper plus one downstream handler so a
/// regression in either layer fails an assertion instead of silently rewiring
/// the dispatch target.
@MainActor
struct AppFeatureActionTargetContextTests {
  // MARK: - Rank 10 (load-bearing)

  /// `.runScript` in canvas mode reads the focused worktree's
  /// `@Shared(.repositorySettings).runScript`, not `state.selectedRunScript`
  /// (which mirrors the sidebar selection).
  @Test(.dependencies)
  func runScriptInCanvasUsesFocusedWorktreeRepoScript() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let storage = SettingsTestStorage()
    let sent = LockIsolated<[TerminalClient.Command]>([])

    // Seed the canvas-focused repo's runScript via the shared storage.
    try? withDependencies({ $0.settingsFileStorage = storage.storage }) {
      @Shared(.repositorySettings(focused.repositoryRootURL)) var focusedSettings
      $focusedSettings.withLock { $0.runScript = "make canvas-script" }
    }

    var state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [sidebar, focused], selection: .canvas(.overall)),
      settings: SettingsFeature.State()
    )
    // Sidebar-derived state holds a *different* script to prove the helper
    // doesn't fall back to it when canvas-focus resolves.
    state.selectedRunScript = "make sidebar-script"

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
        $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
      }
    }

    await store.send(.runScript)
    await store.finish()

    #expect(sent.value == [.runScript(focused, script: "make canvas-script")])
  }

  /// `.runCustomCommand(index)` in canvas mode indexes into the focused repo's
  /// effective commands (per-repo merged with globals), not the sidebar-derived
  /// `state.selectedCustomCommands` array.
  @Test(.dependencies)
  func runCustomCommandInCanvasUsesFocusedRepoCommands() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let storage = SettingsTestStorage()
    let sent = LockIsolated<[TerminalClient.Command]>([])

    let focusedCommand = UserCustomCommand(
      title: "Focused",
      systemImage: "checkmark.circle",
      command: "echo canvas",
      execution: .shellScript,
      shortcut: nil
    )
    try? withDependencies({ $0.settingsFileStorage = storage.storage }) {
      @Shared(.userRepositorySettings(focused.repositoryRootURL)) var focusedUserSettings
      $focusedUserSettings.withLock { $0.customCommands = [focusedCommand] }
    }

    var state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [sidebar, focused], selection: .canvas(.overall)),
      settings: SettingsFeature.State()
    )
    // Sidebar-derived array holds a *different* command at index 0 to prove
    // the helper doesn't index into it when canvas-focus resolves.
    state.selectedCustomCommands = [
      UserCustomCommand(
        title: "Sidebar",
        systemImage: "circle",
        command: "echo sidebar",
        execution: .shellScript,
        shortcut: nil
      )
    ]

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
        $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
      }
    }

    await store.send(.runCustomCommand(0))
    await store.finish()

    #expect(
      sent.value == [
        .createTabWithInput(
          focused,
          input: "echo canvas",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Focused",
          customCommandIcon: "checkmark.circle"
        )
      ]
    )
  }

  /// The palette `runCustomCommand(commandID)` delegate resolves the commandID
  /// against the focused repo's effective commands list. A command that exists
  /// only in the focused repo must dispatch even if it's absent from the
  /// sidebar-derived `state.selectedCustomCommands`.
  @Test(.dependencies)
  func paletteRunCustomCommandResolvesAgainstFocusedRepoCommands() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    let focusedCommand = UserCustomCommand(
      title: "Focused",
      systemImage: "checkmark.circle",
      command: "echo canvas",
      execution: .shellScript,
      shortcut: nil
    )

    // `@Shared(.userRepositorySettings)` reads through `repositoryLocalSettingsStorage`
    // (backed by `defaultFileStorage`), not `settingsFileStorage`. Wrap the seed
    // and store creation in the same `defaultFileStorage = .inMemory` scope so
    // the reducer's `actionTargetContext` reads the focused repo's commands.
    let store = withDependencies {
      $0.defaultFileStorage = .inMemory
    } operation: {
      @Shared(.userRepositorySettings(focused.repositoryRootURL)) var focusedUserSettings
      $focusedUserSettings.withLock { $0.customCommands = [focusedCommand] }

      var state = AppFeature.State(
        repositories: makeRepositoriesState(
          worktrees: [sidebar, focused], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
      // Sidebar-derived array is empty, so resolving against it would alert.
      // The fix routes through the focused repo's effective commands instead.
      state.selectedCustomCommands = []

      return TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
        $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
      }
    }
    store.exhaustivity = .off

    await store.send(.commandPalette(.delegate(.runCustomCommand(commandID: focusedCommand.id))))
    await store.finish()

    // Production also sends `.focusSelectedTab(focused)` as a separate side
    // effect of the canvas-focus path before the command's tab is created.
    // Assert containment rather than strict equality so the test focuses on
    // the dispatch behavior under verification.
    #expect(
      sent.value.contains(
        .createTabWithInput(
          focused,
          input: "echo canvas",
          runSetupScriptIfNew: false,
          autoCloseOnSuccess: false,
          customCommandName: "Focused",
          customCommandIcon: "checkmark.circle"
        )
      )
    )
  }

  // MARK: - Rank 9

  /// `.openSelectedWorktree` in canvas mode re-routes through
  /// `.openWorktreeForWorktree` with the focused worktree's ID and its repo's
  /// `openActionID` — not the sidebar-derived `state.openActionSelection`.
  @Test(.dependencies)
  func openSelectedWorktreeInCanvasReRoutesToFocusedWorktreeAndAction() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let storage = SettingsTestStorage()

    try? withDependencies({ $0.settingsFileStorage = storage.storage }) {
      @Shared(.repositorySettings(focused.repositoryRootURL)) var focusedSettings
      $focusedSettings.withLock { $0.openActionID = OpenWorktreeAction.finder.settingsID }
    }

    var state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [sidebar, focused], selection: .canvas(.overall)),
      settings: SettingsFeature.State()
    )
    // Sidebar's selection differs from focused's openActionID. If the handler
    // accidentally fell back to sidebar state, this would route to Editor.
    state.openActionSelection = .editor

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
      }
    }
    store.exhaustivity = .off

    await store.send(.openSelectedWorktree)
    await store.receive(\.openWorktreeForWorktree)
    await store.finish()
  }

  /// The canvas target helper must pass the focused worktree's working directory
  /// into Automatic open-action resolution. Without it, project-aware defaults
  /// such as Xcode for Swift packages are skipped in multi-card canvas mode.
  @Test(.dependencies)
  func actionTargetContextInCanvasResolvesAutomaticOpenActionWithFocusedWorkingDirectory() throws {
    try withTemporaryDirectory { directory in
      try Data().write(to: directory.appending(path: "Package.swift"))
      let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
      let focused = Worktree(
        id: directory.path(percentEncoded: false),
        name: "apple-project",
        detail: "detail",
        workingDirectory: directory,
        repositoryRootURL: directory
      )
      let storage = SettingsTestStorage()

      try? withDependencies({ $0.settingsFileStorage = storage.storage }) {
        @Shared(.repositorySettings(focused.repositoryRootURL)) var focusedSettings
        $focusedSettings.withLock {
          $0.openActionID = OpenWorktreeAction.automaticSettingsID
        }
      }

      var settings = SettingsFeature.State()
      settings.defaultEditorID = OpenWorktreeAction.automaticSettingsID
      let state = AppFeature.State(
        repositories: makeRepositoriesState(
          worktrees: [sidebar, focused],
          selection: .canvas(.overall)
        ),
        settings: settings
      )

      let context = withDependencies {
        $0.settingsFileStorage = storage.storage
        $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
      } operation: {
        AppFeature().actionTargetContext(state: state)
      }

      let expected = OpenWorktreeAction.fromSettingsID(
        OpenWorktreeAction.automaticSettingsID,
        defaultEditorID: settings.defaultEditorID,
        workingDirectory: focused.workingDirectory
      )
      #expect(context?.worktree == focused)
      #expect(context?.openAction == expected)
    }
  }

  /// `.openActionResetToAutomaticForWorktree` is the canvas focused-card sibling
  /// of `.openActionResetToAutomatic` (which targets the nil-in-canvas sidebar
  /// selection). It re-pins the given worktree's repo to automatic — overwriting
  /// a prior concrete-app pin — and reopens it via `.openWorktreeForWorktree`.
  @Test(.dependencies)
  func openActionResetToAutomaticForWorktreePinsAutomaticAndReopens() async {
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let storage = SettingsTestStorage()

    // Start pinned to a concrete app so the reset has a non-automatic pin to clear.
    try? withDependencies({ $0.settingsFileStorage = storage.storage }) {
      @Shared(.repositorySettings(focused.repositoryRootURL)) var focusedSettings
      $focusedSettings.withLock { $0.openActionID = OpenWorktreeAction.finder.settingsID }
    }

    let state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [focused], selection: .canvas(.worktree(focused.id))),
      settings: SettingsFeature.State()
    )

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: state) {
        AppFeature()
      }
    }
    store.exhaustivity = .off

    await store.send(.openActionResetToAutomaticForWorktree(focused.id))
    await store.receive(\.openWorktreeForWorktree)
    await store.finish()

    // The focused repo's pin is now automatic, not the prior `.finder`.
    withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.repositorySettings(focused.repositoryRootURL)) var focusedSettings
      #expect(focusedSettings.openActionID == OpenWorktreeAction.automaticSettingsID)
    }
  }

  // MARK: - Rank 8

  /// `.newTerminal` in canvas mode creates a tab on the focused worktree and
  /// resolves `runSetupScriptIfNew` against the *focused* worktree's pending
  /// setup-script membership, not the sidebar's.
  @Test(.dependencies)
  func newTerminalInCanvasCreatesTabOnFocusedWorktree() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    var repositoriesState = makeRepositoriesState(
      worktrees: [sidebar, focused], selection: .canvas(.overall))
    repositoriesState.pendingSetupScriptWorktreeIDs = [focused.id]

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: repositoriesState,
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.newTerminal)
    await store.finish()

    #expect(sent.value == [.createTab(focused, runSetupScriptIfNew: true)])
  }

  /// `.stopRunScript` in canvas mode targets the focused worktree's terminal,
  /// not the sidebar's. Without this, start/stop split across worktrees.
  @Test(.dependencies)
  func stopRunScriptInCanvasTargetsFocusedWorktree() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(
          worktrees: [sidebar, focused], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.stopRunScript)
    await store.finish()

    #expect(sent.value == [.stopRunScript(focused)])
  }

  // MARK: - Rank 7 (boundary cases that pin the "no silent fallback" invariant)

  /// `isShowingCanvas == true` but `canvasFocusedWorktreeID()` returns nil:
  /// the helper returns nil — `.runScript` short-circuits with no `.send` to
  /// the terminal. The previous draft of the helper silently fell through to
  /// the sidebar's worktree here; this test pins the post-fix behavior so a
  /// future refactor can't reintroduce the fall-through.
  @Test(.dependencies)
  func runScriptInCanvasWithNoFocusReturnsNoneInsteadOfSidebarFallback() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktrees: [sidebar], selection: .canvas(.overall)),
      settings: SettingsFeature.State()
    )
    state.selectedRunScript = "make sidebar-script"

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { nil }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.runScript)
    await store.finish()

    #expect(sent.value.isEmpty)
    #expect(!state.isRunScriptPromptPresented)
  }

  /// `isShowingCanvas == true` and `canvasFocusedWorktreeID()` returns an ID
  /// that no longer resolves in `state.repositories` (worktree pruned after
  /// canvas was opened): the helper returns nil rather than masking the stale
  /// state by silently retargeting the sidebar.
  @Test(.dependencies)
  func runScriptInCanvasWithStaleFocusReturnsNoneInsteadOfSidebarFallback() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let staleID = "/tmp/repo-vanished/wt-removed"
    let sent = LockIsolated<[TerminalClient.Command]>([])

    var state = AppFeature.State(
      repositories: makeRepositoriesState(worktrees: [sidebar], selection: .canvas(.overall)),
      settings: SettingsFeature.State()
    )
    state.selectedRunScript = "make sidebar-script"

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { staleID }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.runScript)
    await store.finish()

    #expect(sent.value.isEmpty)
  }

  // MARK: - Search family routing

  /// The 5 search handlers (`.startSearch`, `.searchSelection`,
  /// `.navigateSearchNext`, `.navigateSearchPrevious`, `.endSearch`) all share
  /// the same target-resolution pattern via `actionTargetContext`. Pinning
  /// `.startSearch` is sufficient to lock in the contract for the family;
  /// `.navigateSearchNext` is tested separately to catch a regression where
  /// only `.startSearch` got migrated and the nav handlers were left on the
  /// old `selectedTerminalWorktree` path (resulting in a half-working search
  /// UX in canvas mode).
  @Test(.dependencies)
  func startSearchInCanvasTargetsFocusedWorktree() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(
          worktrees: [sidebar, focused], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.startSearch)
    await store.finish()

    #expect(sent.value == [.startSearch(focused)])
  }

  /// Pins the search-nav arm of the family. A future refactor that touches
  /// `.startSearch` without touching `.navigateSearchNext` would fail this
  /// test instead of silently shipping a half-broken search in canvas mode.
  @Test(.dependencies)
  func navigateSearchNextInCanvasTargetsFocusedWorktree() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(
          worktrees: [sidebar, focused], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.navigateSearchNext)
    await store.finish()

    #expect(sent.value == [.navigateSearchNext(focused)])
  }

  /// In multi-card canvas with no card focused, search handlers must no-op
  /// rather than fall back to sidebar (which has no worktree id in repo /
  /// overall canvas). Pins the no-focus → no-op invariant for the family.
  @Test(.dependencies)
  func startSearchInCanvasWithNoFocusReturnsNoneInsteadOfSidebarFallback() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktrees: [sidebar], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { nil }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.startSearch)
    await store.finish()

    #expect(sent.value.isEmpty)
  }

  // MARK: - Per-worktree canvas (scope is authoritative, no focus required)

  /// `.canvas(.worktree(id))` selection: the scope itself names the target
  /// worktree, so `.runScript` must dispatch even when `canvasFocusedWorktreeID`
  /// returns nil. The previous draft of the helper required focus for all
  /// canvas modes, breaking ⌘R/⌘O on the per-worktree canvas the moment the
  /// user opened the canvas without first clicking into a pane.
  @Test(.dependencies)
  func runScriptInPerWorktreeCanvasResolvesScopeIDWithoutCanvasFocus() async {
    let worktree = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let storage = SettingsTestStorage()
    let sent = LockIsolated<[TerminalClient.Command]>([])

    try? withDependencies({ $0.settingsFileStorage = storage.storage }) {
      @Shared(.repositorySettings(worktree.repositoryRootURL)) var settings
      $settings.withLock { $0.runScript = "make per-worktree-script" }
    }

    let state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [worktree],
        selection: .canvas(.worktree(worktree.id))
      ),
      settings: SettingsFeature.State()
    )

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { nil }
        $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
      }
    }

    await store.send(.runScript)
    await store.finish()

    #expect(sent.value == [.runScript(worktree, script: "make per-worktree-script")])
  }

  /// `.canvas(.worktree(id))` is authoritative even if `canvasFocusedWorktreeID`
  /// reports a *different* worktree (e.g. stale focus state from a prior repo
  /// canvas). The scope wins; the focus is ignored. Locks the per-worktree
  /// branch as the SSOT for its target id.
  @Test(.dependencies)
  func runScriptInPerWorktreeCanvasIgnoresMismatchedCanvasFocus() async {
    let scoped = makeWorktree(repoRoot: "/tmp/repo-scoped")
    let other = makeWorktree(repoRoot: "/tmp/repo-other")
    let storage = SettingsTestStorage()
    let sent = LockIsolated<[TerminalClient.Command]>([])

    try? withDependencies({ $0.settingsFileStorage = storage.storage }) {
      @Shared(.repositorySettings(scoped.repositoryRootURL)) var scopedSettings
      $scopedSettings.withLock { $0.runScript = "make scoped" }
      @Shared(.repositorySettings(other.repositoryRootURL)) var otherSettings
      $otherSettings.withLock { $0.runScript = "make other" }
    }

    let state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [scoped, other],
        selection: .canvas(.worktree(scoped.id))
      ),
      settings: SettingsFeature.State()
    )

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { other.id }
        $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
      }
    }

    await store.send(.runScript)
    await store.finish()

    #expect(sent.value == [.runScript(scoped, script: "make scoped")])
  }

  // MARK: - Rank 6 (sidebar wins when canvas not showing)

  /// `isShowingCanvas == false` and a stale `canvasFocusedWorktreeID()`
  /// non-nil value: sidebar wins. Locks down the order of `isShowingCanvas`
  /// vs `canvasFocusedWorktreeID()` checks in the helper.
  @Test(.dependencies)
  func runScriptOutsideCanvasIgnoresStaleCanvasFocusAndUsesSidebar() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let staleCanvas = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let sent = LockIsolated<[TerminalClient.Command]>([])

    var state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [sidebar, staleCanvas],
        selection: .worktree(sidebar.id)
      ),
      settings: SettingsFeature.State()
    )
    state.selectedRunScript = "make sidebar-script"

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.canvasFocusedWorktreeID = { staleCanvas.id }
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.runScript)
    await store.finish()

    #expect(sent.value == [.runScript(sidebar, script: "make sidebar-script")])
  }

  // MARK: - Broadcast custom command (runCustomCommandOnWorktrees)

  /// Broadcast mode must fan the command out to EVERY target worktree, not just
  /// the first. The handler re-implements the single-target switch inside a
  /// `for worktree in worktrees` loop, so a regression (broadcasting to one, or
  /// reversing order) would otherwise ship silently.
  @Test(.dependencies)
  func runCustomCommandOnWorktreesBroadcastsToEveryTarget() async {
    let wtA = makeWorktree(repoRoot: "/tmp/repo-a")
    let wtB = makeWorktree(repoRoot: "/tmp/repo-b")
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let command = UserCustomCommand(
      title: "Build",
      systemImage: "hammer",
      command: "make build",
      execution: .shellScript,
      shortcut: nil
    )

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktrees: [wtA, wtB], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.runCustomCommandOnWorktrees(command, [wtA.id, wtB.id]))
    await store.finish()

    let targetIDs = sent.value.compactMap { cmd -> Worktree.ID? in
      if case .createTabWithInput(
        let worktree, input: _, runSetupScriptIfNew: _, autoCloseOnSuccess: _,
        customCommandName: _, customCommandIcon: _) = cmd
      {
        return worktree.id
      }
      return nil
    }
    #expect(Set(targetIDs) == [wtA.id, wtB.id])
    #expect(targetIDs.count == 2)
  }

  /// All target IDs resolving away (e.g. cards pruned between selection and
  /// dispatch) → no commands sent, no crash.
  @Test(.dependencies)
  func runCustomCommandOnWorktreesNoOpsWhenNoTargetsResolve() async {
    let wt = makeWorktree(repoRoot: "/tmp/repo-a")
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let command = UserCustomCommand(
      title: "Build",
      systemImage: "hammer",
      command: "make build",
      execution: .shellScript,
      shortcut: nil
    )

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktrees: [wt], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.runCustomCommandOnWorktrees(command, ["/tmp/repo-vanished/wt-x"]))
    await store.finish()
    #expect(sent.value.isEmpty)
  }

  /// A command with an empty body is not runnable → broadcast is a no-op.
  @Test(.dependencies)
  func runCustomCommandOnWorktreesNoOpsForNonRunnableCommand() async {
    let wt = makeWorktree(repoRoot: "/tmp/repo-a")
    let sent = LockIsolated<[TerminalClient.Command]>([])
    let blank = UserCustomCommand(
      title: "Blank",
      systemImage: "terminal",
      command: "   ",
      execution: .shellScript,
      shortcut: nil
    )

    let store = TestStore(
      initialState: AppFeature.State(
        repositories: makeRepositoriesState(worktrees: [wt], selection: .canvas(.overall)),
        settings: SettingsFeature.State()
      )
    ) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
    }

    await store.send(.runCustomCommandOnWorktrees(blank, [wt.id]))
    await store.finish()
    #expect(sent.value.isEmpty)
  }

  // MARK: - Save Run Script in multi-card canvas (regression)

  /// Regression for the multi-card-canvas silent-discard bug: in
  /// `.canvas(.overall)`/`.canvas(.repository)` there is no
  /// `selectedTerminalWorktree`, so `.saveRunScriptAndRun` must resolve its
  /// target via `actionTargetContext` (the canvas-focused card). Previously it
  /// guarded on `selectedTerminalWorktree` (nil here) and silently dropped the
  /// typed script. This pins that it saves to the focused repo and runs it.
  @Test(.dependencies)
  func saveRunScriptAndRunResolvesFocusedWorktreeInMultiCardCanvas() async {
    let sidebar = makeWorktree(repoRoot: "/tmp/repo-sidebar")
    let focused = makeWorktree(repoRoot: "/tmp/repo-canvas")
    let storage = SettingsTestStorage()
    let sent = LockIsolated<[TerminalClient.Command]>([])

    var state = AppFeature.State(
      repositories: makeRepositoriesState(
        worktrees: [sidebar, focused], selection: .canvas(.overall)),
      settings: SettingsFeature.State()
    )
    state.runScriptDraft = "make canvas"

    let store = withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      TestStore(initialState: state) {
        AppFeature()
      } withDependencies: {
        $0.terminalClient.canvasFocusedWorktreeID = { focused.id }
        $0.terminalClient.send = { command in sent.withValue { $0.append(command) } }
      }
    }
    store.exhaustivity = .off

    await store.send(.saveRunScriptAndRun)
    await store.finish()

    // Persisted to the focused (canvas) repo, then ran it there — NOT silently dropped.
    #expect(sent.value == [.runScript(focused, script: "make canvas")])
    withDependencies {
      $0.settingsFileStorage = storage.storage
    } operation: {
      @Shared(.repositorySettings(focused.repositoryRootURL)) var focusedSettings
      #expect(focusedSettings.runScript == "make canvas")
    }
  }
}

// MARK: - Helpers

private func makeWorktree(
  repoRoot: String,
  name: String = "wt-1"
) -> Worktree {
  let id = "\(repoRoot)/\(name)"
  return Worktree(
    id: id,
    name: name,
    detail: "detail",
    workingDirectory: URL(fileURLWithPath: id),
    repositoryRootURL: URL(fileURLWithPath: repoRoot)
  )
}

private func makeRepositoriesState(
  worktrees: [Worktree],
  selection: SidebarSelection
) -> RepositoriesFeature.State {
  // One repository per distinct repositoryRootURL, owning its worktrees.
  let grouped = Dictionary(grouping: worktrees, by: { $0.repositoryRootURL })
  let repositories = grouped.map { rootURL, worktrees in
    Repository(
      id: rootURL.path(percentEncoded: false),
      rootURL: rootURL,
      name: rootURL.lastPathComponent,
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
  }
  var state = RepositoriesFeature.State()
  state.repositories = IdentifiedArray(uniqueElements: repositories)
  state.selection = selection
  return state
}

private func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
  let directory = FileManager.default.temporaryDirectory.appending(
    path: "AppFeatureActionTargetContextTests-\(UUID().uuidString)",
    directoryHint: .isDirectory
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try body(directory)
}
