import Foundation

private let agentDetectionRecentLineLimit = 24

extension DetectedAgent {
  func detectState(in screen: String) -> AgentRawState {
    let screen = recentLines(screen, limit: agentDetectionRecentLineLimit)
    switch self {
    case .pi:
      return detectPi(screen)
    case .claude:
      return detectClaude(screen)
    case .codex:
      return detectCodex(screen)
    case .gemini:
      return detectGemini(screen)
    case .cursor:
      return detectCursor(screen)
    case .cline:
      return detectCline(screen)
    case .opencode:
      return detectOpenCode(screen)
    case .copilot:
      return detectCopilot(screen)
    case .kimi:
      return detectKimi(screen)
    case .droid:
      return detectDroid(screen)
    case .amp:
      return detectAmp(screen)
    }
  }
}

private func recentLines(_ content: String, limit: Int) -> String {
  let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  var remainingNonBlankLines = limit
  var startIndex = lines.startIndex

  for index in lines.indices.reversed() {
    guard !lines[index].trimmingCharacters(in: .whitespaces).isEmpty else {
      continue
    }
    remainingNonBlankLines -= 1
    if remainingNonBlankLines == 0 {
      startIndex = index
      break
    }
  }

  return lines[startIndex...].joined(separator: "\n")
}

private func detectPi(_ content: String) -> AgentRawState {
  content.contains("Working...") ? .working : .idle
}

private func detectClaude(_ content: String) -> AgentRawState {
  let lower = content.lowercased()

  if content.contains("⌕ Search…") || lower.contains("ctrl+r to toggle") {
    return .idle
  }
  let currentInteraction = claudeCurrentInteractionRegion(content)
  if hasClaudeBlockedPrompt(content: currentInteraction, lower: currentInteraction.lowercased()) {
    return .blocked
  }

  let above = contentAbovePromptBox(content)
  let aboveLower = above.lowercased()
  if aboveLower.contains("esc to interrupt") || aboveLower.contains("ctrl+c to interrupt") {
    return .working
  }
  if hasSpinnerActivity(above) {
    return .working
  }
  return .idle
}

private func detectCodex(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("press enter to confirm or esc to cancel")
    || lower.contains("enter to submit answer")
    || lower.contains("allow command?")
    || lower.contains("[y/n]")
    || lower.contains("yes (y)")
    || hasConfirmationPrompt(lower)
  {
    return .blocked
  }
  if hasInterruptPattern(lower) || hasCodexWorkingHeader(content) {
    return .working
  }
  return .idle
}

private func detectGemini(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("waiting for user confirmation")
    || content.contains("│ Apply this change")
    || content.contains("│ Allow execution")
    || content.contains("│ Do you want to proceed")
    || hasConfirmationPrompt(lower)
  {
    return .blocked
  }
  if lower.contains("esc to cancel") {
    return .working
  }
  return .idle
}

private func detectCursor(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("(y) (enter)")
    || lower.contains("keep (n)")
    || lower.contains("skip (esc or n)")
    || (lower.contains("(y)") && (lower.contains("allow") || lower.contains("run")))
  {
    return .blocked
  }
  if lower.contains("ctrl+c to stop") || hasCursorSpinner(content) {
    return .working
  }
  return .idle
}

private func detectCline(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("let cline use this tool")
    || ((lower.contains("[act mode]") || lower.contains("[plan mode]")) && lower.contains("yes"))
  {
    return .blocked
  }
  if lower.contains("cline is ready for your message") {
    return .idle
  }
  return .working
}

private func detectOpenCode(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if content.contains("△ Permission required")
    || (lower.contains("↑↓ select")
      && (lower.contains("enter confirm") || lower.contains("enter submit") || lower.contains("enter toggle"))
      && lower.contains("esc dismiss"))
    || hasConfirmationPrompt(lower)
  {
    return .blocked
  }
  if lower.contains("esc to interrupt") {
    return .working
  }
  return .idle
}

private func detectCopilot(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if lower.contains("│ do you want")
    || (lower.contains("confirm with") && lower.contains("enter"))
    || hasConfirmationPrompt(lower)
  {
    return .blocked
  }
  if lower.contains("esc to cancel") {
    return .working
  }
  return .idle
}

private func detectKimi(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  let blockedPatterns = [
    "allow?", "confirm?", "approve?", "proceed?", "[y/n]", "(y/n)",
  ]
  if blockedPatterns.contains(where: lower.contains)
    || hasConfirmationPrompt(lower)
    || hasKimiApprovalPanel(content: content, lower: lower)
  {
    return .blocked
  }

  let workingPatterns = [
    "thinking", "processing", "generating", "waiting for response", "ctrl+c to cancel",
  ]
  if workingPatterns.contains(where: lower.contains)
    || hasKimiMoonSpinner(content)
    || hasKimiToolSpinner(content: content, lower: lower)
  {
    return .working
  }
  return .idle
}

