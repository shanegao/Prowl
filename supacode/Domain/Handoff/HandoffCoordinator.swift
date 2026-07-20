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
      let augmented = await Task.detached {
        Self.embeddingCurrentArtifact(into: request, store: store)
      }.value
      let reply = try await resume(augmented, store.rootURL)
      return await Task.detached {
        store.applyPreparationReply(reply, now: now) ? HandoffPreparationOutcome.completed : .failed
      }.value
    } catch {
      return .failed
    }
  }

  /// Append the current agent-authored artifact to the preparation prompt.
  /// The resume is read-only and its prompt bars file access, so this is the
  /// only way the source can actually carry earlier notes forward. The
  /// seeded template carries no prose and is not worth embedding.
  nonisolated static func embeddingCurrentArtifact(
    into request: AgentResumeRequest,
    store: HandoffStore
  ) -> AgentResumeRequest {
    guard
      let existing = try? String(contentsOf: store.currentURL, encoding: .utf8),
      existing.trimmingCharacters(in: .whitespacesAndNewlines)
        != HandoffStore.template.trimmingCharacters(in: .whitespacesAndNewlines)
    else { return request }
    return AgentResumeRequest(
      agent: request.agent,
      session: request.session,
      prompt: request.prompt
        + "\n\nCurrent contents of .prowl/handoff/current.md (carry forward what is still relevant):\n\n"
        + existing,
      model: request.model
    )
  }

  /// Refresh generated context with an already-decided preparation outcome.
  /// Staged callers (the HUD) run `prepare` separately so they can report
  /// progress and support Skip; `save`/`makeTransitionArtifacts` compose this
  /// for single-shot callers.
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
