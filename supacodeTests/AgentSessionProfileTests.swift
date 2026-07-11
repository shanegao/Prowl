import Darwin
import Foundation
import SQLite3
import Testing

@testable import supacode

struct AgentSessionProfileTests {
  private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
  private let now = Date(timeIntervalSince1970: 1_783_800_000)

  // MARK: - Working-directory encoders

  @Test func claudeRootSanitizesEveryNonAlphanumericCharacter() {
    let roots = AgentSessionProfile.profile(for: .claude).candidateRoots(
      home,
      URL(fileURLWithPath: "/private/tmp/prowl_556.enc", isDirectory: true),
      now,
      now
    )
    #expect(roots.map(\.path) == ["/Users/me/.claude/projects/-private-tmp-prowl-556-enc"])
  }

  @Test func piAndDroidRootsKeepDotsAndSpaces() {
    let cwd = URL(fileURLWithPath: "/Users/me/.prowl/repos/My App", isDirectory: true)
    let piRoots = AgentSessionProfile.profile(for: .pi).candidateRoots(home, cwd, now, now)
    #expect(piRoots.map(\.path) == ["/Users/me/.pi/agent/sessions/--Users-me-.prowl-repos-My App--"])
    let droidRoots = AgentSessionProfile.profile(for: .droid).candidateRoots(home, cwd, now, now)
    #expect(droidRoots.map(\.path) == ["/Users/me/.factory/sessions/-Users-me-.prowl-repos-My App"])
  }

  // MARK: - Candidate-root narrowing

  @Test func codexRootsNarrowToProcessLifetimeDays() {
    let calendar = Calendar.current
    let processStartedAt = calendar.date(byAdding: .day, value: -2, to: now)!
    let roots = AgentSessionProfile.profile(for: .codex).candidateRoots(home, nil, processStartedAt, now)

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy/MM/dd"
    let expected = (0...3).map { offset in
      let day = calendar.date(byAdding: .day, value: -offset, to: now)!
      return "/Users/me/.codex/sessions/\(formatter.string(from: day))"
    }
    #expect(Set(roots.map(\.path)) == Set(expected))
    let fallback = AgentSessionProfile.profile(for: .codex).fallbackRoots(home, nil)
    #expect(fallback.map(\.path) == ["/Users/me/.codex/sessions"])
  }

  @Test func kimiAndCursorRootsUseMD5OfWorkingDirectory() {
    let cwd = URL(fileURLWithPath: "/Users/onevcat/Sync/github/Prowl", isDirectory: true)
    let hash = "62c1e94d156560ededc10a672654f7ad"
    let kimi = AgentSessionProfile.profile(for: .kimi)
    #expect(kimi.candidateRoots(home, cwd, now, now).map(\.path) == ["/Users/me/.kimi/sessions/\(hash)"])
    #expect(kimi.fallbackRoots(home, cwd).map(\.path) == ["/Users/me/.kimi/sessions"])
    let cursor = AgentSessionProfile.profile(for: .cursor)
    #expect(cursor.candidateRoots(home, cwd, now, now).map(\.path) == ["/Users/me/.cursor/chats/\(hash)"])
    #expect(cursor.fallbackRoots(home, cwd).map(\.path) == ["/Users/me/.cursor/chats"])
  }

