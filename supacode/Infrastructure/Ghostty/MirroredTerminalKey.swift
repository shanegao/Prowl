import AppKit
import Foundation

struct MirroredTerminalKey: Equatable {
  enum Kind: Equatable {
    case enter
    case backspace
    case deleteForward
    case arrowUp
    case arrowDown
    case arrowLeft
    case arrowRight
    case tab
    case escape
    case controlCharacter
  }

  let kind: Kind
  let keyCode: UInt16
  let characters: String
  let charactersIgnoringModifiers: String
  let modifiers: NSEvent.ModifierFlags
  let isRepeat: Bool

  init?(
    kind: Kind,
    keyCode: UInt16,
    characters: String,
    charactersIgnoringModifiers: String,
    modifiers: NSEvent.ModifierFlags,
    isRepeat: Bool
  ) {
    guard !modifiers.contains(.command) else { return nil }
    self.kind = kind
    self.keyCode = keyCode
    self.characters = characters
    self.charactersIgnoringModifiers = charactersIgnoringModifiers
    self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    self.isRepeat = isRepeat
  }

  init?(event: NSEvent) {
    guard event.type == .keyDown else { return nil }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !modifiers.contains(.command) else { return nil }
    guard let kind = Self.kind(for: event, modifiers: modifiers) else { return nil }
    self.kind = kind
    keyCode = event.keyCode
    characters = event.characters ?? ""
    charactersIgnoringModifiers = event.charactersIgnoringModifiers ?? event.characters ?? ""
    self.modifiers = modifiers
    isRepeat = event.isARepeat
  }

  private static func kind(
    for event: NSEvent,
    modifiers: NSEvent.ModifierFlags
  ) -> Kind? {
    switch event.keyCode {
    case 36, 76: return .enter
    case 48: return .tab
    case 51: return .backspace
    case 117: return .deleteForward
    case 53: return .escape
    case 123: return .arrowLeft
    case 124: return .arrowRight
    case 125: return .arrowDown
    case 126: return .arrowUp
    default:
      break
    }

    if modifiers == [.control],
      let charactersIgnoringModifiers = event.charactersIgnoringModifiers,
      !charactersIgnoringModifiers.isEmpty
    {
      return .controlCharacter
    }

    return nil
  }

  func keyDownEvent(windowNumber: Int) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: windowNumber,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: charactersIgnoringModifiers,
      isARepeat: isRepeat,
      keyCode: keyCode
    )
  }

  func keyUpEvent(windowNumber: Int) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyUp,
      location: .zero,
      modifierFlags: modifiers,
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: windowNumber,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: charactersIgnoringModifiers,
      isARepeat: false,
      keyCode: keyCode
    )
  }
}
