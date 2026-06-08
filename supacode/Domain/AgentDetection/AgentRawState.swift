import Foundation

enum AgentRawState: String, Equatable, Sendable {
  case working
  case blocked
  case idle
  case unknown
}

enum AgentDisplayState: String, Equatable, Sendable {
  case working
  case blocked
  case done
  case idle

  /// User-facing label for the state. Lives on the Domain type (vs. `fileprivate`
  /// on a single view extension) so every surface — agents row, menubar list,
  /// future status displays — reads the same string and the four-case switch
  /// has exactly one definition.
  var label: String {
    switch self {
    case .working: return "Working"
    case .blocked: return "Blocked"
    case .done: return "Done"
    case .idle: return "Idle"
    }
  }
}
