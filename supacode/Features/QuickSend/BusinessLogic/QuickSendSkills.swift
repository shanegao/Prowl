import Foundation

/// Resolves the directories whose skill folders are offered as `/`-completions in
/// the quick-send composer, and lists the skill names inside them.
///
/// Resolution order: an explicit user-configured directory (the
/// `directorySettingKey` app-storage value) wins; otherwise the selected agent's
/// conventional locations — both the global `~/.<agent>/skills` and the
/// project-local `<workingDirectory>/.<agent>/skills` (the agent's worktree) — so
/// per-project skills show alongside the global ones. Empty when nothing resolves
/// (e.g. no agent + no setting), in which case there are no completions.
// `nonisolated` so `skillNames(inAny:)` can run off the main actor (the composer
// lists skills in a `Task.detached`); members touch only arguments + `FileManager`.
nonisolated enum QuickSendSkills {
  /// App-storage key for the user-configured skills directory (empty → per-agent
  /// global + project-local defaults). Shared by the composer and the settings field.
  static let directorySettingKey = "quickSendSkillsDirectory"

  /// Directories to read skill names from for `agent`: a non-empty `configured`
  /// override wins (a single directory); otherwise the agent's global
  /// (`~/.<agent>/skills`) and project-local (`<workingDirectory>/.<agent>/skills`)
  /// locations. Pure (path-only) so it's unit-testable.
  static func directories(for agent: DetectedAgent?, configured: String, workingDirectory: URL?)
    -> [URL]
  {
    let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      return [URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)]
    }
    guard let agent else { return [] }
    // Each agent keeps its skills under a dotfolder named for the agent (the user's
    // claude/codex convention): globally under home, and per-project under the
    // worktree the agent runs in.
    let relativePath = ".\(agent.rawValue)/skills"
    var directories = [
      FileManager.default.homeDirectoryForCurrentUser
        .appending(path: relativePath, directoryHint: .isDirectory)
    ]
    if let workingDirectory {
      directories.append(
        workingDirectory.appending(path: relativePath, directoryHint: .isDirectory))
    }
    return directories
  }

  /// Immediate subdirectory names of `directory`, sorted; empty when the directory is
  /// missing or unreadable. A view-layer filesystem read backing the autocomplete
  /// affordance — not business logic, so it stays a plain helper rather than a client.
  static func skillNames(in directory: URL) -> [String] {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }
    return
      entries
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
      .map(\.lastPathComponent)
      .sorted()
  }

  /// Skill names across all of `directories`, de-duplicated (a skill present both
  /// project-locally and globally appears once) and sorted.
  static func skillNames(inAny directories: [URL]) -> [String] {
    var seen = Set<String>()
    var names: [String] = []
    for directory in directories {
      for name in skillNames(in: directory) where seen.insert(name).inserted {
        names.append(name)
      }
    }
    return names.sorted()
  }
}
