import Foundation
import Testing

@testable import supacode

struct CanvasSelectionStateTests {
  private let tab1 = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
  private let tab2 = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
  private let tab3 = TerminalTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)

  @Test func focusSingleSetsPrimaryAndClearsSelectionMode() {
    var state = CanvasSelectionState()

    state.focusSingle(tab1)

    #expect(state.mode == .idle)
    #expect(state.primaryTabID == tab1)
    #expect(state.selectedTabIDs == [tab1])
    #expect(state.selectionOrder == [tab1])
  }

  @Test func toggleSelectionEntersSelectionModeAndAppendsOrder() {
    var state = CanvasSelectionState()

    state.toggleSelection(tab1)
    state.toggleSelection(tab2)

    #expect(state.mode == .selecting)
    #expect(state.primaryTabID == tab2)
    #expect(state.selectedTabIDs == [tab1, tab2])
    #expect(state.selectionOrder == [tab1, tab2])
  }

  @Test func togglingSelectedPrimaryPromotesPreviousSelection() {
    var state = CanvasSelectionState()
    state.toggleSelection(tab1)
    state.toggleSelection(tab2)
    state.toggleSelection(tab3)

    state.toggleSelection(tab3)

    #expect(state.mode == .selecting)
    #expect(state.primaryTabID == tab2)
    #expect(state.selectedTabIDs == [tab1, tab2])
    #expect(state.selectionOrder == [tab1, tab2])
  }

  @Test func togglingLastSelectedCardClearsState() {
    var state = CanvasSelectionState()
    state.toggleSelection(tab1)

    state.toggleSelection(tab1)

    #expect(state.mode == .idle)
    #expect(state.primaryTabID == nil)
    #expect(state.selectedTabIDs.isEmpty)
    #expect(state.selectionOrder.isEmpty)
  }

  @Test func broadcastInteractionLeavesSelectionSetButExitsSelectionMode() {
    var state = CanvasSelectionState()
    state.toggleSelection(tab1)
    state.toggleSelection(tab2)

    state.beginBroadcastInteractionIfNeeded()

    #expect(state.mode == .idle)
    #expect(state.primaryTabID == tab2)
    #expect(state.selectedTabIDs == [tab1, tab2])
  }

  @Test func pruneDropsMissingTabsAndPreservesNewestVisiblePrimary() {
    var state = CanvasSelectionState()
    state.toggleSelection(tab1)
    state.toggleSelection(tab2)
    state.toggleSelection(tab3)

    state.prune(to: [tab1, tab2])

    #expect(state.primaryTabID == tab2)
    #expect(state.selectedTabIDs == [tab1, tab2])
    #expect(state.selectionOrder == [tab1, tab2])
  }
}
