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

  private var documentCache: [String: DiffDocument] = [:]
  private var loadTask: Task<Void, Never>?

  private let fetchChangedFiles: @Sendable (URL) async -> [DiffChangedFile]
  private let loadDiffDocument: @Sendable (DiffChangedFile, URL) async -> DiffDocument

  init(
    fetchChangedFiles: @escaping @Sendable (URL) async -> [DiffChangedFile] = DiffWindowState.liveFetchChangedFiles,
    loadDiffDocument: @escaping @Sendable (DiffChangedFile, URL) async -> DiffDocument
      = DiffWindowState.liveLoadDocument
  ) {
    self.fetchChangedFiles = fetchChangedFiles
    self.loadDiffDocument = loadDiffDocument
  }

  func load(worktreeURL: URL, branchName: String) {
    self.worktreeURL = worktreeURL
    self.branchName = branchName
    changedFiles = []
    selectedFile = nil
    diffDocument = nil
    documentCache = [:]
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
    diffDocument = documentCache[file.id]
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
          diffDocument = doc
        }
      }
    }

    guard !Task.isCancelled else { return }
    isLoadingFiles = false

    (selectedFile, diffDocument) = Self.resolvedSelection(current: selectedFile, files: files, cache: documentCache)
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
