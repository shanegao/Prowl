import Darwin
import Foundation

/// Outcome of asking the outgoing agent to refresh `current.md` before a save.
nonisolated enum HandoffPreparationOutcome: String, Equatable, Sendable {
  case completed
  case skipped
  case failed
}

/// On-disk store for the cross-agent handoff artifact that lives under a
/// runnable target's `.prowl/handoff/` directory.
///
/// Layout (see `docs/components/handoff.md`):
/// ```
/// <root>/.prowl/handoff/
///   current.md            agent-authored handoff artifact
///   context.md            Prowl-generated repository and session context
///   log.md                append-only handoff history
///   archive/<ts>-<from>-to-<to>.md
///   sessions/<ts>-<pane>.md
/// ```
///
/// Agent-maintained semantic sections (Objective, Next Steps, …) live in
/// `current.md`. Prowl writes generated state to `context.md`, so background
/// saves never rewrite the agent's prose.
///
/// All work is plain filesystem + best-effort `git`, so the type is `Sendable`
/// and `nonisolated` — meant to run off the main actor (e.g. inside
/// `Task.detached`). The module defaults to `MainActor` isolation, so the
/// `nonisolated` annotation is required (mirrors `ProjectWorkspace`).
nonisolated struct HandoffStore: Sendable {
  private static let logLock = NSLock()

  /// The runnable target's root directory: a workspace root or a worktree root.
  let rootURL: URL

  init(rootURL: URL) {
    self.rootURL = rootURL.standardizedFileURL
  }

  // MARK: - Paths

  var handoffDirectory: URL {
    rootURL
      .appending(path: ".prowl", directoryHint: .isDirectory)
      .appending(path: "handoff", directoryHint: .isDirectory)
  }
  var currentURL: URL { handoffDirectory.appending(path: "current.md") }
  var contextURL: URL { handoffDirectory.appending(path: "context.md") }
  var ignoreURL: URL { handoffDirectory.appending(path: ".gitignore") }
  var logURL: URL { handoffDirectory.appending(path: "log.md") }
  var archiveDirectory: URL { handoffDirectory.appending(path: "archive", directoryHint: .isDirectory) }
  var sessionDirectory: URL { handoffDirectory.appending(path: "sessions", directoryHint: .isDirectory) }

  var hasCurrentArtifact: Bool {
    FileManager.default.fileExists(atPath: currentURL.path(percentEncoded: false))
  }

  /// Initial agent-authored artifact. Generated state is kept separately in
  /// `context.md` so Prowl never needs to rewrite this file after scaffolding.
  static let template = """
    # Handoff

    ## Objective
    <!-- one-paragraph task goal; stable across the whole run -->

    ## Current State
    <!-- where things stand right now -->

    ## What Has Been Done
    <!-- completed steps + key decisions/dead-ends -->

    ## Open Questions
    <!-- unresolved decisions the next agent (or human) must settle -->

    ## Risks / Watch Out
    <!-- anything fragile, half-done, or easy to break -->

    ## Next Steps
    <!-- ordered, concrete; the receiving agent starts here -->

    ## Suggested Prompt For Next Agent
    <!-- a ready-to-paste kickoff instruction -->

    ---
    Generated repository and session state: [context.md](context.md) (managed by Prowl).

    """

  // MARK: - Result models

  struct RepoSummary: Sendable, Equatable {
    let name: String
    let path: String
    let branch: String?
    let isGit: Bool
    let changedFileCount: Int
    let insertions: Int
    let deletions: Int
  }

  struct SaveResult: Sendable {
    let artifactPath: String
    let outgoingAgent: String?
    let sessionContext: HandoffSessionPayload?
    let repos: [RepoSummary]
    let changedFiles: [String]
    var totalChangedFiles: Int { repos.reduce(0) { $0 + $1.changedFileCount } }
  }

  struct SessionContext: Sendable, Equatable {
    let agent: String?
    let sessionID: String?
    let paneID: String
    let paneTitle: String?
    let source: String
    let confidence: String
    let transcriptPath: String?
    let excerptText: String?

    init(
      agent: String?,
      sessionID: String? = nil,
      paneID: String,
      paneTitle: String?,
      source: String,
      confidence: String,
      transcriptPath: String? = nil,
      excerptText: String?
    ) {
      self.agent = agent
      self.sessionID = sessionID
      self.paneID = paneID
      self.paneTitle = paneTitle
      self.source = source
      self.confidence = confidence
      self.transcriptPath = transcriptPath
      self.excerptText = excerptText
    }
  }

  struct StatusResult: Sendable, Equatable {
    let artifactPath: String
    let exists: Bool
    let workspaceTitle: String?
    let lastLogLine: String?
  }

  // MARK: - Scaffold

  /// Create the `.prowl/handoff/` tree and seed `current.md` from the template
  /// when it does not yet exist.
  func ensureScaffold() throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
    if !fileManager.fileExists(atPath: ignoreURL.path(percentEncoded: false)) {
      try "*\n".write(to: ignoreURL, atomically: true, encoding: .utf8)
    }
    if !fileManager.fileExists(atPath: currentURL.path(percentEncoded: false)) {
      let temporaryURL = handoffDirectory.appending(path: ".current-\(UUID().uuidString).tmp")
      defer { try? fileManager.removeItem(at: temporaryURL) }
      try Data(Self.template.utf8).write(to: temporaryURL, options: .atomic)
      if Darwin.link(
        temporaryURL.path(percentEncoded: false),
        currentURL.path(percentEncoded: false)
      ) != 0, errno != EEXIST {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    }
  }

  // MARK: - Save

  /// Refresh generated repository/session state in `context.md` and append a
  /// `save` line to the log. Never rewrites the agent-authored `current.md`.
  @discardableResult
  func save(
    outgoingAgent: String?,
    sessionContext: SessionContext? = nil,
    note: String?,
    preparation: HandoffPreparationOutcome? = nil,
    now: Date
  ) throws -> SaveResult {
    try ensureScaffold()

    let repos = repoSummaries()
    let changedFiles = changedFilePaths(for: repos)
    let savedSessionContext = try writeSessionContext(sessionContext, now: now)
    let appendix = buildAppendix(
      outgoingAgent: outgoingAgent,
      sessionContext: savedSessionContext,
      repos: repos,
      changedFiles: changedFiles,
      now: now
    )

    try appendix.write(to: contextURL, atomically: true, encoding: .utf8)

    let total = repos.reduce(0) { $0 + $1.changedFileCount }
    var logLine = "save  agent=\(outgoingAgent ?? "unknown")  repos=\(repos.count)  changed=\(total)"
    if let preparation {
      logLine += "  preparation=\(preparation.rawValue)"
    }
    try appendLog(logLine + Self.noteSuffix(note), now: now)

    return SaveResult(
      artifactPath: currentURL.path(percentEncoded: false),
      outgoingAgent: outgoingAgent,
      sessionContext: savedSessionContext,
      repos: repos,
      changedFiles: changedFiles
    )
  }

  // MARK: - Prepared artifact

  /// Validates a source agent's preparation reply and transcribes it into
  /// `current.md`. Prowl never authors semantic prose: the reply text is the
  /// source agent's, this method only checks shape and writes it verbatim.
  /// Returns false (leaving the existing artifact in place) when the reply is
  /// empty, still the seeded template, or missing the core semantic sections.
  func applyPreparationReply(_ reply: String) -> Bool {
    guard let artifact = Self.preparedArtifact(fromAgentReply: reply) else { return false }
    do {
      try FileManager.default.createDirectory(at: handoffDirectory, withIntermediateDirectories: true)
      try artifact.write(to: currentURL, atomically: true, encoding: .utf8)
      return true
    } catch {
      return false
    }
  }

  /// Normalizes a preparation reply into artifact content, or nil when unusable.
  static func preparedArtifact(fromAgentReply reply: String) -> String? {
    var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
    text = droppingOpeningFence(text)
    text = droppingPreamble(text)
    text = droppingClosingFence(text)
    let requiredSections = ["## Objective", "## Current State", "## Next Steps"]
    guard !text.isEmpty, requiredSections.allSatisfy(text.contains) else { return nil }
    guard text != template.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
    return text + "\n"
  }

  /// Unwraps the opening line of a markdown code fence ("```markdown").
  private static func droppingOpeningFence(_ text: String) -> String {
    guard text.hasPrefix("```") else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Drops chat preamble ahead of the artifact ("Sure, here's the file: …").
  private static func droppingPreamble(_ text: String) -> String {
    guard !text.hasPrefix("#") else { return text }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let start = lines.firstIndex(where: { $0.hasPrefix("# ") || $0.hasPrefix("## ") }) else {
      return text
    }
    return lines[start...].joined(separator: "\n")
  }

  /// Drops a trailing code-fence line left over after preamble removal.
  private static func droppingClosingFence(_ text: String) -> String {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard let last = lines.last, last.trimmingCharacters(in: .whitespaces) == "```" else { return text }
    lines.removeLast()
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Archive

  /// Copy the current artifact into `archive/` under a `<ts>-<from>-to-<to>.md`
  /// name, leaving `current.md` in place for the receiving agent. Returns the
  /// archived path relative to the handoff directory, or nil when there is
  /// nothing to archive.
  @discardableResult
  func archiveCurrent(from: String, toAgent: String, now: Date) throws -> String? {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: currentURL.path(percentEncoded: false)) else { return nil }
    try fileManager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)

    let stem = "\(Self.fileStamp(now))-\(Self.slug(from))-to-\(Self.slug(toAgent))"
    let destination = try Self.reserveFileURL(in: archiveDirectory, stem: stem, fileExtension: "md")
    var didWrite = false
    defer {
      if !didWrite {
        try? fileManager.removeItem(at: destination)
      }
    }
    let prose = try String(contentsOf: currentURL, encoding: .utf8)
    let context = (try? String(contentsOf: contextURL, encoding: .utf8)) ?? ""
    let snapshot = context.isEmpty ? prose : "\(prose.trimmingCharacters(in: .whitespacesAndNewlines))\n\n\(context)\n"
    try snapshot.write(to: destination, atomically: true, encoding: .utf8)
    didWrite = true
    return "handoff/archive/\(destination.lastPathComponent)"
  }

  // MARK: - Log

  func appendLog(_ event: String, now: Date) throws {
    try FileManager.default.createDirectory(at: handoffDirectory, withIntermediateDirectories: true)
    let line = "- \(Self.iso(now))  \(event)\n"
    Self.logLock.lock()
    defer { Self.logLock.unlock() }

    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: logURL.path(percentEncoded: false)) {
      try "# Handoff log\n\n".write(to: logURL, atomically: true, encoding: .utf8)
    }
    let handle = try FileHandle(forWritingTo: logURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(line.utf8))
  }

  // MARK: - Status

  func readStatus() -> StatusResult {
    let exists = FileManager.default.fileExists(atPath: currentURL.path(percentEncoded: false))
    let lastLogLine = (try? String(contentsOf: logURL, encoding: .utf8))?
      .split(separator: "\n", omittingEmptySubsequences: true)
      .last { $0.hasPrefix("- ") }
      .map(String.init)
    return StatusResult(
      artifactPath: currentURL.path(percentEncoded: false),
      exists: exists,
      workspaceTitle: workspaceTitle,
      lastLogLine: lastLogLine
    )
  }

  // MARK: - Repo enumeration

  /// Repos in scope: workspace children when `workspace.json` is present,
  /// otherwise the root itself.
  private var scopedRepos: [(name: String, url: URL)] {
    if let workspace = ProjectWorkspace.load(from: rootURL), !workspace.repositories.isEmpty {
      return workspace.repositories.map { entry in
        let resolved = entry.resolvedURL(relativeTo: rootURL)
        let name = entry.name.isEmpty ? resolved.lastPathComponent : entry.name
        return (name, resolved)
      }
    }
    let name = rootURL.lastPathComponent.isEmpty ? rootURL.path(percentEncoded: false) : rootURL.lastPathComponent
    return [(name, rootURL)]
  }

  private var workspaceTitle: String? {
    guard let workspace = ProjectWorkspace.load(from: rootURL) else { return nil }
    return workspace.title.isEmpty ? nil : workspace.title
  }

  private func repoSummaries() -> [RepoSummary] {
    scopedRepos.map { repo in
      let insideWorkTree = Self.git(["rev-parse", "--is-inside-work-tree"], in: repo.url)
      let isGit = insideWorkTree?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
      guard isGit else {
        return RepoSummary(
          name: repo.name,
          path: repo.url.path(percentEncoded: false),
          branch: nil,
          isGit: false,
          changedFileCount: 0,
          insertions: 0,
          deletions: 0
        )
      }
      let branch = Self.git(["rev-parse", "--abbrev-ref", "HEAD"], in: repo.url)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let porcelain = Self.git(["-c", "core.quotePath=false", "status", "--porcelain"], in: repo.url) ?? ""
      let changedCount = porcelain.split(separator: "\n", omittingEmptySubsequences: true).count
      let (insertions, deletions) = Self.parseShortstat(Self.git(["diff", "HEAD", "--shortstat"], in: repo.url) ?? "")
      return RepoSummary(
        name: repo.name,
        path: repo.url.path(percentEncoded: false),
        branch: branch,
        isGit: true,
        changedFileCount: changedCount,
        insertions: insertions,
        deletions: deletions
      )
    }
  }

  private func changedFilePaths(for repos: [RepoSummary]) -> [String] {
    var files: [String] = []
    for repo in repos where repo.isGit {
      let repoURL = URL(fileURLWithPath: repo.path, isDirectory: true)
      let porcelain = Self.git(["-c", "core.quotePath=false", "status", "--porcelain"], in: repoURL) ?? ""
      for line in porcelain.split(separator: "\n", omittingEmptySubsequences: true) {
        let entry = String(line.dropFirst(3))  // strip 2-char status + space
        let relative = entry.contains(" -> ") ? String(entry.split(separator: " -> ").last ?? "") : entry
        files.append("\(repo.name)/\(relative)")
      }
    }
    return files
  }

  // MARK: - Session context

  private func writeSessionContext(_ context: SessionContext?, now: Date) throws -> HandoffSessionPayload? {
    guard let context else { return nil }

    let stem = "\(Self.fileStamp(now))-\(Self.slug(context.paneID))"
    let destination = try Self.reserveFileURL(in: sessionDirectory, stem: stem, fileExtension: "md")
    var didWrite = false
    defer {
      if !didWrite {
        try? FileManager.default.removeItem(at: destination)
      }
    }
    let relativePath = "handoff/sessions/\(destination.lastPathComponent)"
    let payload = HandoffSessionPayload(
      agent: context.agent,
      sessionID: context.sessionID,
      paneID: context.paneID,
      paneTitle: context.paneTitle,
      source: context.source,
      confidence: context.confidence,
      excerptPath: relativePath,
      transcriptPath: context.transcriptPath
    )

    let markdown = Self.renderSessionContext(context, payload: payload, now: now)
    try markdown.write(to: destination, atomically: true, encoding: .utf8)
    didWrite = true
    return payload
  }

  private static func renderSessionContext(
    _ context: SessionContext,
    payload: HandoffSessionPayload,
    now: Date
  ) -> String {
    let text = trimmedSessionExcerpt(context.excerptText)
    var lines: [String] = []
    lines.append("# Handoff Session Context")
    lines.append("")
    lines.append("- Captured: \(iso(now))")
    lines.append("- Agent: \(payload.agent ?? "unknown")")
    lines.append("- Session ID: \(payload.sessionID ?? "unknown")")
    lines.append("- Pane: \(payload.paneID)\(payload.paneTitle.map { " (\($0))" } ?? "")")
    lines.append("- Source: \(payload.source)")
    lines.append("- Confidence: \(payload.confidence)")
    lines.append("- Native transcript: \(payload.transcriptPath ?? "unknown")")
    lines.append("")
    lines.append("## Terminal Excerpt")
    lines.append("")
    if text.isEmpty {
      lines.append("_No terminal text was captured._")
    } else {
      lines.append("````text")
      lines.append(text)
      lines.append("````")
    }
    lines.append("")
    return lines.joined(separator: "\n")
  }

  private static func trimmedSessionExcerpt(_ text: String?) -> String {
    guard let text else { return "" }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    let lineLimited = lines.suffix(240).joined(separator: "\n")
    guard lineLimited.count > 20_000 else { return lineLimited }
    let suffix = String(lineLimited.suffix(20_000))
    return "[... earlier terminal content truncated ...]\n" + suffix
  }

  // MARK: - Appendix builder (pure)

  func buildAppendix(
    outgoingAgent: String?,
    sessionContext: HandoffSessionPayload?,
    repos: [RepoSummary],
    changedFiles: [String],
    now: Date
  ) -> String {
    var lines: [String] = []
    lines.append("# Handoff Context (generated)")
    lines.append("- Generated: \(Self.iso(now))")
    lines.append("- Outgoing agent (detected): \(outgoingAgent ?? "unknown")")
    lines.append("- Workspace: \(workspaceTitle ?? "(none)")  (\(rootURL.path(percentEncoded: false)))")
    lines.append("- Session Context:")
    if let sessionContext {
      lines.append("  - Agent: \(sessionContext.agent ?? "unknown")")
      lines.append("  - Session ID: \(sessionContext.sessionID ?? "unknown")")
      lines.append("  - Source: \(sessionContext.source)")
      lines.append("  - Confidence: \(sessionContext.confidence)")
      lines.append("  - Pane: \(sessionContext.paneID)")
      lines.append("  - Context excerpt: .prowl/\(sessionContext.excerptPath ?? "handoff/sessions/unknown.md")")
      lines.append("  - Native transcript: \(sessionContext.transcriptPath ?? "unknown")")
    } else {
      lines.append("  - (not captured)")
    }
    lines.append("- Repos & branches:")
    if repos.isEmpty {
      lines.append("  - (none)")
    } else {
      for repo in repos {
        if repo.isGit {
          lines.append(
            "  - \(repo.name)  \(repo.branch ?? "?")  "
              + "(\(repo.changedFileCount) files changed, +\(repo.insertions)/-\(repo.deletions))"
          )
        } else {
          lines.append("  - \(repo.name)  (not a git repo)")
        }
      }
    }
    lines.append("- Changed files:")
    if changedFiles.isEmpty {
      lines.append("  - (none)")
    } else {
      let cap = 60
      for file in changedFiles.prefix(cap) {
        lines.append("  - \(file)")
      }
      if changedFiles.count > cap {
        lines.append("  - … (\(changedFiles.count - cap) more changed files)")
      }
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - Helpers

  private static func noteSuffix(_ note: String?) -> String {
    guard let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
    let cleaned = note.replacing("\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return "  note=\"\(cleaned)\""
  }

  private static func slug(_ value: String) -> String {
    let allowed = value.lowercased().map { character -> Character in
      character.isLetter || character.isNumber ? character : "-"
    }
    return String(allowed)
  }

  /// Atomically reserve a unique destination before its content is written.
  /// Reservation makes the following atomic replacement safe against concurrent
  /// saves that share a timestamp and file stem.
  static func reserveFileURL(in directory: URL, stem: String, fileExtension: String) throws -> URL {
    var suffix = 1
    while true {
      let suffixPart = suffix == 1 ? "" : "-\(suffix)"
      let candidate = directory.appending(path: "\(stem)\(suffixPart).\(fileExtension)")
      let descriptor = Darwin.open(
        candidate.path(percentEncoded: false),
        O_WRONLY | O_CREAT | O_EXCL,
        S_IRUSR | S_IWUSR
      )
      if descriptor >= 0 {
        _ = Darwin.close(descriptor)
        return candidate
      }
      guard errno == EEXIST else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      suffix += 1
    }
  }

  static func parseShortstat(_ text: String) -> (insertions: Int, deletions: Int) {
    func value(matching keyword: String) -> Int {
      // text like " 3 files changed, 120 insertions(+), 14 deletions(-)"
      for fragment in text.split(separator: ",") where fragment.contains(keyword) {
        let number = fragment.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
        return Int(number) ?? 0
      }
      return 0
    }
    return (value(matching: "insertion"), value(matching: "deletion"))
  }

  private static func iso(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  private static func fileStamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HHmm"
    return formatter.string(from: date)
  }

  /// Run a git command in `directory`, returning trimmed stdout or nil on failure.
  /// stderr is discarded; non-zero exit yields nil. Used best-effort for the
  /// appendix — a non-git directory simply produces nil.
  private static func git(_ arguments: [String], in directory: URL) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", directory.path(percentEncoded: false)] + arguments
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
