import SwiftUI

struct AppShortcut {
  let keyEquivalent: KeyEquivalent
  let modifiers: EventModifiers
  private let ghosttyKeyName: String

  init(key: Character, modifiers: EventModifiers) {
    self.keyEquivalent = KeyEquivalent(key)
    self.modifiers = modifiers
    self.ghosttyKeyName = String(key).lowercased()
  }

  init(keyEquivalent: KeyEquivalent, ghosttyKeyName: String, modifiers: EventModifiers) {
    self.keyEquivalent = keyEquivalent
    self.modifiers = modifiers
    self.ghosttyKeyName = ghosttyKeyName
  }

  var keyboardShortcut: KeyboardShortcut {
    KeyboardShortcut(keyEquivalent, modifiers: modifiers)
  }

  var ghosttyKeybind: String {
    let parts = ghosttyModifierParts + [ghosttyKeyName]
    return parts.joined(separator: "+")
  }

  var ghosttyUnbindArgument: String {
    "--keybind=\(ghosttyKeybind)=unbind"
  }

  var display: String {
    let parts = displayModifierParts + [keyEquivalent.display]
    return parts.joined()
  }

  var displaySymbols: [String] {
    display.map { String($0) }
  }

  fileprivate var normalizedConflictKey: String? {
    guard ghosttyKeyName.count == 1 else { return nil }
    return ghosttyKeyName
  }

  private var ghosttyModifierParts: [String] {
    var parts: [String] = []
    if modifiers.contains(.control) { parts.append("ctrl") }
    if modifiers.contains(.option) { parts.append("alt") }
    if modifiers.contains(.shift) { parts.append("shift") }
    if modifiers.contains(.command) { parts.append("super") }
    return parts
  }

  private var displayModifierParts: [String] {
    var parts: [String] = []
    if modifiers.contains(.command) { parts.append("⌘") }
    if modifiers.contains(.shift) { parts.append("⇧") }
    if modifiers.contains(.option) { parts.append("⌥") }
    if modifiers.contains(.control) { parts.append("⌃") }
    return parts
  }
}

enum AppShortcuts {
  struct ReservedCustomCommandShortcut: Equatable {
    let actionTitle: String
    let display: String
    let key: String
    let modifiers: EventModifiers
  }

  private struct TabSelectionBinding {
    let unicode: String
    let physical: String
    let tabIndex: Int
  }

  private static let tabSelectionBindings: [TabSelectionBinding] = [
    TabSelectionBinding(unicode: "1", physical: "digit_1", tabIndex: 1),
    TabSelectionBinding(unicode: "2", physical: "digit_2", tabIndex: 2),
    TabSelectionBinding(unicode: "3", physical: "digit_3", tabIndex: 3),
    TabSelectionBinding(unicode: "4", physical: "digit_4", tabIndex: 4),
    TabSelectionBinding(unicode: "5", physical: "digit_5", tabIndex: 5),
    TabSelectionBinding(unicode: "6", physical: "digit_6", tabIndex: 6),
    TabSelectionBinding(unicode: "7", physical: "digit_7", tabIndex: 7),
    TabSelectionBinding(unicode: "8", physical: "digit_8", tabIndex: 8),
    TabSelectionBinding(unicode: "9", physical: "digit_9", tabIndex: 9),
    TabSelectionBinding(unicode: "0", physical: "digit_0", tabIndex: 10),
  ]

