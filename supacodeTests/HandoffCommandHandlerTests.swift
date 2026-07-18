import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

/// A shape-valid preparation reply used when a test does not care about the
/// reply content itself.
nonisolated private let preparedHandoffReply = """
  # Handoff

  ## Objective
  Ship the checkout flow.

  ## Current State
  Tests are green.

  ## Next Steps
  1. Review the PR.
  """

@MainActor
struct HandoffCommandHandlerTests {
  private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "handoff-handler-tests", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }

  private let fixedDate = Date(timeIntervalSince1970: 1_760_000_000)

  private func makeHandler(
    root: URL,
    outgoingAgent: String?,
    outgoingLaunchObservation: AgentLaunchObservation? = AgentLaunchObservation(
      model: "gpt-5.4",
      executionMode: .unrestricted
    ),
    outgoingSession: AgentSession? = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .exact
    ),
    sessionContext: HandoffStore.SessionContext? = HandoffStore.SessionContext(
      agent: "codex",
      paneID: "pane-0",
      paneTitle: "codex",
      source: "terminal-scrollback",
      confidence: "fallback",
      excerptText: "working on handoff"
    ),
    launched: HandoffLaunchedPane? = HandoffLaunchedPane(
      worktreeID: "ws", worktreeName: "Workspace", tabID: "tab-1", paneID: "pane-1", paneTitle: "claude"
    ),
    launchSpy: (@MainActor (AgentStartRequest) -> Void)? = nil,
    preparationSpy: (@Sendable (AgentResumeRequest, URL) async throws -> String)? = nil,
  ) -> HandoffCommandHandler {
    HandoffCommandHandler(
      resolveProvider: { _ in
        .success(
          HandoffResolvedTarget(
            worktreeID: "ws",
            worktreeName: "Workspace",
            rootPath: root.path(percentEncoded: false),
            paneID: "pane-0",
            outgoingAgent: outgoingAgent,
            outgoingLaunchObservation: outgoingLaunchObservation,
            outgoingSession: outgoingSession,
            sessionContext: sessionContext
          )
        )
      },
      launchProvider: { _, request in
        launchSpy?(request)
        return launched
      },
      preparationProvider: { request, directory in
        guard let preparationSpy else { return preparedHandoffReply }
        return try await preparationSpy(request, directory)
      },
      now: { [fixedDate] in fixedDate }
    )
  }

  private func envelope(_ input: HandoffInput) -> CommandEnvelope {
    CommandEnvelope(output: .json, command: .handoff(input))
  }

  @Test func saveWritesArtifactAndReturnsPayload() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(root: root, outgoingAgent: "codex")

    let response = await handler.handle(envelope: envelope(HandoffInput(action: .save, note: "wip")))

    #expect(response.ok)
    #expect(response.command == "handoff")
    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    #expect(payload.action == .save)
    #expect(payload.outgoingAgent == "codex")
    let session = try #require(payload.sessionContext)
    #expect(session.excerptPath?.hasPrefix("handoff/sessions/") == true)

    let store = HandoffStore(rootURL: root)
    #expect(FileManager.default.fileExists(atPath: store.currentURL.path(percentEncoded: false)))
    let content = try String(contentsOf: store.contextURL, encoding: .utf8)
    #expect(content.contains("Session Context:"))
    #expect(content.contains(".prowl/handoff/sessions/"))
  }

  @Test func saveTranscribesVerifiedSourceReplyBeforePersistingHandoff() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let resumed = LockIsolated<AgentResumeRequest?>(nil)
    let handler = makeHandler(
      root: root,
      outgoingAgent: "codex",
      preparationSpy: { request, _ in
        resumed.setValue(request)
        return """
          Here is the updated artifact:

          # Handoff

          ## Objective
          Source-authored status.

          ## Current State
          Awaiting review.

          ## Next Steps
          1. Hand off.
          """
      }
    )

    let response = await handler.handle(envelope: envelope(HandoffInput(action: .save)))

    #expect(response.ok)
    #expect(resumed.value?.agent == .codex)
    #expect(resumed.value?.session.confidence == .exact)
    #expect(resumed.value?.model == "gpt-5.4")
    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    #expect(payload.preparation == "completed")
    // Prowl transcribed the reply (preamble dropped) into current.md.
    let content = try String(contentsOf: HandoffStore(rootURL: root).currentURL, encoding: .utf8)
    #expect(content.hasPrefix("# Handoff"))
    #expect(content.contains("Source-authored status."))
    // One save produces exactly one log line, carrying the preparation outcome.
    let log = try String(contentsOf: HandoffStore(rootURL: root).logURL, encoding: .utf8)
    let entries = log.split(separator: "\n").filter { $0.hasPrefix("- ") }
    #expect(entries.count == 1)
    #expect(entries.first?.contains("preparation=completed") == true)
  }

  @Test func saveMarksPreparationFailedForUnusableReply() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(
      root: root,
      outgoingAgent: "codex",
      preparationSpy: { _, _ in "I could not update the handoff file." }
    )

    let response = await handler.handle(envelope: envelope(HandoffInput(action: .save)))

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    #expect(payload.preparation == "failed")
    // The scaffolded template stays in place; no reply prose leaks into it.
    let content = try String(contentsOf: HandoffStore(rootURL: root).currentURL, encoding: .utf8)
    #expect(content == HandoffStore.template)
    let log = try String(contentsOf: HandoffStore(rootURL: root).logURL, encoding: .utf8)
    #expect(log.contains("preparation=failed"))
  }

  @Test func saveSkipsPreparationWhenDisabled() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let resumeCalled = LockIsolated(false)
    let handler = makeHandler(
      root: root,
      outgoingAgent: "codex",
      preparationSpy: { _, _ in
        resumeCalled.setValue(true)
        return preparedHandoffReply
      }
    )

    let response = await handler.handle(envelope: envelope(HandoffInput(action: .save, prepare: false)))

    #expect(response.ok)
    #expect(resumeCalled.value == false)
    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    #expect(payload.preparation == "skipped")
  }

  @Test func preparationRequiresVerifiableSourceSession() {
    let session = AgentSession(
      id: "ambiguous-session",
      transcriptPath: nil,
      source: .recentFile,
      confidence: .medium
    )

    #expect(
      HandoffCommandHandler.preparationRequest(
        outgoingAgent: "codex",
        session: session,
        observation: AgentLaunchObservation(executionMode: .unrestricted)
      ) == nil
    )
  }

  @Test func preparationRequestKeepsSameAdapterModelOnly() throws {
    let request = try #require(
      HandoffCommandHandler.preparationRequest(
        outgoingAgent: "codex",
        session: AgentSession(
          id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
          transcriptPath: nil,
          source: .openFile,
          confidence: .high
        ),
        observation: AgentLaunchObservation(model: "gpt-5.4", executionMode: .unrestricted)
      )
    )

    #expect(request.agent == .codex)
    #expect(request.model == "gpt-5.4")
  }

  @Test func savePreservesResolvedNativeSessionContext() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(
      root: root,
      outgoingAgent: "codex",
      sessionContext: HandoffStore.SessionContext(
        agent: "codex",
        sessionID: "native-session",
        paneID: "pane-0",
        paneTitle: "codex",
        source: "open_file",
        confidence: "exact",
        transcriptPath: "/tmp/native-session.jsonl",
        excerptText: "working on handoff"
      )
    )

    let response = await handler.handle(envelope: envelope(HandoffInput(action: .save)))

    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    let session = try #require(payload.sessionContext)
    #expect(session.sessionID == "native-session")
    #expect(session.source == "open_file")
    #expect(session.confidence == "exact")
    #expect(session.transcriptPath == "/tmp/native-session.jsonl")
  }

  @Test func toRefreshesArchivesAndLaunches() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }

    var launchedRequest: AgentStartRequest?
    let handler = makeHandler(
      root: root,
      outgoingAgent: "codex",
      launchSpy: { launchedRequest = $0 }
    )

    let response = await handler.handle(
      envelope: envelope(HandoffInput(action: .toAgent, toAgent: "claude", note: "over to you"))
    )

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    #expect(payload.action == .toAgent)
    #expect(payload.toAgent == "claude")
    #expect(payload.archivedPath?.hasPrefix("handoff/archive/") == true)
    #expect(payload.launchedPane?.paneID == "pane-1")

    // The receiving adapter gets a semantic handoff prompt and only portable
    // source configuration. Cross-agent model identifiers must not leak.
    #expect(launchedRequest?.agent == .claude)
    #expect(launchedRequest?.configuration.model == nil)
    #expect(launchedRequest?.configuration.executionMode == .unrestricted)
    #expect(launchedRequest?.prompt.contains(".prowl/handoff/current.md") == true)

    // Log records the transition.
    let store = HandoffStore(rootURL: root)
    let log = try String(contentsOf: store.logURL, encoding: .utf8)
    #expect(log.contains("codex → claude"))
  }

  @Test func toWithoutLaunchSkipsAgentButArchives() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }

    var launchCalled = false
    let handler = makeHandler(
      root: root,
      outgoingAgent: "codex",
      launchSpy: { _ in launchCalled = true }
    )

    let response = await handler.handle(
      envelope: envelope(HandoffInput(action: .toAgent, toAgent: "codex", launch: false))
    )

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    #expect(payload.launchedPane == nil)
    #expect(payload.archivedPath != nil)
    #expect(launchCalled == false)
  }

  @Test func toAcceptsDetectedAgentToken() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(root: root, outgoingAgent: "codex")

    let response = await handler.handle(
      envelope: envelope(HandoffInput(action: .toAgent, toAgent: "gemini", launch: false))
    )

    #expect(response.ok)
    let payload = try #require(try response.data?.decode(as: HandoffCommandPayload.self))
    #expect(payload.toAgent == "gemini")
  }

  @Test func toRejectsLaunchForAgentWithoutVerifiedLauncher() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(root: root, outgoingAgent: "codex")

    let response = await handler.handle(
      envelope: envelope(HandoffInput(action: .toAgent, toAgent: "gemini"))
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.invalidArgument)
  }

  @Test func toRejectsUnknownAgent() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(root: root, outgoingAgent: "codex")

    let response = await handler.handle(
      envelope: envelope(HandoffInput(action: .toAgent, toAgent: "unknown-agent"))
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.invalidArgument)
  }

  @Test func supportedAgentsMatchDetectedAgents() {
    #expect(HandoffAgentSupport.supportedAgents == DetectedAgent.allCases.map(\.rawValue))
  }

  @Test func toReportsFailureWhenLaunchReturnsNil() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(root: root, outgoingAgent: "codex", launched: nil)

    let response = await handler.handle(
      envelope: envelope(HandoffInput(action: .toAgent, toAgent: "claude"))
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.handoffFailed)
    let log = try String(contentsOf: HandoffStore(rootURL: root).logURL, encoding: .utf8)
    #expect(log.contains("codex → claude"))
    #expect(log.contains("launch=failed"))
    #expect(log.contains("archive=handoff/archive/"))
  }

  @Test func statusReflectsExistence() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(root: root, outgoingAgent: "codex")

    let before = await handler.handle(envelope: envelope(HandoffInput(action: .status)))
    let beforePayload = try #require(try before.data?.decode(as: HandoffCommandPayload.self))
    #expect(beforePayload.exists == false)

    _ = await handler.handle(envelope: envelope(HandoffInput(action: .save)))

    let after = await handler.handle(envelope: envelope(HandoffInput(action: .status)))
    let afterPayload = try #require(try after.data?.decode(as: HandoffCommandPayload.self))
    #expect(afterPayload.exists == true)
  }
}
