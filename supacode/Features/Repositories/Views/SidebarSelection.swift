enum SidebarSelection: Hashable {
  case worktree(Worktree.ID)
  case archivedWorktrees
  case repository(Repository.ID)
  case canvasOverall
  case canvasForWorktree(Worktree.ID)

  var worktreeID: Worktree.ID? {
    switch self {
    case .worktree(let id), .canvasForWorktree(let id):
      return id
    case .archivedWorktrees, .repository, .canvasOverall:
      return nil
    }
  }
}
