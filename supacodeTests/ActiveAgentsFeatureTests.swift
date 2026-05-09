import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
struct ActiveAgentsFeatureTests {
  @Test func entriesAreSortedByStateThenRecency() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    let old = Date(timeIntervalSince1970: 10)
    let new = Date(timeIntervalSince1970: 20)
    let idle = entry(id: UUID(0), state: .idle, changedAt: new)
    let blocked = entry(id: UUID(1), state: .blocked, changedAt: old)
    let working = entry(id: UUID(2), state: .working, changedAt: new)
    let done = entry(id: UUID(3), state: .done, changedAt: new)

    await store.send(.agentEntryChanged(idle)) {
      $0.entries = [idle]
    }
    await store.send(.agentEntryChanged(blocked)) {
      $0.entries = [blocked, idle]
    }
    await store.send(.agentEntryChanged(working)) {
      $0.entries = [blocked, working, idle]
    }
    await store.send(.agentEntryChanged(done)) {
      $0.entries = [blocked, working, done, idle]
    }
  }

  @Test func panelHeightIsClamped() async {
    let store = TestStore(initialState: ActiveAgentsFeature.State()) {
      ActiveAgentsFeature()
    }

    await store.send(.panelHeightChanged(20)) {
      $0.$panelHeight.withLock { $0 = 120 }
    }
    await store.send(.panelHeightChanged(900)) {
      $0.$panelHeight.withLock { $0 = 420 }
    }
  }

  private func entry(id: UUID, state: AgentDisplayState, changedAt: Date) -> ActiveAgentEntry {
    ActiveAgentEntry(
      id: id,
      worktreeID: "/repo/wt",
      worktreeName: "wt",
      tabID: TerminalTabID(rawValue: UUID()),
      tabTitle: "1",
      surfaceID: id,
      paneIndex: 1,
      agent: .codex,
      rawState: state == .blocked ? .blocked : state == .working ? .working : .idle,
      displayState: state,
      lastChangedAt: changedAt
    )
  }
}

extension UUID {
  fileprivate init(_ value: UInt8) {
    self.init(uuid: (value, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  }
}
