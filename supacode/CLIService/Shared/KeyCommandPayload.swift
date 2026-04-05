// ProwlShared/KeyCommandPayload.swift
// Success payload for `prowl key --json` matching key.md contract.

import Foundation

public struct KeyCommandPayload: Codable, Sendable {
  public let requested: KeyRequested
  public let key: KeyInfo
  public let delivery: KeyDelivery
  public let target: KeyTarget

  public init(
    requested: KeyRequested,
    key: KeyInfo,
    delivery: KeyDelivery,
    target: KeyTarget
  ) {
    self.requested = requested
    self.key = key
    self.delivery = delivery
    self.target = target
  }
}

public struct KeyRequested: Codable, Sendable {
  public let token: String
  public let `repeat`: Int

  public init(token: String, repeat: Int) {
    self.token = token
    self.repeat = `repeat`
  }
}

public struct KeyInfo: Codable, Sendable {
  public let normalized: String
  public let category: KeyCategory

  public init(normalized: String, category: KeyCategory) {
    self.normalized = normalized
    self.category = category
  }
}

public enum KeyCategory: String, Codable, Sendable {
  case navigation
  case editing
  case control
  case shortcut
  case function
}

public struct KeyDelivery: Codable, Sendable {
  public let attempted: Int
  public let delivered: Int
  public let mode: String

  public init(attempted: Int, delivered: Int, mode: String = "keyDownUp") {
    self.attempted = attempted
    self.delivered = delivered
    self.mode = mode
  }
}

public struct KeyTarget: Codable, Sendable {
  public let worktree: KeyTargetWorktree
  public let tab: KeyTargetTab
  public let pane: KeyTargetPane

  public init(worktree: KeyTargetWorktree, tab: KeyTargetTab, pane: KeyTargetPane) {
    self.worktree = worktree
    self.tab = tab
    self.pane = pane
  }
}

public struct KeyTargetWorktree: Codable, Sendable {
  public let id: String
  public let name: String
  public let path: String
  public let rootPath: String
  public let kind: String

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case path
    case rootPath = "root_path"
    case kind
  }

  public init(id: String, name: String, path: String, rootPath: String, kind: String) {
    self.id = id
    self.name = name
    self.path = path
    self.rootPath = rootPath
    self.kind = kind
  }
}

public struct KeyTargetTab: Codable, Sendable {
  public let id: String
  public let title: String
  public let selected: Bool

  public init(id: String, title: String, selected: Bool) {
    self.id = id
    self.title = title
    self.selected = selected
  }
}

public struct KeyTargetPane: Codable, Sendable {
  public let id: String
  public let title: String
  public let cwd: String?
  public let focused: Bool

  public init(id: String, title: String, cwd: String?, focused: Bool) {
    self.id = id
    self.title = title
    self.cwd = cwd
    self.focused = focused
  }
}

// MARK: - Token Normalization

public enum KeyModifier: String, Codable, Sendable, CaseIterable {
  case cmd
  case shift
  case opt
  case ctrl

  static let canonicalOrder: [KeyModifier] = [.cmd, .shift, .opt, .ctrl]

  static func resolve(_ raw: String) -> KeyModifier? {
    switch raw {
    case "cmd", "command", "super":
      return .cmd
    case "shift":
      return .shift
    case "opt", "option", "alt":
      return .opt
    case "ctrl", "control":
      return .ctrl
    default:
      return nil
    }
  }
}

public struct KeyTokenDescriptor: Equatable, Sendable {
  public let normalized: String
  public let baseToken: String
  public let modifiers: [KeyModifier]
  public let category: KeyCategory

  public init(normalized: String, baseToken: String, modifiers: [KeyModifier], category: KeyCategory) {
    self.normalized = normalized
    self.baseToken = baseToken
    self.modifiers = modifiers
    self.category = category
  }
}

private struct KeyBaseDescriptor {
  let canonical: String
  let category: KeyCategory
}

/// Shared token definitions for the `key` command.
/// Used by CLI for validation and by app for response building.
public enum KeyTokens {
  public static func normalize(_ raw: String) -> String? {
    descriptor(for: raw)?.normalized
  }

  public static func category(for canonical: String) -> KeyCategory? {
    descriptor(for: canonical)?.category
  }

  public static func descriptor(for raw: String) -> KeyTokenDescriptor? {
    let normalizedInput = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "+", with: "-")

    guard !normalizedInput.isEmpty else { return nil }

    let parts = normalizedInput
      .split(separator: "-", omittingEmptySubsequences: false)
      .map(String.init)
    guard !parts.isEmpty, !parts.contains(where: \.isEmpty) else { return nil }

