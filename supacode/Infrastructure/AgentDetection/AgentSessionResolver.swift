import Foundation

nonisolated struct AgentSession: Equatable, Sendable {
  enum Source: String, Equatable, Sendable {
    case commandLine = "command_line"
    case openFile = "open_file"
    case processLog = "process_log"
    case storeRecord = "store_record"
    case transcriptMatch = "transcript_match"
    case recentFile = "recent_file"
  }

  enum Confidence: String, Equatable, Sendable {
    case exact
    case high
    case medium
  }

  let id: String
  let transcriptPath: URL?
  let source: Source
  let confidence: Confidence

  init(
    id: String,
    transcriptPath: URL?,
    source: Source,
    confidence: Confidence = .medium
  ) {
    self.id = id
    self.transcriptPath = transcriptPath
    self.source = source
    self.confidence = confidence
  }
}

nonisolated struct AgentSessionCandidate: Equatable, Sendable {
  let session: AgentSession
  let modifiedAt: Date

  /// The sole session active during the process lifetime, or nil when zero or
  /// several distinct sessions qualify. Grouping by session id keeps layouts
  /// with several files per session (Kimi, Cline, Copilot) resolvable.
  nonisolated static func uniqueActiveCandidate(
    _ candidates: [Self],
    processStartedAt: Date,
    clockSkew: TimeInterval = 2
  ) -> Self? {
    let active = candidates.filter { $0.modifiedAt >= processStartedAt.addingTimeInterval(-clockSkew) }
    let sessions = Dictionary(grouping: active) { $0.session.id }
    guard sessions.count == 1, let group = sessions.values.first else { return nil }
    return group.max { $0.modifiedAt < $1.modifiedAt }
  }
}

/// Compatibility shim over the per-agent profiles; the actual rules live in
/// `AgentSessionProfile`.
nonisolated enum AgentSessionPathParser {
  static func parse(path: String, agent: DetectedAgent) -> AgentSession? {
    AgentSessionProfile.profile(for: agent).parsePath(path)
  }
}

actor AgentSessionResolver {
  static let shared = AgentSessionResolver()

  private struct CacheKey: Hashable {
    let pid: pid_t
    let startedAt: Date
  }

  private struct CachedResult {
    let resolvedAt: Date
    let session: AgentSession?
  }

  private var cache: [CacheKey: CachedResult] = [:]
  private let fileManager: FileManager
  private let homeDirectory: URL

  init(
    fileManager: FileManager = .default,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    self.fileManager = fileManager
    self.homeDirectory = homeDirectory
  }

  func resolve(
    identified: IdentifiedAgentProcess,
    workingDirectory: URL?,
    activeText: String,
    now: Date = Date()
  ) -> AgentSession? {
    let process = identified.process
    guard let startedAt = ProcessDetection.processStartDate(pid: process.pid) else { return nil }
    let key = CacheKey(pid: process.pid, startedAt: startedAt)
    if let cached = cache[key] {
      let lifetime: TimeInterval = cached.session == nil ? 1 : 5
      if now.timeIntervalSince(cached.resolvedAt) < lifetime { return cached.session }
    }

    let session = resolveUncached(
      identified: identified,
      processStartedAt: startedAt,
      workingDirectory: workingDirectory,
      activeText: activeText,
      now: now
    )
    cache[key] = CachedResult(resolvedAt: now, session: session)
    if cache.count > 128 {
      cache = cache.filter { ProcessDetection.processBSDInfo(pid: $0.key.pid) != nil }
    }
    return session
  }

  private func resolveUncached(
    identified: IdentifiedAgentProcess,
    processStartedAt: Date,
    workingDirectory: URL?,
    activeText: String,
    now: Date
  ) -> AgentSession? {
    let profile = AgentSessionProfile.profile(for: identified.agent)

    let openSessions = ProcessDetection.openFilePaths(pid: identified.process.pid)
      .compactMap { profile.parsePath($0) }
    if let session = uniqueSession(openSessions) {
      return AgentSession(
        id: session.id,
        transcriptPath: session.transcriptPath,
        source: .openFile,
        confidence: .exact
      )
    }

    if let session = profile.pidKeyedSession?(homeDirectory, identified.process.pid, processStartedAt) {
      return session
    }

    let openCandidates = openSessions.compactMap { session -> AgentSessionCandidate? in
      guard let path = session.transcriptPath,
        let attributes = try? fileManager.attributesOfItem(atPath: path.path),
        let modifiedAt = attributes[.modificationDate] as? Date
      else { return nil }
      return AgentSessionCandidate(session: session, modifiedAt: modifiedAt)
    }
    if let matched = AgentSessionFingerprintMatcher.bestMatch(
      activeText: activeText,
      candidates: openCandidates
    ) {
      return AgentSession(
        id: matched.session.id,
        transcriptPath: matched.session.transcriptPath,
        source: .transcriptMatch,
        confidence: .high
      )
    }

    let candidates = recentCandidates(
      profile: profile,
      processStartedAt: processStartedAt,
      workingDirectory: workingDirectory,
      now: now
    )
    if let matched = AgentSessionFingerprintMatcher.bestMatch(activeText: activeText, candidates: candidates) {
      return AgentSession(
        id: matched.session.id,
        transcriptPath: matched.session.transcriptPath,
        source: .transcriptMatch,
        confidence: .high
      )
    }
    return AgentSessionCandidate.uniqueActiveCandidate(candidates, processStartedAt: processStartedAt)?.session
  }

  private func uniqueSession(_ sessions: [AgentSession]) -> AgentSession? {
    let unique = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return unique.count == 1 ? unique.values.first : nil
  }

  private func recentCandidates(
    profile: AgentSessionProfile,
    processStartedAt: Date,
    workingDirectory: URL?,
    now: Date
  ) -> [AgentSessionCandidate] {
    let stored =
      profile.storeCandidates?(homeDirectory, workingDirectory, processStartedAt.addingTimeInterval(-2)) ?? []
    let primary = candidates(
      in: profile.candidateRoots(homeDirectory, workingDirectory, processStartedAt, now),
      profile: profile,
      processStartedAt: processStartedAt
    )
    let combined = primary + stored
    guard combined.isEmpty else { return combined }
    return candidates(
      in: profile.fallbackRoots(homeDirectory, workingDirectory),
      profile: profile,
      processStartedAt: processStartedAt
    )
  }

  private func candidates(
    in roots: [URL],
    profile: AgentSessionProfile,
    processStartedAt: Date
  ) -> [AgentSessionCandidate] {
    roots.flatMap { root in
      recentFiles(in: root, modifiedAfter: processStartedAt.addingTimeInterval(-2)).compactMap { item in
        guard let session = profile.parsePath(item.url.path) else { return nil }
        let enriched =
          sessionIDFromHeader(at: item.url).map {
            AgentSession(id: $0, transcriptPath: item.url, source: .recentFile)
          } ?? session
        return AgentSessionCandidate(session: enriched, modifiedAt: item.modifiedAt)
      }
    }
  }

  private func sessionIDFromHeader(at url: URL) -> String? {
    guard url.pathExtension == "jsonl",
      let handle = try? FileHandle(forReadingFrom: url)
    else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8_192),
      let line = data.split(separator: 0x0A).first,
      let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
    else { return nil }
    for key in ["sessionId", "session_id", "id"] {
      if let value = object[key] as? String, !value.isEmpty { return value }
    }
    return nil
  }

  private func recentFiles(in root: URL, modifiedAfter threshold: Date) -> [(url: URL, modifiedAt: Date)] {
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    var result: [(URL, Date)] = []
    for case let url as URL in enumerator {
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
        values.isRegularFile == true,
        let modifiedAt = values.contentModificationDate,
        modifiedAt >= threshold
      else { continue }
      result.append((url, modifiedAt))
    }
    return result
  }
}

