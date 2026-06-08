import ComposableArchitecture
import Foundation

struct TerminalClient {
  var send: @MainActor @Sendable (Command) -> Void
  var events: @MainActor @Sendable () -> AsyncStream<Event>
  var canvasFocusedWorktreeID: @MainActor @Sendable () -> Worktree.ID?
  /// Active surface in the selected tab. Lets the reducer capture the target
  /// synchronously before an async dispatch races against AppKit focus reshuffle
  /// (e.g. when a palette dismisses and the leftmost pane reclaims first responder).
  var selectedSurfaceID: @MainActor @Sendable (Worktree.ID) -> UUID?
  var latestUnreadNotification: @MainActor @Sendable () -> NotificationLocation?
  var focusSurface: @MainActor @Sendable (Worktree.ID, UUID) -> Bool
  var markNotificationRead: @MainActor @Sendable (Worktree.ID, UUID) -> Void
  var markNotificationsReadForSurface: @MainActor @Sendable (Worktree.ID, UUID) -> Void
  /// Types `text` into the pane identified by `surfaceID` (regardless of current
  /// focus) and presses Return when `trailingEnter` is true. Returns whether the
  /// text was actually delivered — `false` when the worktree has no terminal
  /// state or the target surface is gone (the agent pane closed between composing
  /// and sending), so the caller can surface the failure instead of silently
  /// dropping the user's message. Routes through `WorktreeTerminalState`'s
  /// `insertCommittedText(_:in:)` + `submitLine(in:)` — the same surface-level
  /// injection the `prowl send` CLI uses. Backs the quick-send-to-agent panel.
  var sendTextToSurface: @MainActor @Sendable (Worktree, UUID, String, Bool) -> Bool
  /// Sends a single key token (e.g. "1", "enter", "esc") to the pane identified by
  /// `surfaceID` as a real keypress — the path that answers an agent's TUI prompt
  /// (a Claude permission selection), where pasted text wouldn't register. Returns
  /// whether it was delivered. Mirrors the `prowl key` CLI's key injection.
  var sendKeyToken: @MainActor @Sendable (Worktree, UUID, String) -> Bool
  /// Reads the pane's visible text and parses a Claude permission prompt from it,
  /// or `nil` when none is found. Backs the actionable permission notification.
  var readPermissionPrompt: @MainActor @Sendable (Worktree.ID, UUID) -> ClaudePermissionPrompt?

  enum Command: Equatable {
    case createTab(Worktree, runSetupScriptIfNew: Bool)
    case createTabWithInput(
      Worktree,
      input: String,
      runSetupScriptIfNew: Bool,
      autoCloseOnSuccess: Bool,
      customCommandName: String? = nil,
      customCommandIcon: String? = nil
    )
    case createSplitWithInput(
      Worktree,
      direction: UserCustomSplitDirection,
      input: String,
      autoCloseOnSuccess: Bool,
      customCommandName: String? = nil,
      customCommandIcon: String? = nil
    )
    case createTabInDirectory(Worktree, directory: URL)
    case focusOrCreateTabInDirectory(Worktree, directory: URL, title: String?)
    case ensureInitialTab(Worktree, runSetupScriptIfNew: Bool, focusing: Bool)
    case runScript(Worktree, script: String)
    case insertText(Worktree, text: String)
    case stopRunScript(Worktree)
    case closeFocusedTab(Worktree)
    case closeFocusedSurface(Worktree)
    case performBindingAction(Worktree, action: String)
    case performBindingActionOnSurface(Worktree, surfaceID: UUID, action: String)
    case startSearch(Worktree)
    case searchSelection(Worktree)
    case navigateSearchNext(Worktree)
    case navigateSearchPrevious(Worktree)
    case endSearch(Worktree)
    case focusSelectedTab(Worktree)
    case prune(Set<Worktree.ID>)
    case setNotificationsEnabled(Bool)
    case setCommandFinishedNotification(enabled: Bool, threshold: Int)
    case setCanvasMode(Bool)
    case setSelectedWorktreeID(Worktree.ID?)
    /// Externally requested canvas focus. `WorktreeTerminalManager` writes the
    /// value to `canvasFocusedWorktreeID`; `CanvasView` observes that field and
    /// switches its primary card to the worktree's first tab when the request
    /// diverges from the current primary. Used by repo-canvas sidebar taps to
    /// move focus to the tapped worktree without exiting canvas.
    case setCanvasFocusedWorktreeID(Worktree.ID?)
    case saveLayoutSnapshot
    case restoreLayoutSnapshot(worktrees: [Worktree])
    case presentTabIconPicker(Worktree)
  }

  enum Event: Equatable {
    case customCommandSucceeded(worktreeID: Worktree.ID, name: String, durationMs: Int)
    case notificationReceived(worktreeID: Worktree.ID, surfaceID: UUID, title: String, body: String)
    case notificationIndicatorChanged(count: Int)
    case tabCreated(worktreeID: Worktree.ID)
    case tabClosed(worktreeID: Worktree.ID, remainingTabs: Int)
    case focusChanged(worktreeID: Worktree.ID, surfaceID: UUID)
    case taskStatusChanged(worktreeID: Worktree.ID, status: WorktreeTaskStatus)
    case agentEntryChanged(ActiveAgentEntry)
    case agentEntryRemoved(ActiveAgentEntry.ID)
    case runScriptStatusChanged(worktreeID: Worktree.ID, isRunning: Bool)
    case commandPaletteToggleRequested(worktreeID: Worktree.ID)
    case setupScriptConsumed(worktreeID: Worktree.ID)
    case fontSizeChanged(Float32?)
    case layoutRestored(selectedWorktreeID: Worktree.ID?)
    case layoutRestoreFailed(message: String)
  }
}

extension TerminalClient: DependencyKey {
  static let liveValue = TerminalClient(
    send: { _ in fatalError("TerminalClient.send not configured") },
    events: { fatalError("TerminalClient.events not configured") },
    canvasFocusedWorktreeID: { nil },
    selectedSurfaceID: { _ in nil },
    latestUnreadNotification: { nil },
    focusSurface: { _, _ in false },
    markNotificationRead: { _, _ in },
    markNotificationsReadForSurface: { _, _ in },
    sendTextToSurface: { _, _, _, _ in false },
    sendKeyToken: { _, _, _ in false },
    readPermissionPrompt: { _, _ in nil }
  )

  static let testValue = TerminalClient(
    send: { _ in },
    events: { AsyncStream { $0.finish() } },
    canvasFocusedWorktreeID: { nil },
    selectedSurfaceID: { _ in nil },
    latestUnreadNotification: { nil },
    focusSurface: { _, _ in false },
    markNotificationRead: { _, _ in },
    markNotificationsReadForSurface: { _, _ in },
    sendTextToSurface: { _, _, _, _ in true },
    sendKeyToken: { _, _, _ in false },
    readPermissionPrompt: { _, _ in nil }
  )
}

extension DependencyValues {
  var terminalClient: TerminalClient {
    get { self[TerminalClient.self] }
    set { self[TerminalClient.self] = newValue }
  }
}
