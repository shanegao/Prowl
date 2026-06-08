import ComposableArchitecture
import Foundation

/// Quick-send composer: pick an active agent and fire a (multi-line) message into
/// its terminal pane without leaving the keyboard. Presented in a non-activating
/// panel (see `QuickSendPanelManager`) so it can pop over from the menubar without
/// bringing the main window forward.
///
/// Dismissal (cancel + post-submit) is delegated to the parent (`AppFeature`),
/// which owns the panel's lifecycle; text delivery is a `delegate(.send)` the
/// parent fulfils, because resolving the `Worktree` + calling `terminalClient`
/// lives there.
@Reducer
struct QuickSendFeature {
  @ObservableState
  struct State: Equatable {
    /// Active agents offered as targets, snapshotted when the panel opens.
    var agents: IdentifiedArrayOf<ActiveAgentEntry>
    /// Per-agent repo/branch labels for rendering rows, resolved by the parent
    /// from the same SSOT the sidebar and menubar use. Keyed by agent id.
    var displays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay]
    /// The currently selected target agent.
    var selectedAgentID: ActiveAgentEntry.ID?
    /// The message being composed. Multi-line; internal newlines are preserved.
    var draft: String = ""

    /// - Parameter selectedAgentID: the preferred default selection (the agent
    ///   whose menubar row opened the panel, or the active agent for the
    ///   shortcut). Falls back to the first agent when absent/stale.
    init(
      agents: IdentifiedArrayOf<ActiveAgentEntry>,
      displays: [ActiveAgentEntry.ID: ActiveAgentRowDisplay] = [:],
      selectedAgentID: ActiveAgentEntry.ID? = nil
    ) {
      self.agents = agents
      self.displays = displays
      self.selectedAgentID =
        selectedAgentID.flatMap { agents[id: $0] != nil ? $0 : nil } ?? agents.first?.id
    }

    var selectedAgent: ActiveAgentEntry? {
      selectedAgentID.flatMap { agents[id: $0] }
    }

    /// Repo color of the currently selected target, resolved from the same
    /// display data the rows render. Drives the panel's background identity
    /// wash; `nil` (no tint) when there's no selection or the repo has no
    /// assigned color. Derived (not stored) so it stays in lock-step with the
    /// selection — switching the target agent re-resolves it for free.
    var selectedRepositoryColor: RepositoryColorChoice? {
      selectedAgentID.flatMap { displays[$0]?.color }
    }

    /// Send is enabled only with a live target and non-blank text.
    var canSend: Bool {
      selectedAgent != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case selectAgent(ActiveAgentEntry.ID)
    case submit
    case cancel
    case openInProwl
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    /// Deliver `text` to `agent`'s pane. The parent resolves the worktree and
    /// routes through `terminalClient.sendTextToSurface(...)` (surfacing a toast
    /// if the pane is gone), then closes the panel.
    case send(agent: ActiveAgentEntry, text: String)
    /// User dismissed without sending; the parent closes the panel.
    case cancelled
    /// User asked to jump to `agent` in the main app; the parent focuses its
    /// pane, surfaces the main window, and closes the panel.
    case focusAgent(ActiveAgentEntry)
  }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .selectAgent(let id):
        guard state.agents[id: id] != nil else { return .none }
        state.selectedAgentID = id
        return .none

      case .submit:
        guard let agent = state.selectedAgent else { return .none }
        let text = state.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .none }
        return .send(.delegate(.send(agent: agent, text: text)))

      case .cancel:
        return .send(.delegate(.cancelled))

      case .openInProwl:
        guard let agent = state.selectedAgent else { return .none }
        return .send(.delegate(.focusAgent(agent)))

      case .delegate:
        return .none
      }
    }
  }
}
