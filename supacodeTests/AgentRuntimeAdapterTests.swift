import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

struct AgentRuntimeAdapterTests {
  @Test func codexStartBuildsUnrestrictedInvocation() throws {
    let invocation = try AgentRuntimeAdapterRegistry.makeStartInvocation(
      AgentStartRequest(
        agent: .codex,
        prompt: "Continue the handoff.",
        configuration: AgentLaunchConfiguration(model: "gpt-5.4", executionMode: .unrestricted)
      )
    )

    #expect(invocation.executable == "codex")
    #expect(
      invocation.arguments
        == ["--model", "gpt-5.4", "--dangerously-bypass-approvals-and-sandbox", "Continue the handoff."]
    )
  }

  @Test func claudeResumeBuildsUnrestrictedInvocation() throws {
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .exact
    )
    let invocation = try AgentRuntimeAdapterRegistry.makeResumeInvocation(
      AgentResumeRequest(
        agent: .claude,
        session: session,
        prompt: "Write the handoff artifact.",
        configuration: AgentLaunchConfiguration(model: "claude-opus-4", executionMode: .unrestricted)
      )
    )

    #expect(invocation.executable == "claude")
    #expect(
      invocation.arguments
        == [
          "-p",
          "--resume",
          "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
          "--model",
          "claude-opus-4",
          "--dangerously-skip-permissions",
          "Write the handoff artifact.",
        ]
    )
  }

  @Test func observedLaunchOnlyClaimsExplicitUnrestrictedMode() {
    let codex = AgentRuntimeAdapterRegistry.observe(
      agent: .codex,
      arguments: ["codex", "--model", "gpt-5.4", "--dangerously-bypass-approvals-and-sandbox"]
    )
    #expect(codex.model == "gpt-5.4")
    #expect(codex.executionMode == .unrestricted)

    let claude = AgentRuntimeAdapterRegistry.observe(
      agent: .claude,
      arguments: ["claude", "--allow-dangerously-skip-permissions"]
    )
    #expect(claude.executionMode == nil)
  }

  @Test func inheritedConfigurationCarriesOnlyPortableSourceIntent() {
    let observation = AgentLaunchObservation(model: "gpt-5.4", executionMode: .unrestricted)

    let claude = AgentRuntimeAdapterRegistry.inheritedConfiguration(
      from: .codex,
      observation: observation,
      to: .claude
    )
    #expect(claude.model == nil)
    #expect(claude.executionMode == .unrestricted)

    let codex = AgentRuntimeAdapterRegistry.inheritedConfiguration(
      from: .codex,
      observation: observation,
      to: .codex
    )
    #expect(codex.model == "gpt-5.4")
    #expect(codex.executionMode == .unrestricted)
  }

  @Test func resumeRejectsMediumConfidenceSession() throws {
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .recentFile,
      confidence: .medium
    )

    #expect(throws: AgentRuntimeError.self) {
      try AgentRuntimeAdapterRegistry.makeResumeInvocation(
        AgentResumeRequest(agent: .codex, session: session, prompt: "Summarize the task.")
      )
    }
  }

  @Test func terminalInputQuotesEveryArgument() {
    let invocation = AgentInvocation(
      executable: "codex",
      arguments: ["exec", "resume", "session id", "Write 'current.md'\nwithout shell injection."]
    )

    #expect(
      invocation.terminalInput
        == "'codex' 'exec' 'resume' 'session id' 'Write '\"'\"'current.md'\"'\"'\nwithout shell injection.'"
    )
  }
  @Test func runtimeClientRunsResumeThroughDirectArgv() async throws {
    let recordedExecutable = LockIsolated<URL?>(nil)
    let recordedArguments = LockIsolated<[String]>([])
    let recordedDirectory = LockIsolated<URL?>(nil)
    let recordedLog = LockIsolated<Bool?>(nil)
    let shell = ShellClient(
      run: { _, _, _ in ShellOutput(stdout: "", stderr: "", exitCode: 0) },
      runLoginImpl: { executable, arguments, directory, log in
        recordedExecutable.setValue(executable)
        recordedArguments.setValue(arguments)
        recordedDirectory.setValue(directory)
        recordedLog.setValue(log)
        return ShellOutput(stdout: "complete", stderr: "", exitCode: 0)
      }
    )
    let directory = URL(fileURLWithPath: "/tmp/handoff", isDirectory: true)
    let session = AgentSession(
      id: "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
      transcriptPath: nil,
      source: .openFile,
      confidence: .high
    )

    let output = try await AgentRuntimeClient.live(shell: shell).resume(
      AgentResumeRequest(
        agent: .codex,
        session: session,
        prompt: "Write the handoff artifact.",
        configuration: AgentLaunchConfiguration(executionMode: .unrestricted)
      ),
      in: directory
    )

    #expect(output.stdout == "complete")
    #expect(recordedExecutable.value?.path == "/usr/bin/env")
    #expect(
      recordedArguments.value
        == [
          "codex",
          "exec",
          "resume",
          "--dangerously-bypass-approvals-and-sandbox",
          "9B0E3B0E-67B3-4D45-A3A0-7DD9BC713711",
          "Write the handoff artifact.",
        ]
    )
    #expect(recordedDirectory.value == directory)
    #expect(recordedLog.value == false)
  }
}
