import Foundation
import Testing

@testable import supacode

@MainActor
struct WorktreeTerminalStateViewedSurfaceTests {
  @Test func surfaceIsViewedWhenSelectedFocusedAndWindowActive() {
    let (state, surfaceId) = makeViewedState()

    #expect(state.isViewedSurface(surfaceId))
  }

  @Test func surfaceIsNotViewedWhenWindowStateIsUnknown() {
    let (state, surfaceId) = makeViewedState()
    state.lastWindowIsKey = nil
    state.lastWindowIsVisible = nil

    #expect(!state.isViewedSurface(surfaceId))
  }

  @Test func surfaceIsNotViewedWhenWindowIsNotKey() {
    let (state, surfaceId) = makeViewedState()
    state.lastWindowIsKey = false

    #expect(!state.isViewedSurface(surfaceId))
  }

  @Test func surfaceIsNotViewedWhenCanvasManaged() {
    // Canvas mode tears down the normal-mode window observers, so the window
    // flags freeze at their pre-canvas values; a stale `true` must not mute
    // notifications while the app is in the background.
    let (state, surfaceId) = makeViewedState()
    state.isCanvasManaged = true

    #expect(!state.isViewedSurface(surfaceId))
  }

  @Test func differentSurfaceIsNotViewed() {
    let (state, _) = makeViewedState()

    #expect(!state.isViewedSurface(UUID()))
  }

  private func makeViewedState() -> (WorktreeTerminalState, UUID) {
    let state = WorktreeTerminalState(
      runtime: GhosttyRuntime(),
      worktree: Worktree(
        id: "/tmp/repo/wt-1",
        name: "wt-1",
        detail: "",
        workingDirectory: URL(fileURLWithPath: "/tmp/repo/wt-1"),
        repositoryRootURL: URL(fileURLWithPath: "/tmp/repo")
      )
    )
    let tabId = state.tabManager.createTab(title: "tab", icon: nil)
    state.tabManager.selectTab(tabId)
    let surfaceId = UUID()
    state.focusedSurfaceIdByTab[tabId] = surfaceId
    state.isSelected = { true }
    state.lastWindowIsKey = true
    state.lastWindowIsVisible = true
    return (state, surfaceId)
  }
}
