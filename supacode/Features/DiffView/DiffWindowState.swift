import Foundation
import YiTong

@Observable
@MainActor
final class DiffWindowState {
  var worktreeURL: URL?
  var branchName: String = ""
  var changedFiles: [DiffChangedFile] = []
  var selectedFile: DiffChangedFile?
  var diffDocument: DiffDocument?
  var isLoadingFiles = false
  /// True while the WebView-backed `DiffView` is still rendering the current
  /// `diffDocument` — this can take noticeably longer than the cache lookup for
  /// large files, since diffing/painting happens on the JS side. Cleared by
  /// `markDiffRendered()` once the view reports its `didRender` event.
  var isRenderingDiff = false
  /// Set by `markDiffFailed(_:)` when `DiffView` reports a `.didFail` event, so
  /// the render-in-progress indicator doesn't stay stuck forever. Cleared as soon
  /// as a new document starts rendering.
  var renderError: DiffError?

  private var documentCache: [String: DiffDocument] = [:]
  private var loadTask: Task<Void, Never>?
  private var selectDebounceTask: Task<Void, Never>?

  private let fetchChangedFiles: @Sendable (URL) async -> [DiffChangedFile]
  private let loadDiffDocument: @Sendable (DiffChangedFile, URL) async -> DiffDocument
  private let selectDebounceInterval: Duration
  private let sleep: @Sendable (Duration) async throws -> Void

  init<C: Clock<Duration>>(
    fetchChangedFiles: @escaping @Sendable (URL) async -> [DiffChangedFile] = DiffWindowState.liveFetchChangedFiles,
    loadDiffDocument: @escaping @Sendable (DiffChangedFile, URL) async -> DiffDocument
      = DiffWindowState.liveLoadDocument,
    selectDebounceInterval: Duration = .milliseconds(150),
    clock: C = ContinuousClock()
  ) {
    self.fetchChangedFiles = fetchChangedFiles
    self.loadDiffDocument = loadDiffDocument
    self.selectDebounceInterval = selectDebounceInterval
    self.sleep = { duration in try await clock.sleep(for: duration) }
  }

  func load(worktreeURL: URL, branchName: String) {
    self.worktreeURL = worktreeURL
    self.branchName = branchName
    changedFiles = []
    selectedFile = nil
    diffDocument = nil
    documentCache = [:]
    selectDebounceTask?.cancel()
    loadTask?.cancel()
    loadTask = Task { await loadAllFiles(worktreeURL: worktreeURL) }
  }

  func refresh() {
    guard let worktreeURL else { return }
    // Keep cache intact so file switching remains responsive during refresh
    loadTask?.cancel()
    loadTask = Task { await loadAllFiles(worktreeURL: worktreeURL) }
  }

  func selectFile(_ file: DiffChangedFile) {
    guard selectedFile != file else { return }
    selectedFile = file

    // Debounced so that flicking quickly through several files (e.g. A -> B -> C)
    // never triggers a render for a file the user only passed through — only the
    // selection that's still current once the interval elapses gets applied.
    selectDebounceTask?.cancel()
    let sleep = self.sleep
    let interval = selectDebounceInterval
    selectDebounceTask = Task { [weak self, sleep] in
      do {
        try await sleep(interval)
      } catch {
        return
      }
      guard let self, !Task.isCancelled else { return }
      // The selection may have changed via a path other than `selectFile` while this
      // task was waiting (e.g. `loadAllFiles` reconciliation after a refresh) — only
      // apply this debounced document if `file` is still the current selection.
      guard self.selectedFile?.id == file.id else { return }
      self.updateDiffDocument(self.documentCache[file.id])
    }
  }

  /// Called by the view once `DiffView` reports its `didRender` event.
  func markDiffRendered() {
    isRenderingDiff = false
  }

  /// Called by the view once `DiffView` reports its `didFail` event, so the
  /// loading indicator doesn't stay stuck forever when a render fails.
  func markDiffFailed(_ error: DiffError) {
    isRenderingDiff = false
    renderError = error
  }

  private func updateDiffDocument(_ newDocument: DiffDocument?) {
    guard newDocument != diffDocument else { return }
    isRenderingDiff = newDocument != nil
    if isRenderingDiff {
      renderError = nil
    }
    diffDocument = newDocument
  }

