// supacodeTests/OpenCommandHandlerTests.swift
// Unit tests for OpenCommandHandler.

import Foundation
import Testing

@testable import supacode

struct OpenCommandHandlerTests {

  // MARK: - Bring to front (no path)

  @MainActor
  @Test func openWithNoPathReturnsBringToFront() async throws {
    var selectCalled = false
    var addCalled = false

    let handler = OpenCommandHandler(
      resolver: { path in
        #expect(path == nil)
        return .bringToFront
      },
      selectWorktree: { _ in selectCalled = true },
      addAndOpen: { _ in addCalled = true }
    )

    let envelope = CommandEnvelope(output: .json, command: .open(OpenInput()))
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == true)
    #expect(response.command == "open")
    #expect(response.schemaVersion == "prowl.cli.open.v1")
    #expect(!selectCalled)
    #expect(!addCalled)

    if let data = response.data {
      let payload = try data.decode(as: OpenCommandPayload.self)
      #expect(payload.broughtToFront == true)
      #expect(payload.worktreeID == nil)
    }
  }

  // MARK: - Known worktree

  @MainActor
  @Test func openKnownWorktreeSelectsAndReturnsPayload() async throws {
    var selectedID: String?

    let handler = OpenCommandHandler(
      resolver: { _ in
        .worktree(
          id: "Prowl:/Users/test/Projects/Prowl",
          name: "Prowl",
          path: "/Users/test/Projects/Prowl",
          repositoryRoot: "/Users/test/Projects/Prowl"
        )
      },
      selectWorktree: { id in selectedID = id },
      addAndOpen: { _ in }
    )

    let envelope = CommandEnvelope(
      output: .text,
      command: .open(OpenInput(path: "/Users/test/Projects/Prowl"))
    )
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == true)
    #expect(selectedID == "Prowl:/Users/test/Projects/Prowl")

    if let data = response.data {
      let payload = try data.decode(as: OpenCommandPayload.self)
      #expect(payload.worktreeID == "Prowl:/Users/test/Projects/Prowl")
      #expect(payload.worktreeName == "Prowl")
      #expect(payload.path == "/Users/test/Projects/Prowl")
      #expect(payload.broughtToFront == true)
    }
  }

  // MARK: - Unknown path triggers addAndOpen

  @MainActor
  @Test func openUnknownPathCallsAddAndOpen() async throws {
    var addedURL: URL?

    let handler = OpenCommandHandler(
      resolver: { _ in .unknownPath("/Users/test/NewProject") },
      selectWorktree: { _ in },
      addAndOpen: { url in addedURL = url }
    )

    let envelope = CommandEnvelope(
      output: .json,
      command: .open(OpenInput(path: "/Users/test/NewProject"))
    )
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == true)
    #expect(addedURL?.path == "/Users/test/NewProject")

    if let data = response.data {
      let payload = try data.decode(as: OpenCommandPayload.self)
      #expect(payload.worktreeID == nil)
      #expect(payload.path == "/Users/test/NewProject")
      #expect(payload.broughtToFront == true)
    }
  }

  // MARK: - Router dispatches to injected open handler

  @MainActor
  @Test func routerUsesInjectedOpenHandler() async {
    let handler = OpenCommandHandler(
      resolver: { _ in .bringToFront },
      selectWorktree: { _ in },
      addAndOpen: { _ in }
    )

    let router = CLICommandRouter(openHandler: handler)
    let envelope = CommandEnvelope(output: .json, command: .open(OpenInput()))
    let response = await router.route(envelope)

    #expect(response.ok == true)
    #expect(response.command == "open")
    #expect(response.schemaVersion == "prowl.cli.open.v1")
  }

  // MARK: - Wrong command type

  @MainActor
  @Test func handlerRejectsNonOpenCommand() async {
    let handler = OpenCommandHandler(
      resolver: { _ in .bringToFront },
      selectWorktree: { _ in },
      addAndOpen: { _ in }
    )

    // Directly call handle with a list envelope (shouldn't happen via router, but tests guard)
    let envelope = CommandEnvelope(output: .json, command: .list(ListInput()))
    let response = await handler.handle(envelope: envelope)

    #expect(response.ok == false)
    #expect(response.error?.code == "INVALID_ARGUMENT")
  }
}
