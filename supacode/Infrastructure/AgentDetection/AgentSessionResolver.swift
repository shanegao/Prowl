import Foundation

private nonisolated let agentSessionLogger = SupaLogger("AgentSession")

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

nonisolated extension [AgentSessionCandidate] {
  /// Store rows queried under two cwd variants can duplicate a session.
  fileprivate func uniquedBySessionID() -> [AgentSessionCandidate] {
    var seen: Set<String> = []
    return filter { seen.insert($0.session.id).inserted }
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
    let usedWideScan: Bool
    var unresolvedStreak: Int = 0
    var provisionalSoleID: String?
  }

  /// Unresolved lookups retry quickly while the narrow scan stays cheap, then
  /// back off exponentially while the pane stays ambiguous; wide fallback
  /// scans (full history trees) start at the slow end. 15 s cap keeps a
  /// permanently ambiguous pane at negligible background cost while still
  /// converging after a session rotation.
  nonisolated static func cacheLifetime(hasSession: Bool, usedWideScan: Bool, unresolvedStreak: Int) -> TimeInterval {
    if hasSession { return 5 }
    let base: TimeInterval = usedWideScan ? 8 : 1
    return min(15, base * TimeInterval(1 << min(unresolvedStreak, 4)))
  }

  /// A sole process-lifetime candidate is only trusted after two consecutive
  /// resolutions agree on it. A pane that starts in a directory where another
  /// agent is actively writing can otherwise adopt that agent's session during
  /// the sub-second window before its own file lands.
  nonisolated static func confirmSole(
    _ session: AgentSession?,
    previousProvisionalID: String?
  ) -> (session: AgentSession?, provisionalID: String?) {
    guard let session else { return (nil, nil) }
    guard session.confidence == .medium else { return (session, nil) }
    guard session.id == previousProvisionalID else { return (nil, session.id) }
    return (session, nil)
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
    let cached = cache[key]
    if let cached {
      let lifetime = Self.cacheLifetime(
        hasSession: cached.session != nil,
        usedWideScan: cached.usedWideScan,
        unresolvedStreak: cached.unresolvedStreak
      )
      if now.timeIntervalSince(cached.resolvedAt) < lifetime { return cached.session }
    }

    let (resolved, usedWideScan) = resolveUncached(
      identified: identified,
      processStartedAt: startedAt,
      workingDirectory: workingDirectory,
      activeText: activeText,
      now: now
    )
    var session = resolved
    var provisionalID: String?
    if let candidate = session, candidate.confidence == .medium {
      if claimedByAnotherProcess(candidate.id, excluding: key) {
        session = nil
      } else {
        (session, provisionalID) = Self.confirmSole(candidate, previousProvisionalID: cached?.provisionalSoleID)
      }
    }
    cache[key] = CachedResult(
      resolvedAt: now,
      session: session,
      usedWideScan: usedWideScan,
      // A pending sole confirmation retries fast instead of backing off.
      unresolvedStreak: session == nil && provisionalID == nil ? (cached?.unresolvedStreak ?? 0) + 1 : 0,
      provisionalSoleID: provisionalID
    )
    if cache.count > 128 {
      cache = cache.filter { entry in
        ProcessDetection.processStartDate(pid: entry.key.pid) == entry.key.startedAt
      }
    }
    return session
  }

  /// A session id already resolved for a different live process cannot also
  /// belong to this one; sole-candidate attribution must not steal it.
  private func claimedByAnotherProcess(_ id: String, excluding key: CacheKey) -> Bool {
    cache.contains { entry in
      entry.key != key && entry.value.session?.id == id
        && ProcessDetection.processStartDate(pid: entry.key.pid) == entry.key.startedAt
    }
  }

  private func resolveUncached(
    identified: IdentifiedAgentProcess,
    processStartedAt: Date,
    workingDirectory: URL?,
    activeText: String,
    now: Date
  ) -> (session: AgentSession?, usedWideScan: Bool) {
    let profile = AgentSessionProfile.profile(for: identified.agent)

    let openSessions = ProcessDetection.openFilePaths(pid: identified.process.pid)
      .compactMap { profile.parsePath($0) }
      .map { session -> AgentSession in
        guard let path = session.transcriptPath,
          let fullID = Self.sessionIDFromHeader(at: path, keys: profile.headerSessionIDKeys)
        else { return session }
        return AgentSession(id: fullID, transcriptPath: path, source: session.source)
      }
    if let session = uniqueSession(openSessions) {
      let resolved = AgentSession(
        id: session.id,
        transcriptPath: session.transcriptPath,
        source: .openFile,
        confidence: .exact
      )
      return (resolved, false)
    }

    if let session = profile.pidKeyedSession?(homeDirectory, identified.process.pid, processStartedAt) {
      return (session, false)
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
      let resolved = AgentSession(
        id: matched.session.id,
        transcriptPath: matched.session.transcriptPath,
        source: .transcriptMatch,
        confidence: .high
      )
      return (resolved, false)
    }

    let (candidates, usedWideScan) = recentCandidates(
      profile: profile,
      processStartedAt: processStartedAt,
      workingDirectory: workingDirectory,
      now: now
    )
    if let matched = AgentSessionFingerprintMatcher.bestMatch(activeText: activeText, candidates: candidates) {
      let resolved = AgentSession(
        id: matched.session.id,
        transcriptPath: matched.session.transcriptPath,
        source: .transcriptMatch,
        confidence: .high
      )
      return (resolved, usedWideScan)
    }
    let sole = AgentSessionCandidate.uniqueActiveCandidate(candidates, processStartedAt: processStartedAt)?.session
    return (sole, usedWideScan)
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
  ) -> (candidates: [AgentSessionCandidate], usedWideScan: Bool) {
    let cwdVariants = workingDirectoryVariants(workingDirectory)
    let threshold = processStartedAt.addingTimeInterval(-2)
    let stored = cwdVariants.flatMap { profile.storeCandidates?(homeDirectory, $0, threshold) ?? [] }
    var primaryRoots: [URL] = []
    for cwd in cwdVariants {
      for root in profile.candidateRoots(homeDirectory, cwd, processStartedAt, now)
      where !primaryRoots.contains(root) {
        primaryRoots.append(root)
      }
    }
    let primary = candidates(in: primaryRoots, profile: profile, processStartedAt: processStartedAt)
    let combined = primary + stored.uniquedBySessionID()
    guard combined.isEmpty else { return (combined, false) }
    let fallbackRoots = profile.fallbackRoots(homeDirectory, workingDirectory)
    guard !fallbackRoots.isEmpty else { return ([], false) }
    return (candidates(in: fallbackRoots, profile: profile, processStartedAt: processStartedAt), true)
  }

  /// The pane reports the shell's logical `$PWD` while agents usually record
  /// the physical path (`/tmp` vs `/private/tmp`); try both encodings.
  private func workingDirectoryVariants(_ cwd: URL?) -> [URL?] {
    guard let cwd else { return [nil] }
    let resolved = cwd.resolvingSymlinksInPath()
    return resolved.path == cwd.path ? [cwd] : [cwd, resolved]
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
          Self.sessionIDFromHeader(at: item.url, keys: profile.headerSessionIDKeys).map {
            AgentSession(id: $0, transcriptPath: item.url, source: .recentFile)
          } ?? session
        return AgentSessionCandidate(session: enriched, modifiedAt: item.modifiedAt)
      }
    }
  }

  nonisolated static func sessionIDFromHeader(at url: URL, keys: [String]) -> String? {
    guard !keys.isEmpty, url.pathExtension == "jsonl",
      let handle = try? FileHandle(forReadingFrom: url)
    else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8_192),
      let line = data.split(separator: 0x0A).first,
      let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
    else { return nil }
    for key in keys {
      if let value = object[key] as? String, !value.isEmpty { return value }
    }
    return nil
  }

  private func recentFiles(
    in root: URL,
    modifiedAfter threshold: Date,
    visitLimit: Int = 20_000
  ) -> [(url: URL, modifiedAt: Date)] {
    guard
      let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    var visited = 0
    var result: [(URL, Date)] = []
    for case let url as URL in enumerator {
      visited += 1
      if visited > visitLimit {
        // A pathological tree; missing candidates degrades to "unresolved",
        // never to a wrong id.
        agentSessionLogger.warning("Agent session scan truncated at \(visitLimit) entries under \(root.path)")
        break
      }
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
    // Cap tail reads: the freshest files carry the on-screen conversation.
    let recent = candidates.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(12)
    let scored = recent.compactMap { candidate -> (AgentSessionCandidate, Int)? in
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
