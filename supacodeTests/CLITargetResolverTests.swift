import Foundation
import GhosttyKit
import Testing

@testable import supacode

@MainActor
struct CLITargetResolverTests {
  @Test func explicitTabAndPaneSelectorsAcceptUUIDsAndShortHandles() throws {
    let tabID = UUID()
    let firstPaneID = UUID()
    let focusedPaneID = UUID()
    let snapshot = makeSnapshot(
      worktreeID: "worktree",
      worktreeName: "main",
      tab: (id: tabID, handle: 4),
      panes: [(id: firstPaneID, handle: 5), (id: focusedPaneID, handle: 6)],
      focusedPaneID: focusedPaneID
    )
    let resolver = TargetResolver { snapshot }

    for selector in [tabID.uuidString, "4", "t4"] {
      let target = try resolvedTarget(from: resolver.resolve(.tab(selector)))
      #expect(target.tabID == tabID)
      #expect(target.paneID == focusedPaneID)
    }

    for selector in [firstPaneID.uuidString, "5", "p5"] {
      let target = try resolvedTarget(from: resolver.resolve(.pane(selector)))
      #expect(target.paneID == firstPaneID)
    }
  }

  @Test func autoSelectorKeepsNumericValuesForWorktrees() throws {
    let paneSnapshot = makeSnapshot(
      worktreeID: "pane-worktree",
      worktreeName: "other",
      tab: (id: UUID(), handle: 1),
      panes: [(id: UUID(), handle: 3)],
      focusedPaneID: nil
    )
    let numericWorktreeSnapshot = makeSnapshot(
      worktreeID: "numeric-worktree",
      worktreeName: "3",
      tab: (id: UUID(), handle: 4),
      panes: [(id: UUID(), handle: 5)],
      focusedPaneID: nil
    )
    let resolver = TargetResolver {
      TargetResolutionSnapshot(
        worktrees: [paneSnapshot.worktrees[0], numericWorktreeSnapshot.worktrees[0]],
        focusedWorktreeID: nil
      )
    }

    let numericTarget = try resolvedTarget(from: resolver.resolve(.auto("3")))
    #expect(numericTarget.worktreeID == "numeric-worktree")

    if case .failure(.notFound) = resolver.resolve(.auto("p3")) {
      // Expected: short handles are explicit-selector-only.
    } else {
      Issue.record("--target must not resolve a short pane handle")
    }
  }

  private func makeSnapshot(
    worktreeID: String,
    worktreeName: String,
    tab tabInfo: (id: UUID, handle: Int),
    panes: [(id: UUID, handle: Int)],
    focusedPaneID: UUID?
  ) -> TargetResolutionSnapshot {
    let runtime = GhosttyRuntime()
    let surfaceView = GhosttySurfaceView(
      runtime: runtime,
      workingDirectory: nil,
      context: GHOSTTY_SURFACE_CONTEXT_TAB,
      skipsSurfaceCreationForTesting: true
    )
    let targetPanes = panes.map { pane in
      TargetResolutionSnapshot.Pane(
        id: pane.id,
        handle: pane.handle,
        title: "shell",
        cwd: "/tmp/\(worktreeID)",
        isFocusedInTab: pane.id == focusedPaneID,
        surfaceView: surfaceView
      )
    }
    let tab = TargetResolutionSnapshot.Tab(
      id: tabInfo.id,
      handle: tabInfo.handle,
      title: "Tab",
      selected: true,
      panes: targetPanes,
      focusedPaneID: focusedPaneID
    )
    return TargetResolutionSnapshot(
      worktrees: [
        .init(
          id: worktreeID,
          name: worktreeName,
          path: "/tmp/\(worktreeID)",
          rootPath: "/tmp/\(worktreeID)",
          kind: .git,
          tabs: [tab]
        )
      ],
      focusedWorktreeID: worktreeID
    )
  }

  private func resolvedTarget(
    from result: Result<ResolvedTarget, TargetResolverError>
  ) throws -> ResolvedTarget {
    switch result {
    case .success(let target):
      return target
    case .failure(let error):
      Issue.record("Unexpected resolution failure: \(error)")
      throw error
    }
  }
}