  static let newWorktree = AppShortcut(key: "n", modifiers: .command)
  static let openSettings = AppShortcut(key: ",", modifiers: .command)
  static let openFinder = AppShortcut(key: "o", modifiers: .command)
  static let copyPath = AppShortcut(key: "c", modifiers: [.command, .shift])
  static let openRepository = AppShortcut(key: "o", modifiers: [.command, .shift])
  static let openPullRequest = AppShortcut(key: "g", modifiers: [.command, .control])
  static let toggleLeftSidebar = AppShortcut(key: "b", modifiers: .command)
  static let refreshWorktrees = AppShortcut(key: "r", modifiers: [.command, .option])
  static let runScript = AppShortcut(key: "r", modifiers: .command)
  static let stopRunScript = AppShortcut(key: "r", modifiers: [.command, .shift])
  static let checkForUpdates = AppShortcut(key: ",", modifiers: [.command, .shift])
  static let showDiff = AppShortcut(key: "]", modifiers: [.command, .shift])
  static let toggleCanvas = AppShortcut(
    keyEquivalent: .return, ghosttyKeyName: "return", modifiers: [.command, .option]
  )
  static let archivedWorktrees = AppShortcut(key: "a", modifiers: [.command, .control])
  static let selectNextWorktree = AppShortcut(
    keyEquivalent: .downArrow, ghosttyKeyName: "arrow_down", modifiers: [.command, .control]
  )
  static let selectPreviousWorktree = AppShortcut(
    keyEquivalent: .upArrow, ghosttyKeyName: "arrow_up", modifiers: [.command, .control]
  )
  static let selectWorktree1 = AppShortcut(key: "1", modifiers: [.control])
  static let selectWorktree2 = AppShortcut(key: "2", modifiers: [.control])
  static let selectWorktree3 = AppShortcut(key: "3", modifiers: [.control])
  static let selectWorktree4 = AppShortcut(key: "4", modifiers: [.control])
  static let selectWorktree5 = AppShortcut(key: "5", modifiers: [.control])
  static let selectWorktree6 = AppShortcut(key: "6", modifiers: [.control])
  static let selectWorktree7 = AppShortcut(key: "7", modifiers: [.control])
  static let selectWorktree8 = AppShortcut(key: "8", modifiers: [.control])
  static let selectWorktree9 = AppShortcut(key: "9", modifiers: [.control])
  static let selectWorktree0 = AppShortcut(key: "0", modifiers: [.control])
  static let worktreeSelection: [AppShortcut] = [
    selectWorktree1,
    selectWorktree2,
    selectWorktree3,
    selectWorktree4,
    selectWorktree5,
    selectWorktree6,
    selectWorktree7,
    selectWorktree8,
    selectWorktree9,
    selectWorktree0,
  ]

  private static let reservedCustomCommandBindings: [(title: String, shortcut: AppShortcut)] = [
    ("Open Settings", openSettings),
    ("Toggle Left Sidebar", toggleLeftSidebar),
    ("Run Script", runScript),
    ("Stop Script", stopRunScript),
    ("Check for Updates", checkForUpdates),
    ("Show Diff", showDiff),
    ("Open Worktree", openFinder),
    ("Open Repository", openRepository),
  ]

  static var reservedCustomCommandShortcuts: [ReservedCustomCommandShortcut] {
    reservedCustomCommandBindings.compactMap { binding in
      guard let key = binding.shortcut.normalizedConflictKey else { return nil }
      return ReservedCustomCommandShortcut(
        actionTitle: binding.title,
        display: binding.shortcut.display,
        key: key,
        modifiers: binding.shortcut.modifiers
      )
    }
  }

  static func customCommandConflict(for shortcut: OnevcatCustomShortcut) -> ReservedCustomCommandShortcut? {
    guard let key = shortcut.normalizedConflictKey else { return nil }
    let modifiers = shortcut.modifiers.eventModifiers
    return reservedCustomCommandShortcuts.first {
      $0.key == key && $0.modifiers == modifiers
    }
  }

  static func sanitizeCustomCommands(_ commands: [OnevcatCustomCommand]) -> [OnevcatCustomCommand] {
    commands.map { command in
      var normalized = command.normalized()
      guard let shortcut = normalized.shortcut else { return normalized }
      if customCommandConflict(for: shortcut) != nil {
        normalized.shortcut = nil
      }
      return normalized
    }
  }

  static let tabSelectionGhosttyKeybindArguments: [String] = tabSelectionBindings.flatMap { binding in
    [
      "--keybind=ctrl+\(binding.unicode)=goto_tab:\(binding.tabIndex)",
      "--keybind=ctrl+\(binding.physical)=goto_tab:\(binding.tabIndex)",
    ]
  }

  static var ghosttyCLIKeybindArguments: [String] {
    all.map(\.ghosttyUnbindArgument) + tabSelectionGhosttyKeybindArguments
  }

  static let all: [AppShortcut] = [
    newWorktree,
    openSettings,
    openFinder,
    copyPath,
    openRepository,
    openPullRequest,
    toggleLeftSidebar,
    refreshWorktrees,
    runScript,
    stopRunScript,
    checkForUpdates,
    showDiff,
    toggleCanvas,
    archivedWorktrees,
    selectNextWorktree,
    selectPreviousWorktree,
    selectWorktree1,
    selectWorktree2,
    selectWorktree3,
    selectWorktree4,
    selectWorktree5,
    selectWorktree6,
    selectWorktree7,
    selectWorktree8,
    selectWorktree9,
    selectWorktree0,
  ]
}

private extension OnevcatCustomShortcut {
  var normalizedConflictKey: String? {
    let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard normalized.count == 1 else { return nil }
    return normalized
  }
}
