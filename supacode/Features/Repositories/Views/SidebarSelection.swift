enum CanvasScope: Hashable, Sendable {
  case overall
  case worktree(Worktree.ID)
  case repository(Repository.ID)
  /// Global canvas showing only tabs that currently have an active agent,
  /// across every worktree. Like `.overall` it isn't bound to a single
  /// worktree/repository — the visible set is derived at render time from
  /// `ActiveAgentsFeature.State.entries` (their `tabID`s).
  case activeAgents
}

enum SidebarSelection: Hashable, Sendable {
  case worktree(Worktree.ID)
  case archivedWorktrees
  case repository(Repository.ID)
  case canvas(CanvasScope)

  var worktreeID: Worktree.ID? {
    switch self {
    case .worktree(let id), .canvas(.worktree(let id)):
      return id
    case .archivedWorktrees, .repository, .canvas(.overall), .canvas(.repository),
      .canvas(.activeAgents):
      return nil
    }
  }

  /// Same-kind canvas rebind: returns `.canvas(.worktree(id))` only if `self`
  /// is already `.canvas(.worktree(_))`. Used by `selectWorktree` to suppress
  /// the canvas-exit branch when the user navigates between worktrees while
  /// in per-worktree canvas — the canvas stays open with the new worktree
  /// as its scope. Returns `nil` for any other selection so the regular
  /// selection path runs.
  func reboundCanvas(toWorktree id: Worktree.ID) -> SidebarSelection? {
    guard case .canvas(.worktree) = self else { return nil }
    return .canvas(.worktree(id))
  }

  /// Same-kind canvas rebind for repository scope. Used by `selectRepository`
  /// (and by `selectWorktree` when the tap targets a worktree in a different
  /// repo than the currently-scoped one).
  func reboundCanvas(toRepository id: Repository.ID) -> SidebarSelection? {
    guard case .canvas(.repository) = self else { return nil }
    return .canvas(.repository(id))
  }
}
