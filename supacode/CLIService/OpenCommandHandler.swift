// supacode/CLIService/OpenCommandHandler.swift
// Handles `prowl open [path]` — resolves path to worktree, selects it, brings app to front.

import AppKit
import Foundation

/// Result of resolving an open command against current app state.
enum OpenResolution: Sendable {
  /// Path matched an existing worktree.
  case worktree(id: String, name: String, path: String, repositoryRoot: String)
  /// No path provided — just bring app to front.
  case bringToFront
  /// Path is a valid directory but not a known worktree/repository.
  case unknownPath(String)
}

/// Payload returned on successful open.
struct OpenCommandPayload: Codable {
  let worktreeID: String?
  let worktreeName: String?
  let path: String?
  let repositoryRoot: String?
  let broughtToFront: Bool

  enum CodingKeys: String, CodingKey {
    case worktreeID = "worktree_id"
    case worktreeName = "worktree_name"
    case path
    case repositoryRoot = "repository_root"
    case broughtToFront = "brought_to_front"
  }
}

final class OpenCommandHandler: CommandHandler {
  typealias Resolver = @MainActor (String?) -> OpenResolution
  typealias SelectAction = @MainActor (String) -> Void
  typealias AddAndOpenAction = @MainActor (URL) -> Void

  private let resolver: Resolver
  private let selectWorktree: SelectAction
  private let addAndOpen: AddAndOpenAction

  init(
    resolver: @escaping Resolver,
    selectWorktree: @escaping SelectAction,
    addAndOpen: @escaping AddAndOpenAction
  ) {
    self.resolver = resolver
    self.selectWorktree = selectWorktree
    self.addAndOpen = addAndOpen
  }

  // swiftlint:disable:next async_without_await
  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .open(let input) = envelope.command else {
      return CommandResponse(
        ok: false,
        command: "open",
        schemaVersion: "prowl.cli.open.v1",
        error: CommandError(code: CLIErrorCode.invalidArgument, message: "Expected open command.")
      )
    }

    let resolution = resolver(input.path)

    switch resolution {
    case .bringToFront:
      bringAppToFront()
      return makeSuccess(
        worktreeID: nil,
        worktreeName: nil,
        path: nil,
        repositoryRoot: nil,
        broughtToFront: true
      )

    case .worktree(let id, let name, let path, let repositoryRoot):
      selectWorktree(id)
      bringAppToFront()
      return makeSuccess(
        worktreeID: id,
        worktreeName: name,
        path: path,
        repositoryRoot: repositoryRoot,
        broughtToFront: true
      )

    case .unknownPath(let path):
      let url = URL(fileURLWithPath: path, isDirectory: true)
      addAndOpen(url)
      bringAppToFront()
      return makeSuccess(
        worktreeID: nil,
        worktreeName: nil,
        path: path,
        repositoryRoot: nil,
        broughtToFront: true
      )
    }
  }

  // MARK: - Private

  private func bringAppToFront() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      window.makeKeyAndOrderFront(nil)
    }
  }

  private func makeSuccess(
    worktreeID: String?,
    worktreeName: String?,
    path: String?,
    repositoryRoot: String?,
    broughtToFront: Bool
  ) -> CommandResponse {
    let payload = OpenCommandPayload(
      worktreeID: worktreeID,
      worktreeName: worktreeName,
      path: path,
      repositoryRoot: repositoryRoot,
      broughtToFront: broughtToFront
    )
    do {
      return try CommandResponse(
        ok: true,
        command: "open",
        schemaVersion: "prowl.cli.open.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      return CommandResponse(
        ok: false,
        command: "open",
        schemaVersion: "prowl.cli.open.v1",
        error: CommandError(
          code: CLIErrorCode.openFailed,
          message: "Failed to encode response."
        )
      )
    }
  }
}
