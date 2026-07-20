import Foundation

/// The outgoing side of a handoff as observed on the selected pane: the
/// session context persisted into the artifact, the argv-derived launch
/// observation, and the pid-anchored native session used for preparation.
nonisolated struct HandoffSourceContext: Sendable, Equatable {
  let sessionContext: HandoffStore.SessionContext?
  let observation: AgentLaunchObservation?
  let session: AgentSession?
}

/// A source preparation reply before it is accepted for persistence.
/// HUD callers keep this transient until their reducer accepts the briefing
/// completion; a cancelled HUD must never let a late reply mutate the artifact.
nonisolated enum HandoffPreparationReply: Equatable, Sendable {
  case reply(String)
  case skipped
  case failed
}

/// Shared orchestration core for a handoff: optional source-authored
/// preparation, the mechanical context save, the pre-launch archive, and the
/// transition log line. The CLI's `HandoffCommandHandler` and the Command
/// Palette reducer drive this one sequence so the entry points cannot drift;
/// a future toolbar UI becomes a third caller of the same type.
///
/// Launching the receiving agent stays with the caller — the CLI needs the
/// synchronously resolved pane for its payload while the palette fires a
/// terminal command — but every persisted artifact and log format lives here.
nonisolated struct HandoffCoordinator: Sendable {
  /// Resumes a source session headlessly and returns its reply text.
  typealias Resume = @Sendable (AgentResumeRequest, URL) async throws -> String

  let store: HandoffStore
  private let resume: Resume

  init(store: HandoffStore, resume: @escaping Resume) {
    self.store = store
    self.resume = resume
  }

  /// Everything `handoff to` persists before the receiving agent launches.
  struct TransitionArtifacts: Sendable {
    let preparation: HandoffPreparationOutcome
    let save: HandoffStore.SaveResult
    let archivedPath: String?
  }

  /// How the receiving agent was (or wasn't) started, for the log line.
  enum LaunchDisposition: Sendable {
    /// Launched into a resolved pane (CLI path).
    case pane(String)
    /// Launch was handed to the terminal without a resolved pane (palette path).
    case requested
    /// `--no-launch`.
    case skipped
    /// The launch attempt returned no pane.
    case failed
  }

  /// Resume the source read-only without mutating the artifact. Staged callers
  /// must explicitly accept and apply a reply so cancellation remains a real
  /// filesystem transaction boundary.
  func collectPreparation(_ request: AgentResumeRequest?) async -> HandoffPreparationReply {
    guard let request else { return .skipped }
    do {
      return .reply(try await resume(request, store.rootURL))
    } catch {
      return .failed
    }
  }

  /// Validate and transcribe an accepted preparation reply into `current.md`.
  /// A cancelled task never writes, including when its resume dependency
  /// returned a reply after observing cancellation late.
  func applyPreparation(_ reply: HandoffPreparationReply, now: Date) -> HandoffPreparationOutcome {
    switch reply {
    case .reply(let text):
      guard !Task.isCancelled else { return .skipped }
      return store.applyPreparationReply(text, now: now) ? .completed : .failed
    case .skipped:
      return .skipped
    case .failed:
      return .failed
    }
  }

  /// Resume, then immediately apply the reply for single-shot callers such as
  /// the CLI. HUD callers use `collectPreparation` and `applyPreparation`
  /// separately so reducer state decides whether a reply may be persisted.
  func prepare(_ request: AgentResumeRequest?, now: Date) async -> HandoffPreparationOutcome {
    applyPreparation(await collectPreparation(request), now: now)
  }

  /// Refresh generated context with an already-decided preparation outcome.
  /// Staged callers collect a reply before the reducer accepts it, while
  /// `save`/`makeTransitionArtifacts` compose collection and persistence.
  func saveArtifact(
    outgoingAgent: String?,
    sessionContext: HandoffStore.SessionContext?,
    note: String?,
    preparation: HandoffPreparationOutcome?,
    now: Date
  ) async throws -> HandoffStore.SaveResult {
    let store = self.store
    return try await Task.detached {
      try store.save(
        outgoingAgent: outgoingAgent,
        sessionContext: sessionContext,
        note: note,
        preparation: preparation,
        now: now
      )
    }.value
  }

  /// Archive the combined artifact snapshot ahead of the destination launch.
  func archive(from: String, toAgent: String, now: Date) async throws -> String? {
    let store = self.store
    return try await Task.detached {
      try store.archiveCurrent(from: from, toAgent: toAgent, now: now)
    }.value
  }

  /// `handoff save`: prepare, then refresh generated context, recording the
  /// preparation outcome on the single save log line.
  func save(
    outgoingAgent: String?,
    sessionContext: HandoffStore.SessionContext?,
    note: String?,
    preparationRequest: AgentResumeRequest?,
    now: Date
  ) async throws -> (result: HandoffStore.SaveResult, preparation: HandoffPreparationOutcome) {
    let preparation = await prepare(preparationRequest, now: now)
    let result = try await saveArtifact(
      outgoingAgent: outgoingAgent,
      sessionContext: sessionContext,
      note: note,
      preparation: preparation,
      now: now
    )
    return (result, preparation)
  }

  /// `handoff to`, up to the destination launch: prepare, refresh generated
  /// context, and archive the combined artifact snapshot. The preparation
  /// outcome is recorded on the transition log line, not the save line.
  func makeTransitionArtifacts(
    outgoingAgent: String?,
    toAgent: String,
    sessionContext: HandoffStore.SessionContext?,
    preparationRequest: AgentResumeRequest?,
    now: Date
  ) async throws -> TransitionArtifacts {
    let preparation = await prepare(preparationRequest, now: now)
    let save = try await saveArtifact(
      outgoingAgent: outgoingAgent,
      sessionContext: sessionContext,
      note: nil,
      preparation: nil,
      now: now
    )
    let archivedPath = try await archive(from: outgoingAgent ?? "agent", toAgent: toAgent, now: now)
    return TransitionArtifacts(preparation: preparation, save: save, archivedPath: archivedPath)
  }

  /// Append the single transition line; every entry point shares this format.
  func logTransition(
    from: String,
    toAgent: String,
    disposition: LaunchDisposition,
    preparation: HandoffPreparationOutcome,
    archivedPath: String? = nil,
    note: String? = nil,
    source: String? = nil,
    now: Date
  ) async {
    let line = Self.transitionLogLine(
      from: from,
      toAgent: toAgent,
      disposition: disposition,
      preparation: preparation,
      archivedPath: archivedPath,
      note: note,
      source: source
    )
    let store = self.store
    try? await Task.detached {
      try store.appendLog(line, now: now)
    }.value
  }

  static func transitionLogLine(
    from: String,
    toAgent: String,
    disposition: LaunchDisposition,
    preparation: HandoffPreparationOutcome,
    archivedPath: String? = nil,
    note: String? = nil,
    source: String? = nil
  ) -> String {
    let launchPart =
      switch disposition {
      case .pane(let paneID): "  pane=\(paneID)"
      case .requested: "  launch=requested"
      case .skipped: "  (no launch)"
      case .failed: "  launch=failed"
      }
    var line = "\(from) → \(toAgent)\(launchPart)  preparation=\(preparation.rawValue)"
    if case .failed = disposition, let archivedPath {
      line += "  archive=\(archivedPath)"
    }
    if let source {
      line += "  source=\(source)"
    }
    if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      line += "  note=\"\(note.replacing("\n", with: " "))\""
    }
    return line
  }
}
