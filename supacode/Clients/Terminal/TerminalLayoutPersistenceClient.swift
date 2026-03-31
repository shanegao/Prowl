import ComposableArchitecture
import Foundation

struct TerminalLayoutPersistenceClient {
  var clearSnapshot: @Sendable () async -> Bool
}

extension TerminalLayoutPersistenceClient: DependencyKey {
  static let liveValue = TerminalLayoutPersistenceClient(
    clearSnapshot: {
      do {
        try SupacodePaths.migrateLegacyCacheFilesIfNeeded()
        let url = SupacodePaths.terminalLayoutSnapshotURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
          return true
        }
        try FileManager.default.removeItem(at: url)
        return true
      } catch {
        return false
      }
    }
  )

  static let testValue = TerminalLayoutPersistenceClient(
    clearSnapshot: { true }
  )
}

extension DependencyValues {
  var terminalLayoutPersistence: TerminalLayoutPersistenceClient {
    get { self[TerminalLayoutPersistenceClient.self] }
    set { self[TerminalLayoutPersistenceClient.self] = newValue }
  }
}