    for baseLength in [2, 1] where parts.count >= baseLength {
      let baseRaw = parts.suffix(baseLength).joined(separator: "-")
      guard let base = baseDescriptor(for: baseRaw) else { continue }

      let modifierParts = parts.dropLast(baseLength)
      var modifierSet = Set<KeyModifier>()
      for modifierRaw in modifierParts {
        guard let modifier = KeyModifier.resolve(modifierRaw), modifierSet.insert(modifier).inserted else {
          return nil
        }
      }

      let modifiers = KeyModifier.canonicalOrder.filter { modifierSet.contains($0) }
      let normalized = (modifiers.map(\.rawValue) + [base.canonical]).joined(separator: "-")
      let category = category(for: base, modifiers: modifiers)
      return KeyTokenDescriptor(
        normalized: normalized,
        baseToken: base.canonical,
        modifiers: modifiers,
        category: category
      )
    }

    return nil
  }

  private static func category(for base: KeyBaseDescriptor, modifiers: [KeyModifier]) -> KeyCategory {
    guard !modifiers.isEmpty else { return base.category }
    if modifiers == [.ctrl] {
      return .control
    }
    return .shortcut
  }

  private static func baseDescriptor(for raw: String) -> KeyBaseDescriptor? {
    switch raw {
    case "enter", "return":
      return KeyBaseDescriptor(canonical: "enter", category: .editing)
    case "esc", "escape":
      return KeyBaseDescriptor(canonical: "esc", category: .control)
    case "tab":
      return KeyBaseDescriptor(canonical: "tab", category: .navigation)
    case "backspace", "delete", "del":
      return KeyBaseDescriptor(canonical: "backspace", category: .editing)
    case "delete-forward", "forward-delete", "deleteforward", "forwarddelete":
      return KeyBaseDescriptor(canonical: "delete-forward", category: .editing)
    case "insert", "ins":
      return KeyBaseDescriptor(canonical: "insert", category: .editing)
    case "up", "arrow-up":
      return KeyBaseDescriptor(canonical: "up", category: .navigation)
    case "down", "arrow-down":
      return KeyBaseDescriptor(canonical: "down", category: .navigation)
    case "left", "arrow-left":
      return KeyBaseDescriptor(canonical: "left", category: .navigation)
    case "right", "arrow-right":
      return KeyBaseDescriptor(canonical: "right", category: .navigation)
    case "pageup", "page-up", "pgup":
      return KeyBaseDescriptor(canonical: "pageup", category: .navigation)
    case "pagedown", "page-down", "pgdn":
      return KeyBaseDescriptor(canonical: "pagedown", category: .navigation)
    case "home":
      return KeyBaseDescriptor(canonical: "home", category: .navigation)
    case "end":
      return KeyBaseDescriptor(canonical: "end", category: .navigation)
    case "space":
      return KeyBaseDescriptor(canonical: "space", category: .editing)
    case "minus", "hyphen", "dash":
      return KeyBaseDescriptor(canonical: "minus", category: .editing)
    case "equal", "equals":
      return KeyBaseDescriptor(canonical: "equal", category: .editing)
    case "comma":
      return KeyBaseDescriptor(canonical: "comma", category: .editing)
    case "period", "dot":
      return KeyBaseDescriptor(canonical: "period", category: .editing)
    case "slash":
      return KeyBaseDescriptor(canonical: "slash", category: .editing)
    case "backslash":
      return KeyBaseDescriptor(canonical: "backslash", category: .editing)
    case "semicolon":
      return KeyBaseDescriptor(canonical: "semicolon", category: .editing)
    case "quote", "apostrophe":
      return KeyBaseDescriptor(canonical: "quote", category: .editing)
    case "grave", "backtick":
      return KeyBaseDescriptor(canonical: "grave", category: .editing)
    case "left-bracket", "leftbracket", "lbracket":
      return KeyBaseDescriptor(canonical: "[", category: .editing)
    case "right-bracket", "rightbracket", "rbracket":
      return KeyBaseDescriptor(canonical: "]", category: .editing)
    default:
      break
    }

    if raw.count == 1, let scalar = raw.unicodeScalars.first, scalar.isASCII, !scalar.properties.isWhitespace {
      return KeyBaseDescriptor(canonical: raw, category: .editing)
    }

    if raw.count >= 2,
      raw.first == "f",
      let number = Int(raw.dropFirst()),
      (1...12).contains(number)
    {
      return KeyBaseDescriptor(canonical: raw, category: .function)
    }

    return nil
  }
}
