import Foundation
import Testing

@testable import supacode

struct HandoffTranscriptResolverTests {
  private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "handoff-transcript-resolver-tests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  @Test func claudeProjectDirectoryNameMatchesClaudeCodeConvention() {
    let rootURL = URL(fileURLWithPath: "/Users/mikoto/.prowl/repos/Prowl/feature's branch", isDirectory: true)

    let name = HandoffTranscriptResolver.claudeProjectDirectoryName(for: rootURL)

    #expect(name == "-Users-mikoto--prowl-repos-Prowl-feature-s-branch")
  }

  @Test func doesNotResolveAmbiguousClaudeTranscriptForProjectDirectory() throws {
    let home = try makeTempRoot()
    defer { remove(home) }
    let rootURL = URL(fileURLWithPath: "/Users/mikoto/Documents/Repos/github/Prowl", isDirectory: true)
    let projectDirectory =
      home
      .appending(path: ".claude", directoryHint: .isDirectory)
      .appending(path: "projects", directoryHint: .isDirectory)
      .appending(path: HandoffTranscriptResolver.claudeProjectDirectoryName(for: rootURL), directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
    let old = projectDirectory.appending(path: "old.jsonl")
    let latest = projectDirectory.appending(path: "latest.jsonl")
    try """
    {"type":"mode","sessionId":"old-session"}
    {"type":"user","cwd":"/Users/mikoto/Documents/Repos/github/Prowl","sessionId":"old-session"}
    """.write(to: old, atomically: true, encoding: .utf8)
    try """
    {"type":"mode","sessionId":"new-session"}
    {"type":"user","cwd":"/Users/mikoto/Documents/Repos/github/Prowl","sessionId":"new-session"}
    """.write(to: latest, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: old.path)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: latest.path)

    let resolved = HandoffTranscriptResolver(homeDirectory: home).resolve(agent: "claude", rootURL: rootURL)

    #expect(resolved == nil)
  }

  @Test func resolvesLatestCodexTranscriptMatchingCWD() throws {
    let home = try makeTempRoot()
    defer { remove(home) }
    let rootURL = home.appending(path: "Project", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    let sessions =
      home
      .appending(path: ".codex", directoryHint: .isDirectory)
      .appending(path: "sessions/2026/06/17", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let other = sessions.appending(path: "rollout-other.jsonl")
    let matched = sessions.appending(path: "rollout-matched.jsonl")
    try """
    {"timestamp":"2026-06-17T00:00:00Z","type":"session_meta","payload":{"id":"other","cwd":"/tmp/Other"}}
    """.write(to: other, atomically: true, encoding: .utf8)
    let rootPath = rootURL.path(percentEncoded: false)
    try """
    {"timestamp":"2026-06-17T00:00:00Z","type":"session_meta","payload":{"id":"matched","cwd":"\(rootPath)"}}
    {"timestamp":"2026-06-17T00:00:01Z","type":"event_msg","payload":{"type":"agent_message","message":"working"}}
    """.write(to: matched, atomically: true, encoding: .utf8)

    let resolved = HandoffTranscriptResolver(homeDirectory: home).resolve(agent: "codex", rootURL: rootURL)

    #expect(resolved?.sessionID == "matched")
    #expect(resolved?.source == "codex-rollout-jsonl")
    #expect(resolved?.confidence == "medium")
    #expect(resolved?.transcriptPath.hasSuffix("/rollout-matched.jsonl") == true)
    #expect(FileManager.default.fileExists(atPath: resolved?.transcriptPath ?? ""))
  }

  @Test func codexResolverDoesNotGuessBetweenSessionsWithTheSameCWD() throws {
    let home = try makeTempRoot()
    defer { remove(home) }
    let rootURL = home.appending(path: "Project", directoryHint: .isDirectory)
    let sessions = home.appending(path: ".codex/sessions/2026/06/17", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let rootPath = rootURL.path(percentEncoded: false)
    for sessionID in ["pane-a", "pane-b"] {
      try """
      {"type":"session_meta","payload":{"id":"\(sessionID)","cwd":"\(rootPath)"}}
      """.write(
        to: sessions.appending(path: "\(sessionID).jsonl"),
        atomically: true,
        encoding: .utf8
      )
    }

    let resolved = HandoffTranscriptResolver(homeDirectory: home).resolve(agent: "codex", rootURL: rootURL)

    #expect(resolved == nil)
  }

  @Test func codexResolverDoesNotMatchDifferentCWD() throws {
    let home = try makeTempRoot()
    defer { remove(home) }
    let rootURL = home.appending(path: "Project", directoryHint: .isDirectory)
    let sessions =
      home
      .appending(path: ".codex", directoryHint: .isDirectory)
      .appending(path: "sessions/2026/06/17", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    let rollout = sessions.appending(path: "rollout-other.jsonl")
    try """
    {"timestamp":"2026-06-17T00:00:00Z","type":"session_meta","payload":{"id":"other","cwd":"/tmp/Other"}}
    """.write(to: rollout, atomically: true, encoding: .utf8)

    let resolved = HandoffTranscriptResolver(homeDirectory: home).resolve(agent: "codex", rootURL: rootURL)

    #expect(resolved == nil)
  }
}
