import Foundation

nonisolated struct AgentSession: Equatable, Sendable {
  enum Source: String, Equatable, Sendable {
    case commandLine = "command_line"
    case openFile = "open_file"
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

  nonisolated static func uniqueActiveCandidate(
    _ candidates: [Self],
    processStartedAt: Date,
    clockSkew: TimeInterval = 2
  ) -> Self? {
    let active = candidates.filter { $0.modifiedAt >= processStartedAt.addingTimeInterval(-clockSkew) }
    return active.count == 1 ? active[0] : nil
  }
}

nonisolated enum AgentSessionPathParser {
  static func parse(path: String, agent: DetectedAgent) -> AgentSession? {
    let url = URL(fileURLWithPath: path)
    let id = sessionID(path: path, url: url, agent: agent)
    guard let id, !id.isEmpty else { return nil }
    return AgentSession(id: id, transcriptPath: url, source: .recentFile)
  }

  private static func sessionID(path: String, url: URL, agent: DetectedAgent) -> String? {
    switch agent {
    case .codex: uuidJSONL(path: path, marker: "/.codex/sessions/", url: url)
    case .claude: uuidJSONL(path: path, marker: "/.claude/projects/", url: url)
    case .pi: uuidJSONL(path: path, marker: "/.pi/agent/sessions/", url: url)
    case .gemini: geminiID(path: path, url: url)
    case .cursor: parentID(path: path, marker: "/.cursor/chats/", filename: "store.db", url: url)
    case .cline: markedComponent(path: path, marker: "/.cline/data/tasks/", component: "tasks", url: url)
    case .copilot:
      markedComponent(path: path, marker: "/.copilot/session-state/", component: "session-state", url: url)
    case .kimi: kimiID(path: path, url: url)
    case .droid: uuidJSONL(path: path, marker: "/.factory/sessions/", url: url)
    case .opencode, .amp, .qwen: nil
    }
  }

  private static func uuidJSONL(path: String, marker: String, url: URL) -> String? {
    guard path.contains(marker), url.pathExtension == "jsonl" else { return nil }
    return uuid(in: url.deletingPathExtension().lastPathComponent)
  }

  private static func geminiID(path: String, url: URL) -> String? {
    guard path.contains("/.gemini/tmp/"), path.contains("/chats/"), url.pathExtension == "jsonl" else { return nil }
    return url.deletingPathExtension().lastPathComponent.split(separator: "-").last.map(String.init)
  }

  private static func parentID(path: String, marker: String, filename: String, url: URL) -> String? {
    guard path.contains(marker), url.lastPathComponent == filename else { return nil }
    return url.pathComponents.dropLast().last
  }

  private static func markedComponent(path: String, marker: String, component: String, url: URL) -> String? {
    guard path.contains(marker) else { return nil }
    return self.component(after: component, in: url.pathComponents)
  }

  private static func kimiID(path: String, url: URL) -> String? {
    guard path.contains("/.kimi/sessions/") else { return nil }
    let components = url.pathComponents
    guard let index = components.firstIndex(of: "sessions"), components.count > index + 2 else { return nil }
    return components[index + 2]
  }

  private static func uuid(in value: String) -> String? {
    let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
    guard let range = value.range(of: pattern, options: .regularExpression) else { return nil }
    return String(value[range]).lowercased()
  }

  private static func component(after marker: String, in components: [String]) -> String? {
    guard let index = components.firstIndex(of: marker), components.indices.contains(index + 1) else { return nil }
    return components[index + 1]
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
      activeText: activeText
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
    activeText: String
  ) -> AgentSession? {
    let openSessions = ProcessDetection.openFilePaths(pid: identified.process.pid)
      .compactMap { AgentSessionPathParser.parse(path: $0, agent: identified.agent) }
    if let session = uniqueSession(openSessions) {
      return AgentSession(
        id: session.id,
        transcriptPath: session.transcriptPath,
        source: .openFile,
        confidence: .exact
      )
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
      agent: identified.agent,
      workingDirectory: workingDirectory,
      processStartedAt: processStartedAt
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
    agent: DetectedAgent,
    workingDirectory: URL?,
    processStartedAt: Date
  ) -> [AgentSessionCandidate] {
    candidateRoots(agent: agent, workingDirectory: workingDirectory).flatMap { root in
      recentFiles(in: root, modifiedAfter: processStartedAt.addingTimeInterval(-2)).compactMap { item in
        guard let session = AgentSessionPathParser.parse(path: item.url.path, agent: agent) else { return nil }
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

  private func candidateRoots(agent: DetectedAgent, workingDirectory: URL?) -> [URL] {
    switch agent {
    case .codex:
      return [homeDirectory.appending(path: ".codex/sessions")]
    case .claude:
      guard let workingDirectory else { return [] }
      return [homeDirectory.appending(path: ".claude/projects/\(encodedClaudePath(workingDirectory.path))")]
    case .pi:
      guard let workingDirectory else { return [] }
      return [homeDirectory.appending(path: ".pi/agent/sessions/-\(encodedClaudePath(workingDirectory.path))--")]
    case .gemini:
      return [homeDirectory.appending(path: ".gemini/tmp")]
    case .cursor:
      return [homeDirectory.appending(path: ".cursor/chats")]
    case .cline:
      return [homeDirectory.appending(path: ".cline/data/tasks")]
    case .copilot:
      return [homeDirectory.appending(path: ".copilot/session-state")]
    case .kimi:
      return [homeDirectory.appending(path: ".kimi/sessions")]
    case .droid:
      guard let workingDirectory else { return [] }
      return [homeDirectory.appending(path: ".factory/sessions/\(encodedClaudePath(workingDirectory.path))")]
    case .opencode, .amp, .qwen:
      return []
    }
  }

  private func encodedClaudePath(_ path: String) -> String {
    path.replacing("/", with: "-")
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
    }.sorted { $0.1 > $1.1 }

    guard let best = scored.first, best.1 >= 40 else { return nil }
    if scored.count > 1, best.1 - scored[1].1 < 20 { return nil }
    return best.0
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
