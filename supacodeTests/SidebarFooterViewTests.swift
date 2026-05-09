import Testing

@testable import supacode

struct SidebarFooterViewTests {
  @Test func activeAgentsPanelToggleUsesStableSymbols() {
    #expect(SidebarFooterView.activeAgentsPanelIconName(isPanelHidden: true) == "eye")
    #expect(SidebarFooterView.activeAgentsPanelIconName(isPanelHidden: false) == "eye.slash")
  }
}
