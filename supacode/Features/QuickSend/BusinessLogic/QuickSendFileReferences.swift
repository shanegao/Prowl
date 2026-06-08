import Foundation

nonisolated struct QuickSendFileReference: Equatable, Sendable {
  let relativePath: String
  /// Whether `relativePath` names a directory rather than a regular file. Drives
  /// the completion popup's icon and whether the inserted token gets a trailing `/`.
  let isDirectory: Bool

  init(relativePath: String, isDirectory: Bool = false) {
    self.relativePath = relativePath
    self.isDirectory = isDirectory
  }

  var fileName: String {
    (relativePath as NSString).lastPathComponent
  }

  var parentPath: String? {
    let parent = (relativePath as NSString).deletingLastPathComponent
    return parent == "." ? nil : parent
  }
}

/// Indexes regular files and directories under a quick-send agent's resolved
/// root so `@` completion can insert paths (relative to that root) for either.
/// `nonisolated` so the filesystem scan can run off the main actor (callers use
/// `Task.detached`); it touches only its arguments and `FileManager`, never
/// main-actor state.
nonisolated enum QuickSendFileReferences {
  private enum Constants {
    /// Upper bound for one autocomplete index pass (files + directories combined).
    /// It keeps very large repos from spending unbounded time in the panel while
    /// still covering normal app repos.
    static let maximumIndexedEntries = 8_000
    /// Generated/dependency folders skipped by the fallback filesystem scanner.
    /// These names come from common macOS, Swift, Node, Rust, and build-tool outputs.
    static let ignoredDirectoryNames: Set<String> = [
      "Carthage",
      "DerivedData",
      "Pods",
      "build",
      "dist",
      "node_modules",
      "target",
    ]
    /// Candidate cap before the popup applies its visible-row cap; enough for
    /// keyboard refinement without carrying the whole file index through SwiftUI.
    static let maximumRankedMatches = 50
    /// File-reference ranking buckets. File-name matches beat parent/path matches
    /// because `@` completion is normally driven by the file name the user remembers.
    static let exactFileNameScore = 400
    static let fileNamePrefixScore = 300
    static let fileNameContainsScore = 200
    static let relativePathPrefixScore = 150
    static let relativePathContainsScore = 100
  }

  /// Root used for `@` completion: nearest enclosing git root, then the owning
  /// worktree/plain-folder root when it contains the cwd, then the cwd itself.
  static func rootDirectory(workingDirectory: URL?, fallbackWorktreePath: String?) -> URL? {
    let fallbackRoot = fallbackWorktreePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    guard let workingDirectory else { return fallbackRoot }
    if let gitRoot = gitRoot(containing: workingDirectory) {
      return gitRoot
    }
    if let fallbackRoot, PathPolicy.contains(workingDirectory, in: fallbackRoot) {
      return fallbackRoot
    }
    return workingDirectory
  }

  static func references(in root: URL, fileManager: FileManager = .default) -> [QuickSendFileReference] {
    let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else {
      return []
    }

    var references: [QuickSendFileReference] = []
    for case let url as URL in enumerator {
      guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { continue }
      if values.isDirectory == true {
        // Generated/dependency folders are neither offered as candidates nor
        // descended into; every other directory is itself a reference.
        if Constants.ignoredDirectoryNames.contains(url.lastPathComponent) {
          enumerator.skipDescendants()
          continue
        }
        guard let relativePath = relativePath(from: root, to: url) else { continue }
        references.append(QuickSendFileReference(relativePath: relativePath, isDirectory: true))
      } else {
        guard values.isRegularFile == true, let relativePath = relativePath(from: root, to: url) else {
          continue
        }
        references.append(QuickSendFileReference(relativePath: relativePath, isDirectory: false))
      }
      if references.count >= Constants.maximumIndexedEntries {
        break
      }
    }
    return references.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
  }

  static func rankedMatches(
    in references: [QuickSendFileReference],
    query: String,
    limit: Int = Constants.maximumRankedMatches
  ) -> [QuickSendFileReference] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedQuery.isEmpty else {
      return Array(references.prefix(limit))
    }

    let scored = references.compactMap { reference -> (reference: QuickSendFileReference, score: Int)? in
      guard let score = matchScore(for: reference, query: normalizedQuery) else { return nil }
      return (reference, score)
    }
    return Array(
      scored
        .sorted { left, right in
          if left.score != right.score {
            return left.score > right.score
          }
          if left.reference.relativePath.count != right.reference.relativePath.count {
            return left.reference.relativePath.count < right.reference.relativePath.count
          }
          return left.reference.relativePath.localizedStandardCompare(right.reference.relativePath) == .orderedAscending
        }
        .prefix(limit)
        .map(\.reference)
    )
  }

  private static func matchScore(for reference: QuickSendFileReference, query: String) -> Int? {
    let fileName = reference.fileName.lowercased()
    let relativePath = reference.relativePath.lowercased()
    if fileName == query { return Constants.exactFileNameScore }
    if fileName.hasPrefix(query) { return Constants.fileNamePrefixScore }
    if fileName.contains(query) { return Constants.fileNameContainsScore }
    if relativePath.hasPrefix(query) { return Constants.relativePathPrefixScore }
    if relativePath.contains(query) { return Constants.relativePathContainsScore }
    return nil
  }

  private static func gitRoot(containing directory: URL, fileManager: FileManager = .default) -> URL? {
    var current = directory.standardizedFileURL
    while true {
      let gitURL = current.appending(path: ".git")
      if fileManager.fileExists(atPath: gitURL.path(percentEncoded: false)) {
        return current
      }
      let parent = current.deletingLastPathComponent()
      guard parent != current else { return nil }
      current = parent
    }
  }

  private static func relativePath(from root: URL, to file: URL) -> String? {
    let rootPath = root.standardizedFileURL.path(percentEncoded: false)
    let filePath = file.standardizedFileURL.path(percentEncoded: false)
    let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard filePath.hasPrefix(prefix) else { return nil }
    let relativePath = String(filePath.dropFirst(prefix.count))
    return relativePath.isEmpty ? nil : relativePath
  }
}
