import SwiftUI

/// Coordinates exclusive presentation among hover-driven toolbar popover
/// buttons (Sidebar, Active Agents, Notifications, …).
///
/// **Why this exists.** Each toolbar popover button owns its own
/// `@State isPresented` and triggers `.popover(isPresented:)`. AppKit's
/// `NSPopover` from the same window is internally arbitrated — opening a
/// second popover force-closes the first. Without coordination, fast
/// cursor sweeps between two popover buttons hit a state-vs-AppKit
/// disagreement: SwiftUI still thinks both `isPresented` are `true`
/// (open is synchronous-immediate, close is async-deferred through a
/// 150 ms task), but AppKit only has one popover live. SwiftUI sees the
/// disagreement and tries to re-present the force-closed one, which
/// force-closes the other, and so on — a feedback loop that pegs the
/// main thread and freezes the app.
///
/// **How it fixes the freeze.** Each button calls `claim(owner:dismiss:)`
/// when its `isPresented` flips to `true`. If a different owner was
/// already claimed, this coordinator runs the previous owner's dismiss
/// closure first (synchronously setting the previous view's
/// `isPresented = false`). By the time SwiftUI commits the next view
/// update, the previous popover's `isPresented` is already `false`, so
/// AppKit only sees a clean "close A, then open B" sequence — no
/// concurrent-live state, no feedback loop.
///
/// **Lifetime / injection.** One instance is created in
/// `SupacodeApp.init()` and injected via `.environment(coordinator)` on
/// the main `Window` scene. Settings/other windows that don't wire this
/// coordinator in are unaffected — they get the same default instance
/// but don't use it, so its `activeOwner` stays nil for them.
@MainActor
@Observable
final class PopoverPresentationCoordinator {
  /// UUID of the owner that currently has presentation, or `nil` when no
  /// coordinated popover is open. Owners are identified by a UUID that
  /// each popover button creates as `@State` (stable per view-instance,
  /// distinct between buttons).
  private var activeOwner: UUID?

  /// Closure that closes the active owner's popover. Invoked when a new
  /// owner claims — runs synchronously inside `claim(...)` so SwiftUI
  /// commits the previous owner's `isPresented = false` before the new
  /// owner's `isPresented = true` reaches AppKit.
  private var dismissActive: (() -> Void)?

  /// Mark `owner` as the actively presented popover. If a *different*
  /// owner held the slot, its `dismiss` closure runs first.
  ///
  /// - Parameters:
  ///   - owner: Stable UUID identifying the calling popover button.
  ///   - dismiss: Closure that sets the caller's `isPresented = false`.
  ///     Captures `Binding<Bool>` or `@State` writer; kept until release.
  func claim(owner: UUID, dismiss: @escaping () -> Void) {
    if let activeOwner, activeOwner != owner {
      dismissActive?()
    }
    activeOwner = owner
    dismissActive = dismiss
  }

  /// Release the slot if `owner` is the active one. No-op otherwise —
  /// when claim transferred ownership to a new owner, the previous
  /// owner's eventual `release` is harmless: the slot is already
  /// reassigned, so this guard makes the operation idempotent and safe.
  func release(owner: UUID) {
    guard activeOwner == owner else { return }
    activeOwner = nil
    dismissActive = nil
  }
}
