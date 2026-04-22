import Foundation

/// Resolves a tab icon from a command title surfaced by the
/// auto-detector (typically the OSC 2 title set by the shell's
/// `preexec`, or one a TUI rewrites on launch).
///
/// Two lookup paths exist:
///
/// - `iconForFirstToken(_:)`: case-insensitive match on the *first
///   whitespace-delimited token*. Used by the debounce path so short
///   commands (`ls`, `git status`) never trigger an icon swap.
///   Examples: `"swift build"` and `"swift test"` route through the
///   `swift` entry; `"claude"` routes through `claude`.
///
/// - `iconForSubstring(_:)`: case-insensitive substring match against
///   the entire title. Used as an immediate-apply path that bypasses
///   the debounce, intended for TUI tools that overwrite their own
///   title after launch (e.g. `claude` → `✳ Claude Code`). The
///   substring rule wins so a TUI's branded title can refine the
///   icon set by the initial command name.
///
/// Both return `nil` when nothing matches; the auto-detector then
/// leaves the tab's existing icon untouched (selection-2 semantics —
/// a previously-detected icon is preserved across unknown commands).
enum CommandIconMap {
  static func iconForFirstToken(_ title: String) -> TabIconSource? {
    let token = firstToken(of: title).lowercased()
    return firstTokenMapping[token]
  }

  static func iconForSubstring(_ title: String) -> TabIconSource? {
    let lowered = title.lowercased()
    for (needle, icon) in substringMapping where lowered.contains(needle) {
      return icon
    }
    return nil
  }

  private static func firstToken(of title: String) -> String {
    title
      .split(separator: " ", omittingEmptySubsequences: true)
      .first
      .map(String.init)
      ?? title
  }

  /// First-token table. Grouped by category and alphabetised within
  /// each group. SF Symbols only at this layer keep things glanceable
  /// before asset rendering is wired; entries that ship branded
  /// artwork should add `assetName:` and let renderers prefer it.
  private static let firstTokenMapping: [String: TabIconSource] = [
    // Coding agents — the SF Symbol is just a placeholder so the icon
    // is non-blank; the real branded artwork is picked up via the
    // substring path (which routes the post-launch TUI title to an
    // assetName entry).
    "claude": TabIconSource(systemSymbol: "sparkle", assetName: "Claude Code"),
    "codex": TabIconSource(systemSymbol: "sparkle"),
    "aider": TabIconSource(systemSymbol: "sparkle"),

    // Editors / pagers
    "vim": TabIconSource(systemSymbol: "pencil.and.scribble"),
    "nvim": TabIconSource(systemSymbol: "pencil.and.scribble"),
    "nano": TabIconSource(systemSymbol: "pencil.and.scribble"),

    // Package managers / JS runtimes
    "npm": TabIconSource(systemSymbol: "shippingbox"),
    "pnpm": TabIconSource(systemSymbol: "shippingbox"),
    "yarn": TabIconSource(systemSymbol: "shippingbox"),
    "bun": TabIconSource(systemSymbol: "shippingbox"),

    // VCS
    "git": TabIconSource(systemSymbol: "arrow.triangle.branch"),
    "gh": TabIconSource(systemSymbol: "arrow.triangle.branch"),

    // Build tools
    "make": TabIconSource(systemSymbol: "hammer"),
    "swift": TabIconSource(systemSymbol: "hammer"),
    "cargo": TabIconSource(systemSymbol: "hammer"),
    "xcodebuild": TabIconSource(systemSymbol: "hammer"),
    "gradle": TabIconSource(systemSymbol: "hammer"),

    // Container / orchestration
    "docker": TabIconSource(systemSymbol: "shippingbox.fill"),
    "kubectl": TabIconSource(systemSymbol: "shippingbox.fill"),
    "podman": TabIconSource(systemSymbol: "shippingbox.fill"),

    // Network / remote
    "ssh": TabIconSource(systemSymbol: "network"),
    "mosh": TabIconSource(systemSymbol: "network"),
    "curl": TabIconSource(systemSymbol: "network"),

    // Process / system viewers
    "htop": TabIconSource(systemSymbol: "waveform.path.ecg"),
    "btop": TabIconSource(systemSymbol: "waveform.path.ecg"),
    "top": TabIconSource(systemSymbol: "waveform.path.ecg"),

    // Database REPLs
    "psql": TabIconSource(systemSymbol: "cylinder.split.1x2"),
    "mysql": TabIconSource(systemSymbol: "cylinder.split.1x2"),
    "sqlite3": TabIconSource(systemSymbol: "cylinder.split.1x2"),

    // Logs / streams
    "tail": TabIconSource(systemSymbol: "text.justifyleft"),
    "journalctl": TabIconSource(systemSymbol: "text.justifyleft"),
  ]

  /// Substring patterns for TUI tools that rewrite their own title
  /// after launch. Needles are matched case-insensitively against the
  /// full title; the first match wins, so list more specific
  /// patterns earlier when conflicts arise.
  private static let substringMapping: [(needle: String, icon: TabIconSource)] = [
    ("claude code", TabIconSource(systemSymbol: "sparkle", assetName: "Claude Code")),
  ]
}
