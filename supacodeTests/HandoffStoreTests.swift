import Foundation
import Testing

@testable import supacode

struct HandoffStoreTests {
  // MARK: - Helpers

  private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "handoff-tests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private func runGit(_ arguments: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", directory.path(percentEncoded: false)] + arguments
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw NSError(
        domain: "HandoffStoreTests.Git",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: String(data: errorOutput, encoding: .utf8) ?? "git failed"]
      )
    }
    return String(data: output, encoding: .utf8) ?? ""
  }

  private let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)

  // MARK: - parseShortstat (pure)

  @Test func parseShortstatExtractsInsertionsAndDeletions() {
    let (insertions, deletions) = HandoffStore.parseShortstat(
      " 3 files changed, 120 insertions(+), 14 deletions(-)"
    )
    #expect(insertions == 120)
    #expect(deletions == 14)
  }

  @Test func parseShortstatHandlesInsertionsOnly() {
    let (insertions, deletions) = HandoffStore.parseShortstat(" 1 file changed, 5 insertions(+)")
    #expect(insertions == 5)
    #expect(deletions == 0)
  }

  @Test func parseShortstatHandlesEmpty() {
    let (insertions, deletions) = HandoffStore.parseShortstat("")
    #expect(insertions == 0)
    #expect(deletions == 0)
  }

  // MARK: - preparedArtifact (pure)

  @Test func preparedArtifactAcceptsPlainDocument() {
    let reply = """
      # Handoff

      ## Objective
      Ship it.

      ## Current State
      Green.

      ## Next Steps
      1. Review.
      """
    #expect(HandoffStore.preparedArtifact(fromAgentReply: reply) == reply + "\n")
  }

  @Test func preparedArtifactUnwrapsCodeFenceAndDropsPreamble() {
    let reply = """
      Sure! Here's the updated handoff:

      ```markdown
      # Handoff

      ## Objective
      Ship it.

      ## Current State
      Green.

      ## Next Steps
      1. Review.
      ```
      """
    let artifact = HandoffStore.preparedArtifact(fromAgentReply: reply)
    #expect(artifact?.hasPrefix("# Handoff") == true)
    #expect(artifact?.contains("```") == false)
    #expect(artifact?.contains("Sure!") == false)
  }

  @Test func preparedArtifactRejectsUnusableReplies() {
    #expect(HandoffStore.preparedArtifact(fromAgentReply: "") == nil)
    #expect(HandoffStore.preparedArtifact(fromAgentReply: "I could not update the file.") == nil)
    // Missing required sections.
    #expect(HandoffStore.preparedArtifact(fromAgentReply: "# Handoff\n\n## Objective\nOnly this.") == nil)
    // Echoing the seeded template back is not a prepared artifact.
    #expect(HandoffStore.preparedArtifact(fromAgentReply: HandoffStore.template) == nil)
  }

  @Test func applyPreparationReplyTranscribesIntoCurrent() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    let reply = """
      # Handoff

      ## Objective
      Ship it.

      ## Current State
      Green.

      ## Next Steps
      1. Review.
      """
    #expect(store.applyPreparationReply(reply, now: fixedDate))
    let content = try String(contentsOf: store.currentURL, encoding: .utf8)
    #expect(content == reply + "\n")

    // An unusable reply leaves the transcribed artifact untouched.
    #expect(store.applyPreparationReply("nope", now: fixedDate) == false)
    let unchanged = try String(contentsOf: store.currentURL, encoding: .utf8)
    #expect(unchanged == reply + "\n")
  }

  @Test func applyPreparationReplyArchivesPreviousArtifact() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)
    let previous = "# Handoff\n\n## Objective\nEarlier notes worth keeping.\n"
    try FileManager.default.createDirectory(at: store.handoffDirectory, withIntermediateDirectories: true)
    try previous.write(to: store.currentURL, atomically: true, encoding: .utf8)

    let reply = """
      # Handoff

      ## Objective
      Ship it.

      ## Current State
      Green.

      ## Next Steps
      1. Review.
      """
    #expect(store.applyPreparationReply(reply, now: fixedDate))

    let archived = try FileManager.default.contentsOfDirectory(
      at: store.archiveDirectory,
      includingPropertiesForKeys: nil
    )
    let backup = try #require(archived.first { $0.lastPathComponent.hasSuffix("-preparation-backup.md") })
    #expect(archived.count == 1)
    #expect(try String(contentsOf: backup, encoding: .utf8) == previous)
    #expect(try String(contentsOf: store.currentURL, encoding: .utf8) == reply + "\n")
  }

  @Test func applyPreparationReplySkipsArchiveForTemplateOrMissingArtifact() throws {
    let reply = """
      # Handoff

      ## Objective
      Ship it.

      ## Current State
      Green.

      ## Next Steps
      1. Review.
      """

    // First-ever preparation: no current.md to snapshot.
    let freshRoot = try makeTempRoot()
    defer { remove(freshRoot) }
    let freshStore = HandoffStore(rootURL: freshRoot)
    #expect(freshStore.applyPreparationReply(reply, now: fixedDate))
    #expect(!FileManager.default.fileExists(atPath: freshStore.archiveDirectory.path(percentEncoded: false)))

    // A never-edited seeded template carries no prose worth archiving.
    let seededRoot = try makeTempRoot()
    defer { remove(seededRoot) }
    let seededStore = HandoffStore(rootURL: seededRoot)
    try seededStore.ensureScaffold()
    #expect(seededStore.applyPreparationReply(reply, now: fixedDate))
    let archived = try FileManager.default.contentsOfDirectory(
      at: seededStore.archiveDirectory,
      includingPropertiesForKeys: nil
    )
    #expect(archived.isEmpty)
  }

  // MARK: - save (filesystem; non-git root)

  @Test func scaffoldSelfIgnoresHandoffInGitRepository() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    _ = try runGit(["init", "--quiet"], in: root)
    let store = HandoffStore(rootURL: root)

    try store.ensureScaffold()

    let ignore = try String(contentsOf: store.ignoreURL, encoding: .utf8)
    #expect(ignore == "*\n")
    #expect(try runGit(["status", "--porcelain"], in: root).isEmpty)
  }

  @Test func saveKeepsNonASCIIChangedFileNamesReadable() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    _ = try runGit(["init", "--quiet"], in: root)
    try "draft".write(to: root.appending(path: "交接记录.md"), atomically: true, encoding: .utf8)
    let store = HandoffStore(rootURL: root)

    let result = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)

    #expect(result.changedFiles.contains { $0.contains("交接记录.md") })
    let context = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(context.contains("交接记录.md"))
  }

  @Test func saveSeedsArtifactWithAppendixForNonGitRoot() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    let result = try store.save(outgoingAgent: "codex", note: "wip", now: fixedDate)

    #expect(FileManager.default.fileExists(atPath: store.currentURL.path(percentEncoded: false)))
    let current = try String(contentsOf: store.currentURL, encoding: .utf8)
    #expect(current.contains("## Objective"))
    let context = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(context.contains("Outgoing agent (detected): codex"))
    #expect(context.contains("(not a git repo)"))
    #expect(result.outgoingAgent == "codex")
    // A non-git root contributes no git repos summary count.
    #expect(result.totalChangedFiles == 0)
  }

  @Test func saveWritesSessionContextExcerpt() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)
    let sessionContext = HandoffStore.SessionContext(
      agent: "codex",
      sessionID: "codex-session",
      paneID: "pane-123",
      paneTitle: "codex",
      source: "terminal-scrollback",
      confidence: "fallback",
      transcriptPath: "/tmp/codex.jsonl",
      excerptText: "Implemented handoff session context.\nNext: run tests."
    )

    let result = try store.save(
      outgoingAgent: "codex",
      sessionContext: sessionContext,
      note: nil,
      now: fixedDate
    )

    let session = try #require(result.sessionContext)
    #expect(session.excerptPath?.hasPrefix("handoff/sessions/") == true)
    let excerptPath = try #require(session.excerptPath?.replacing("handoff/", with: ""))
    let excerptURL = store.handoffDirectory.appending(path: excerptPath)
    let excerpt = try String(contentsOf: excerptURL, encoding: .utf8)
    #expect(excerpt.contains("# Handoff Session Context"))
    #expect(excerpt.contains("Session ID: codex-session"))
    #expect(excerpt.contains("Native transcript: /tmp/codex.jsonl"))
    #expect(excerpt.contains("Implemented handoff session context."))

    let context = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(context.contains("Session Context:"))
    #expect(context.contains("Session ID: codex-session"))
    #expect(context.contains(".prowl/handoff/sessions/"))
  }

  @Test func saveWritesUniqueSessionContextExcerptsForSameTimestamp() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)
    let sessionContext = HandoffStore.SessionContext(
      agent: "codex",
      paneID: "pane-123",
      paneTitle: "codex",
      source: "terminal-scrollback",
      confidence: "fallback",
      excerptText: "first excerpt"
    )

    let first = try store.save(
      outgoingAgent: "codex",
      sessionContext: sessionContext,
      note: nil,
      now: fixedDate
    )
    let second = try store.save(
      outgoingAgent: "codex",
      sessionContext: sessionContext,
      note: nil,
      now: fixedDate
    )

    let firstPath = try #require(first.sessionContext?.excerptPath)
    let secondPath = try #require(second.sessionContext?.excerptPath)
    #expect(firstPath != secondPath)
    #expect(secondPath.hasSuffix("-2.md"))

    let firstURL = store.handoffDirectory.appending(
      path: firstPath.replacingOccurrences(of: "handoff/", with: "")
    )
    let secondURL = store.handoffDirectory.appending(
      path: secondPath.replacingOccurrences(of: "handoff/", with: "")
    )
    #expect(FileManager.default.fileExists(atPath: firstURL.path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: secondURL.path(percentEncoded: false)))
  }
  @Test func reserveFileURLIsExclusiveAcrossConcurrentCalls() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let directory = root.appending(path: "sessions", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let reserved = try await withThrowingTaskGroup(of: URL.self, returning: [URL].self) { group in
      for _ in 0..<40 {
        group.addTask {
          try HandoffStore.reserveFileURL(in: directory, stem: "same", fileExtension: "md")
        }
      }
      var urls: [URL] = []
      for try await url in group {
        urls.append(url)
      }
      return urls
    }

    #expect(Set(reserved).count == 40)
    #expect(reserved.allSatisfy { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })
  }

  @Test func saveTwiceReplacesGeneratedContext() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    _ = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)
    _ = try store.save(outgoingAgent: "claude", note: nil, now: fixedDate)

    let content = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(content.contains("Outgoing agent (detected): claude"))
    #expect(!content.contains("Outgoing agent (detected): codex"))
  }

  @Test func savePreservesEditedProse() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    _ = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)
    // Simulate the agent editing the semantic section.
    var content = try String(contentsOf: store.currentURL, encoding: .utf8)
    content = content.replacingOccurrences(
      of: "## Objective\n<!-- one-paragraph task goal; stable across the whole run -->",
      with: "## Objective\nFinish the checkout flow."
    )
    try content.write(to: store.currentURL, atomically: true, encoding: .utf8)

    _ = try store.save(outgoingAgent: "claude", note: nil, now: fixedDate)

    let updated = try String(contentsOf: store.currentURL, encoding: .utf8)
    #expect(updated == content)
    let context = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(context.contains("Outgoing agent (detected): claude"))
  }

  @Test func saveNeverRewritesCurrentArtifactAfterScaffold() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)
    try store.ensureScaffold()
    let prose = "# Handoff\n\n## Objective\nPreserve this concurrent objective.\n"
    try prose.write(to: store.currentURL, atomically: true, encoding: .utf8)

    _ = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)

    let updated = try String(contentsOf: store.currentURL, encoding: .utf8)
    #expect(updated == prose)
    let context = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(context.contains("Outgoing agent (detected): codex"))
  }

  // MARK: - log + archive

  @Test func appendLogGrowsAndArchiveCopies() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    _ = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)
    try store.appendLog("codex → claude", now: fixedDate)

    let log = try String(contentsOf: store.logURL, encoding: .utf8)
    #expect(log.contains("codex → claude"))
    #expect(log.split(separator: "\n").filter { $0.hasPrefix("- ") }.count >= 2)

    let archivedRelative = try store.archiveCurrent(from: "codex", toAgent: "claude", now: fixedDate)
    #expect(archivedRelative != nil)
    #expect(archivedRelative?.hasPrefix("handoff/archive/") == true)
    #expect(archivedRelative?.contains("codex-to-claude") == true)
    let archiveURL = store.handoffDirectory.appending(
      path: try #require(archivedRelative).replacing("handoff/", with: "")
    )
    let archive = try String(contentsOf: archiveURL, encoding: .utf8)
    #expect(archive.contains("## Objective"))
    #expect(archive.contains("# Handoff Context (generated)"))
    // current.md remains for the receiving agent.
    #expect(FileManager.default.fileExists(atPath: store.currentURL.path(percentEncoded: false)))
  }

  @Test func appendLogPreservesConcurrentEntries() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)
    let date = fixedDate

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<40 {
        group.addTask {
          try store.appendLog("event=\(index)", now: date)
        }
      }
      try await group.waitForAll()
    }

    let log = try String(contentsOf: store.logURL, encoding: .utf8)
    let entries = log.split(separator: "\n").filter { $0.hasPrefix("- ") }
    #expect(entries.count == 40)
    for index in 0..<40 {
      #expect(entries.contains { $0.contains("event=\(index)") })
    }
  }

  @Test func archiveCurrentKeepsExistingSameTimestampArchives() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    _ = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)
    let first = try #require(try store.archiveCurrent(from: "codex", toAgent: "claude", now: fixedDate))
    let second = try #require(try store.archiveCurrent(from: "codex", toAgent: "claude", now: fixedDate))

    #expect(first != second)
    #expect(first.hasSuffix(".md"))
    #expect(second.hasSuffix("-2.md"))

    let firstURL = store.handoffDirectory.appending(
      path: first.replacingOccurrences(of: "handoff/", with: "")
    )
    let secondURL = store.handoffDirectory.appending(
      path: second.replacingOccurrences(of: "handoff/", with: "")
    )
    #expect(FileManager.default.fileExists(atPath: firstURL.path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: secondURL.path(percentEncoded: false)))
  }

  @Test func readStatusReportsExistenceAndLastLog() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    let before = store.readStatus()
    #expect(before.exists == false)

    _ = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)
    let after = store.readStatus()
    #expect(after.exists == true)
    #expect(after.lastLogLine?.contains("save") == true)
  }
}
