# 035 — Protected Terminal Close: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-25 | Confirmation policy + wiring for pane, tab, and tab-batch closes; run-script tab replacement and dead-process closes skip the prompt; policy unit tests | PR #345 (fork issue #341) |
| 2026-06-07 | Confirmation flow moved into `WorktreeTerminalState+Surfaces.swift` during the large-file split; mode/target enums widened from `private` to internal | PR #403 |
| 2026-06-07 | CLI tab/pane close commands route through the same confirmation; `--force` maps to `.skip` | PR #405 |

## Outcome & current state (as of 2026-07-12)

- `supacode/Features/Terminal/Models/TerminalCloseConfirmationPolicy.swift` —
  `TerminalCloseProtectionCandidate`, `TerminalCloseProtectionReason`
  (`agentActive` / `longRunningCommand`), `TerminalCloseConfirmationDecision`,
  and the pure `decision(for:threshold:)` with
  `longRunningCommandThreshold = 10` seconds. Agent panes are protected while
  `agentDisplayState` is `.working` / `.blocked` / `.done`; `.idle` (and
  agent-less panes under the threshold) are not.
- `supacode/Features/Terminal/Models/WorktreeTerminalState.swift` — declares
  `TerminalCloseConfirmationMode` (`.prompt(target)` / `.skip`) and
  `TerminalCloseConfirmationTarget` (`.pane` / `.tab` / `.tabs(count:)` with
  alert copy); `closeTab(_:confirmation:)` guards on the confirmation, and
  `closeOtherTabs` / `closeTabsToRight` / `closeAllTabs` confirm once with
  `.prompt(.tabs(count:))` then close each tab with `.skip`. Run-script tab
  replacement (`runScript` / `stopRunScript`) closes with `.skip`.
- `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift` —
  `confirmCloseIfNeeded(tabIds:/surfaceIDs:mode:)`,
  `closeProtectionCandidates(surfaceIDs:)`, the `NSAlert`-based
  `presentCloseConfirmation` (synchronous `runModal`), and
  `closeConfirmationMessage(for:)`. `closeSurface(id:confirmation:)` defaults
  to `.prompt(.pane)`; `handleCloseRequest(for:processAlive:)` prompts only
  when the process is alive. `updateRunningState(for:)` maintains
  `surfaceRunningStartedAtById` from each surface's Ghostty progress state.
- Agent signal: `surfaceAgentStates: [UUID: PaneAgentState]`
  (`supacode/Domain/AgentDetection/PaneAgentState.swift`); `displayState`
  maps raw `idle` to `.done` while `seen == false`, so "unseen result"
  protection ends exactly when the pane is viewed
  (see [030-agent-status-detection](../030-agent-status-detection/000-plan.md)).
- CLI integration: the `closeTab` / `closePane` handlers in
  `supacode/App/supacodeApp.swift` pass `force ? .skip : .prompt(...)`, so
  `prowl close-tab` / `close-pane` hit the same GUI prompt unless `--force`
  is given — documented in `docs/components/cli.md`.
- Tests: `supacodeTests/TerminalCloseConfirmationPolicyTests.swift` — four
  Swift Testing cases covering working/blocked/done protection, idle
  exemption, the 10 s threshold boundary, and pane counting across a tab.

## Deviations from plan

None known. PR #345's structure survived intact; PR #403 only relocated the
confirmation helpers from `WorktreeTerminalState.swift` into the `+Surfaces`
extension file, and PR #405 extended the existing mode parameter to CLI
callers rather than adding a parallel path.

## Open questions

- `closeConfirmationMessage(for:)` hardcodes "at least 10 seconds" in the
  alert text while the policy's threshold is a parameter (defaulted to the
  same constant). If the threshold were ever tuned, the copy would silently
  drift. Cosmetic only today since all call sites use the default.
