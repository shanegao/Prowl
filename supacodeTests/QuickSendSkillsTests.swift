import Foundation
import Testing

@testable import supacode

struct QuickSendSkillsTests {
  @Test func configuredDirectoryWinsAndExpandsTilde() {
    let dirs = QuickSendSkills.directories(
      for: .codex, configured: "~/Dropbox/skills",
      workingDirectory: URL(fileURLWithPath: "/tmp/wt", isDirectory: true))
    let expected = URL(
      fileURLWithPath: ("~/Dropbox/skills" as NSString).expandingTildeInPath, isDirectory: true)
    // Explicit override wins and is the only directory — no global/local fallback.
    #expect(dirs == [expected])
  }

  @Test func fallsBackToGlobalAndProjectLocalWhenUnset() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let worktree = URL(fileURLWithPath: "/tmp/wt", isDirectory: true)
    let dirs = QuickSendSkills.directories(for: .claude, configured: "", workingDirectory: worktree)
    #expect(
      dirs.map { $0.path(percentEncoded: false) } == [
        home.appending(path: ".claude/skills", directoryHint: .isDirectory)
          .path(percentEncoded: false),
        worktree.appending(path: ".claude/skills", directoryHint: .isDirectory)
          .path(percentEncoded: false),
      ]
    )
  }

  @Test func globalOnlyWhenNoWorkingDirectory() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    // Whitespace-only configured is treated as unset; no worktree → global only.
    let dirs = QuickSendSkills.directories(for: .codex, configured: "  ", workingDirectory: nil)
    #expect(
      dirs.map { $0.path(percentEncoded: false) } == [
        home.appending(path: ".codex/skills", directoryHint: .isDirectory).path(percentEncoded: false)
      ]
    )
  }

  @Test func noAgentAndNoSettingResolvesToEmpty() {
    #expect(QuickSendSkills.directories(for: nil, configured: "", workingDirectory: nil).isEmpty)
  }

  @Test func skillNamesAcrossDirectoriesDedupeAndSort() throws {
    let base = FileManager.default.temporaryDirectory
      .appending(path: "QuickSendSkillsTest-\(UUID().uuidString)", directoryHint: .isDirectory)
    let global = base.appending(path: "global", directoryHint: .isDirectory)
    let local = base.appending(path: "local", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }
    for sub in ["alpha", "shared"] {
      try FileManager.default.createDirectory(
        at: global.appending(path: sub, directoryHint: .isDirectory), withIntermediateDirectories: true)
    }
    for sub in ["beta", "shared"] {
      try FileManager.default.createDirectory(
        at: local.appending(path: sub, directoryHint: .isDirectory), withIntermediateDirectories: true)
    }
    // "shared" exists in both → once; result is the sorted union.
    #expect(QuickSendSkills.skillNames(inAny: [global, local]) == ["alpha", "beta", "shared"])
  }

  @Test func fileReferencesIncludeDirectoriesAndSkipGeneratedFolders() throws {
    let base = FileManager.default.temporaryDirectory
      .appending(path: "QuickSendFilesTest-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }

    let source = base.appending(path: "Sources/App", directoryHint: .isDirectory)
    let generated = base.appending(path: "node_modules/pkg", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
    try "view".write(to: source.appending(path: "QuickSendView.swift"), atomically: true, encoding: .utf8)
    try "dep".write(to: generated.appending(path: "index.js"), atomically: true, encoding: .utf8)

    let references = QuickSendFileReferences.references(in: base)

    // Directories are offered alongside files (each carries `isDirectory`); the
    // ignored `node_modules` folder is neither offered nor descended into, so its
    // `index.js` never appears. Order is the indexer's path-sorted output.
    #expect(
      references == [
        QuickSendFileReference(relativePath: "Sources", isDirectory: true),
        QuickSendFileReference(relativePath: "Sources/App", isDirectory: true),
        QuickSendFileReference(relativePath: "Sources/App/QuickSendView.swift", isDirectory: false),
      ])
  }

  @Test func fileReferenceMatchesPreferFileNamesOverParentPathMatches() {
    let references = [
      QuickSendFileReference(relativePath: "Sources/App/QuickSendView.swift"),
      QuickSendFileReference(relativePath: "QuickSend/Notes.md"),
      QuickSendFileReference(relativePath: "Sources/App/Other.swift"),
    ]

    let matches = QuickSendFileReferences.rankedMatches(in: references, query: "quick")

    #expect(
      matches.map(\.relativePath) == [
        "Sources/App/QuickSendView.swift",
        "QuickSend/Notes.md",
      ])
  }

  @Test func fileReferenceRootPrefersGitRootForNestedWorkingDirectory() throws {
    let base = FileManager.default.temporaryDirectory
      .appending(path: "QuickSendRootTest-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }

    let nested = base.appending(path: "Sources/App", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: base.appending(path: ".git", directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    #expect(
      QuickSendFileReferences.rootDirectory(
        workingDirectory: nested,
        fallbackWorktreePath: "/tmp/other"
      ) == base.standardizedFileURL
    )
  }

  @Test func fileReferenceRootFallsBackToOwningWorktreeForPlainFolders() throws {
    let base = FileManager.default.temporaryDirectory
      .appending(path: "QuickSendPlainRootTest-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }

    let nested = base.appending(path: "notes/inbox", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    #expect(
      QuickSendFileReferences.rootDirectory(
        workingDirectory: nested,
        fallbackWorktreePath: base.path(percentEncoded: false)
      ) == base
    )
  }

  @Test func rankedMatchesEmptyOrWhitespaceQueryReturnsPrefixInInputOrder() {
    let references = [
      QuickSendFileReference(relativePath: "b.swift"),
      QuickSendFileReference(relativePath: "a.swift"),
    ]
    // Typing just `@` (empty query) is the popup's first render: show the head of the
    // index in its existing order, not a ranked/sorted subset. Whitespace trims to empty.
    #expect(
      QuickSendFileReferences.rankedMatches(in: references, query: "").map(\.relativePath)
        == ["b.swift", "a.swift"])
    #expect(
      QuickSendFileReferences.rankedMatches(in: references, query: "   ").map(\.relativePath)
        == ["b.swift", "a.swift"])
    // The prefix honours `limit`.
    #expect(
      QuickSendFileReferences.rankedMatches(in: references, query: "", limit: 1).map(\.relativePath)
        == ["b.swift"])
  }

  @Test func rankedMatchesReturnsEmptyWhenNothingMatches() {
    let references = [QuickSendFileReference(relativePath: "Sources/App/View.swift")]
    #expect(QuickSendFileReferences.rankedMatches(in: references, query: "zzznomatch").isEmpty)
  }

  @Test func rankedMatchesOrderByScoreBucketHighToLow() {
    let references = [
      QuickSendFileReference(relativePath: "x/view-y/z.txt"),  // path contains (100)
      QuickSendFileReference(relativePath: "Overview.swift"),  // file-name contains (200)
      QuickSendFileReference(relativePath: "view"),  // exact file name (400)
      QuickSendFileReference(relativePath: "view/c.swift"),  // path prefix (150)
      QuickSendFileReference(relativePath: "ViewModel.swift"),  // file-name prefix (300)
    ]
    let matches = QuickSendFileReferences.rankedMatches(in: references, query: "view")
    #expect(
      matches.map(\.relativePath) == [
        "view",  // 400
        "ViewModel.swift",  // 300
        "Overview.swift",  // 200
        "view/c.swift",  // 150
        "x/view-y/z.txt",  // 100
      ])
  }

  @Test func rankedMatchesBreakScoreTiesByShorterPath() {
    let references = [
      QuickSendFileReference(relativePath: "a/b/View.swift"),  // file-name prefix, longest path
      QuickSendFileReference(relativePath: "View.swift"),  // file-name prefix, shortest path
      QuickSendFileReference(relativePath: "z/View.swift"),  // file-name prefix, mid path
    ]
    // All share the file-name-prefix bucket (300); ties break by shorter relativePath.
    let matches = QuickSendFileReferences.rankedMatches(in: references, query: "view")
    #expect(matches.map(\.relativePath) == ["View.swift", "z/View.swift", "a/b/View.swift"])
  }

  @Test func fileReferenceDerivesFileNameAndParentPath() {
    let topLevel = QuickSendFileReference(relativePath: "README.md")
    #expect(topLevel.fileName == "README.md")
    #expect(topLevel.parentPath == nil)  // no subtitle for a root-level file

    let nested = QuickSendFileReference(relativePath: "Sources/App/Main View.swift")
    #expect(nested.fileName == "Main View.swift")  // spaces preserved
    #expect(nested.parentPath == "Sources/App")
  }

  @Test func fileReferenceRootUsesFallbackWhenNoWorkingDirectory() {
    #expect(
      QuickSendFileReferences.rootDirectory(workingDirectory: nil, fallbackWorktreePath: "/tmp/wt")
        == URL(fileURLWithPath: "/tmp/wt", isDirectory: true))
    // Nothing to index when neither a working directory nor a fallback is known.
    #expect(
      QuickSendFileReferences.rootDirectory(workingDirectory: nil, fallbackWorktreePath: nil) == nil)
  }
}
