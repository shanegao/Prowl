# 029 — Active Agents Panel: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-09 | Created `onevcat/ghostty` fork branch `release/v1.3.1-patched` exporting `ghostty_surface_pid()`; Prowl submodule repointed to the fork | change-list 2026-05-09 |
| 2026-05-09 | During bring-up, added a second fork export `ghostty_surface_foreground_process_group()` (pty `tcgetpgrp`) after `proc_bsdinfo.e_tpgid` returned nil for the shell PID in manual testing | task log, PR #274 |
| 2026-05-10 | Shipped Phases 0–2: detection layer (`ProcessDetection`, `AgentClassifier`, `ScreenHeuristics`), domain model (`DetectedAgent`, `AgentRawState`, `PaneAgentState`), per-surface detection loop in `WorktreeTerminalState`, `ActiveAgentsFeature` + panel/row views, footer toggle, ⌘⌥P shortcut, auto-show setting, click-to-focus, agent icons | PR #274 |
| 2026-05-24 | ⌃⌥↑/↓ Select Next/Previous Agent shortcuts | PR #335 (see [002](002-selection-and-keyboard-navigation.md)) |
| 2026-05-24 | Fixed tab flip + highlight flicker when selecting agents (focus-before-select ordering) | PR #336 (see [002](002-selection-and-keyboard-navigation.md)) |
| 2026-05-25 | Fixed row activation for agents in plain folders | PR #344 (see [002](002-selection-and-keyboard-navigation.md)) |
| 2026-05-28 | Row repo/branch resolved from the agent's working directory, not the owning tab's worktree | PR #363 (see [003](003-row-display-resolution.md)) |
| 2026-06-04 | Setting to show tab titles instead of branch names in agent rows | PR #386 (see [003](003-row-display-resolution.md)) |
| 2026-06-19 | Agent working/blocked state folded into the worktree running indicator (`taskStatus`) | PR #475 (see [004](004-agent-busy-running-indicator.md)) |

## Outcome & current state (as of 2026-07-12)

- **Panel feature**: `supacode/Features/ActiveAgents/` — `Reducer/ActiveAgentsFeature.swift`
  (entries as `IdentifiedArrayOf<ActiveAgentEntry>`, `focusedSurfaceID` keyboard anchor,
  `selectNextEntry`/`selectPreviousEntry`, panel visibility/height via
  `@Shared(.appStorage)`), `Views/ActiveAgentsPanel.swift`, `Views/ActiveAgentRow.swift`
  (status pill uses a `BaguaWorkingIndicator` animation), `Models/ActiveAgentEntry.swift`
  (carries `workingDirectory: URL?` for display resolution).
- **Detection layer**: `supacode/Infrastructure/AgentDetection/` — `ProcessDetection.swift`,
  `AgentClassifier.swift`, `ScreenHeuristics.swift` (single file; per-agent detectors are
  private pure functions exposed as `DetectedAgent.detectState(in:)`). The directory has
  since grown session-identity files (`AgentSessionProfile.swift`,
  `AgentSessionResolver.swift`, `AgentPidArtifacts.swift`, `OpenCodeSessionStore.swift`)
  belonging to [045](../045-native-agent-session-detection/000-plan.md), and
  `supacode/Domain/AgentDetection/AgentDetectionSchedule.swift` from the detection
  hardening tracked in [030](../030-agent-status-detection/000-plan.md).
- **Domain model**: `supacode/Domain/AgentDetection/` — `DetectedAgent.swift` (now 12
  cases; `qwen` added later, see [030](../030-agent-status-detection/000-plan.md)),
  `AgentRawState.swift`, `PaneAgentState.swift` (including `isBusy` from PR #475).
- **Ghostty bridge**: `supacode/Infrastructure/Ghostty/GhosttySurfaceBridge.swift` —
  `childPID()` and `foregroundProcessGroupID()` call the fork exports
  `ghostty_surface_pid` / `ghostty_surface_foreground_process_group` directly (the
  initial `dlsym` indirection used before the xcframework rebuild is gone);
  `readViewportText()` feeds the heuristics.
- **Terminal integration**: `supacode/Features/Terminal/Models/WorktreeTerminalState.swift`
  runs the per-surface detection loop and owns `tabAgentBusyById`;
  `supacode/Clients/Terminal/TerminalClient.swift` carries `agentEntryChanged` /
  `agentEntryRemoved` events and the `focusSurface` command.
- **Wiring**: footer toggle in `supacode/Features/Repositories/Views/SidebarFooterView.swift`
  (`person.crop.rectangle.stack[.fill]`); shortcuts `toggleActiveAgentsPanel` (⌘⌥P),
  `selectNextActiveAgent`, `selectPreviousActiveAgent` in `supacode/App/AppShortcuts.swift`;
  settings `autoShowActiveAgentsPanel` and `showActiveAgentTabTitles` in
  `supacode/Features/Settings/Models/GlobalSettings.swift`; row display resolution in
  `supacode/Features/Repositories/Views/SidebarListView.swift`
  (`activeAgentRowDisplays` / `resolveWorktreeID(forWorkingDirectory:in:)`).
- User-facing behavior is documented in `docs/components/active-agents.md` and
  `docs/components/agent-detection.md`; the `prowl agents` CLI view over the same data
  is [013-prowl-cli/002-agents-command](../013-prowl-cli/002-agents-command.md).

## Deviations from plan

- **No `ActiveAgentsRegistry`**: the plan called for a top-level `@Observable` registry
  (`Features/ActiveAgents/Models/ActiveAgentsRegistry.swift`). Instead, entries flow as
  `TerminalClient` events (`agentEntryChanged`/`agentEntryRemoved`) straight into
  `ActiveAgentsFeature` state; no registry file exists.
- **No status-priority sorting**: the planned reducer-side sort
  (blocked → working → done → idle) was listed as a follow-up in PR #274 and was never
  implemented; entries stay in insertion order in the `IdentifiedArray`.
- **Footer toggle symbol**: plan proposed `rectangle.bottomthird.inset[.filled]`; shipped
  `person.crop.rectangle.stack[.fill]` because the planned symbol rendered empty in the
  hidden state on the tested system.
- **Extra fork export**: the plan required only `ghostty_surface_pid`;
  `ghostty_surface_foreground_process_group` was added during implementation because
  `e_tpgid` was unreliable.
- **Extra scope in #274**: ⌘⌥P shortcut, View-menu entry, and the auto-show setting were
  not in the plan (which only specified the footer toggle).
- **Single `ScreenHeuristics.swift`**: the optional per-agent `Detectors/` file split was
  not done.
- Agent display names use short lowercase command tokens (`claude`, `codex`, …) by
  decision — the panel is a compact terminal-status surface, not product branding.

## Open questions

- The planned status-priority sorting of panel rows (blocked first) is still absent as
  of 2026-07-12; unclear whether it was dropped deliberately or just never picked up.
- PR #274 listed "off-main-actor process scanning" as a follow-up (polling happened on
  the MainActor per surface every 300–500 ms); whether the current scheduling
  (`AgentDetectionSchedule`, entry [030](../030-agent-status-detection/000-plan.md))
  fully addressed this was not verified here.
