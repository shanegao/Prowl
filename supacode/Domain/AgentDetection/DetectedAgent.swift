import Foundation

enum DetectedAgent: String, CaseIterable, Equatable, Identifiable, Sendable {
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
    switch self {
    case .pi:
      return "Pi"
    case .claude:
      return "Claude"
    case .codex:
      return "Codex"
    case .gemini:
      return "Gemini"
    case .cursor:
      return "Cursor"
    case .cline:
      return "Cline"
    case .opencode:
      return "OpenCode"
    case .copilot:
      return "Copilot"
    case .kimi:
      return "Kimi"
    case .droid:
      return "Droid"
    case .amp:
      return "Amp"
    }
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