nonisolated enum AgentSessionFingerprintMatcher {
  static func bestMatch(
    activeText: String,
    candidates: [AgentSessionCandidate]
  ) -> AgentSessionCandidate? {
    let screen = normalize(activeText)
    guard screen.count >= 12 else { return nil }
    let scored = candidates.compactMap { candidate -> (AgentSessionCandidate, Int)? in
      guard let path = candidate.session.transcriptPath,
        let data = tailData(at: path),
        let text = String(data: data, encoding: .utf8)
      else { return nil }
      let score = transcriptStrings(text).reduce(0) { best, fragment in
        let normalized = normalize(fragment)
        guard normalized.count >= 12 else { return best }
        if screen.contains(normalized) { return max(best, min(200, normalized.count + 80)) }
        let suffix = String(normalized.suffix(80))
        return suffix.count >= 24 && screen.contains(suffix) ? max(best, suffix.count) : best
      }
      return score > 0 ? (candidate, score) : nil
    }

    // The margin rule guards against picking between *sessions* that look
    // alike; files belonging to one session reinforce it instead of competing.
    let sessions = Dictionary(grouping: scored) { $0.0.session.id }
      .map { id, group in
        (id: id, best: group.max { $0.1 < $1.1 }!)
      }
      .sorted { $0.best.1 > $1.best.1 }

    guard let winner = sessions.first, winner.best.1 >= 40 else { return nil }
    if sessions.count > 1, winner.best.1 - sessions[1].best.1 < 20 { return nil }
    return winner.best.0
  }

  static func normalize(_ value: String) -> String {
    value
      .replacing(#/\u{001B}\[[0-?]*[ -\/]*[@-~]/#, with: " ")
      .lowercased()
      .split(whereSeparator: \Character.isWhitespace)
      .joined(separator: " ")
  }

  private static func tailData(at url: URL, byteLimit: UInt64 = 131_072) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd() else { return nil }
    try? handle.seek(toOffset: size > byteLimit ? size - byteLimit : 0)
    return try? handle.readToEnd()
  }

  private static func transcriptStrings(_ text: String) -> [String] {
    text.split(separator: "\n").suffix(80).flatMap { line -> [String] in
      guard let data = line.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data)
      else { return [] }
      return strings(in: json, key: nil)
    }
  }

  private static func strings(in value: Any, key: String?) -> [String] {
    if let string = value as? String,
      ["content", "text", "message", "result", "prompt", "last_assistant_message"].contains(key ?? "")
    {
      return [string]
    }
    if let array = value as? [Any] {
      return array.flatMap { strings(in: $0, key: key) }
    }
    if let object = value as? [String: Any] {
      return object.flatMap { strings(in: $0.value, key: $0.key) }
    }
    return []
  }
}
