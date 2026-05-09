import Testing

@testable import supacode

struct AgentClassifierTests {
  @Test func identifiesDirectAgentProcessNames() {
    #expect(identifyAgent(processName: "pi") == .pi)
    #expect(identifyAgent(processName: "claude") == .claude)
    #expect(identifyAgent(processName: "claude-code") == .claude)
    #expect(identifyAgent(processName: "codex") == .codex)
    #expect(identifyAgent(processName: "gemini") == .gemini)
    #expect(identifyAgent(processName: "cursor") == .cursor)
    #expect(identifyAgent(processName: "cline") == .cline)
    #expect(identifyAgent(processName: "opencode") == .opencode)
    #expect(identifyAgent(processName: "open-code") == .opencode)
    #expect(identifyAgent(processName: "github-copilot") == .copilot)
    #expect(identifyAgent(processName: "ghcs") == .copilot)
    #expect(identifyAgent(processName: "kimi") == .kimi)
    #expect(identifyAgent(processName: "droid") == .droid)
    #expect(identifyAgent(processName: "amp") == .amp)
    #expect(identifyAgent(processName: "amp-local") == .amp)
  }

  @Test func ignoresPlainShellsAndUnknownProcesses() {
    #expect(identifyAgent(processName: "zsh") == nil)
    #expect(identifyAgent(processName: "bash") == nil)
    #expect(identifyAgent(processName: "node") == nil)
    #expect(identifyAgent(processName: "vim") == nil)
  }

  @Test func identifiesWrappedRuntimeCommandLines() throws {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(
          pid: 100,
          name: "node",
          argv0: "node",
          cmdline: "node /opt/homebrew/bin/codex --model gpt-5"
        )
      ]
    )

    let result = try #require(identifyAgentInJob(job))
    #expect(result.agent == .codex)
    #expect(result.name == "codex")
  }

  @Test func prefersDirectAgentProcessOverWrapper() throws {
    let job = ForegroundJob(
      processGroupID: 42,
      processes: [
        ForegroundProcess(pid: 100, name: "node", argv0: "node", cmdline: "node /tmp/codex"),
        ForegroundProcess(pid: 101, name: "claude", argv0: "claude", cmdline: "claude"),
      ]
    )

    let result = try #require(identifyAgentInJob(job))
    #expect(result.agent == .claude)
    #expect(result.name == "claude")
  }
}
