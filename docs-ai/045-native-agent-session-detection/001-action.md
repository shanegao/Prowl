# 045 — Native Agent Session Detection: Action Log

All implementation happened on one branch (`feat/agent-session-detection`) over
2026-07-11 and merged as PR #556 on 2026-07-12; the timeline below follows the branch
commits because each row is a distinct review/hardening wave.

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-11 | 12-CLI session-identity research (env vars, hooks, pre-mint, resume, storage encodings), verified against installed CLIs (Codex 0.144.1, Claude Code 2.1.207, Pi 0.79.2, Gemini 0.46.0, Droid 0.147.0, Kimi 1.41.0, OpenCode 1.17.18, Amp 2026-05, Copilot 1.0.70) | PR #556 review thread; [research-cli-session-identity.md](research-cli-session-identity.md) |
| 2026-07-11 | Initial implementation: session resolver + per-agent path parsing, `session` on `PaneAgentState` and in `prowl agents` | `3bb648de` |
| 2026-07-11 | Hardening + declarative `AgentSessionProfile` per agent; Claude cwd encoder fixed to all-non-alphanumeric → `-` (old slash-only rule failed every `~/.prowl/repos` worktree); uniqueness grouped by session id (multi-file layouts); surface re-check after resolver suspension; new exact evidence: Amp thread-log FDs, Copilot pid logs, Qwen runtime sidecars; OpenCode `opencode.db` store query; child-env channel prototyped and rejected | `cff1d78d` |
| 2026-07-11 | Qwen layout verified from source (`qwen-code@deb45ae`) instead of a local install; sidecar validation (`schema_version == 1`, `started_at` vs process start) rejects stale claims on reused pids | `a5fad65a` |
| 2026-07-11 | Adversarial review round 1 (nine findings): sticky-session expiry after two fresh ambiguous resolutions, two-agreeing rule + cross-process claim check for `medium`, writable-descriptors-only, opt-in header enrichment (Gemini only) with full-uuid reads, NFC + per-UTF-16-code-unit cwd encoding, symlink-resolved cwd variants, exponential backoff + 20k enumeration cap, locale-pinned Codex day directories | `47ac3f33` |
| 2026-07-11 | Round 2: truncated enumeration voids the whole scan; fingerprint read budget allocated per session (2 files × ≤12 sessions); `resolve()` reports fresh vs cache-replay so retention ages only on fresh results; Gemini requires a successful header read | `42f335b9` |
| 2026-07-11 | Round 3: truncated primary scan no longer falls through to the (superset) fallback root; unresolved-backoff streak resets when a resolved session turns ambiguous | `6eca2549` |
| 2026-07-11 | Round 4: sessions with no comparable transcript text block fingerprint uniqueness instead of being silently dropped; tails decoded lossily (128 KiB window can cut a multi-byte character) | `4afe3f3a` |
| 2026-07-11 | Round 5: "scoreable" threshold aligned with the 12-character comparison floor so short-fragment sessions cannot count as having testified | `9d3e87af` |
| 2026-07-12 | PR merged; `docs/components/cli.md` documents the `session` field and its confidence semantics in the same change | #556 (`9d8794d0`) |

## Outcome & current state (as of 2026-07-12)

Verified against the working tree:

- **Resolver**: `supacode/Infrastructure/AgentDetection/AgentSessionResolver.swift` —
  `AgentSession` (`Source`: `command_line`/`open_file`/`process_log`/`store_record`/
  `transcript_match`/`recent_file`; `Confidence`: `exact`/`high`/`medium`),
  `AgentSessionCandidate.uniqueActiveCandidate` (session-id grouping),
  `AgentSessionResolution.isFresh`, and the `AgentSessionResolver` actor
  (`AgentSessionResolver.shared`).
- **Per-agent knowledge**: `supacode/Infrastructure/AgentDetection/AgentSessionProfile.swift`
  — one profile per `DetectedAgent` case (all 12 agents), with `parsePath`,
  `candidateRoots`/`fallbackRoots`, `headerSessionIDKeys` + `requiresHeaderSessionID`
  (Gemini), `pidKeyedSession`, `storeCandidates`. `AgentSessionPathParser` survives as a
  thin compatibility shim over the profiles.
- **Pid artifacts**: `supacode/Infrastructure/AgentDetection/AgentPidArtifacts.swift`
  (`CopilotProcessLog`, `QwenRuntimeStatus`); **store query**:
  `supacode/Infrastructure/AgentDetection/OpenCodeSessionStore.swift` (read-only sqlite).
- **Darwin FD inspection**: `ProcessDetection.openFilePaths(pid:)` in
  `supacode/Infrastructure/AgentDetection/ProcessDetection.swift`, filtering to
  writable descriptors.
- **State & retention**: `supacode/Domain/AgentDetection/PaneAgentState.swift` carries
  `session` + `sessionMissStreak` and the pure `retainedSession` policy;
  `supacode/Features/Terminal/Models/WorktreeTerminalState+AgentDetection.swift` wires
  the resolver into detection (`resolveRetainedSession`), including the post-await
  surface re-check that prevents ghost Active Agents entries.
- **CLI surface**: `AgentsCommandSession` in
  `supacode/CLIService/Shared/AgentsCommandPayload.swift`, populated by
  `supacode/CLIService/AgentsCommandHandler.swift`; text mode appends
  `session=<id> [<confidence>]` in `ProwlCLI/Output/OutputRenderer.swift`. Behavior
  documented in `docs/components/cli.md` (session field, confidence caveat).
- **Tests**: `supacodeTests/AgentSessionResolverTests.swift` and
  `supacodeTests/AgentSessionProfileTests.swift` (path parsing, cwd encoders, root
  narrowing, FD enumeration against the test process, lifetime filtering, transcript
  matching, Copilot/Qwen artifacts, OpenCode fixture db);
  `ProwlCLITests/ProwlCLIIntegrationTests.swift` extended for the session payload.

## Deviations from plan

None structural — the plan doc was written alongside the implementation and merged in
the same PR. Two support-matrix rows shipped below the verification bar stated for the
rest: Qwen's layout is source-verified only (no local install), and Cursor's open
`store.db` descriptor evidence is path-recognition only, unverified live. Both are
flagged as such in the research doc's support matrix.

## Open questions

- Qwen (`runtime.json` sidecar) and Cursor (open `store.db` FD) evidence paths have
  never been exercised against a real installed CLI; first field use may surprise.
- Profiles pin "latest released CLI" as of 2026-07-11; known in-flight drift (Kimi
  `~/.kimi` → `~/.kimi-code`, Cline 3.x hub + sqlite) will silently degrade those
  agents to unresolved until someone edits the profile — there is no drift detection or
  telemetry for resolution rates.
- `AgentSession.Source` declares a `command_line` case that nothing emits (the sole
  occurrence in the tree is the declaration itself), and `docs/components/cli.md`'s
  source enumeration omits it; presumably reserved for pre-minted spawns. Harmless, but
  enum and doc disagree on the value set.
- The end-to-end manual acceptance pass (`prowl agents --json` per agent) described in
  the research doc's Verification section was defined but, per the PR description,
  running the *new* evidence paths end-to-end still needed an updated installed build at
  merge time.
