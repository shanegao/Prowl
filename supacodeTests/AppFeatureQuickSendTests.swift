import AppKit
import ComposableArchitecture
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct AppFeatureQuickSendTests {
  // C2: a successful delivery forwards the text to the target surface (with a
  // trailing Return), then keeps the panel open with a cleared composer (so the
  // user can fire another message) and remembers the target for next time.
  @Test(.dependencies) func sendDeliversTextToTargetSurface() async {
    let worktree = makeWorktree(id: "/tmp/repo-qs/wt-1", name: "wt-1", repoRoot: "/tmp/repo-qs")
    let repository = makeRepository(id: "/tmp/repo-qs", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    var state = AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())
    let surfaceID = UUID()
    let agent = quickSendAgent(worktreeID: worktree.id, surfaceID: surfaceID)
    state.quickSend = QuickSendFeature.State(agents: [agent], selectedAgentID: agent.id)
    state.quickSend?.draft = "build it"

    let delivered = LockIsolated<[DeliveredText]>([])
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendTextToSurface = { targetWorktree, targetSurfaceID, text, trailingEnter in
        delivered.withValue {
          $0.append(
            DeliveredText(
              worktreeID: targetWorktree.id,
              surfaceID: targetSurfaceID,
              text: text,
              trailingEnter: trailingEnter
            )
          )
        }
        return true
      }
      $0.quickSendPanelClient.hide = {}
    }
    // `.off`: the success path also fires a `showToast` effect (like the failure
    // tests); drain received actions afterwards to apply the delivered-state changes.
    store.exhaustivity = .off

    await store.send(.quickSend(.delegate(.send(agent: agent, text: "build it"))))
    await store.finish()
    await store.skipReceivedActions()

    // Text forwarded to the surface with a trailing Return…
    #expect(
      delivered.value == [
        DeliveredText(worktreeID: worktree.id, surfaceID: surfaceID, text: "build it", trailingEnter: true)
      ]
    )
    // …and the panel stays open with a cleared composer + remembered target.
    #expect(store.state.quickSend != nil)
    #expect(store.state.quickSend?.draft == "")
    #expect(store.state.lastSelectedQuickSendAgentID == agent.id)
  }

  // C2: a failed delivery (the agent pane closed before send) surfaces a warning
  // toast instead of silently dropping the typed message.
  @Test(.dependencies) func sendSurfacesWarningToastWhenDeliveryFails() async {
    let worktree = makeWorktree(id: "/tmp/repo-qs/wt-1", name: "wt-1", repoRoot: "/tmp/repo-qs")
    let repository = makeRepository(id: "/tmp/repo-qs", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    var state = AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())
    let agent = quickSendAgent(worktreeID: worktree.id, surfaceID: UUID())
    state.quickSend = QuickSendFeature.State(agents: [agent], selectedAgentID: agent.id)

    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendTextToSurface = { _, _, _, _ in false }
      $0.quickSendPanelClient.hide = {}
    }
    store.exhaustivity = .off

    await store.send(.quickSend(.delegate(.send(agent: agent, text: "build it"))))
    await store.finish()
    // The composer stays open with the typed text so the user can retarget/retry
    // instead of losing what they wrote.
    #expect(store.state.quickSend != nil)
  }

  // C2: if the agent's worktree was archived/removed between composing and
  // submitting, the panel hides and a warning toast appears — and no delivery is
  // attempted against a stale surface.
  @Test(.dependencies) func sendSurfacesWarningToastWhenWorktreeMissing() async {
    var state = AppFeature.State(
      repositories: RepositoriesFeature.State(),
      settings: SettingsFeature.State()
    )
    let agent = quickSendAgent(worktreeID: "/tmp/repo-qs/gone", surfaceID: UUID())
    state.quickSend = QuickSendFeature.State(agents: [agent], selectedAgentID: agent.id)

    let attempted = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.terminalClient.sendTextToSurface = { _, _, _, _ in
        attempted.setValue(true)
        return true
      }
      $0.quickSendPanelClient.hide = {}
    }
    store.exhaustivity = .off

    await store.send(.quickSend(.delegate(.send(agent: agent, text: "build it"))))
    await store.finish()
    // No worktree to deliver into, so nothing is attempted — but the composer stays
    // open with the typed text rather than discarding it.
    #expect(attempted.value == false)
    #expect(store.state.quickSend != nil)
  }

  // ⌘⇧P toggles: when the panel is already up, the toggle dismisses it (clears the
  // composer state + hides the panel) instead of re-presenting.
  @Test(.dependencies) func toggleDismissesWhenAlreadyVisible() async {
    let agent = quickSendAgent(worktreeID: "/tmp/repo-qs/wt-1", surfaceID: UUID())
    var state = AppFeature.State(
      repositories: RepositoriesFeature.State(),
      settings: SettingsFeature.State()
    )
    state.quickSend = QuickSendFeature.State(agents: [agent], selectedAgentID: agent.id)

    let hidden = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.quickSendPanelClient.hide = { hidden.setValue(true) }
    }

    await store.send(.toggleQuickSend) {
      $0.lastSelectedQuickSendAgentID = agent.id
      $0.quickSend = nil
    }
    await store.finish()
    #expect(hidden.value == true)
  }

  // presentQuickSend with no active agents: there's nothing to target, so the
  // panel is not built and `show()` never fires (the shortcut becomes a no-op).
  @Test(.dependencies) func presentQuickSendDoesNothingWithoutActiveAgents() async {
    let state = AppFeature.State(
      repositories: RepositoriesFeature.State(),
      settings: SettingsFeature.State()
    )

    let shown = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.quickSendPanelClient.show = { shown.setValue(true) }
    }

    await store.send(.presentQuickSend(defaultAgentID: nil))
    await store.finish()
    #expect(store.state.quickSend == nil)
    #expect(shown.value == false)
  }

  // presentQuickSend with an explicit default: that agent is pre-selected and the
  // panel is shown.
  @Test(.dependencies) func presentQuickSendSelectsExplicitDefaultAgent() async {
    let worktree = makeWorktree(id: "/tmp/repo-qs/wt-1", name: "wt-1", repoRoot: "/tmp/repo-qs")
    let repository = makeRepository(id: "/tmp/repo-qs", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    let agentA = quickSendAgent(worktreeID: worktree.id, surfaceID: UUID())
    let agentB = quickSendAgent(worktreeID: worktree.id, surfaceID: UUID())
    repositoriesState.activeAgents.entries = [agentA, agentB]
    let state = AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())

    let shown = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.quickSendPanelClient.show = { shown.setValue(true) }
    }

    // Pick the second agent explicitly so we prove the default wins over both the
    // first-agent fallback in the State init and the focus/last-selected fallbacks.
    await store.send(.presentQuickSend(defaultAgentID: agentB.id)) {
      $0.quickSend = QuickSendFeature.State(
        agents: [agentA, agentB],
        displays: SidebarListView.activeAgentRowDisplays(
          entries: [agentA, agentB],
          repositories: [repository],
          metadata: SidebarListView.activeAgentWorktreeMetadata(
            repositories: [repository],
            customTitles: [:]
          )
        ),
        selectedAgentID: agentB.id
      )
    }
    await store.finish()
    #expect(store.state.quickSend?.selectedAgentID == agentB.id)
    #expect(shown.value == true)
  }

  // presentQuickSend with no explicit default but a remembered last-selected agent
  // that is still active: the last-selected agent wins over the first-agent fallback.
  @Test(.dependencies) func presentQuickSendFallsBackToLastSelectedAgent() async {
    let worktree = makeWorktree(id: "/tmp/repo-qs/wt-1", name: "wt-1", repoRoot: "/tmp/repo-qs")
    let repository = makeRepository(id: "/tmp/repo-qs", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    let agentA = quickSendAgent(worktreeID: worktree.id, surfaceID: UUID())
    let agentB = quickSendAgent(worktreeID: worktree.id, surfaceID: UUID())
    repositoriesState.activeAgents.entries = [agentA, agentB]
    var state = AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())
    // Last targeted the *second* agent — it must be re-selected, not agentA (first).
    state.lastSelectedQuickSendAgentID = agentB.id

    let shown = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.quickSendPanelClient.show = { shown.setValue(true) }
    }

    await store.send(.presentQuickSend(defaultAgentID: nil)) {
      $0.quickSend = QuickSendFeature.State(
        agents: [agentA, agentB],
        displays: SidebarListView.activeAgentRowDisplays(
          entries: [agentA, agentB],
          repositories: [repository],
          metadata: SidebarListView.activeAgentWorktreeMetadata(
            repositories: [repository],
            customTitles: [:]
          )
        ),
        selectedAgentID: agentB.id
      )
    }
    await store.finish()
    #expect(store.state.quickSend?.selectedAgentID == agentB.id)
    #expect(shown.value == true)
  }

  // presentQuickSend with no explicit default and a stale last-selected agent (not in
  // the active list): the focused surface decides the selection instead.
  @Test(.dependencies) func presentQuickSendFallsBackToFocusedAgent() async {
    let worktree = makeWorktree(id: "/tmp/repo-qs/wt-1", name: "wt-1", repoRoot: "/tmp/repo-qs")
    let repository = makeRepository(id: "/tmp/repo-qs", worktrees: [worktree])
    var repositoriesState = RepositoriesFeature.State()
    repositoriesState.repositories = [repository]
    let agentA = quickSendAgent(worktreeID: worktree.id, surfaceID: UUID())
    let agentB = quickSendAgent(worktreeID: worktree.id, surfaceID: UUID())
    repositoriesState.activeAgents.entries = [agentA, agentB]
    // Focus the *second* agent's surface so it (not agentA) is the resolved default.
    repositoriesState.activeAgents.focusedSurfaceID = agentB.surfaceID
    var state = AppFeature.State(repositories: repositoriesState, settings: SettingsFeature.State())
    // A last-selected id that is no longer active must be ignored.
    state.lastSelectedQuickSendAgentID = UUID()

    let shown = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.quickSendPanelClient.show = { shown.setValue(true) }
    }

    await store.send(.presentQuickSend(defaultAgentID: nil)) {
      $0.quickSend = QuickSendFeature.State(
        agents: [agentA, agentB],
        displays: SidebarListView.activeAgentRowDisplays(
          entries: [agentA, agentB],
          repositories: [repository],
          metadata: SidebarListView.activeAgentWorktreeMetadata(
            repositories: [repository],
            customTitles: [:]
          )
        ),
        selectedAgentID: agentB.id
      )
    }
    await store.finish()
    #expect(store.state.quickSend?.selectedAgentID == agentB.id)
    #expect(shown.value == true)
  }

  // Cancelling the panel remembers the target for next time, tears down the composer
  // state, and hides the panel.
  @Test(.dependencies) func cancelledRemembersTargetHidesAndClears() async {
    let agent = quickSendAgent(worktreeID: "/tmp/repo-qs/wt-1", surfaceID: UUID())
    var state = AppFeature.State(
      repositories: RepositoriesFeature.State(),
      settings: SettingsFeature.State()
    )
    state.quickSend = QuickSendFeature.State(agents: [agent], selectedAgentID: agent.id)

    let hidden = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.quickSendPanelClient.hide = { hidden.setValue(true) }
    }

    await store.send(.quickSend(.delegate(.cancelled))) {
      $0.lastSelectedQuickSendAgentID = agent.id
      $0.quickSend = nil
    }
    await store.finish()
    #expect(hidden.value == true)
  }

  // focusAgent jumps the user to the agent's pane: it remembers the target, tears down
  // the panel, hides it, and surfaces the main window. (The agent is intentionally left
  // out of `activeAgents.entries`, so the merged `entryTapped` effect short-circuits and
  // does not cascade into terminal focus work.)
  @Test(.dependencies) func focusAgentHidesPanelAndSurfacesMainWindow() async {
    let agent = quickSendAgent(worktreeID: "/tmp/repo-qs/wt-1", surfaceID: UUID())
    var state = AppFeature.State(
      repositories: RepositoriesFeature.State(),
      settings: SettingsFeature.State()
    )
    state.quickSend = QuickSendFeature.State(agents: [agent], selectedAgentID: agent.id)

    let hidden = LockIsolated(false)
    let surfaced = LockIsolated(false)
    let store = TestStore(initialState: state) {
      AppFeature()
    } withDependencies: {
      $0.quickSendPanelClient.hide = { hidden.setValue(true) }
      $0.appLifecycleClient.surfaceMainWindow = {
        surfaced.setValue(true)
        return true
      }
    }
    store.exhaustivity = .off

    await store.send(.quickSend(.delegate(.focusAgent(agent))))
    await store.finish()
    await store.skipReceivedActions()

    #expect(store.state.quickSend == nil)
    #expect(store.state.lastSelectedQuickSendAgentID == agent.id)
    #expect(hidden.value == true)
    #expect(surfaced.value == true)
  }

  // MARK: - Helpers

  private struct DeliveredText: Equatable {
    let worktreeID: Worktree.ID
    let surfaceID: UUID
    let text: String
    let trailingEnter: Bool
  }

  private func quickSendAgent(worktreeID: Worktree.ID, surfaceID: UUID) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: surfaceID,
      worktreeID: worktreeID,
      worktreeName: "wt-1",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      tabTitle: "1",
      surfaceID: surfaceID,
      paneIndex: 1,
      iconLookupToken: "codex",
      agent: .codex,
      rawState: .working,
      displayState: .working,
      lastChangedAt: Date(timeIntervalSince1970: 10)
    )
  }
}

private func makeWorktree(id: String, name: String, repoRoot: String = "/tmp/repo") -> Worktree {
  Worktree(
    id: id,
    name: name,
    detail: "detail",
    workingDirectory: URL(fileURLWithPath: id),
    repositoryRootURL: URL(fileURLWithPath: repoRoot)
  )
}

private func makeRepository(id: String, worktrees: [Worktree]) -> Repository {
  Repository(
    id: id,
    rootURL: URL(fileURLWithPath: id),
    name: "repo",
    worktrees: IdentifiedArray(uniqueElements: worktrees)
  )
}
