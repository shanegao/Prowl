# 044 — Foundation Model Branch Name Suggestions: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-27 | Core implementation: `LLMService` + `FoundationModelLLMService`, `BranchNameSuggestionClient`, `BranchNameSanitizer`, dialog integration, `lastDefocusedAt` tracking | PR #518 (`82055a63`) |
| 2026-06-27 | Refined within the PR: random placeholder as the default, AI suggestion demoted to an opt-in hint with "Use" button (no auto-fill); tests updated | PR #518 (`e929b62f`, `64e500a2`) |
| 2026-06-27 | Suggestion tooltip moved to a trailing `questionmark.circle` icon on the hint row | PR #518 (`ec26c5d4`, `bcd83977`) |
| 2026-06-27 | Merged | #518 (`7cb3dd75`) |

## Outcome & current state (as of 2026-07-12)

All pieces from the plan exist and are unchanged since the merge:

- `supacode/Infrastructure/LLM/LLMService.swift` — `LLMService` protocol
  (`isAvailable`, `generate(prompt:)`).
- `supacode/Infrastructure/LLM/FoundationModelLLMService.swift` — wraps
  `LanguageModelSession`, availability via `SystemLanguageModel.default.isAvailable`,
  3-second timeout implemented with a racing task group.
- `supacode/Clients/BranchNameSuggestion/BranchNameSuggestionClient.swift` —
  `BranchNameSuggestionContext` (+ `TerminalHint`), prefix-enforcing `buildPrompt`,
  `live(llmService:)` validating output through `BranchNameSanitizer.validate`.
- `supacode/Domain/BranchNameSanitizer.swift` — `sanitize`, `detectConventionPrefix`
  (fixed known-prefix list: `feature/`, `fix/`, `bugfix/`, `hotfix/`, `chore/`,
  `refactor/`, `docs/`, `test/`, `ci/`), `ensurePrefix` (`worktree/` fallback),
  `validate` (max length 50, min 3, duplicate rejection).
- `supacode/App/supacodeApp.swift` — `makeBranchNameSuggestionClient(terminalManager:)`
  overrides `gatherContext`: same-repo filter, selected worktree first then
  `lastDefocusedAt` descending, top 3, focused pane title + active content capped at
  300 chars per pane.
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` —
  `var lastDefocusedAt: Date?`, set on focus-away in
  `supacode/Features/Terminal/BusinessLogic/WorktreeTerminalManager.swift`.
- `supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeCreation.swift` —
  kicks off the suggestion effect from `promptedWorktreeCreationDataLoaded`
  (cancellable via `CancelID.branchNameSuggestion`, cancelled on prompt dismissal);
  the non-prompt path still uses `nameSource: .random`.
- `supacode/Features/Repositories/Reducer/WorktreeCreationPromptFeature.swift` —
  `isSuggestingName`, `suggestedBranchName`, `randomPlaceholder`,
  `effectiveBranchName`; actions `branchNameSuggestionReceived` /
  `useSuggestedBranchName`.
- `supacode/Features/Repositories/Views/WorktreeCreationPromptView.swift` — placeholder
  prompt text, mini `ProgressView` overlay while suggesting, hint row with "Use" button
  and a help tooltip on a `questionmark.circle` icon.

User-facing behavior is documented in `docs/components/repositories-and-worktrees.md`
(creation prompt section).

## Deviations from plan

- The plan sketched loading branch refs and requesting the suggestion "in parallel";
  the implementation starts the suggestion after the refs load (the context needs
  `baseRefOptions`), so it runs sequentially after data load, still async to the dialog.
- `LLMService.isAvailable` is a synchronous property, not `get async` as sketched.
- The plan's ~1000-char total content budget across worktrees is not implemented; only
  the 300-char per-pane cap and the 3-worktree limit exist.
- The plan document's own verification list (item 6: "non-prompt path → AI name is
  used") contradicts its "Non-prompt path: No change" section; the implementation and
  the PR test plan follow the latter (non-prompt stays random).

## Open questions

- `BranchNameSanitizer` has no dedicated unit tests despite being pure logic; only
  reducer-level tests (`supacodeTests/RepositoriesFeatureTests.swift`,
  `supacodeTests/WorktreeCreationPlacementTests.swift`) were touched in #518.
- `detectConventionPrefix` only recognizes its fixed prefix list, so repos using
  variants like `feat/` get the `worktree/` fallback when the model output lacks a
  slash, even though `buildPrompt` correctly advertises `feat/` to the model. Minor
  inconsistency between the prompt-side and sanitizer-side prefix detection.
