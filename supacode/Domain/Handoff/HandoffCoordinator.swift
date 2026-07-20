import Foundation

/// The outgoing side of a handoff as observed on the selected pane: the
/// session context persisted into the artifact, the argv-derived launch
/// observation, and the pid-anchored native session used for preparation.
nonisolated struct HandoffSourceContext: Sendable, Equatable {
  let sessionContext: HandoffStore.SessionContext?
  let observation: AgentLaunchObservation?
  let session: AgentSession?
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

  /// Resume the source read-only and transcribe its validated reply into
  /// `current.md`. A nil request means preparation is skipped: no safe
  /// session, an unsupported adapter, or `--no-prepare`.
  func prepare(_ request: AgentResumeRequest?, now: Date) async -> HandoffPreparationOutcome {
    guard let request else { return .skipped }
    let store = self.store
    do {
      let reply = try await resume(request, store.rootURL)
      return await Task.detached {
        store.applyPreparationReply(reply, now: now) ? HandoffPreparationOutcome.completed : .failed
      }.value
    } catch {
      return .failed
    }
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
    let store = self.store
    let result = try await Task.detached {
      try store.save(
        outgoingAgent: outgoingAgent,
        sessionContext: sessionContext,
        note: note,
        preparation: preparation,
        now: now
      )
    }.value
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
    let store = self.store
    let from = outgoingAgent ?? "agent"
    let (save, archivedPath) = try await Task.detached {
      let save = try store.save(
        outgoingAgent: outgoingAgent,
        sessionContext: sessionContext,
        note: nil,
        now: now
      )
      let archivedPath = try store.archiveCurrent(from: from, toAgent: toAgent, now: now)
      return (save, archivedPath)
    }.value
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
