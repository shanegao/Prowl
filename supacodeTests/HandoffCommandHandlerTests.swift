import Foundation
import Testing

@testable import supacode

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
    launched: HandoffLaunchedPane? = HandoffLaunchedPane(
      worktreeID: "ws", worktreeName: "Workspace", tabID: "tab-1", paneID: "pane-1", paneTitle: "claude"
    ),
    launchSpy: (@MainActor (String) -> Void)? = nil
  ) -> HandoffCommandHandler {
    HandoffCommandHandler(
      resolveProvider: { _ in
        .success(
          HandoffResolvedTarget(
            worktreeID: "ws",
            worktreeName: "Workspace",
            rootPath: root.path(percentEncoded: false),
            paneID: "pane-0",
            outgoingAgent: outgoingAgent
          )
        )
      },
      launchProvider: { _, kickoff in
        launchSpy?(kickoff)
        return launched
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

    let store = HandoffStore(rootURL: root)
    #expect(FileManager.default.fileExists(atPath: store.currentURL.path(percentEncoded: false)))
  }

  @Test func toRefreshesArchivesAndLaunches() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }

    var launchedKickoff: String?
    let handler = makeHandler(
      root: root,
      outgoingAgent: "codex",
      launchSpy: { launchedKickoff = $0 }
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

    // The launched agent's kickoff command targets the handoff artifact.
    #expect(launchedKickoff?.hasPrefix("claude ") == true)
    #expect(launchedKickoff?.contains(".prowl/handoff/current.md") == true)

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

  @Test func toRejectsUnsupportedAgent() async throws {
    let root = try makeTempRoot()
    defer { remove(root) }
    let handler = makeHandler(root: root, outgoingAgent: "codex")

    let response = await handler.handle(
      envelope: envelope(HandoffInput(action: .toAgent, toAgent: "gemini"))
    )

    #expect(response.ok == false)
    #expect(response.error?.code == CLIErrorCode.invalidArgument)
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
