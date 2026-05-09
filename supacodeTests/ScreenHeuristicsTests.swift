import Testing

@testable import supacode

struct ScreenHeuristicsTests {
  @Test func unknownAgentIsUnknown() {
    #expect(detectState(agent: nil, screen: "Working...") == .unknown)
  }

  @Test func piDetection() {
    #expect(detectState(agent: .pi, screen: "Working...") == .working)
    #expect(detectState(agent: .pi, screen: "Done") == .idle)
  }

  @Test func claudeDetection() {
    #expect(
      detectState(
        agent: .claude,
        screen: """
          Reading file
          ✽ Tempering…
          ─────────
          ❯
          ─────────
          """
      ) == .working
    )
    #expect(
      detectState(
        agent: .claude,
        screen: """
          Do you want to proceed?
          ❯ 1. Yes
            2. No

          Esc to cancel · Tab to amend
          """
      ) == .blocked
    )
    #expect(
      detectState(
        agent: .claude,
        screen: """
          Task complete.
          ─────────
          ❯
          ─────────
          """
      ) == .idle
    )
  }

  @Test func codexDetection() {
    #expect(detectState(agent: .codex, screen: "press enter to confirm or esc to cancel") == .blocked)
    #expect(detectState(agent: .codex, screen: "• Working (12s)\nesc to interrupt") == .working)
    #expect(detectState(agent: .codex, screen: "Ready for input") == .idle)
  }

  @Test func otherAgentDetectorsCoverStateTriplets() {
    #expect(detectState(agent: .gemini, screen: "│ Apply this change") == .blocked)
    #expect(detectState(agent: .gemini, screen: "esc to cancel") == .working)
    #expect(detectState(agent: .gemini, screen: "done") == .idle)

    #expect(detectState(agent: .cursor, screen: "Run command? (y) (enter)") == .blocked)
    #expect(detectState(agent: .cursor, screen: "⬡ indexing") == .working)
    #expect(detectState(agent: .cursor, screen: "done") == .idle)

    #expect(detectState(agent: .cline, screen: "Let Cline use this tool? yes") == .blocked)
    #expect(detectState(agent: .cline, screen: "Cline is ready for your message") == .idle)
    #expect(detectState(agent: .cline, screen: "still processing") == .working)

    #expect(detectState(agent: .opencode, screen: "△ Permission required") == .blocked)
    #expect(detectState(agent: .opencode, screen: "esc to interrupt") == .working)
    #expect(detectState(agent: .opencode, screen: "done") == .idle)

    #expect(detectState(agent: .copilot, screen: "│ do you want to run this?") == .blocked)
    #expect(detectState(agent: .copilot, screen: "esc to cancel") == .working)
    #expect(detectState(agent: .copilot, screen: "done") == .idle)

    #expect(detectState(agent: .kimi, screen: "approve? [y/n]") == .blocked)
    #expect(detectState(agent: .kimi, screen: "thinking") == .working)
    #expect(detectState(agent: .kimi, screen: "done") == .idle)

    #expect(detectState(agent: .droid, screen: "EXECUTE\nenter to select") == .blocked)
    #expect(detectState(agent: .droid, screen: "⠋ esc to stop") == .working)
    #expect(detectState(agent: .droid, screen: "done") == .idle)

    #expect(detectState(agent: .amp, screen: "waiting for approval\nallow all for this session") == .blocked)
    #expect(detectState(agent: .amp, screen: "esc to cancel") == .working)
    #expect(detectState(agent: .amp, screen: "done") == .idle)
  }
}
