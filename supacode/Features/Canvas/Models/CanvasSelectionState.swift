import Foundation

struct CanvasSelectionState: Equatable {
  enum Mode: Equatable {
    case idle
    case selecting
  }

  private(set) var mode: Mode = .idle
  private(set) var selectedTabIDs: Set<TerminalTabID> = []
  private(set) var primaryTabID: TerminalTabID?
  private(set) var selectionOrder: [TerminalTabID] = []

  var isSelecting: Bool {
    mode == .selecting
  }

  var isBroadcasting: Bool {
    selectedTabIDs.count > 1
  }

  mutating func focusSingle(_ tabID: TerminalTabID) {
    mode = .idle
    selectedTabIDs = [tabID]
    primaryTabID = tabID
    selectionOrder = [tabID]
  }

  mutating func toggleSelection(_ tabID: TerminalTabID) {
    mode = .selecting
    if selectedTabIDs.contains(tabID) {
      selectedTabIDs.remove(tabID)
      selectionOrder.removeAll { $0 == tabID }
      if selectedTabIDs.isEmpty {
        mode = .idle
        primaryTabID = nil
        selectionOrder = []
      } else if primaryTabID == tabID {
        primaryTabID = selectionOrder.last ?? selectedTabIDs.first
      }
      return
    }

    selectedTabIDs.insert(tabID)
    selectionOrder.removeAll { $0 == tabID }
    selectionOrder.append(tabID)
    primaryTabID = tabID
  }

  mutating func beginBroadcastInteractionIfNeeded() {
    guard isSelecting, selectedTabIDs.count > 1 else { return }
    mode = .idle
  }

  mutating func clear() {
    mode = .idle
    selectedTabIDs = []
    primaryTabID = nil
    selectionOrder = []
  }

  mutating func prune(to visibleTabIDs: Set<TerminalTabID>) {
    selectedTabIDs.formIntersection(visibleTabIDs)
    selectionOrder.removeAll { !visibleTabIDs.contains($0) }
    if let primaryTabID, !visibleTabIDs.contains(primaryTabID) {
      self.primaryTabID = selectionOrder.last ?? selectedTabIDs.first
    }
    if selectedTabIDs.isEmpty {
      clear()
    }
  }
}
