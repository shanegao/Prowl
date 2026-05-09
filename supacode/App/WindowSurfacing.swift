import AppKit

enum WindowID {
  static let main = "main"
  static let settings = "settings"
}

extension NSApplication {
  @MainActor
  @discardableResult
  func surfaceMainWindow() -> Bool {
    guard let window = mainWindowCandidate() else {
      activate(ignoringOtherApps: true)
      return false
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    return true
  }

  private func mainWindowCandidate() -> NSWindow? {
    if let window = windows.first(where: { $0.identifier?.rawValue == WindowID.main }) {
      return window
    }
    let candidates = windows.filter { !($0 is NSPanel) }
    if let window = candidates.first(where: { $0.identifier?.rawValue != WindowID.settings }) {
      return window
    }
    return candidates.first
  }
}
