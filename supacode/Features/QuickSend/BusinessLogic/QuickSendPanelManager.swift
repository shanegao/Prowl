import AppKit
import ComposableArchitecture
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
  /// System-wide hotkey that opens the quick-send composer from any app — even
  /// when Prowl is in the background. Defaults to ⌘⇧P (matching the in-app
  /// `quickSendActiveAgent` binding); the library persists any user override.
  static let quickSendActiveAgent = Self(
    "quickSendActiveAgent",
    default: .init(.p, modifiers: [.command, .shift])
  )
}

/// Owns the quick-send panel: a titled-but-chromeless, non-activating `NSPanel`
/// that hosts `QuickSendPanelRoot`. `.nonactivatingPanel` is the load-bearing flag —
/// showing the panel (even via `makeKeyAndOrderFront`, so the composer can receive
/// typing) does NOT bring the main app forward, which is the whole point of
/// triggering it from the menubar. Mirrors `SettingsWindowManager`'s
/// imperative-window pattern.
@MainActor
@Observable
final class QuickSendPanelManager {
  @ObservationIgnored static let shared = QuickSendPanelManager()

  @ObservationIgnored private var panel: NSPanel?
  @ObservationIgnored private var store: StoreOf<AppFeature>?
  @ObservationIgnored private var didRegisterHotkey = false
  /// Size the panel had before its last collapse, so the Expand button restores the
  /// user's previous width + height rather than snapping to the default expanded size.
  @ObservationIgnored private var lastExpandedSize: NSSize?
  /// Persists the panel's user-chosen frame across shows and launches. Held
  /// strongly here (the panel references it only weakly via `delegate`).
  @ObservationIgnored private let frameSaver = QuickSendPanelFrameSaver()

  /// Panel sizing. `expandedSize` is the first-show (and Expand-target) size;
  /// `collapsedSize` is the compact parked bar the panel snaps to (and its minimum
  /// while collapsed). `minSize` is the expanded floor — wide/tall enough for the
  /// footer controls; `setExpanded` swaps the panel's `minSize` between the two so the
  /// collapsed bar can be far narrower than the expanded composer needs.
  private enum Layout {
    static let expandedSize = NSSize(width: 340, height: 260)
    static let collapsedSize = NSSize(width: 300, height: 84)
    static let defaultSize = expandedSize
    static let minSize = NSSize(width: 340, height: 260)
  }

  private init() {}

