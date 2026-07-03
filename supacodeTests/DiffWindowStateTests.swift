import Clocks
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

  @Test func selectFileMarksRenderingWhenDocumentIsCached() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let docA = DiffDocument(files: [], title: "a")
    let docB = DiffDocument(files: [], title: "b")
    let clock = TestClock()
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB] },
      loadDiffDocument: { file, _ in file.id == "a.swift" ? docA : docB },
      clock: clock
    )
    // Seed documentCache via the public loading path (auto-selects fileA).
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    state.markDiffRendered()

    state.selectFile(fileB)
    await advanceSelectDebounce(clock)

    #expect(state.isRenderingDiff)
    #expect(state.diffDocument == docB)
  }

  @Test func selectFileDoesNotMarkRenderingWhenDocumentIsUnchanged() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let sharedDoc = DiffDocument(files: [], title: "same")
    let clock = TestClock()
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB] },
      loadDiffDocument: { _, _ in sharedDoc },
      clock: clock
    )
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    state.markDiffRendered()

    state.selectFile(fileB)
    await advanceSelectDebounce(clock)

    #expect(!state.isRenderingDiff)
  }

  @Test func loadAllFilesMarksRenderingWhenAutoSelectedDocumentArrives() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let docA = DiffDocument(files: [], title: "a")
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA] },
      loadDiffDocument: { _, _ in docA }
    )

    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))

    #expect(state.isRenderingDiff)
  }

  @Test func selectFileDoesNotUpdateDocumentBeforeDebounceSettles() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let docA = DiffDocument(files: [], title: "a")
    let docB = DiffDocument(files: [], title: "b")
    let clock = TestClock()
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB] },
      loadDiffDocument: { file, _ in file.id == "a.swift" ? docA : docB },
      clock: clock
    )
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    state.markDiffRendered()

    state.selectFile(fileB)
    await Task.yield()

    #expect(state.diffDocument == docA)
    #expect(!state.isRenderingDiff)
  }

  @Test func selectFileOnlyAppliesFinalSelectionWhenSwitchedRapidly() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let fileC = DiffChangedFile(status: .modified, oldPath: "c.swift", newPath: "c.swift")
    let docA = DiffDocument(files: [], title: "a")
    let docB = DiffDocument(files: [], title: "b")
    let docC = DiffDocument(files: [], title: "c")
    let docs = ["a.swift": docA, "b.swift": docB, "c.swift": docC]
    let clock = TestClock()
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB, fileC] },
      loadDiffDocument: { file, _ in docs[file.id]! },
      clock: clock
    )
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    state.markDiffRendered()

    state.selectFile(fileB)
    state.selectFile(fileC)
    await advanceSelectDebounce(clock)

    #expect(state.selectedFile == fileC)
    #expect(state.diffDocument == docC)
  }

  @Test func selectFileDebounceSkipsStaleUpdateIfSelectionChangedElsewhere() async {
    // Reproduces a review comment on PR onevcat/Prowl#529: a pending debounce
    // task only cancels when routed through `selectFile` again. If something
    // else (e.g. `loadAllFiles` reconciliation) changes `selectedFile` directly
    // in the meantime, the stale debounce must not overwrite state once it fires.
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let fileC = DiffChangedFile(status: .modified, oldPath: "c.swift", newPath: "c.swift")
    let docA = DiffDocument(files: [], title: "a")
    let docB = DiffDocument(files: [], title: "b")
    let docC = DiffDocument(files: [], title: "c")
    let docs = ["a.swift": docA, "b.swift": docB, "c.swift": docC]
    let clock = TestClock()
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB, fileC] },
      loadDiffDocument: { file, _ in docs[file.id]! },
      clock: clock
    )
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    state.markDiffRendered()

    state.selectFile(fileB)
    state.selectedFile = fileC
    await advanceSelectDebounce(clock)

    #expect(state.selectedFile == fileC)
    #expect(state.diffDocument != docB)
  }

  @Test func loadCancelsPendingSelectDebounce() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let docA = DiffDocument(files: [], title: "a")
    let docB = DiffDocument(files: [], title: "b")
    let docs = ["a.swift": docA, "b.swift": docB]
    let clock = TestClock()
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB] },
      loadDiffDocument: { file, _ in docs[file.id]! },
      clock: clock
    )
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    state.markDiffRendered()

    state.selectFile(fileB)
    state.load(worktreeURL: URL(fileURLWithPath: "/tmp2"), branchName: "other")
    await advanceSelectDebounce(clock)

    #expect(state.diffDocument != docB)
  }

  @Test func markDiffFailedClearsRenderingAndStoresError() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let docA = DiffDocument(files: [], title: "a")
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA] },
      loadDiffDocument: { _, _ in docA }
    )
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    #expect(state.isRenderingDiff)

    let error = DiffError(code: "render_failed", message: "boom")
    state.markDiffFailed(error)

    #expect(!state.isRenderingDiff)
    #expect(state.renderError == error)
  }

  @Test func selectingANewFileClearsAPriorRenderError() async {
    let fileA = DiffChangedFile(status: .modified, oldPath: "a.swift", newPath: "a.swift")
    let fileB = DiffChangedFile(status: .modified, oldPath: "b.swift", newPath: "b.swift")
    let docA = DiffDocument(files: [], title: "a")
    let docB = DiffDocument(files: [], title: "b")
    let docs = ["a.swift": docA, "b.swift": docB]
    let clock = TestClock()
    let state = DiffWindowState(
      fetchChangedFiles: { _ in [fileA, fileB] },
      loadDiffDocument: { file, _ in docs[file.id]! },
      clock: clock
    )
    await state.loadAllFiles(worktreeURL: URL(fileURLWithPath: "/tmp"))
    state.markDiffFailed(DiffError(code: "render_failed", message: "boom"))
    #expect(state.renderError != nil)

    state.selectFile(fileB)
    await advanceSelectDebounce(clock)

    #expect(state.renderError == nil)
  }
}

@MainActor
private func advanceSelectDebounce(_ clock: TestClock<Duration>, by duration: Duration = .milliseconds(150)) async {
  await Task.yield()
  await clock.advance(by: duration)
  await Task.yield()
}
