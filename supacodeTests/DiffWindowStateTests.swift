import Foundation
import Testing
import YiTong

@testable import supacode

@MainActor
struct DiffWindowStateTests {
  @Test func evictedCacheRemovesEntriesNotInFileIDs() {
    let cache = [
      "a.swift": DiffDocument(files: [], title: "a"),
      "b.swift": DiffDocument(files: [], title: "b"),
    ]
    let result = DiffWindowState.evictedCache(cache, keeping: ["a.swift"])
    #expect(result.keys.sorted() == ["a.swift"])
  }

  @Test func resolvedSelectionKeepsCurrentWhenItsDocumentIsCached() {
    let current = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let other = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let doc = DiffDocument(files: [], title: "a")
    let result = DiffWindowState.resolvedSelection(
      current: current,
      files: [other, current],
      cache: ["a.swift": doc]
    )
    #expect(result.file == current)
    #expect(result.document == doc)
  }

  @Test func resolvedSelectionFallsBackToFirstFileWhenCurrentHasNoCachedDocument() {
    let current = DiffChangedFile(status: .modified, oldPath: "removed.swift", newPath: "removed.swift")
    let first = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let doc = DiffDocument(files: [], title: "a")
    let result = DiffWindowState.resolvedSelection(
      current: current,
      files: [first],
      cache: ["a.swift": doc]
    )
    #expect(result.file == first)
    #expect(result.document == doc)
  }

  @Test func resolvedSelectionPicksFirstFileWhenNoneSelected() {
    let first = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let second = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let doc = DiffDocument(files: [], title: "a")
    let result = DiffWindowState.resolvedSelection(
      current: nil,
      files: [first, second],
      cache: ["a.swift": doc]
    )
    #expect(result.file == first)
    #expect(result.document == doc)
  }

  @Test func resolvedSelectionReturnsNilWhenNoFiles() {
    let result = DiffWindowState.resolvedSelection(current: nil, files: [], cache: [:])
    #expect(result.file == nil)
    #expect(result.document == nil)
  }

  @Test func loadAllFilesPopulatesCacheAndAutoSelectsFirstFile() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let docs = [
      "a.swift": DiffDocument(files: [], title: "a"),
      "b.swift": DiffDocument(files: [], title: "b"),
    ]
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB] },
      loadDiffDocument: { file, _ in docs[file.id]! }
    )

    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))

    #expect(state.changedFiles == [fileA, fileB])
    #expect(state.selectedFile == fileA)
    #expect(state.diffDocument == docs["a.swift"])
    #expect(!state.isLoadingFiles)
  }

  @Test func loadAllFilesPreservesSelectionWhenStillPresent() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let docs = [
      "a.swift": DiffDocument(files: [], title: "a"),
      "b.swift": DiffDocument(files: [], title: "b"),
    ]
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB] },
      loadDiffDocument: { file, _ in docs[file.id]! }
    )
    state.selectedFile = fileB

    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))

    #expect(state.selectedFile == fileB)
    #expect(state.diffDocument == docs["b.swift"])
  }

  @Test func loadAllFilesClearsSelectionWhenFileRemoved() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let removed = DiffChangedFile(status: .modified, oldPath: "removed.swift", newPath: "removed.swift")
    let docs = ["a.swift": DiffDocument(files: [], title: "a")]
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA] },
      loadDiffDocument: { file, _ in docs[file.id]! }
    )
    state.selectedFile = removed

    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))

    #expect(state.selectedFile == fileA)
    #expect(state.diffDocument == docs["a.swift"])
  }
}