  func configure(store: StoreOf<AppFeature>) {
    self.store = store
    guard !didRegisterHotkey else { return }
    didRegisterHotkey = true
    // System-wide hotkey: the KeyboardShortcuts library installs a global monitor,
    // so this opens the composer from any app, not just when Prowl is focused. The
    // panel is itself non-activating, so showing it never brings Prowl forward. The
    // library invokes the handler on the main thread.
    KeyboardShortcuts.onKeyDown(for: .quickSendActiveAgent) { [weak self] in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.store?.send(.toggleQuickSend)
      }
    }
  }

  func show() {
    guard let panel = panel ?? makePanel() else { return }
    self.panel = panel
    // A re-show always opens expanded, so restore the expanded minimum (a prior
    // collapse left the panel at the narrow collapsed floor).
    panel.minSize = Layout.minSize
    // Restore the user's saved size + position on EVERY show, not just the first.
    // While the panel is dismissed, `QuickSendPanelRoot` renders empty and the
    // window collapses to a degenerate size; restoring here repairs that before
    // the panel becomes visible. Fall back to `position(_:)` (reset to default
    // size + center) when nothing is saved yet OR the saved frame is below the
    // minimum — the latter self-heals any degenerate frame a prior build wrote.
    let restored = panel.setFrameUsingName(QuickSendPanelFrameSaver.frameName)
    if !restored || panel.frame.width < Layout.minSize.width
      || panel.frame.height < Layout.minSize.height
    {
      position(panel)
    }
    panel.makeKeyAndOrderFront(nil)
  }

  func hide() {
    panel?.orderOut(nil)
  }

  /// Snap the panel between its expanded size and the compact collapsed bar — both
  /// width and height. Collapse remembers the current size and shrinks to
  /// `collapsedSize` (lowering the panel's minimum to the bar first); Expand restores
  /// the remembered size (raising the minimum back afterwards) so the bar can be far
  /// narrower than the expanded composer's floor. The top-left corner stays put.
  /// `QuickSendView` drives this from its Expand/Collapse buttons; the height change
  /// flips the view's collapsed/expanded layout via its geometry observer.
  func setExpanded(_ expanded: Bool) {
    guard let panel else { return }
    var frame = panel.frame
    let top = frame.maxY
    if expanded {
      // Grow first (allowed under the still-low collapsed minimum), then raise the floor.
      let size = lastExpandedSize ?? Layout.expandedSize
      frame.size = size
      frame.origin.y = top - size.height
      panel.setFrame(frame, display: true, animate: true)
      panel.minSize = Layout.minSize
    } else {
      // Remember the size to restore, lower the floor to the bar, then shrink.
      lastExpandedSize = frame.size
      panel.minSize = Layout.collapsedSize
      frame.size = Layout.collapsedSize
      frame.origin.y = top - Layout.collapsedSize.height
      panel.setFrame(frame, display: true, animate: true)
    }
  }

  private func makePanel() -> NSPanel? {
    guard let store else { return nil }
    let hosting = NSHostingController(
      rootView: QuickSendPanelRoot(store: store, onSetExpanded: { [weak self] in self?.setExpanded($0) })
    )
    // Let the panel own its size — user-resizable and restored from the saved
    // frame — instead of the hosting controller snapping it to the content's
    // ideal size.
    hosting.sizingOptions = []
    // Titled but chromeless: a `.titled` + `.resizable` window is genuinely
    // user-resizable (drag any edge) AND enforces `minSize`, whereas a
    // `.borderless` window is neither — it has no frame view, so it ignored
    // `minSize` and silently collapsed to 0×0, which the frame autosave then
    // persisted. `.fullSizeContentView` plus a transparent, hidden title bar and
    // hidden traffic-light buttons reclaim the chrome so `QuickSendView` still
    // paints its own rounded `.regularMaterial` panel edge-to-edge. The subclass
    // re-enables key status so the composer accepts typing; `.nonactivatingPanel`
    // keeps the main app in the background.
    let panel = KeyableQuickSendPanel(
      contentRect: NSRect(origin: .zero, size: Layout.defaultSize),
      styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentViewController = hosting
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    // Stay above every other app, on every Space, and over full-screen apps, so the
    // composer remains reachable no matter what's frontmost (pairs with the global
    // ⌘⇧P hotkey that can summon it from any app). `.floating` keeps it above normal
    // windows app-wide; the collection behavior adds cross-Space + full-screen reach.
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.isMovableByWindowBackground = true
    panel.isExcludedFromWindowsMenu = true
    panel.minSize = Layout.minSize
    // The saver persists the frame on user gestures only — see its doc comment
    // for why `frameAutosaveName` can't be used here.
    panel.delegate = frameSaver
    return panel
  }

  /// Resets the panel to its default size and centers it on the active screen —
  /// the first-show default before any saved user frame, and the repair path when
  /// the dismissed panel's empty content has collapsed the window.
  private func position(_ panel: NSPanel) {
    panel.setContentSize(Layout.defaultSize)
    guard let visible = (NSScreen.main ?? panel.screen)?.visibleFrame else {
      panel.center()
      return
    }
    let size = panel.frame.size
    panel.setFrameOrigin(
      NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
    )
  }
}

/// Persists the panel's user-chosen frame. We deliberately do NOT use
/// `frameAutosaveName`: it auto-saves on EVERY frame change, including the
/// transient collapse to ~0×32 that happens when `QuickSendPanelRoot` renders
/// empty on dismiss (`state.quickSend = nil`) — which would clobber the saved
/// size. Instead we save only after genuine user gestures (finishing a drag
/// resize, or moving the panel) and ignore any frame smaller than the window's
/// minimum, so a collapsed frame is never written. `show()` restores via
/// `setFrameUsingName(_:)` using the same defaults-backed key.
@MainActor
private final class QuickSendPanelFrameSaver: NSObject, NSWindowDelegate {
  /// Backing key for the saved frame in `UserDefaults` ("NSWindow Frame <name>"),
  /// shared by `saveFrame(usingName:)` here and `setFrameUsingName(_:)` in `show()`.
  static let frameName = "QuickSendPanel"

  func windowDidEndLiveResize(_ notification: Notification) {
    saveFrame(of: notification.object as? NSWindow)
  }

  func windowDidMove(_ notification: Notification) {
    saveFrame(of: notification.object as? NSWindow)
  }

  private func saveFrame(of window: NSWindow?) {
    guard let window else { return }
    // A frame below the window's minimum is the dismissed-panel collapse, never a
    // real user size — don't let it overwrite the saved frame.
    guard window.frame.width >= window.minSize.width,
      window.frame.height >= window.minSize.height
    else { return }
    window.saveFrame(usingName: Self.frameName)
  }
}

/// The quick-send composer must accept keyboard input, so this `NSPanel`
/// subclass force-allows key-window status — a guarantee that holds regardless
/// of the style mask or the `.nonactivatingPanel` flag (which suppresses app
/// activation, not key status).
private final class KeyableQuickSendPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}