private func detectDroid(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if content.contains("EXECUTE")
    && (lower.contains("enter to select") || lower.contains("↑↓ to navigate"))
  {
    return .blocked
  }
  if hasDroidSpinner(content) {
    return .working
  }
  return .idle
}

private func detectAmp(_ content: String) -> AgentRawState {
  let lower = content.lowercased()
  if (lower.contains("waiting for approval")
    || lower.contains("invoke tool")
    || lower.contains("run this command?"))
    && (lower.contains("approve") || lower.contains("allow all for this session"))
  {
    return .blocked
  }
  if lower.contains("esc to cancel") {
    return .working
  }
  return .idle
}

private func contentAbovePromptBox(_ content: String) -> String {
  let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  guard let promptIndex = lines.lastIndex(where: { $0.contains("❯") }) else {
    return content
  }
  let borderIndex = lines[..<promptIndex].lastIndex(where: isBoxBorderLine)
  let endIndex = borderIndex ?? promptIndex
  return lines[..<endIndex].joined(separator: "\n")
}

private func isBoxBorderLine(_ line: String) -> Bool {
  let trimmed = line.trimmingCharacters(in: .whitespaces)
  guard trimmed.count >= 3 else { return false }
  return trimmed.allSatisfy { $0 == "─" || $0 == "-" }
}

private func claudeCurrentInteractionRegion(_ content: String) -> String {
  let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  guard let promptIndex = lines.lastIndex(where: { $0.contains("❯") }) else {
    return lines.suffix(18).joined(separator: "\n")
  }

  let lowerBound = max(lines.startIndex, promptIndex - 10)
  let upperBound = min(lines.endIndex, promptIndex + 11)
  return lines[lowerBound..<upperBound].joined(separator: "\n")
}

private func hasClaudeBlockedPrompt(content: String, lower: String) -> Bool {
  if lower.contains("do you want to proceed?")
    || lower.contains("waiting for permission")
    || lower.contains("do you want to allow this connection?")
  {
    return true
  }
  if (lower.contains("do you want") || lower.contains("would you like"))
    && (lower.contains("yes") || content.contains("❯"))
  {
    return true
  }
  return hasSelectionPrompt(content) && (lower.contains("yes") || lower.contains("no"))
}

private func hasSelectionPrompt(_ content: String) -> Bool {
  content.contains("❯")
    || content.split(separator: "\n").contains { line in
      line.trimmingCharacters(in: .whitespaces).hasPrefix("1.")
    }
}

private func hasKimiApprovalPanel(content: String, lower: String) -> Bool {
  lower.contains("requesting approval")
    || (lower.contains("approve once") && lower.contains("approve for this session") && lower.contains("reject"))
    || (content.contains("─ approval") && content.contains("↵ confirm"))
}

private func hasKimiMoonSpinner(_ content: String) -> Bool {
  let moonSpinners: Set<Character> = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]
  return content.contains { moonSpinners.contains($0) }
}

private func hasKimiToolSpinner(content: String, lower: String) -> Bool {
  guard lower.contains("using ") else { return false }
  return content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.unicodeScalars.first else { return false }
    return (0x2800...0x28FF).contains(Int(first.value))
  }
}

private func hasConfirmationPrompt(_ lower: String) -> Bool {
  (lower.contains("allow") || lower.contains("approve") || lower.contains("confirm") || lower.contains("proceed"))
    && (lower.contains("[y/n]") || lower.contains("(y/n)") || lower.contains(" yes") || lower.contains(" yes (y)"))
}

private func hasInterruptPattern(_ lower: String) -> Bool {
  lower.contains("esc to interrupt") || lower.contains("ctrl+c to interrupt")
}

private func hasCodexWorkingHeader(_ content: String) -> Bool {
  content.split(separator: "\n").contains { line in
    line.trimmingCharacters(in: .whitespaces).hasPrefix("• Working (")
  }
}

private func hasSpinnerActivity(_ content: String) -> Bool {
  let spinnerScalars: Set<UnicodeScalar> = [
    "✱", "✲", "✳", "✴", "✵", "✶", "✷", "✸", "✹", "✺", "✻", "✼", "✽", "✾", "✿", "·",
  ]
  return content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard let first = trimmed.unicodeScalars.first else { return false }
    return spinnerScalars.contains(first) && trimmed.contains("…")
  }
}

private func hasCursorSpinner(_ content: String) -> Bool {
  content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
    return (trimmed.hasPrefix("⬡") || trimmed.hasPrefix("⬢")) && trimmed.contains("ing")
  }
}

private func hasDroidSpinner(_ content: String) -> Bool {
  content.split(separator: "\n").contains { line in
    let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
    guard let first = trimmed.unicodeScalars.first else { return false }
    return (0x2800...0x28FF).contains(Int(first.value)) && trimmed.contains("esc to stop")
  }
}