  @Test func geminiRootsPreferProjectsJSONSlugAndHash() throws {
    let temporaryHome = FileManager.default.temporaryDirectory
      .appending(path: "prowl-gemini-home-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: temporaryHome.appending(path: ".gemini"),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryHome) }
    let cwd = URL(fileURLWithPath: "/Users/onevcat/Sync/github/Prowl", isDirectory: true)
    try #"{"projects": {"/Users/onevcat/Sync/github/Prowl": "prowl"}}"#
      .write(to: temporaryHome.appending(path: ".gemini/projects.json"), atomically: true, encoding: .utf8)

    let roots = AgentSessionProfile.profile(for: .gemini).candidateRoots(temporaryHome, cwd, now, now)
    let paths = Set(roots.map(\.path))
    let sha = "a165a63702653924c088535c5594c435580d1ddeaf52f638d8a1fa830adf95e0"
    #expect(paths.contains(temporaryHome.appending(path: ".gemini/tmp/prowl/chats").path))
    #expect(paths.contains(temporaryHome.appending(path: ".gemini/tmp/\(sha)/chats").path))
    let fallback = AgentSessionProfile.profile(for: .gemini).fallbackRoots(temporaryHome, cwd)
    #expect(fallback.map(\.path) == [temporaryHome.appending(path: ".gemini/tmp").path])
  }

  // MARK: - Session-id grouping

  @Test func uniqueActiveCandidateAcceptsMultipleFilesOfOneSession() {
    let start = Date(timeIntervalSince1970: 1_000)
    let files = ["context.jsonl", "wire.jsonl", "state.json"].enumerated().map { index, name in
      AgentSessionCandidate(
        session: AgentSession(
          id: "fe8b1447",
          transcriptPath: URL(fileURLWithPath: "/tmp/session/\(name)"),
          source: .recentFile
        ),
        modifiedAt: Date(timeIntervalSince1970: 1_001 + TimeInterval(index))
      )
    }
    let unique = AgentSessionCandidate.uniqueActiveCandidate(files, processStartedAt: start)
    #expect(unique?.session.id == "fe8b1447")
    #expect(unique?.modifiedAt == Date(timeIntervalSince1970: 1_003))
  }

  @Test func fingerprintDoesNotApplyMarginBetweenFilesOfOneSession() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "prowl-same-session-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let content = #"{"message":{"content":"Refactor the authentication middleware without changing its API."}}"#
    let urls = [root.appending(path: "context.jsonl"), root.appending(path: "wire.jsonl")]
    for url in urls { try content.write(to: url, atomically: true, encoding: .utf8) }
    let candidates = urls.map { url in
      AgentSessionCandidate(
        session: AgentSession(id: "same-session", transcriptPath: url, source: .recentFile),
        modifiedAt: .now
      )
    }

    let match = AgentSessionFingerprintMatcher.bestMatch(
      activeText: "❯ Refactor the authentication middleware without changing its API.",
      candidates: candidates
    )
    #expect(match?.session.id == "same-session")
  }

  // MARK: - Pid-keyed artifacts

