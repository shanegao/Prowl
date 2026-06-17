import Foundation

nonisolated struct HandoffTranscriptReference: Sendable, Equatable {
  let sessionID: String
  let transcriptPath: String
  let source: String
  let confidence: String
}

/// Resolves native agent transcripts at handoff time. It is intentionally
/// best-effort: failure falls back to the terminal excerpt path.
nonisolated struct HandoffTranscriptResolver {
  let homeDirectory: URL
  let fileManager: FileManager

  init(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    fileManager: FileManager = .default
  ) {
    self.homeDirectory = homeDirectory.standardizedFileURL
    self.fileManager = fileManager
  }

  func resolve(agent: String?, rootURL: URL) -> HandoffTranscriptReference? {
    guard let agent else { return nil }
    switch agent {
    case "claude":
      return resolveClaude(rootURL: rootURL)
    case "codex":
      return resolveCodex(rootURL: rootURL)
    default:
      return nil
    }
  }

  private func resolveClaude(rootURL: URL) -> HandoffTranscriptReference? {
    let projectDirectory =
      homeDirectory
      .appending(path: ".claude", directoryHint: .isDirectory)
      .appending(path: "projects", directoryHint: .isDirectory)
      .appending(path: Self.claudeProjectDirectoryName(for: rootURL), directoryHint: .isDirectory)
    let candidates = jsonlFiles(in: projectDirectory, recursive: false)
    guard
      let latest = latestTranscript(
        in: candidates,
        matchingRoot: nil,
        sessionIDReader: Self.claudeSessionID(in:)
      )
    else {
      return nil
    }
    return HandoffTranscriptReference(
      sessionID: latest.sessionID,
      transcriptPath: latest.url.path(percentEncoded: false),
      source: "claude-project-jsonl",
      confidence: "high"
    )
  }

  private func resolveCodex(rootURL: URL) -> HandoffTranscriptReference? {
    let sessionsDirectory =
      homeDirectory
      .appending(path: ".codex", directoryHint: .isDirectory)
      .appending(path: "sessions", directoryHint: .isDirectory)
    let rootPath = Self.normalizedPath(rootURL)
    let candidates = jsonlFiles(in: sessionsDirectory, recursive: true)
    guard
      let latest = latestTranscript(
        in: candidates,
        matchingRoot: rootPath,
        sessionIDReader: Self.codexSessionIDAndCWD(in:)
      )
    else {
      return nil
    }
    return HandoffTranscriptReference(
      sessionID: latest.sessionID,
      transcriptPath: latest.url.path(percentEncoded: false),
      source: "codex-rollout-jsonl",
      confidence: "high"
    )
  }

  private func jsonlFiles(in directory: URL, recursive: Bool) -> [URL] {
    guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
    if recursive {
      let keys: [URLResourceKey] = [.isRegularFileKey]
      guard
        let enumerator = fileManager.enumerator(
          at: directory,
          includingPropertiesForKeys: keys,
          options: [.skipsHiddenFiles]
        )
      else {
        return []
      }
      return enumerator.compactMap { item -> URL? in
        guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
        let values = try? url.resourceValues(forKeys: Set(keys))
        return values?.isRegularFile == false ? nil : url
      }
    }

    let urls =
      (try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
      )) ?? []
    return urls.filter { url in
      guard url.pathExtension == "jsonl" else { return false }
      let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
      return values?.isRegularFile != false
    }
  }

  private func latestTranscript(
    in urls: [URL],
    matchingRoot rootPath: String?,
    sessionIDReader: (URL) -> (sessionID: String, cwd: String?)?
  ) -> (url: URL, sessionID: String)? {
    urls
      .compactMap { url -> TranscriptCandidate? in
        guard let metadata = sessionIDReader(url) else { return nil }
        if let rootPath, metadata.cwd.map(Self.normalizedPath(_:)) != rootPath {
          return nil
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return TranscriptCandidate(
          url: url,
          sessionID: metadata.sessionID,
          modifiedAt: values?.contentModificationDate ?? .distantPast
        )
      }
      .sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
      .first
      .map { (url: $0.url, sessionID: $0.sessionID) }
  }

  private struct TranscriptCandidate {
    let url: URL
    let sessionID: String
    let modifiedAt: Date
  }

  private static func claudeSessionID(in url: URL) -> (sessionID: String, cwd: String?)? {
    guard let firstSessionLine = firstJSONObjectLine(in: url, matching: "\"sessionId\""),
      let sessionID = firstSessionLine["sessionId"] as? String,
      !sessionID.isEmpty
    else {
      return nil
    }
    let cwd = firstSessionLine["cwd"] as? String
    return (sessionID, cwd)
  }

  private static func codexSessionIDAndCWD(in url: URL) -> (sessionID: String, cwd: String?)? {
    guard let line = firstJSONObjectLine(in: url, matching: "\"session_meta\""),
      line["type"] as? String == "session_meta",
      let payload = line["payload"] as? [String: Any],
      let sessionID = payload["id"] as? String,
      !sessionID.isEmpty
    else {
      return nil
    }
    return (sessionID, payload["cwd"] as? String)
  }

  private static func firstJSONObjectLine(in url: URL, matching needle: String) -> [String: Any]? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }

    var buffer = Data()
    while true {
      let chunk = try? handle.read(upToCount: 16 * 1024)
      guard let chunk, !chunk.isEmpty else {
        return parseJSONObjectLine(buffer)
      }
      buffer.append(chunk)
      while let newline = buffer.firstIndex(of: 0x0A) {
        let lineData = buffer[..<newline]
        buffer.removeSubrange(...newline)
        guard let line = String(data: lineData, encoding: .utf8) else { continue }
        guard line.contains(needle) else { continue }
        return parseJSONObjectLine(Data(lineData))
      }
      if buffer.count > 256 * 1024 {
        return nil
      }
    }
  }

  private static func parseJSONObjectLine(_ data: Data) -> [String: Any]? {
    guard !data.isEmpty else { return nil }
    let object = try? JSONSerialization.jsonObject(with: data)
    return object as? [String: Any]
  }

  static func claudeProjectDirectoryName(for rootURL: URL) -> String {
    normalizedPath(rootURL).replacing("/", with: "-")
  }

  private static func normalizedPath(_ url: URL) -> String {
    normalizedPath(url.standardizedFileURL.path(percentEncoded: false))
  }

  private static func normalizedPath(_ path: String) -> String {
    var result = URL(fileURLWithPath: path).standardizedFileURL.path(percentEncoded: false)
    while result.count > 1, result.hasSuffix("/") {
      result.removeLast()
    }
    return result
  }
}
