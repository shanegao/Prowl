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

  private let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)

  // MARK: - replaceAutogen (pure)

  @Test func replaceAutogenSwapsBlockAndKeepsProse() {
    let original = """
      # Handoff

      ## Objective
      Ship the login redesign.

      \(HandoffStore.beginMarker)
      old appendix
      \(HandoffStore.endMarker)
      """
    let block = "\(HandoffStore.beginMarker)\nNEW APPENDIX\n\(HandoffStore.endMarker)"

    let result = HandoffStore.replaceAutogen(in: original, with: block)

    #expect(result.contains("Ship the login redesign."))
    #expect(result.contains("NEW APPENDIX"))
    #expect(!result.contains("old appendix"))
    // Exactly one AUTOGEN block survives.
    #expect(result.components(separatedBy: HandoffStore.beginMarker).count - 1 == 1)
  }

  @Test func replaceAutogenAppendsWhenNoMarkers() {
    let original = "# Handoff\n\n## Objective\nDo the thing.\n"
    let block = "\(HandoffStore.beginMarker)\nappendix\n\(HandoffStore.endMarker)"

    let result = HandoffStore.replaceAutogen(in: original, with: block)

    #expect(result.contains("Do the thing."))
    #expect(result.contains(HandoffStore.beginMarker))
    #expect(result.contains("appendix"))
  }

  @Test func replaceAutogenToleratesMissingEndMarker() {
    let original = "intro\n\(HandoffStore.beginMarker)\ndangling"
    let block = "\(HandoffStore.beginMarker)\nfresh\n\(HandoffStore.endMarker)"

    let result = HandoffStore.replaceAutogen(in: original, with: block)

    #expect(result.contains("intro"))
    #expect(result.contains("fresh"))
    #expect(!result.contains("dangling"))
  }

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

  // MARK: - save (filesystem; non-git root)

  @Test func saveSeedsArtifactWithAppendixForNonGitRoot() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    let result = try store.save(outgoingAgent: "codex", note: "wip", now: fixedDate)

    #expect(FileManager.default.fileExists(atPath: store.currentURL.path(percentEncoded: false)))
    let content = try String(contentsOf: store.currentURL, encoding: .utf8)
    #expect(content.contains("## Objective"))  // template prose preserved
    #expect(content.contains("Outgoing agent (detected): codex"))
    #expect(content.contains("(not a git repo)"))
    #expect(result.outgoingAgent == "codex")
    // A non-git root contributes no git repos summary count.
    #expect(result.totalChangedFiles == 0)
  }

  @Test func saveTwiceDoesNotDuplicateAutogenBlock() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let store = HandoffStore(rootURL: root)

    _ = try store.save(outgoingAgent: "codex", note: nil, now: fixedDate)
    _ = try store.save(outgoingAgent: "claude", note: nil, now: fixedDate)

    let content = try String(contentsOf: store.currentURL, encoding: .utf8)
    #expect(content.components(separatedBy: HandoffStore.beginMarker).count - 1 == 1)
    // Latest agent wins in the appendix.
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
    #expect(updated.contains("Finish the checkout flow."))
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
    // current.md remains for the receiving agent.
    #expect(FileManager.default.fileExists(atPath: store.currentURL.path(percentEncoded: false)))
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
