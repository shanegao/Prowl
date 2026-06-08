import Foundation

/// A Claude Code permission prompt parsed from a pane's visible screen text — the
/// question plus its numbered options. Used to turn the generic "Claude needs your
/// permission" notification into one that shows the real question and per-option
/// quick-answer buttons.
///
/// FRAGILE BY NATURE: this parses Claude's TUI prompt box, whose layout can change
/// between Claude Code versions. Callers MUST treat a `nil` parse as "fall back to
/// the plain notification" — never assume a prompt is present or that the numbers
/// are exhaustive.
struct ClaudePermissionPrompt: Equatable, Sendable {
  struct Option: Equatable, Sendable {
    /// The digit the user presses to choose this option — also the key token Prowl
    /// sends to the pane to answer (`sendCLIKeyToken("\(number)")`).
    let number: Int
    /// The option text, with its leading "N." and any selection caret stripped.
    let label: String
  }

  /// The prompt headline shown above the options (e.g. "Do you want to make this
  /// edit to Foo.swift?"), or `nil` when the box has options but no readable
  /// headline — the caller then keeps the agent's own notification body instead
  /// of showing a synthesized placeholder.
  let question: String?
  let options: [Option]
}

extension ClaudePermissionPrompt {
  /// Box-drawing glyphs Claude wraps its prompt in; stripped so option/question
  /// lines read identically whether or not they sit inside a border box.
  private static let boxChars = Set("│┃╎╏┆┇┊┋╭╮╰╯┌┐└┘├┤┬┴┼─━┄┅┈┉")

  /// Best-effort parse of a Claude permission prompt from `screen` (a pane's visible
  /// text). Returns `nil` when no numbered-option prompt is found — the caller then
  /// keeps the plain notification.
  static func parse(screen: String) -> ClaudePermissionPrompt? {
    let lines =
      screen
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { stripChrome(String($0)) }

    var options: [Option] = []
    var firstOptionLineIndex: Int?
    var runHasSelectionCaret = false
    for (index, line) in lines.enumerated() {
      guard let option = parseOption(line) else { continue }
      // Options are consecutive and 1-based; reset if the numbering doesn't continue
      // so stray "1." text far above the real prompt doesn't anchor a false parse.
      if option.number == 1 {
        options = [option]
        firstOptionLineIndex = index
        runHasSelectionCaret = line.hasPrefix("❯")
      } else if option.number == options.count + 1 {
        options.append(option)
        runHasSelectionCaret = runHasSelectionCaret || line.hasPrefix("❯")
      }
    }

    // Require at least two consecutive numbered options AND the interactive
    // selection caret (❯) on one of them. A real Claude prompt always highlights
    // its active choice; a coincidental numbered list in agent output never does,
    // so the caret is what stops a stray list from triggering a false answer
    // keypress. A real prompt momentarily read without the caret degrades safely
    // to the plain notification.
    guard options.count >= 2, runHasSelectionCaret, let firstOptionLineIndex else { return nil }

    // The question is the nearest non-empty, non-option content line above the first
    // option (the prompt headline inside the box), or nil when there's no headline.
    let question =
      lines[..<firstOptionLineIndex]
      .reversed()
      .first { !$0.isEmpty && parseOption($0) == nil }

    return ClaudePermissionPrompt(question: question, options: options)
  }

  private static func stripChrome(_ line: String) -> String {
    String(line.filter { !boxChars.contains($0) }).trimmingCharacters(in: .whitespaces)
  }

  /// Parses a "❯ 1. Yes" / "2. No…" option line into its number + label, or `nil`.
  private static func parseOption(_ line: String) -> Option? {
    var rest = line
    if rest.hasPrefix("❯") {
      rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    guard let dot = rest.firstIndex(of: "."),
      let number = Int(rest[..<dot]),
      number > 0
    else {
      return nil
    }
    let label = String(rest[rest.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty else { return nil }
    return Option(number: number, label: label)
  }
}
