# 044 — Foundation Model Branch Name Suggestions: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-06-27 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #518 |
| **Sources** | `doc-onevcat/plans/2026-06-27-foundation-model-branch-name.md`, PR #518 description |
| **Related** | [019-worktree-creation-and-lifecycle](../019-worktree-creation-and-lifecycle/000-plan.md), `docs/components/repositories-and-worktrees.md` |

## Background

Creating a new worktree requires typing a branch name (e.g. `feature/my-change`) in the
creation dialog — friction on every Cmd+N. macOS 26 ships the on-device
`FoundationModels` framework, which can generate a contextual name from signals Prowl
already has: existing branch naming conventions, sibling worktree branch names, terminal
pane titles (OSC-2), and active terminal content. When the model is unavailable (older
hardware) or the suggestion fails, the existing `WorktreeNameGenerator`
(adjective-animal-NNN, e.g. `bold-cat-042`) remains the fallback.

A Phase 0 spike (standalone CLI tool, not kept in the repo) validated model quality and
latency first; the prefix-enforced prompt variant ("V3") performed best and gated the
go decision. Had the spike failed, only the random-name behavior would have shipped.

## Goals

- Auto-suggest a branch name in the worktree creation dialog, filled in asynchronously —
  the dialog opens immediately and the user can start typing at once.
- Never overwrite user input; the suggestion is advisory.
- Fall back to a random adjective-animal-NNN name whenever the model is unavailable or
  the suggestion fails validation.
- Abstract the LLM backend behind a protocol so future backends (stronger/remote models)
  can slot in without touching business logic.

### Non-goals

- The non-prompt path (`promptForWorktreeCreation == false`) keeps `nameSource: .random`
  unchanged — it exists for instant creation, and AI latency would violate that intent.
- Clipboard content is not used as a signal (macOS paste indicator + privacy concerns).

## Design / Approach

**LLM service layer.** `LLMService` protocol
(`supacode/Infrastructure/LLM/LLMService.swift`) with `isAvailable` and
`generate(prompt:)`. `FoundationModelLLMService`
(`supacode/Infrastructure/LLM/FoundationModelLLMService.swift`) wraps
`LanguageModelSession`, checks `SystemLanguageModel.default` availability, and applies a
3-second timeout.

**TCA dependency.** `BranchNameSuggestionClient`
(`supacode/Clients/BranchNameSuggestion/BranchNameSuggestionClient.swift`) exposes
`gatherContext` (a `@MainActor` closure, wired in `supacode/App/supacodeApp.swift`
capturing `WorktreeTerminalManager`) and `suggest` (builds the prompt, calls the LLM,
sanitizes/validates, returns `nil` on any failure so the caller falls back).

**Context gathering**, by signal priority: existing branch names (`baseRefOptions`,
first 10, for convention inference) → same-repo worktree branch names → terminal pane
titles → terminal active content via `readActiveContentsForCLI()` (per-pane cap
~300 chars, total budget ~1000 chars) → repository name. Worktrees are filtered to the
target repository, sorted selected-first then by a new
`WorktreeTerminalState.lastDefocusedAt` timestamp (set on focus-away in
`WorktreeTerminalManager`), and capped at 3.

**Prompt (V3, prefix-enforced).** Detects `/`-prefixes from existing branches and
instructs the model it MUST use one; falls back to "descriptive kebab-case" wording for
fresh repos. Rules: single line, max 50 chars, no duplicate of an existing branch.

**Sanitization & validation.** `BranchNameSanitizer`
(`supacode/Domain/BranchNameSanitizer.swift`): trim/lowercase, hyphenate whitespace and
underscores, strip invalid git-ref characters, collapse hyphen runs, truncate to 50.
Post-sanitization prefix enforcement: prepend the most common convention prefix from
existing branches, or `worktree/` when none. Validation returns `nil` (→ random
fallback) on duplicates (case-insensitive), length < 3 or > 50, or empty output.

**Dialog integration** (`WorktreeCreationPromptFeature` / `WorktreeCreationPromptView`):
the dialog opens with an empty field whose placeholder is a pre-generated random name
(`randomPlaceholder`); `isSuggestingName` drives a subtle trailing `ProgressView`. When
the suggestion arrives (`branchNameSuggestionReceived`) it is shown as a dim
"Auto suggestion: {name}" hint line with a "Use" button (`useSuggestedBranchName`) — it
does not auto-fill the field. On submit, `effectiveBranchName` uses the typed name if
non-empty, otherwise the random placeholder; empty input no longer blocks creation.

## Alternatives & decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Timing | Dialog opens immediately, name fills async | Don't block UI; user can start typing |
| Suggestion delivery | Opt-in hint + "Use" button, not auto-fill | Never overwrite user input (refined within the PR) |
| Fallback | Random adjective-animal-NNN | Uniform for prompt and non-prompt paths |
| Clipboard signal | Skipped entirely | macOS paste indicator + privacy |
| LLM layer | Protocol abstraction, Foundation Model default | Extensible without over-engineering |
| Spike gate | Ship random-name-only if spike failed | Avoid committing to insufficient model quality |

## Amendments

(none)