  @Test func copilotProcessLogYieldsRegisteredSession() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "prowl-copilot-\(UUID().uuidString)", directoryHint: .isDirectory)
    let logs = root.appending(path: "logs")
    let state = root.appending(path: "session-state")
    let id = "e7f43538-26a4-4dfd-a4af-06427bc9d69d"
    try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: state.appending(path: id), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: state.appending(path: "\(id)/events.jsonl").path, contents: Data())
    defer { try? FileManager.default.removeItem(at: root) }
    let log = """
      2026-07-11T02:58:34.100Z [INFO] Registering foreground session: 11111111-2222-3333-4444-555555555555
      2026-07-11T02:58:34.500Z [INFO] Unregistering foreground session: 11111111-2222-3333-4444-555555555555
      2026-07-11T02:58:34.928Z [INFO] Registering foreground session: \(id)
      """
    try log.write(to: logs.appending(path: "process-1783748855136-4242.log"), atomically: true, encoding: .utf8)

    let session = CopilotProcessLog.session(
      logsDirectory: logs,
      sessionStateDirectory: state,
      pid: 4242,
      processStartedAt: .now.addingTimeInterval(-60)
    )
    #expect(session?.id == id)
    #expect(session?.source == .processLog)
    #expect(session?.confidence == .exact)
    #expect(session?.transcriptPath?.path == state.appending(path: "\(id)/events.jsonl").path)

    let mismatch = CopilotProcessLog.session(
      logsDirectory: logs,
      sessionStateDirectory: state,
      pid: 9999,
      processStartedAt: .now.addingTimeInterval(-60)
    )
    #expect(mismatch == nil)
  }

  @Test func qwenRuntimeSidecarYieldsPidMatchedSession() throws {
    let projects = FileManager.default.temporaryDirectory
      .appending(path: "prowl-qwen-\(UUID().uuidString)", directoryHint: .isDirectory)
    let chats = projects.appending(path: "-Users-me-App/chats")
    try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: projects) }
    let processStartedAt = Date(timeIntervalSince1970: 1_783_800_000)
    let id = "019f4f1b-3650-7661-a56d-351f02f01139"
    try sidecarJSON(id: id, pid: 555, startedAt: processStartedAt.timeIntervalSince1970 + 5)
      .write(to: chats.appending(path: "\(id).runtime.json"), atomically: true, encoding: .utf8)
    try "{}".write(to: chats.appending(path: "\(id).jsonl"), atomically: true, encoding: .utf8)

    let session = QwenRuntimeStatus.session(projectsRoot: projects, pid: 555, processStartedAt: processStartedAt)
    #expect(session?.id == id)
    #expect(session?.source == .processLog)
    #expect(session?.confidence == .exact)
    // contentsOfDirectory resolves the /var → /private/var symlink; align both sides.
    #expect(
      session?.transcriptPath?.resolvingSymlinksInPath()
        == chats.appending(path: "\(id).jsonl").resolvingSymlinksInPath()
    )
    #expect(QwenRuntimeStatus.session(projectsRoot: projects, pid: 556, processStartedAt: processStartedAt) == nil)
  }

  @Test func qwenRuntimeSidecarRejectsStaleClaimsFromReusedPids() throws {
    let projects = FileManager.default.temporaryDirectory
      .appending(path: "prowl-qwen-stale-\(UUID().uuidString)", directoryHint: .isDirectory)
    let chats = projects.appending(path: "-Users-me-App/chats")
    try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: projects) }
    let processStartedAt = Date(timeIntervalSince1970: 1_783_800_000)

    // Sidecars survive quit/crash; a claim older than the live process's start
    // time belongs to a previous owner of the reused pid.
    let stale = "11111111-2222-3333-4444-555555555555"
    try sidecarJSON(id: stale, pid: 555, startedAt: processStartedAt.timeIntervalSince1970 - 3_600)
      .write(to: chats.appending(path: "\(stale).runtime.json"), atomically: true, encoding: .utf8)
    #expect(QwenRuntimeStatus.session(projectsRoot: projects, pid: 555, processStartedAt: processStartedAt) == nil)

    // Unknown schema versions are not ours to interpret.
    let futuristic = "66666666-7777-8888-9999-000000000000"
    try sidecarJSON(id: futuristic, pid: 555, startedAt: processStartedAt.timeIntervalSince1970 + 5, schema: 2)
      .write(to: chats.appending(path: "\(futuristic).runtime.json"), atomically: true, encoding: .utf8)
    #expect(QwenRuntimeStatus.session(projectsRoot: projects, pid: 555, processStartedAt: processStartedAt) == nil)
  }

  private func sidecarJSON(id: String, pid: Int, startedAt: TimeInterval, schema: Int = 1) -> String {
    #"{"schema_version":\#(schema),"pid":\#(pid),"session_id":"\#(id)","work_dir":"/Users/me/App","#
      + #""hostname":"test","started_at":\#(startedAt),"qwen_version":"0.23.0"}"#
  }

  @Test func qwenRootsNarrowToSanitizedProjectDirectory() {
    let cwd = URL(fileURLWithPath: "/private/tmp/prowl_556.enc", isDirectory: true)
    let qwen = AgentSessionProfile.profile(for: .qwen)
    #expect(
      qwen.candidateRoots(home, cwd, now, now).map(\.path)
        == ["/Users/me/.qwen/projects/-private-tmp-prowl-556-enc/chats"]
    )
    #expect(qwen.fallbackRoots(home, cwd).map(\.path) == ["/Users/me/.qwen/projects"])
  }

  // MARK: - Amp thread log parsing

  @Test func ampParsesOpenThreadLogPath() throws {
    let path = "/Users/me/.cache/amp/logs/threads/T-019f4fbf-040b-704b-8247-d4754f7dae6c.log"
    let session = try #require(AgentSessionPathParser.parse(path: path, agent: .amp))
    #expect(session.id == "T-019f4fbf-040b-704b-8247-d4754f7dae6c")
    #expect(AgentSessionPathParser.parse(path: "/Users/me/.cache/amp/logs/cli.log", agent: .amp) == nil)
  }

  // MARK: - OpenCode store

  @Test func openCodeStoreReturnsLifetimeCandidatesForDirectory() throws {
    let databaseURL = FileManager.default.temporaryDirectory
      .appending(path: "prowl-opencode-\(UUID().uuidString).db")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let schema = "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, time_updated INTEGER);"
    #expect(sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK)
    let threshold = Date(timeIntervalSince1970: 1_783_700_000)
    let rows = [
      "('ses_current', '/tmp/project', \(Int64((threshold.timeIntervalSince1970 + 60) * 1_000)))",
      "('ses_stale', '/tmp/project', \(Int64((threshold.timeIntervalSince1970 - 60) * 1_000)))",
      "('ses_other', '/tmp/other', \(Int64((threshold.timeIntervalSince1970 + 60) * 1_000)))",
    ]
    for row in rows {
      #expect(sqlite3_exec(database, "INSERT INTO session VALUES \(row);", nil, nil, nil) == SQLITE_OK)
    }

    let candidates = OpenCodeSessionStore.candidates(
      databaseURL: databaseURL,
      directory: "/tmp/project",
      modifiedAfter: threshold
    )
    #expect(candidates.map(\.session.id) == ["ses_current"])
    #expect(candidates.first?.session.source == .storeRecord)
  }
}
