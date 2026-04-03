// supacode/CLIService/SendCommandHandler.swift
// Handles `prowl send` by resolving target, delivering text, and optionally waiting.

import Foundation

private let sendLogger = SupaLogger("SendCommandHandler")

@MainActor
final class SendCommandHandler: CommandHandler {
  typealias ResolverProvider = @MainActor () -> TargetResolver
  typealias WaiterProvider = @MainActor (String, UUID) -> AsyncStream<(exitCode: Int?, durationMs: Int)>?

  private let resolverProvider: ResolverProvider
  private let waiterProvider: WaiterProvider

  init(
    resolverProvider: @escaping ResolverProvider,
    waiterProvider: @escaping WaiterProvider
  ) {
    self.resolverProvider = resolverProvider
    self.waiterProvider = waiterProvider
  }

  func handle(envelope: CommandEnvelope) async -> CommandResponse {
    guard case .send(let input) = envelope.command else {
      return errorResponse(code: CLIErrorCode.sendFailed, message: "Invalid command.")
    }

    // Resolve target
    let resolver = resolverProvider()
    let result = resolver.resolve(input.selector)
    let target: ResolvedTarget
    switch result {
    case .success(let resolved):
      target = resolved
    case .failure(let error):
      return mapResolverError(error)
    }

    // Deliver text
    let surfaceView = target.surfaceView
    surfaceView.insertCommittedTextForBroadcast(input.text)

    // Send trailing Enter if requested
    if input.trailingEnter {
      surfaceView.submitLine()
    }

    // Wait for command completion if requested
    let waitResult: SendWaitResult?
    if input.wait {
      waitResult = await waitForCompletion(
        worktreeID: target.worktreeID,
        surfaceID: target.paneID,
        timeoutSeconds: input.timeoutSeconds ?? 30
      )
      if waitResult == nil {
        return errorResponse(
          code: CLIErrorCode.waitTimeout,
          message: "Timed out waiting for command to finish. "
            + "This may happen if the terminal does not have shell integration (OSC 133) enabled."
        )
      }
    } else {
      waitResult = nil
    }

    // Build payload
    let payload = SendCommandPayload(
      target: makeTarget(from: target),
      input: SendInputInfo(
        source: input.source.rawValue,
        characters: input.text.unicodeScalars.count,
        bytes: input.text.utf8.count,
        trailingEnterSent: input.trailingEnter
      ),
      createdTab: false,
      wait: waitResult
    )

    do {
      return try CommandResponse(
        ok: true,
        command: "send",
        schemaVersion: "prowl.cli.send.v1",
        data: RawJSON(encoding: payload)
      )
    } catch {
      sendLogger.warning("Failed to encode send payload: \(error)")
      return errorResponse(code: CLIErrorCode.sendFailed, message: "Failed to encode response.")
    }
  }

  // MARK: - Wait

  private func waitForCompletion(
    worktreeID: String,
    surfaceID: UUID,
    timeoutSeconds: Int
  ) async -> SendWaitResult? {
    guard let stream = waiterProvider(worktreeID, surfaceID) else {
      return nil
    }

    // Race stream result against timeout using raw tuples (Sendable-safe).
    let raw: (exitCode: Int?, durationMs: Int)? = await withTaskGroup(
      of: (Int?, Int)?.self
    ) { group in
      group.addTask {
        for await result in stream {
          return (result.exitCode, result.durationMs)
        }
        return nil
      }

      group.addTask {
        try? await Task.sleep(for: .seconds(timeoutSeconds))
        return nil
      }

      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }

    guard let raw else { return nil }
    return SendWaitResult(exitCode: raw.exitCode, durationMs: raw.durationMs)
  }

  // MARK: - Helpers

  private func makeTarget(from resolved: ResolvedTarget) -> SendTarget {
    SendTarget(
      worktree: SendTargetWorktree(
        id: resolved.worktreeID,
        name: resolved.worktreeName,
        path: resolved.worktreePath,
        rootPath: resolved.worktreeRootPath,
        kind: resolved.worktreeKind.rawValue
      ),
      tab: SendTargetTab(
        id: resolved.tabID.uuidString,
        title: resolved.tabTitle,
        selected: resolved.tabSelected
      ),
      pane: SendTargetPane(
        id: resolved.paneID.uuidString,
        title: resolved.paneTitle,
        cwd: resolved.paneCWD,
        focused: resolved.paneFocused
      )
    )
  }

  private func mapResolverError(_ error: TargetResolverError) -> CommandResponse {
    switch error {
    case .notFound(let message):
      return errorResponse(code: CLIErrorCode.targetNotFound, message: message)
    case .notUnique(let message):
      return errorResponse(code: CLIErrorCode.targetNotUnique, message: message)
    }
  }

  private func errorResponse(code: String, message: String) -> CommandResponse {
    CommandResponse(
      ok: false,
      command: "send",
      schemaVersion: "prowl.cli.send.v1",
      error: CommandError(code: code, message: message)
    )
  }
}
