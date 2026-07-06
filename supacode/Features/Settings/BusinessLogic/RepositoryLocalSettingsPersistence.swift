import Dependencies
import Foundation

nonisolated struct RepositoryLocalSettingsStorage: Sendable {
  var load: @Sendable (URL) throws -> Data
  var save: @Sendable (Data, URL) throws -> Void
}

nonisolated enum RepositoryLocalSettingsStorageKey: DependencyKey {
  static var liveValue: RepositoryLocalSettingsStorage {
    RepositoryLocalSettingsStorage(
      load: { try Data(contentsOf: $0) },
      // Per-repo settings live under `~/.prowl/repo/<name>/` (not inside the
      // cloned repo), so they are user-owned config a dotfiles user may symlink
      // — follow the link on write to preserve it (#478). Upstream keeps a
      // non-following write for its in-repo `supacode.json`; that exception does
      // not apply here because the fork stores these outside the repository.
      save: { data, url in try SymlinkPreservingFileWriter.write(data, to: url) }
    )
  }

  static var previewValue: RepositoryLocalSettingsStorage { .inMemory() }
  static var testValue: RepositoryLocalSettingsStorage { .inMemory() }
}

extension DependencyValues {
  nonisolated var repositoryLocalSettingsStorage: RepositoryLocalSettingsStorage {
    get { self[RepositoryLocalSettingsStorageKey.self] }
    set { self[RepositoryLocalSettingsStorageKey.self] = newValue }
  }
}

extension RepositoryLocalSettingsStorage {
  nonisolated static func inMemory() -> RepositoryLocalSettingsStorage {
    let storage = InMemoryRepositoryLocalSettingsStorage()
    return RepositoryLocalSettingsStorage(
      load: { try storage.load($0) },
      save: { try storage.save($0, $1) }
    )
  }
}

nonisolated enum RepositoryLocalSettingsStorageError: Error {
  case missing
}

nonisolated final class InMemoryRepositoryLocalSettingsStorage: @unchecked Sendable {
  private let lock = NSLock()
  private var dataByURL: [URL: Data] = [:]

  func load(_ url: URL) throws -> Data {
    lock.lock()
    defer { lock.unlock() }
    guard let data = dataByURL[url] else {
      throw RepositoryLocalSettingsStorageError.missing
    }
    return data
  }

  func save(_ data: Data, _ url: URL) throws {
    lock.lock()
    defer { lock.unlock() }
    dataByURL[url] = data
  }
}
