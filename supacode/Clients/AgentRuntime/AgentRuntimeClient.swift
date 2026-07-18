import ComposableArchitecture
import Foundation

nonisolated struct AgentRuntimeClient: Sendable {
  var makeStartInvocation: @Sendable (AgentStartRequest) throws -> AgentInvocation
  private var resumeImpl: @Sendable (AgentResumeRequest, URL) async throws -> ShellOutput

  init(
    makeStartInvocation: @escaping @Sendable (AgentStartRequest) throws -> AgentInvocation,
    resume: @escaping @Sendable (AgentResumeRequest, URL) async throws -> ShellOutput
  ) {
    self.makeStartInvocation = makeStartInvocation
    self.resumeImpl = resume
  }

  func resume(_ request: AgentResumeRequest, in workingDirectory: URL) async throws -> ShellOutput {
    try await resumeImpl(request, workingDirectory)
  }

  static func live(shell: ShellClient) -> Self {
    Self(
      makeStartInvocation: { request in
        try AgentRuntimeAdapterRegistry.makeStartInvocation(request)
      },
      resume: { request, workingDirectory in
        let invocation = try AgentRuntimeAdapterRegistry.makeResumeInvocation(request)
        return try await shell.runLogin(
          URL(fileURLWithPath: "/usr/bin/env"),
          [invocation.executable] + invocation.arguments,
          workingDirectory,
          log: false
        )
      }
    )
  }
}

extension AgentRuntimeClient: DependencyKey {
  nonisolated static let liveValue = AgentRuntimeClient.live(shell: .live)

  nonisolated static let testValue = AgentRuntimeClient(
    makeStartInvocation: { request in
      try AgentRuntimeAdapterRegistry.makeStartInvocation(request)
    },
    resume: { request, _ in
      _ = try AgentRuntimeAdapterRegistry.makeResumeInvocation(request)
      return ShellOutput(stdout: "", stderr: "", exitCode: 0)
    }
  )
}

extension DependencyValues {
  var agentRuntimeClient: AgentRuntimeClient {
    get { self[AgentRuntimeClient.self] }
    set { self[AgentRuntimeClient.self] = newValue }
  }
}
