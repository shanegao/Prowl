import ComposableArchitecture
import ConcurrencyExtras
import DependenciesTestSupport
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct HandoffHudFeatureTests {
  private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "handoff-hud-tests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.standardizedFileURL
  }

  private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private func makeWorktree(root: URL) -> Worktree {
    Worktree(
      id: root.path(percentEncoded: false),
      name: "feature-handoff",
      detail: "feature-handoff",
      workingDirectory: root,
      repositoryRootURL: root
    )
  }

  private func makeSourceContext(
    agent: String = "codex",
    confidence: AgentSession.Confidence = .exact,
    observation: AgentLaunchObservation? = nil
  ) -> HandoffSourceContext {
    HandoffSourceContext(
      sessionContext: HandoffStore.SessionContext(
        agent: agent,
        paneID: "pane-0",
        paneTitle: agent,
        source: "terminal-scrollback",
        confidence: "fallback",
        excerptText: "excerpt"
      ),
      observation: observation,
      session: AgentSession(
        id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
        transcriptPath: nil,
        source: .openFile,
        confidence: confidence
      )
    )
  }

  private nonisolated static let usableReply = """
    # Handoff

    ## Objective
    Finish the HUD.

    ## Current State
    Reducer under test.

    ## Next Steps
    1. Ship it.
    """

  // MARK: - State construction

  @Test func makeRequiresDetectedAgent() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let worktree = makeWorktree(root: root)

    #expect(HandoffHudFeature.State.make(worktree: worktree, source: nil) == nil)
    let noAgent = HandoffSourceContext(
      sessionContext: HandoffStore.SessionContext(
        agent: nil,
        paneID: "pane-0",
        paneTitle: nil,
        source: "terminal-scrollback",
        confidence: "fallback",
        excerptText: nil
      ),
      observation: nil,
      session: nil
    )
    #expect(HandoffHudFeature.State.make(worktree: worktree, source: noAgent) == nil)
  }

  @Test func makeBuildsRegistryTargetsAndMarksCurrentAgent() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let state = try #require(
      HandoffHudFeature.State.make(worktree: makeWorktree(root: root), source: makeSourceContext())
    )

    let agentKinds = state.targets.compactMap(\.agent)
    #expect(agentKinds == AgentRuntimeAdapterRegistry.launchableAgents)
    #expect(state.targets.last?.kind == .briefOnly)
    let codexTarget = try #require(state.targets.first { $0.agent == .codex })
    #expect(codexTarget.isCurrentAgent)
    let claudeTarget = try #require(state.targets.first { $0.agent == .claude })
    #expect(!claudeTarget.isCurrentAgent)
    #expect(state.source.preparationRequest != nil)
    #expect(state.source.displayName == "codex")
  }

  @Test func makeWithMediumConfidenceSkipsPreparationRequest() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let state = try #require(
      HandoffHudFeature.State.make(
        worktree: makeWorktree(root: root),
        source: makeSourceContext(confidence: .medium)
      )
    )
    #expect(state.source.preparationRequest == nil)
  }

  @Test func makeSurfacesCarriedOverUnrestrictedMode() throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let state = try #require(
      HandoffHudFeature.State.make(
        worktree: makeWorktree(root: root),
        source: makeSourceContext(
          observation: AgentLaunchObservation(model: "gpt-5.4", executionMode: .unrestricted)
        )
      )
    )
    let claudeTarget = try #require(state.targets.first { $0.agent == .claude })
    #expect(claudeTarget.subtitle.contains("bypass permissions"))
    #expect(claudeTarget.subtitle.contains("codex"))
    let briefTarget = try #require(state.targets.first { $0.kind == .briefOnly })
    #expect(!briefTarget.subtitle.contains("bypass"))
  }

  // MARK: - Selection

  @Test func selectionMovesWrapAround() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    var state = try #require(
      HandoffHudFeature.State.make(worktree: makeWorktree(root: root), source: makeSourceContext())
    )
    state.selectedIndex = 0
    let count = state.targets.count

    let store = TestStore(initialState: state) { HandoffHudFeature() }
    store.exhaustivity = .on

    await store.send(.moveSelection(delta: -1)) {
      $0.selectedIndex = count - 1
    }
    await store.send(.moveSelection(delta: 1)) {
      $0.selectedIndex = 0
    }
    await store.send(.setSelectedIndex(count))  // out of bounds: ignored
    await store.send(.setSelectedIndex(1)) {
      $0.selectedIndex = 1
    }
  }

  // MARK: - Full hand-off run

  @Test(.dependencies) func handOffRunPersistsArtifactsAndLaunches() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let worktree = makeWorktree(root: root)
    var initial = try #require(
      HandoffHudFeature.State.make(worktree: worktree, source: makeSourceContext())
    )
    let claudeIndex = try #require(initial.targets.firstIndex { $0.agent == .claude })
    initial.selectedIndex = claudeIndex

    let sent = LockIsolated<[TerminalClient.Command]>([])
    let resumed = LockIsolated<AgentResumeRequest?>(nil)
    let startedAt = Date(timeIntervalSince1970: 1_760_000_000)

    let store = TestStore(initialState: initial) {
      HandoffHudFeature()
    } withDependencies: {
      $0.date.now = startedAt
      $0[TerminalClient.self].send = { command in
        sent.withValue { $0.append(command) }
      }
      $0[AgentRuntimeClient.self] = AgentRuntimeClient(
        resume: { request, _ in
          resumed.setValue(request)
          return Self.usableReply
        }
      )
    }

    let claudeTarget = initial.targets[claudeIndex]
    await store.send(.confirmSelection) {
      $0.phase = .running(
        HandoffHudRun(
          target: claudeTarget,
          startedAt: startedAt,
          stages: [.briefing, .saving, .archiving, .launching],
          stage: .briefing
        )
      )
    }
    await store.receive(\.briefingFinished) {
      $0.phase = .running(
        HandoffHudRun(
          target: claudeTarget,
          startedAt: startedAt,
          stages: [.briefing, .saving, .archiving, .launching],
          stage: .saving,
          preparation: .completed
        )
      )
    }
    await store.receive(\.savingFinished) {
      $0.phase = .running(
        HandoffHudRun(
          target: claudeTarget,
          startedAt: startedAt,
          stages: [.briefing, .saving, .archiving, .launching],
          stage: .archiving,
          preparation: .completed
        )
      )
    }
    await store.receive(\.archivingFinished) {
      $0.phase = .running(
        HandoffHudRun(
          target: claudeTarget,
          startedAt: startedAt,
          stages: [.briefing, .saving, .archiving, .launching],
          stage: .launching,
          preparation: .completed
        )
      )
    }
    await store.receive(\.launchFinished) {
      $0.phase = .finished(.handedOff(agentDisplayName: "Claude Code"))
    }

    // Source session was resumed for the brief and transcribed.
    #expect(resumed.value?.agent == .codex)
    let handoffStore = HandoffStore(rootURL: root)
    let current = try String(contentsOf: handoffStore.currentURL, encoding: .utf8)
    #expect(current.contains("Finish the HUD."))

    // Mechanical context, archive, and the unified transition log line exist.
    #expect(FileManager.default.fileExists(atPath: handoffStore.contextURL.path(percentEncoded: false)))
    let archives = try FileManager.default.contentsOfDirectory(atPath: handoffStore.archiveDirectory.path)
    #expect(archives.contains { $0.contains("codex-to-claude") })
    let log = try String(contentsOf: handoffStore.logURL, encoding: .utf8)
    #expect(log.contains("codex → claude"))
    #expect(log.contains("launch=requested"))
    #expect(log.contains("preparation=completed"))
    #expect(log.contains("source=agents-hud"))

    // The receiving tab was requested with the adapter invocation.
    guard case .createTabWithInput(_, let input, let workingDirectory, _, _, let name, _)? = sent.value.first
    else {
      Issue.record("Expected createTabWithInput, got \(sent.value)")
      return
    }
    #expect(input.contains("'claude'"))
    #expect(input.contains(HandoffCommandHandler.kickoffPrompt()))
    #expect(workingDirectory == root)
    #expect(name == "Hand off → Claude Code")
  }

  @Test(.dependencies) func briefOnlyRunSavesWithoutArchiveOrLaunch() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let worktree = makeWorktree(root: root)
    var initial = try #require(
      HandoffHudFeature.State.make(worktree: worktree, source: makeSourceContext())
    )
    let briefIndex = try #require(initial.targets.firstIndex { $0.kind == .briefOnly })
    initial.selectedIndex = briefIndex

    let sent = LockIsolated<[TerminalClient.Command]>([])
    let store = TestStore(initialState: initial) {
      HandoffHudFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0[TerminalClient.self].send = { command in
        sent.withValue { $0.append(command) }
      }
      $0[AgentRuntimeClient.self] = AgentRuntimeClient(resume: { _, _ in Self.usableReply })
    }
    store.exhaustivity = .off

    await store.send(.confirmSelection)
    await store.receive(\.briefingFinished)
    await store.receive(\.savingFinished) {
      $0.phase = .finished(.briefSaved)
    }
    await store.finish()

    #expect(sent.value.isEmpty)
    let handoffStore = HandoffStore(rootURL: root)
    let log = try String(contentsOf: handoffStore.logURL, encoding: .utf8)
    #expect(log.contains("save"))
    #expect(log.contains("preparation=completed"))
    #expect(!log.contains("→"))
    let archiveContents =
      (try? FileManager.default.contentsOfDirectory(atPath: handoffStore.archiveDirectory.path)) ?? []
    #expect(archiveContents.isEmpty)
  }

  @Test(.dependencies) func runWithoutResumableSessionSkipsBriefingStage() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    var initial = try #require(
      HandoffHudFeature.State.make(
        worktree: makeWorktree(root: root),
        source: makeSourceContext(confidence: .medium)
      )
    )
    let claudeIndex = try #require(initial.targets.firstIndex { $0.agent == .claude })
    initial.selectedIndex = claudeIndex

    let store = TestStore(initialState: initial) {
      HandoffHudFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0[TerminalClient.self].send = { _ in }
      $0[AgentRuntimeClient.self] = AgentRuntimeClient(
        resume: { _, _ in
          Issue.record("Resume must not run without a preparation request")
          return ""
        }
      )
    }
    store.exhaustivity = .off

    await store.send(.confirmSelection) {
      #expect($0.run?.stages == [.saving, .archiving, .launching])
      #expect($0.run?.stage == .saving)
      #expect($0.run?.preparation == .skipped)
    }
    await store.receive(\.launchFinished)
    await store.finish()

    let log = try String(contentsOf: HandoffStore(rootURL: root).logURL, encoding: .utf8)
    #expect(log.contains("preparation=skipped"))
  }

  // MARK: - Skip and Cancel

  @Test(.dependencies) func skipDuringBriefingContinuesMechanically() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    var initial = try #require(
      HandoffHudFeature.State.make(worktree: makeWorktree(root: root), source: makeSourceContext())
    )
    let claudeIndex = try #require(initial.targets.firstIndex { $0.agent == .claude })
    initial.selectedIndex = claudeIndex

    let store = TestStore(initialState: initial) {
      HandoffHudFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0[TerminalClient.self].send = { _ in }
      $0[AgentRuntimeClient.self] = AgentRuntimeClient(
        resume: { _, _ in
          // Hangs until Skip cancels the briefing effect.
          try await Task.never()
        }
      )
    }
    store.exhaustivity = .off

    await store.send(.confirmSelection) {
      #expect($0.run?.stage == .briefing)
    }
    await store.send(.skipBriefingTapped) {
      #expect($0.run?.stage == .saving)
      #expect($0.run?.preparation == .skipped)
    }
    await store.receive(\.launchFinished) {
      $0.phase = .finished(.handedOff(agentDisplayName: "Claude Code"))
    }
    await store.finish()

    let handoffStore = HandoffStore(rootURL: root)
    let log = try String(contentsOf: handoffStore.logURL, encoding: .utf8)
    #expect(log.contains("preparation=skipped"))
    // The seeded template stays: no reply was transcribed.
    let current = try String(contentsOf: handoffStore.currentURL, encoding: .utf8)
    #expect(current == HandoffStore.template)
  }

  @Test(.dependencies) func cancelDuringBriefingAbortsWithoutArtifacts() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    var initial = try #require(
      HandoffHudFeature.State.make(worktree: makeWorktree(root: root), source: makeSourceContext())
    )
    let claudeIndex = try #require(initial.targets.firstIndex { $0.agent == .claude })
    initial.selectedIndex = claudeIndex

    let store = TestStore(initialState: initial) {
      HandoffHudFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0[TerminalClient.self].send = { _ in }
      $0[AgentRuntimeClient.self] = AgentRuntimeClient(resume: { _, _ in try await Task.never() })
    }
    store.exhaustivity = .off

    await store.send(.confirmSelection)
    await store.send(.cancelTapped)
    await store.receive(\.delegate.dismiss)
    await store.finish()

    // Nothing was persisted and nothing was logged.
    let handoffDirectory = HandoffStore(rootURL: root).handoffDirectory
    #expect(!FileManager.default.fileExists(atPath: handoffDirectory.path(percentEncoded: false)))
  }

  @Test(.dependencies) func lateBriefingResultAfterSkipIsIgnored() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    var initial = try #require(
      HandoffHudFeature.State.make(worktree: makeWorktree(root: root), source: makeSourceContext())
    )
    let claudeIndex = try #require(initial.targets.firstIndex { $0.agent == .claude })
    initial.selectedIndex = claudeIndex

    let store = TestStore(initialState: initial) {
      HandoffHudFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0[TerminalClient.self].send = { _ in }
      $0[AgentRuntimeClient.self] = AgentRuntimeClient(resume: { _, _ in try await Task.never() })
    }
    store.exhaustivity = .off

    await store.send(.confirmSelection)
    await store.send(.skipBriefingTapped)
    await store.receive(\.launchFinished)
    // A racing completion that arrives after Skip must not resurrect the run.
    await store.send(.briefingFinished(.completed))
    await store.finish()

    let log = try String(contentsOf: HandoffStore(rootURL: root).logURL, encoding: .utf8)
    #expect(log.contains("preparation=skipped"))
    #expect(!log.contains("preparation=completed"))
  }

  @Test(.dependencies) func saveFailureFinishesRunAsFailed() async throws {
    let root = try makeTempRoot()
    let worktree = makeWorktree(root: root)
    var initial = try #require(
      HandoffHudFeature.State.make(worktree: worktree, source: makeSourceContext(confidence: .medium))
    )
    let claudeIndex = try #require(initial.targets.firstIndex { $0.agent == .claude })
    initial.selectedIndex = claudeIndex
    // Break the root: a plain file where the directory should be.
    try FileManager.default.removeItem(at: root)
    try "not a directory".write(to: root, atomically: true, encoding: .utf8)
    defer { remove(root) }

    let store = TestStore(initialState: initial) {
      HandoffHudFeature()
    } withDependencies: {
      $0.date.now = Date(timeIntervalSince1970: 1_760_000_000)
      $0[TerminalClient.self].send = { _ in }
      $0[AgentRuntimeClient.self] = AgentRuntimeClient(resume: { _, _ in "" })
    }
    store.exhaustivity = .off

    await store.send(.confirmSelection)
    await store.receive(\.runFailed)
    await store.finish()

    guard case .finished(.failed) = store.state.phase else {
      Issue.record("Expected failed outcome, got \(store.state.phase)")
      return
    }
  }
}
