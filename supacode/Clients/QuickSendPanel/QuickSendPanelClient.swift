import ComposableArchitecture

/// Reducer-facing seam for the quick-send panel. Wraps the imperative
/// `QuickSendPanelManager` (an AppKit non-activating `NSPanel`) so `AppFeature`
/// can show/hide it as an effect, the same way `SettingsWindowClient` fronts the
/// settings window.
struct QuickSendPanelClient {
  var show: @MainActor @Sendable () -> Void
  var hide: @MainActor @Sendable () -> Void
}

extension QuickSendPanelClient: DependencyKey {
  static let liveValue = QuickSendPanelClient(
    show: { QuickSendPanelManager.shared.show() },
    hide: { QuickSendPanelManager.shared.hide() }
  )

  static let testValue = QuickSendPanelClient(show: {}, hide: {})
}

extension DependencyValues {
  var quickSendPanelClient: QuickSendPanelClient {
    get { self[QuickSendPanelClient.self] }
    set { self[QuickSendPanelClient.self] = newValue }
  }
}
