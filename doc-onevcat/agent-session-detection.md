# Agent Session Detection

## Purpose

Prowl resolves a detected terminal agent process to its native session metadata without requiring hooks. This is a
foundation for future handoff, resume, transcript, and automation features; this layer does not resume or mutate an
agent session.

## Resolution Model

Resolution is anchored to the exact process selected by Active Agents:

1. Preserve the matched process PID instead of only the normalized agent name.
2. Inspect that PID's open vnode paths. A unique recognized session file is `exact` evidence.
3. For agents that open transcripts only while appending, enumerate the agent's known session directory and keep files
   created or modified during the current process lifetime.
4. Extract a bounded tail from each candidate transcript and compare recent `user`, `assistant`, and `result` text with
   the pane's live bottom buffer.
5. Accept only a unique match with a sufficient score and margin. Ambiguous results remain unresolved.
6. Cache and periodically revalidate a mapping by `(pid, process start time)` so PID reuse cannot inherit an old
   session and in-process session rotation can be detected.

The resolver never selects a candidate merely because it is the newest file. A sole process-lifetime candidate is
reported as `medium`; a unique text correlation is `high`; an open file owned by the exact process is `exact`.

## Support Matrix

The following versions were inspected on 2026-07-11:

| Agent | Version | Storage recognized | Current confidence path |
| --- | --- | --- | --- |
| Codex | 0.144.1 | `~/.codex/sessions/**/rollout-*.jsonl` | Exact writable open FD; transcript fallback |
| Claude Code | 2.1.206 | `~/.claude/projects/<cwd>/*.jsonl` | Process lifetime + transcript/screen match |
| Pi / OMP | Pi 0.79.2 | `~/.pi/agent/sessions/<cwd>/*.jsonl` | Process lifetime + transcript/screen match |
| Gemini CLI | 0.46.0 | `~/.gemini/tmp/**/chats/session-*.jsonl` | Best effort, strict unique match |
| Cursor Agent | 2026.05.09-0afadcc | `~/.cursor/chats/<project>/<session>/store.db` | Path recognition; best effort |
| Cline | 2.18.0 | `~/.cline/data/tasks/<task>/...` | Path recognition; best effort |
| GitHub Copilot CLI | 1.0.44 | `~/.copilot/session-state/<session>/...` | Path recognition; best effort |
| Kimi Code | 1.41.0 | `~/.kimi/sessions/<project>/<session>/...` | Path recognition; best effort |
| Droid | 0.147.0 | `~/.factory/sessions/<cwd>/<session>.jsonl` | Process lifetime + transcript/screen match |
| OpenCode | 1.17.18 | Shared `opencode.db` | Unresolved: no safe process-to-row mapping yet |
| Amp | 0.0.1778328768-gb9a37d | No stable transcript mapping observed | Unresolved |
| Qwen | Not installed | Not verified | Unresolved |

Codex kept its rollout JSONL open for the whole interactive session. Claude and Pi were both tested after completing a
real prompt; each created and wrote its JSONL, then closed it while the interactive process remained alive. This is why
open-FD inspection is primary evidence rather than the only strategy.

## Safety and Performance

- Darwin inspection uses `proc_pidinfo` / `proc_pidfdinfo`; Prowl never shells out to `lsof`.
- Results are cached per process lifetime. Unresolved processes retry at most once per second.
- Transcript reads are capped at 128 KiB from the tail.
- Known storage roots are used; arbitrary home-directory searching is not performed.
- Matching accepts ambiguity as a normal outcome. A session ID from `medium` confidence must not be used for automatic
  resume/fork without additional confirmation.
- Local PID inspection cannot see agents behind SSH, containers, VMs, or nested tmux servers.

## Verification

Build and run a Debug Prowl app, start an agent in a pane, send at least one distinctive prompt, then inspect:

```bash
prowl agents --json | jq '.data.agents[] | {type, pane: .pane.id, session}'
```

A simple Codex process with one open rollout uses `source: "open_file"` and `confidence: "exact"`. A Codex process that
also owns subagent rollouts is disambiguated like Claude and Pi: after a distinctive user or assistant message it uses
`source: "transcript_match"` and `confidence: "high"`. Parallel sessions in the same directory with indistinguishable
visible text must return `session: null` rather than guess.

Targeted automated coverage:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/AgentSessionResolverTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

The test suite covers known path parsing, native open-FD enumeration against the test process, process-lifetime
filtering, unique transcript matching, and ambiguous transcript rejection.

## Future Uses

- Add native session identity and confidence to handoff preparation.
- Fork or resume a stopped source agent only when the mapping is exact/high.
- Open or export the correct transcript from Active Agents.
- Restore agent sessions after an app restart.
- Diagnose duplicated or stale agent sessions from `prowl agents` output.
- Add an optional hook provider later as `exact` evidence without changing the consumer contract.
