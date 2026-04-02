// supacode/CLIService/TargetResolver.swift
// Resolves target selectors against current app state.
// Scaffold — actual resolution depends on wiring to WorktreeTerminalManager.

import Foundation

@MainActor
final class TargetResolver {
  /// Resolve a target selector to concrete worktree/tab/pane IDs.
  /// Returns nil if the target cannot be found.
  func resolve(_ selector: TargetSelector) -> ResolvedTarget? {
    // TODO: Wire to WorktreeTerminalManager to resolve against live state.
    // For now, return nil (target not found) for any non-none selector.
    switch selector {
    case .none:
      // Return current focused target
      return nil // TODO: implement
    case .worktree, .tab, .pane:
      return nil // TODO: implement
    }
  }
}

/// Placeholder for resolved target information.
/// Will be populated with actual worktree/tab/pane data when wired.
struct ResolvedTarget {
  let worktreeID: String
  let tabID: String
  let paneID: String
}