  // MARK: - Reconciliation (pure, testable without hitting Git or Task scheduling)

  /// Drops cache entries for files no longer present in the latest changed-file list.
  static func evictedCache(
    _ cache: [String: DiffDocument],
    keeping fileIDs: Set<String>
  ) -> [String: DiffDocument] {
    cache.filter { fileIDs.contains($0.key) }
  }

  /// Keeps the current selection if its document is cached; otherwise falls back to the
  /// first file, or to nothing if there are no files.
  static func resolvedSelection(
    current: DiffChangedFile?,
    files: [DiffChangedFile],
    cache: [String: DiffDocument]
  ) -> (file: DiffChangedFile?, document: DiffDocument?) {
    if let current, let document = cache[current.id] {
      return (current, document)
    } else if let first = files.first {
      return (first, cache[first.id])
    } else {
      return (nil, nil)
    }
  }

  // MARK: - Loading

  /// Exposed (not private) so tests can drive it directly with injected fakes,
  /// bypassing the `Task` scheduling used by `load()`/`refresh()`.
  func loadAllFiles(worktreeURL: URL) async {
    isLoadingFiles = true
    let files = await fetchChangedFiles(worktreeURL)

    guard !Task.isCancelled else { return }

    changedFiles = files

    let fileIDs = Set(files.map(\.id))
    documentCache = Self.evictedCache(documentCache, keeping: fileIDs)

    // Load documents concurrently, updating the cache as each one completes
    // so that file switching is responsive without waiting for all files
    await withTaskGroup(of: (String, DiffDocument).self) { [loadDiffDocument] group in
      for file in files {
        group.addTask {
          let doc = await loadDiffDocument(file, worktreeURL)
          return (file.id, doc)
        }
      }
      for await (id, doc) in group {
        guard !Task.isCancelled else { break }
        documentCache[id] = doc
        if selectedFile?.id == id {
          updateDiffDocument(doc)
        }
      }
    }

    guard !Task.isCancelled else { return }
    isLoadingFiles = false

    let resolved = Self.resolvedSelection(current: selectedFile, files: files, cache: documentCache)
    selectedFile = resolved.file
    updateDiffDocument(resolved.document)
  }

  // MARK: - Live Git integration

  private nonisolated static func liveFetchChangedFiles(worktreeURL: URL) async -> [DiffChangedFile] {
    let gitClient = GitClient()
    async let trackedOutput = gitClient.diffNameStatus(at: worktreeURL)
    async let untrackedPaths = gitClient.untrackedFilePaths(at: worktreeURL)
    let trackedFiles = DiffChangedFile.parseNameStatus(await trackedOutput)
    let untrackedFiles = await untrackedPaths.map {
      DiffChangedFile(status: .added, oldPath: nil, newPath: $0)
    }
    return trackedFiles + untrackedFiles
  }

  private nonisolated static func liveLoadDocument(
    for file: DiffChangedFile,
    worktreeURL: URL
  ) async -> DiffDocument {
    let gitClient = GitClient()
    let oldContents: String
    let newContents: String

    switch file.status {
    case .added:
      oldContents = ""
      newContents = readFile(worktreeURL.appending(path: file.displayPath))
    case .deleted:
      oldContents = await gitClient.showFileAtHEAD(file.oldPath ?? "", in: worktreeURL) ?? ""
      newContents = ""
    case .renamed:
      oldContents = await gitClient.showFileAtHEAD(file.oldPath ?? "", in: worktreeURL) ?? ""
      newContents = readFile(worktreeURL.appending(path: file.newPath ?? ""))
    default:
      let path = file.displayPath
      oldContents = await gitClient.showFileAtHEAD(path, in: worktreeURL) ?? ""
      newContents = readFile(worktreeURL.appending(path: path))
    }

    let diffFile = DiffFile(
      oldPath: file.oldPath,
      newPath: file.newPath,
      oldContents: oldContents,
      newContents: newContents,
    )
    return DiffDocument(files: [diffFile], title: file.displayName)
  }

  private nonisolated static func readFile(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
  }
}
