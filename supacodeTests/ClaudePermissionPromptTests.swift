import Testing

@testable import supacode

struct ClaudePermissionPromptTests {
  @Test func parsesBoxedEditPrompt() {
    let screen = """
      ● I'll make that edit.

      ╭───────────────────────────────────────────────╮
      │ Do you want to make this edit to Foo.swift?     │
      │                                                 │
      │ ❯ 1. Yes                                        │
      │   2. Yes, allow all edits during this session   │
      │   3. No, and tell Claude what to do differently │
      ╰───────────────────────────────────────────────╯
      """

    let prompt = ClaudePermissionPrompt.parse(screen: screen)

    #expect(prompt?.question == "Do you want to make this edit to Foo.swift?")
    #expect(
      prompt?.options == [
        .init(number: 1, label: "Yes"),
        .init(number: 2, label: "Yes, allow all edits during this session"),
        .init(number: 3, label: "No, and tell Claude what to do differently"),
      ]
    )
  }

  @Test func stripsSelectionCaretFromAnyOption() {
    // The caret can sit on whichever option is highlighted, not always the first.
    let screen = """
      Do you want to proceed?
      1. Yes
      ❯ 2. No
      """
    let prompt = ClaudePermissionPrompt.parse(screen: screen)
    #expect(prompt?.options == [.init(number: 1, label: "Yes"), .init(number: 2, label: "No")])
  }

  @Test func returnsNilWhenNoNumberedOptions() {
    let screen = """
      ● Running the build…
      esc to interrupt
      """
    #expect(ClaudePermissionPrompt.parse(screen: screen) == nil)
  }

  @Test func returnsNilForLoneOption() {
    // A single "1." line is more likely stray text than a real choice prompt.
    #expect(ClaudePermissionPrompt.parse(screen: "Step 1. Clone the repo") == nil)
  }

  @Test func ignoresStrayNumberedTextAboveTheRealPrompt() {
    // A "1." far above must not anchor the parse; only the consecutive run counts.
    let screen = """
      Released v1. Today we shipped a lot.
      Do you want to proceed?
      ❯ 1. Yes
      2. No
      """
    let prompt = ClaudePermissionPrompt.parse(screen: screen)
    #expect(prompt?.question == "Do you want to proceed?")
    #expect(prompt?.options.count == 2)
  }

  @Test func returnsNilForEmptyOrBlankScreen() {
    #expect(ClaudePermissionPrompt.parse(screen: "") == nil)
    #expect(ClaudePermissionPrompt.parse(screen: "   \n\n  ") == nil)
  }

  @Test func requiresSelectionCaret() {
    // A numbered list with no ❯ caret is agent output, not an interactive prompt —
    // parsing it would let a quick-answer button fire a stray keypress into the pane.
    let screen = """
      Here are the steps:
      1. Clone the repo
      2. Run the build
      """
    #expect(ClaudePermissionPrompt.parse(screen: screen) == nil)
  }

  @Test func keepsInternalPeriodsInOptionLabels() {
    // Only the first dot delimits the number; periods inside the label are kept.
    let screen = """
      Proceed with the plan?
      ❯ 1. Yes, do it. Then stop.
      2. No.
      """
    let prompt = ClaudePermissionPrompt.parse(screen: screen)
    #expect(
      prompt?.options == [
        .init(number: 1, label: "Yes, do it. Then stop."),
        .init(number: 2, label: "No."),
      ]
    )
  }

  @Test func omitsQuestionWhenNoHeadlineAboveOptions() {
    // No content line above the options → question is nil so the caller keeps the
    // agent's own notification body instead of a synthesized placeholder.
    let screen = """
      ❯ 1. Yes
      2. No
      """
    let prompt = ClaudePermissionPrompt.parse(screen: screen)
    #expect(prompt?.question == nil)
    #expect(prompt?.options.count == 2)
  }

  @Test func dropsNonConsecutiveOption() {
    // A gap in the numbering (3 missing) drops the discontinuous option.
    let screen = """
      Proceed?
      ❯ 1. A
      2. B
      4. D
      """
    let prompt = ClaudePermissionPrompt.parse(screen: screen)
    #expect(prompt?.options == [.init(number: 1, label: "A"), .init(number: 2, label: "B")])
  }

  @Test func strayNumberedLineBelowCollapsesToNil() {
    // A stray "1." below the real prompt re-anchors the run; with only one option
    // left it safely falls back to the plain notification rather than mis-parsing.
    let screen = """
      Do you want to proceed?
      ❯ 1. Yes
      2. No
      1. Unrelated numbered line below
      """
    #expect(ClaudePermissionPrompt.parse(screen: screen) == nil)
  }
}
