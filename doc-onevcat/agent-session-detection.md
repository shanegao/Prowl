# Agent Session Detection

## Purpose

Prowl resolves a detected terminal agent process to its native session metadata without requiring hooks. This is a
foundation for future handoff, resume, transcript, and automation features; this layer does not resume or mutate an
agent session.

## Resolution Model

Resolution is anchored to the exact process selected by Active Agents. Evidence is tried strongest-first:

1. **Open descriptors** (`exact`, `open_file`): inspect the agent pid's open vnode paths via
   `proc_pidinfo`/`proc_pidfdinfo`. A unique recognized session file (or Amp's per-thread log) is decisive.
2. **Pid-keyed artifacts** (`exact`, `process_log`): files that name the agent pid directly — Copilot's
   `logs/process-<epoch-ms>-<pid>.log` (containing "Registering foreground session: <uuid>") and Qwen's
   `<session>.runtime.json` sidecar (`{"pid": ..., "session_id": ...}`).
3. **Transcript/screen correlation** (`high`, `transcript_match`): bounded tails of candidate transcripts are compared
   with the pane's live text. Only a unique match with sufficient score and margin wins; the margin rule applies
   between *distinct sessions* — several files of one session (Kimi, Cline, Copilot) reinforce it instead of competing.
4. **Sole process-lifetime candidate** (`medium`, `recent_file` / `store_record`): storage roots (or OpenCode's sqlite
   `session` table) are filtered to entries modified during the process lifetime; a single distinct session id wins.

Supporting rules:

- Per-agent knowledge (path grammar, storage roots, cwd encoders, pid artifacts, store queries) lives in one place:
  `AgentSessionProfile`. Prowl targets only the **latest released CLI** of each agent — when a CLI changes layout,
  edit its profile in place rather than adding version detection.
- The resolver never picks a candidate merely because it is the newest file. Ambiguity is a normal outcome.
- Results are cached by `(pid, process start time)` so pid reuse cannot inherit an old session; resolved mappings are
  revalidated every 5 s (rotation via `/clear` is caught by the transcript match), unresolved ones retried once per
  second.
- Storage scans use narrowed roots first (Codex day directories, Kimi/Cursor `md5(cwd)`, Gemini slug/sha256), then a
  wider fallback root only when the narrow scan finds nothing (a resumed Codex rollout lives in its original day
  directory).

## Working-directory encoders (verified on-disk)

| Encoder | Rule | Used by |
| --- | --- | --- |
| `alphanumericDashed` | every char outside `[A-Za-z0-9]` → `-` (`/a/b_c.d` → `-a-b-c-d`) | Claude (`~/.claude/projects/`) |
| `slashDashed` | only `/` → `-`; dots and spaces kept | Pi (wrapped `-…--`), Droid |
| `md5(cwd)` | lowercase hex md5 of the absolute path | Kimi, Cursor |
| `sha256(cwd)` | lowercase hex sha256 | Gemini (older layout); newer maps cwd→slug in `~/.gemini/projects.json` |
| plain cwd | stored verbatim in metadata | OpenCode (`session.directory`), Copilot (`workspace.yaml`), Qwen sidecar |

Claude's rule matters in production: Prowl worktrees live under `~/.prowl/repos/...`, and the dot in `.prowl` must be
encoded as `-` or every Claude session in a managed worktree fails to resolve.

## Support Matrix

Verified 2026-07-11 against locally installed CLIs (best effort where noted):

| Agent | Version | Storage recognized | Strongest evidence path |
| --- | --- | --- | --- |
| Codex | 0.144.1 | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | Open rollout FD (`exact`) |
| Claude Code | 2.1.207 | `~/.claude/projects/<sanitized cwd>/*.jsonl` | Lifetime + transcript match |
| Pi / OMP | 0.79.2 | `~/.pi/agent/sessions/-<cwd>--/*.jsonl` | Lifetime + transcript match |
| Gemini CLI | 0.46.0 | `~/.gemini/tmp/<slug|sha256>/chats/session-*.jsonl` | Lifetime + transcript match |
| Cursor Agent | 2026.05.09 | `~/.cursor/chats/<md5(cwd)>/<uuid>/store.db` | Open store.db FD (unverified); path recognition |
| Cline | 2.18.0 | `~/.cline/data/tasks/<task id>/...` | Path recognition; best effort |
| GitHub Copilot CLI | 1.0.70 | `~/.copilot/session-state/<uuid>/...` | **Pid log artifact (`exact`)** |
| Kimi (Python 1.x) | 1.41.0 | `~/.kimi/sessions/<md5(cwd)>/<uuid>/...` | Lifetime + transcript match |
| Droid | 0.147.0 | `~/.factory/sessions/<cwd>/<uuid>.jsonl` | Lifetime + transcript match |
| OpenCode | 1.17.18 | `opencode.db` `session(id, directory, time_updated)` | **Store query (`medium`)** |
| Amp | 2026-05 build | `~/.cache/amp/logs/threads/T-<id>.log` (open FD, logged in) | **Open thread-log FD (`exact`)** |
| Qwen Code | not installed | `~/.qwen/projects/<cwd>/chats/*.jsonl` + `*.runtime.json` | **Pid sidecar (`exact`)**; best effort |

Codex keeps its rollout JSONL open for the whole interactive session. Claude, Pi, Droid, and Kimi close their session
files between writes; Amp only materializes local thread artifacts when logged in; OpenCode's TUI holds only the shared
sqlite database (no per-session file, and by default no local server port — the API worker is in-process).

## Rejected channel: child-process environment variables

Five CLIs inject their session id into tool child processes (Claude `CLAUDE_CODE_SESSION_ID`, Codex `CODEX_THREAD_ID`,
Copilot `COPILOT_AGENT_SESSION_ID`, Qwen `QWEN_CODE_SESSION_ID`, Amp `AMP_CURRENT_THREAD_ID`/`AGENT_THREAD_ID`).
**Reading them from outside is not possible on modern macOS**: since the macOS 15 hardening, `KERN_PROCARGS2` returns
only `argc + exec path + argv` for other processes — the environment block is stripped for non-entitled callers, even
for the caller's own children (verify with `ps eww <pid>`: no env shown). Do not reattempt this channel; the variable
names remain valuable for a future cooperative hook/shell-integration provider that runs *inside* the pane.

## Native identity/handoff surface per agent (2026-07 research)

For the future handoff/dispatch features. "Pre-mint" = the orchestrator chooses or learns the id at spawn time,
removing any need for detection.

| Agent | Hook w/ session id | Pre-mint at spawn | Headless resume |
| --- | --- | --- | --- |
| Claude Code | `SessionStart` etc., stdin JSON incl. `transcript_path` | `--session-id <uuid>` | `claude -p --resume <id>` |
| Codex | hooks GA (`session_id` + rollout path); legacy `notify` | — | `codex exec resume <id> "prompt"` |
| Gemini | hooks ≥ 0.26 (`session_id` + `transcript_path`) | `--session-id <uuid>` | `gemini -r <id> "prompt"` |
| Qwen | Claude-style hooks; official pid sidecar | `--session-id <uuid>` | `qwen --resume <id> -p` |
| Copilot | `sessionStart` hooks (`sessionId`) | `--session-id <uuid>` | `copilot -p "..." --session-id <id>` |
| Cursor | hooks partial in CLI (`sessionStart` fires) | `create-chat` prints id | `cursor-agent -p --resume=<id>` |
| Kimi | hooks in config (`session_id`, no transcript) | — | `kimi -p --session <id>` |
| Droid | Claude-style hooks incl. `transcript_path` | — | `droid exec -s <id> "prompt"` |
| Pi | TS extensions (`session_start`, `getSessionFile()`) | `--session-id <id>` (creates) | `pi --session <id>` |
| OpenCode | JS plugins (`session.created/idle`, `shell.env`) | — | `opencode run -s <id> "msg"` |
| Amp | JS plugins (`session.start` w/ thread id) | `amp threads new` prints id | `amp threads continue <id> -x "msg"` |
| Cline | hooks (`TaskStart`, `taskId`) | — | `cline -y -T <id>` |

Implications:

- When Prowl itself spawns the agent (task dispatch), prefer pre-minting (`--session-id`/`create-chat`/`threads new`):
  identity is exact by construction and this table is the contract to use.
- A cooperative hook provider (Prowl-installed hook configs reporting `{session_id, transcript_path, pid}` back over
  the prowl socket, or via an OSC sequence written to `/dev/tty` so it survives SSH) can later supply `exact` evidence
  for user-started sessions without changing the consumer contract.
- Version drift is real (Kimi is migrating `~/.kimi` → `~/.kimi-code`; Cline 3.x moves to a hub + sqlite; Droid docs
  show a different transcript root than 0.147 uses). Profiles encode the latest observed truth only, and hooks that
  hand Prowl a `transcript_path` should always win over computed paths.

## Safety and Performance

- Darwin inspection uses `proc_pidinfo` / `proc_pidfdinfo`; Prowl never shells out to `lsof`.
- Results are cached per process lifetime. Unresolved processes retry at most once per second.
- Transcript reads are capped at 128 KiB from the tail; Copilot log reads at 256 KiB.
- Known storage roots only; narrowed roots first, wider fallback second; no arbitrary home-directory searching.
- OpenCode's database is opened read-only with a 50 ms busy timeout; failures degrade to "unresolved".
- Matching accepts ambiguity as a normal outcome. A `medium` session id must not be used for automatic resume/fork
  without additional confirmation.
- Local pid inspection cannot see agents behind SSH, containers, VMs, or nested tmux servers.

## Verification

Build and run a Debug Prowl app, start an agent in a pane, send at least one distinctive prompt, then inspect:

```bash
prowl agents --json | jq '.data.agents[] | {type, pane: .pane.id, session}'
```

- Codex with one open rollout: `source: "open_file"`, `confidence: "exact"`.
- Claude in a directory containing `.`/`_`/space (e.g. a `~/.prowl/repos/...` worktree): must resolve via
  `recent_file` or `transcript_match` — this exercises the `alphanumericDashed` encoder.
- Copilot: `source: "process_log"`, `confidence: "exact"` once the TUI has registered its session.
- Amp (logged in): `source: "open_file"` with the thread id from the open per-thread log.
- OpenCode: sole session in the worktree resolves as `source: "store_record"`, `confidence: "medium"`; parallel
  sessions in one directory stay `null`.
- Parallel same-directory sessions with indistinguishable visible text must return `session: null` rather than guess.

Targeted automated coverage:

```bash
xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" \
  -only-testing:supacodeTests/AgentSessionResolverTests \
  -only-testing:supacodeTests/AgentSessionProfileTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation
```

The suites cover path parsing per agent, cwd encoders, root narrowing (day directories, md5, slug), native open-FD
enumeration against the test process, process-lifetime filtering with session-id grouping, unique/ambiguous transcript
matching, the Copilot pid-log and Qwen sidecar artifacts, and the OpenCode store query against a fixture database.

## Future Uses

- Add native session identity and confidence to handoff preparation; pre-mint ids for Prowl-initiated sessions.
- Fork or resume a stopped source agent only when the mapping is exact/high.
- Open or export the correct transcript from Active Agents.
- Restore agent sessions after an app restart.
- Diagnose duplicated or stale agent sessions from `prowl agents` output.
- Add an optional hook provider later as `exact` evidence without changing the consumer contract.
