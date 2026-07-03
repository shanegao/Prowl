import Foundation

/// Coalesces bursts of calls into a single delayed action: each `schedule`
/// replaces the pending action and restarts the interval, and a cancelled
/// action never fires.
///
/// Centralizes the two easy-to-miss parts of the hand-rolled pattern: catching
/// the sleep's `CancellationError` *and* re-checking `Task.isCancelled` once
/// the sleep resumes, so a cancelled task can't slip through and run anyway.
@MainActor
final class Debouncer {
  private let interval: Duration
  private let clock: any Clock<Duration>
  private var task: Task<Void, Never>?

  init(interval: Duration, clock: any Clock<Duration> = ContinuousClock()) {
    self.interval = interval
    self.clock = clock
  }

  /// True when no action is pending, i.e. the next `schedule` starts a fresh
  /// debounce window. Callers implementing leading-edge behavior check this to
  /// decide whether to act immediately instead.
  var isIdle: Bool { task == nil }

  /// Schedules `action` to run after the interval, replacing any pending action.
  func schedule(_ action: @escaping @MainActor () async -> Void) {
    task?.cancel()
    task = Task { [interval, clock] in
      do {
        try await clock.sleep(for: interval)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self.task = nil
      await action()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}

/// A `Debouncer` variant that maintains an independent debounce window per key,
/// for stores that coalesce events per worktree, repository, or host.
@MainActor
final class KeyedDebouncer<Key: Hashable & Sendable> {
  private let interval: Duration
  private let clock: any Clock<Duration>
  private var tasks: [Key: Task<Void, Never>] = [:]

  init(interval: Duration, clock: any Clock<Duration> = ContinuousClock()) {
    self.interval = interval
    self.clock = clock
  }

  /// Schedules `action` for `key` after `interval` (defaulting to the instance
  /// interval), replacing any action already pending for the same key.
  func schedule(_ key: Key, after interval: Duration? = nil, _ action: @escaping @MainActor () async -> Void) {
    tasks[key]?.cancel()
    let interval = interval ?? self.interval
    tasks[key] = Task { [clock] in
      do {
        try await clock.sleep(for: interval)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self.tasks.removeValue(forKey: key)
      await action()
    }
  }

  func cancel(_ key: Key) {
    tasks.removeValue(forKey: key)?.cancel()
  }

  /// Cancels every pending action, or only those whose key matches `shouldCancel`.
  func cancelAll(where shouldCancel: (Key) -> Bool = { _ in true }) {
    for key in Array(tasks.keys) where shouldCancel(key) {
      tasks.removeValue(forKey: key)?.cancel()
    }
  }
}
