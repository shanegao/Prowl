import Foundation

struct GitRemoteWebInfo: Equatable, Sendable {
  let host: String
  let repositoryPath: String

  var repositoryURL: URL? {
    URL(string: "https://\(host)/\(repositoryPath)")
  }
}
