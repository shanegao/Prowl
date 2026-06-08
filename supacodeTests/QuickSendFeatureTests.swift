import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct QuickSendFeatureTests {
  @Test func defaultsToFirstAgentWhenNoSelection() {
    let agents = sampleAgents()
    let state = QuickSendFeature.State(agents: agents)
    #expect(state.selectedAgentID == agents.first?.id)
  }

  @Test func keepsRequestedSelection() {
    let state = QuickSendFeature.State(agents: sampleAgents(), selectedAgentID: UUID(2))
    #expect(state.selectedAgentID == UUID(2))
  }

  @Test func fallsBackToFirstWhenSelectionStale() {
    let agents = sampleAgents()
    let state = QuickSendFeature.State(agents: agents, selectedAgentID: UUID(99))
    #expect(state.selectedAgentID == agents.first?.id)
  }

  @Test func canSendRequiresTargetAndNonBlankText() {
    var state = QuickSendFeature.State(agents: sampleAgents(), selectedAgentID: UUID(0))
    #expect(!state.canSend)
    state.draft = "   \n "
    #expect(!state.canSend)
    state.draft = "hi"
    #expect(state.canSend)
  }

  @Test func selectAgentUpdatesSelection() async {
    let store = TestStore(initialState: QuickSendFeature.State(agents: sampleAgents(), selectedAgentID: UUID(0))) {
      QuickSendFeature()
    }
    await store.send(.selectAgent(UUID(2))) {
      $0.selectedAgentID = UUID(2)
    }
  }

  @Test func selectingUnknownAgentIsIgnored() async {
    let store = TestStore(initialState: QuickSendFeature.State(agents: sampleAgents(), selectedAgentID: UUID(0))) {
      QuickSendFeature()
    }
    await store.send(.selectAgent(UUID(99)))
  }

  @Test func submitEmitsSendDelegateWithTrimmedText() async {
    let agents = sampleAgents()
    var initial = QuickSendFeature.State(agents: agents, selectedAgentID: UUID(0))
    initial.draft = "  build the thing\nthen test  \n"
    let store = TestStore(initialState: initial) { QuickSendFeature() }
    let target = agents[id: UUID(0)]!

    await store.send(.submit)
    // Outer whitespace trimmed; the internal newline (multi-line prompt) is kept.
    await store.receive(.delegate(.send(agent: target, text: "build the thing\nthen test")))
  }

  @Test func submitWithBlankDraftDoesNothing() async {
    var initial = QuickSendFeature.State(agents: sampleAgents(), selectedAgentID: UUID(0))
    initial.draft = "   \n  "
    let store = TestStore(initialState: initial) { QuickSendFeature() }
    await store.send(.submit)
  }

  @Test func cancelEmitsCancelledDelegate() async {
    let store = TestStore(initialState: QuickSendFeature.State(agents: sampleAgents(), selectedAgentID: UUID(0))) {
      QuickSendFeature()
    }
    await store.send(.cancel)
    await store.receive(.delegate(.cancelled))
  }

  @Test func openInProwlEmitsFocusAgentDelegate() async {
    let agents = sampleAgents()
    let store = TestStore(initialState: QuickSendFeature.State(agents: agents, selectedAgentID: UUID(2))) {
      QuickSendFeature()
    }
    let target = agents[id: UUID(2)]!
    await store.send(.openInProwl)
    await store.receive(.delegate(.focusAgent(target)))
  }

  @Test func openInProwlWithoutAgentsDoesNothing() async {
    let store = TestStore(initialState: QuickSendFeature.State(agents: [])) {
      QuickSendFeature()
    }
    await store.send(.openInProwl)
  }

  @Test func selectedRepositoryColorTracksSelectedAgent() {
    let agents = sampleAgents()
    let displays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay] = [
      UUID(0): display(repo: "Alpha", branch: "main", color: .blue),
      UUID(2): display(repo: "Beta", branch: "dev", color: .green),
    ]
    var state = QuickSendFeature.State(agents: agents, displays: displays, selectedAgentID: UUID(0))
    #expect(state.selectedRepositoryColor == .blue)
    // Switching the target re-resolves the tint from the new agent's repo.
    state.selectedAgentID = UUID(2)
    #expect(state.selectedRepositoryColor == .green)
    // An agent without a display entry yields no tint.
    state.selectedAgentID = UUID(1)
    #expect(state.selectedRepositoryColor == nil)
  }

  // MARK: - Helpers

  private func sampleAgents() -> IdentifiedArrayOf<ActiveAgentEntry> {
    [
      entry(id: UUID(0), state: .working),
      entry(id: UUID(1), state: .idle),
      entry(id: UUID(2), state: .blocked),
    ]
  }

  private func display(repo: String, branch: String, color: RepositoryColorChoice?) -> ActiveAgentRowDisplay {
    ActiveAgentRowDisplay(repositoryName: repo, branchName: branch, color: color)
  }

  private func entry(id: UUID, state: AgentDisplayState) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: id,
      worktreeID: "/repo/wt",
      worktreeName: "wt",
      workingDirectory: nil,
      tabID: TerminalTabID(rawValue: UUID()),
      tabTitle: "1",
      surfaceID: id,
      paneIndex: 1,
      iconLookupToken: "codex",
      agent: .codex,
      rawState: state == .blocked ? .blocked : state == .working ? .working : .idle,
      displayState: state,
      lastChangedAt: Date(timeIntervalSince1970: 10)
    )
  }
}

extension UUID {
  fileprivate init(_ value: UInt8) {
    self.init(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  }
}
