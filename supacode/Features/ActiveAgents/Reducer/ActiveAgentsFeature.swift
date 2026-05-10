import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Sharing

@Reducer
struct ActiveAgentsFeature {
  static let minimumPanelHeight = 120.0
  static let maximumPanelHeight = 560.0
  static let reservedSidebarListHeight = 200.0

  @ObservableState
  struct State: Equatable {
    var entries: IdentifiedArrayOf<ActiveAgentEntry> = []
    @Shared(.appStorage("activeAgentsPanelHidden")) var isPanelHidden: Bool = false
    @Shared(.appStorage("activeAgentsPanelHeight")) var panelHeight: Double = 200
  }

  enum Action: Equatable {
    case agentEntryChanged(ActiveAgentEntry, autoShowPanel: Bool)
    case agentEntryRemoved(ActiveAgentEntry.ID)
    case entryTapped(ActiveAgentEntry.ID)
    case togglePanelVisibility
    case panelHeightChanged(Double)
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .agentEntryChanged(let entry, let autoShowPanel):
        state.entries[id: entry.id] = entry
        if autoShowPanel, state.isPanelHidden {
          state.$isPanelHidden.withLock { $0 = false }
        }
        return .none

      case .agentEntryRemoved(let id):
        state.entries.remove(id: id)
        return .none

      case .entryTapped:
        return .none

      case .togglePanelVisibility:
        state.$isPanelHidden.withLock { $0.toggle() }
        return .none

      case .panelHeightChanged(let height):
        state.$panelHeight.withLock { $0 = Self.clampedPanelHeight(height) }
        return .none
      }
    }
  }

  static func clampedPanelHeight(_ height: Double) -> Double {
    min(maximumPanelHeight, max(minimumPanelHeight, height))
  }

  static func maximumPanelHeight(forContainerHeight height: Double) -> Double {
    max(minimumPanelHeight, min(maximumPanelHeight, height - reservedSidebarListHeight))
  }

  static func detectionEnabled(isPanelHidden: Bool, autoShowPanel: Bool) -> Bool {
    !isPanelHidden || autoShowPanel
  }
}
