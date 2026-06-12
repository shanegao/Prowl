import Foundation

public enum HandoffAgentSupport {
  public static let supportedAgents = [
    "pi",
    "claude",
    "codex",
    "gemini",
    "cursor-agent",
    "cline",
    "opencode",
    "copilot",
    "kimi",
    "droid",
    "amp",
  ]

  public static var supportedAgentsDescription: String {
    supportedAgents.joined(separator: ", ")
  }

  public static func normalize(_ agent: String) -> String? {
    let normalized = agent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard supportedAgents.contains(normalized) else { return nil }
    return normalized
  }
}
