import Foundation

enum DetectedAgent: String, CaseIterable, Equatable, Identifiable, Sendable {
  // swiftlint:disable:next identifier_name
  case pi
  case claude
  case codex
  case gemini
  case cursor
  case cline
  case opencode
  case copilot
  case kimi
  case droid
  case amp

  var id: String { rawValue }

  var displayName: String {
    rawValue
  }

  var iconLookupToken: String {
    switch self {
    case .claude:
      return "claude"
    case .copilot:
      return "copilot"
    default:
      return rawValue
    }
  }
}
