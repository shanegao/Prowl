import Foundation

/// Specifies the artwork to use for a tab icon. `systemSymbol` is the
/// always-renderable SF Symbol that the current call sites paint
/// (`Image(systemName:)` in `ShelfSpineView` and
/// `TerminalTabLabelView`). `assetName` is an optional, more specific
/// PNG/SVG shipped in the asset catalog — reserved for tools where
/// stock SF Symbols don't read well (claude, docker, npm, …).
///
/// Today no call site reads `assetName`, so `assetName`-bearing
/// entries gracefully degrade to their `systemSymbol`. To wire real
/// asset rendering:
///   1. Ship the artwork in the app's asset catalog.
///   2. Add an `assetName:` argument on the relevant `CommandIconMap`
///      entry (or use it on a new `TabIconSource(systemSymbol:assetName:)`).
///   3. Extend the icon-rendering call sites to prefer `assetName`
///      when present (`Image(_:)`) and fall back to `systemSymbol`
///      when the asset is missing.
struct TabIconSource: Equatable, Hashable, Sendable {
  /// SF Symbol drawn via `Image(systemName:)`. Always set so callers
  /// have something renderable even before asset rendering is wired.
  let systemSymbol: String
  /// Asset catalog entry, if any. Renderers that support assets
  /// should prefer this when set; renderers that don't will keep
  /// painting `systemSymbol` and the user gets a graceful fallback.
  let assetName: String?

  init(systemSymbol: String, assetName: String? = nil) {
    self.systemSymbol = systemSymbol
    self.assetName = assetName
  }
}
