import Testing

@testable import supacode

struct ScreenHeuristicsTests {
  @Test func unknownAgentIsUnknown() {
    let agent: DetectedAgent? = nil
    #expect(agent?.detectState(in: "Working...") ?? .unknown == .unknown)
  }

  @Test func piDetection() {
    #expect(DetectedAgent.pi.detectState(in: "Working...") == .working)
    #expect(DetectedAgent.pi.detectState(in: "Done") == .idle)
  }

  @Test func claudeDetection() {
    #expect(
      DetectedAgent.claude.detectState(
        in: """
          Reading file
          ✽ Tempering…
          ─────────
          ❯
          ─────────
          """
      ) == .working
    )
    #expect(
      DetectedAgent.claude.detectState(
        in: """
          Do you want to proceed?
          ❯ 1. Yes
            2. No

          Esc to cancel · Tab to amend
          """
      ) == .blocked
    )
    #expect(
      DetectedAgent.claude.detectState(
        in: """
          Task complete.
          ─────────
          ❯
          ─────────
          """
      ) == .idle
    )
  }

  @Test func claudeIgnoresStalePermissionPromptNearCurrentIdlePrompt() {
    #expect(
      DetectedAgent.claude.detectState(
        in: """
          Do you want to proceed?
          ❯ 1. Yes
            2. No

          Completed line 1
          Completed line 2
          Completed line 3
          Completed line 4
          Completed line 5
          Completed line 6
          Completed line 7
          Completed line 8
          Completed line 9
          Completed line 10
          Completed line 11
          Completed line 12
          Task complete.
          ─────────
          ❯
          ─────────
          """
      ) == .idle
    )
  }

  @Test func claudeIgnoresStalePermissionPromptOutsideRecentTail() {
    #expect(
      DetectedAgent.claude.detectState(
        in: """
          Do you want to proceed?
          ❯ 1. Yes
            2. No

          Completed line 1
          Completed line 2
          Completed line 3
          Completed line 4
          Completed line 5
          Completed line 6
          Completed line 7
          Completed line 8
          Completed line 9
          Completed line 10
          Completed line 11
          Completed line 12
          Completed line 13
          Completed line 14
          Completed line 15
          Completed line 16
          Completed line 17
          Completed line 18
          Completed line 19
          Completed line 20
          Completed line 21
          Completed line 22
          Completed line 23
          Completed line 24
          Task complete.
          ─────────
          ❯
          ─────────
          """
      ) == .idle
    )
  }

  @Test func codexDetection() {
    #expect(DetectedAgent.codex.detectState(in: "press enter to confirm or esc to cancel") == .blocked)
    #expect(DetectedAgent.codex.detectState(in: "• Working (12s)\nesc to interrupt") == .working)
    #expect(DetectedAgent.codex.detectState(in: "Ready for input") == .idle)
  }

  @Test func otherAgentDetectorsCoverStateTriplets() {
    #expect(DetectedAgent.gemini.detectState(in: "│ Apply this change") == .blocked)
    #expect(DetectedAgent.gemini.detectState(in: "esc to cancel") == .working)
    #expect(DetectedAgent.gemini.detectState(in: "done") == .idle)

    #expect(DetectedAgent.cursor.detectState(in: "Run command? (y) (enter)") == .blocked)
    #expect(DetectedAgent.cursor.detectState(in: "⬡ indexing") == .working)
    #expect(DetectedAgent.cursor.detectState(in: "done") == .idle)

    #expect(DetectedAgent.cline.detectState(in: "Let Cline use this tool? yes") == .blocked)
    #expect(DetectedAgent.cline.detectState(in: "Cline is ready for your message") == .idle)
    #expect(DetectedAgent.cline.detectState(in: "still processing") == .working)

    #expect(DetectedAgent.opencode.detectState(in: "△ Permission required") == .blocked)
    #expect(DetectedAgent.opencode.detectState(in: "esc to interrupt") == .working)
    #expect(DetectedAgent.opencode.detectState(in: "done") == .idle)

    #expect(DetectedAgent.copilot.detectState(in: "│ do you want to run this?") == .blocked)
    #expect(DetectedAgent.copilot.detectState(in: "esc to cancel") == .working)
    #expect(DetectedAgent.copilot.detectState(in: "done") == .idle)

    #expect(DetectedAgent.kimi.detectState(in: "approve? [y/n]") == .blocked)
    #expect(DetectedAgent.kimi.detectState(in: "thinking") == .working)
    #expect(DetectedAgent.kimi.detectState(in: "🌘") == .working)
    #expect(DetectedAgent.kimi.detectState(in: "⠸ Using Shell (git status)") == .working)
    #expect(
      DetectedAgent.kimi.detectState(
        in: """
          ⠸ Using Shell (git remote -v && echo "--..." && git log --oneline -3)
          ╭─ approval ─────────────────────────────────────────────────────────╮
          │  Shell is requesting approval to run command:                      │
          │                                                                    │
          │ → [1] Approve once                                                 │
          │   [2] Approve for this session                                     │
          │   [3] Reject                                                       │
          │   [4] Reject, tell the model what to do instead                    │
          │                                                                    │
          │   ▲/▼ select  1/2/3/4 choose  ↵ confirm                            │
          ╰────────────────────────────────────────────────────────────────────╯
          """
      ) == .blocked
    )
    #expect(DetectedAgent.kimi.detectState(in: "done") == .idle)

    #expect(DetectedAgent.droid.detectState(in: "EXECUTE\nenter to select") == .blocked)
    #expect(DetectedAgent.droid.detectState(in: "⠋ esc to stop") == .working)
    #expect(DetectedAgent.droid.detectState(in: "done") == .idle)

    #expect(DetectedAgent.amp.detectState(in: "waiting for approval\nallow all for this session") == .blocked)
    #expect(DetectedAgent.amp.detectState(in: "esc to cancel") == .working)
    #expect(DetectedAgent.amp.detectState(in: "done") == .idle)
  }
}
