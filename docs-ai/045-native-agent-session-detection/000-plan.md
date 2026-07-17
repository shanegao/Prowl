# 045 — Native Agent Session Detection: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-07-12 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #556 |
| **Sources** | `doc-onevcat/agent-session-detection.md` (kept verbatim as [research-cli-session-identity.md](research-cli-session-identity.md) in the docs-ai migration), PR #556 description and branch commits, the 2026-07-11 12-CLI session-identity research (same doc) |
| **Related** | [030-agent-status-detection](../030-agent-status-detection/000-plan.md) (predecessor: agent identity + status), [013-prowl-cli](../013-prowl-cli/000-plan.md) / [013.002 `prowl agents`](../013-prowl-cli/002-agents-command.md) (consumer surface), [029-active-agents-panel](../029-active-agents-panel/000-plan.md), `docs/components/cli.md` |

## Background

Entry [030](../030-agent-status-detection/000-plan.md) taught Prowl *which* agent runs in
a pane and whether it is working/blocked/idle — observation from the process table and
the rendered screen. What no layer knew was the agent's **native session identity**: the
session id and transcript path that the agent CLI itself uses for resume, forking, and
history. That identity is the foundation for planned handoff/dispatch features (resume a
stopped agent, open/export the right transcript, restore sessions after an app restart,
pre-mint ids when Prowl spawns agents) — none of which can safely run on a guessed id.

The work was preceded by a research pass (2026-07-11) over 12 agent CLIs — Codex, Claude
Code, Pi/OMP, Gemini, Cursor Agent, Cline, Copilot CLI, Kimi, Droid, OpenCode, Amp, Qwen
Code — covering five channels each: child-process environment variables, hooks, pre-mint
ids at spawn, headless resume, and on-disk storage encodings, verified against locally
installed CLIs where possible. The full findings are kept verbatim as
[research-cli-session-identity.md](research-cli-session-identity.md); this plan absorbs
its conclusions.

## Goals

- Resolve the exact agent process already selected by Active Agents to its native
  session metadata — id, local transcript path, evidence source, confidence — with
  **zero agent-side setup** (no hooks, no wrappers), same constraint as 030.
- Expose the result through `prowl agents` (optional `session` object in JSON, a
  `session=` suffix in text mode) so automation and future features share one contract.
- **Never guess.** A wrong session id silently corrupts any downstream resume/handoff;
  ambiguity is a normal, first-class outcome (`session: null`).
- Bound the cost: resolution runs continuously beside status detection across all panes.

### Non-goals

- Resuming, forking, or otherwise mutating an agent session — this layer only reads.
- A cooperative hook/shell-integration provider (agents self-reporting
  `{session_id, transcript_path, pid}` over the prowl socket or an OSC sequence) —
  designed for later as additional `exact` evidence, deliberately not built now.
- Agents behind SSH, containers, VMs, or nested tmux servers: local pid inspection
  cannot see them.

## Design / Approach

Resolution is anchored to the detected agent pid and tries evidence strongest-first:

1. **Open descriptors** (`exact`) — enumerate the pid's open vnode paths via
   `proc_pidinfo`/`proc_pidfdinfo` (never `lsof`); a unique recognized session file
   (Codex rollout, Amp per-thread log) is decisive. Only descriptors open for
   **writing** count: resume pickers open other sessions read-only.
2. **Pid-keyed artifacts** (`exact`) — files naming the pid directly: Copilot's
   `logs/process-<epoch-ms>-<pid>.log` ("Registering foreground session: <uuid>") and
   Qwen's `<session>.runtime.json` sidecar, validated against the live process
   (`schema_version == 1`, pid match, `started_at` sanity) because Qwen intentionally
   leaves sidecars behind on quit/crash.
3. **Transcript/screen correlation** (`high`) — bounded tails (128 KiB) of candidate
   transcripts compared with the pane's live text; only a unique match with sufficient
   score and margin *between distinct sessions* wins (multi-file layouts reinforce
   rather than compete). Read budget is per session so a chatty session cannot evict a
   competitor from the comparison.
4. **Sole process-lifetime candidate** (`medium`) — storage roots (or OpenCode's sqlite
   `session` table) filtered to entries modified during the process lifetime; a single
   distinct session id wins, but only after two consecutive agreeing resolutions and
   never when another live process already claimed the id (startup race in shared
   directories).

Supporting structure:

- **One declarative profile per agent** (`AgentSessionProfile`): path grammar, storage
  roots and narrowing (Codex day directories, Kimi/Cursor `md5(cwd)`, Gemini
  `projects.json` slug + `sha256(cwd)`), cwd encoders (Claude/Qwen
  `alphanumericDashed` — every non-alphanumeric → `-`, which is what makes
  `~/.prowl/repos/...` worktrees resolvable at all), pid artifacts, store queries.
  Prowl targets only the **latest released CLI** of each agent; layout changes edit the
  profile in place, no version-detection layers.
- **Caching & retention**: results keyed by `(pid, process start time)` so pid reuse
  cannot inherit a session; revalidated every 5 s; unresolved lookups back off
  exponentially (1 s → 15 s cap; wide fallback scans start at 8 s). A previously
  resolved session survives probe gaps and cache replays but at most two consecutive
  *fresh* ambiguous resolutions, so an id rotated away by `/clear` cannot stick forever.
- **Safety caps that preserve the never-wrong invariant**: directory enumeration capped
  at 20 000 entries with truncation voiding the whole scan (a partial view could declare
  a false unique), known storage roots only (narrow first, wide fallback second, no
  home-directory searching), OpenCode's db opened read-only with a 50 ms busy timeout,
  failures degrading to "unresolved".

## Alternatives & decisions

- **New entry, not an 030 amendment.** This work sits on top of 030's detection (same
  pid anchor, same Active Agents membership) and could have been filed as its next
  amendment. It was made a standalone entry deliberately: 030 answers *which agent, in
  what state* (observation for the panel), while this layer answers *which native
  session is it* — a separate resolver with its own consumer contract (`session` in
  `prowl agents`), its own per-agent knowledge base, and a forward-looking scope
  (handoff/resume/pre-minting) that 030 never had. Both entries cross-link; 030's plan
  marks this as its successor wave.
- **Child-process environment variables rejected** (prototyped, then documented so it is
  not reattempted). Five CLIs inject their session id into tool child processes
  (`CLAUDE_CODE_SESSION_ID`, `CODEX_THREAD_ID`, `COPILOT_AGENT_SESSION_ID`,
  `QWEN_CODE_SESSION_ID`, `AMP_CURRENT_THREAD_ID`), but since the macOS 15 hardening
  `KERN_PROCARGS2` strips the environment block for non-entitled callers. The variable
  names stay valuable for a future cooperative hook provider running *inside* the pane.
- **Never "newest file wins".** The resolver refuses to pick a candidate merely for
  recency; every ladder rung demands uniqueness. Consequence accepted: parallel
  same-directory sessions with indistinguishable visible text return `session: null`.
- **Latest-CLI-only profiles.** Version drift is real (Kimi migrating `~/.kimi` →
  `~/.kimi-code`, Cline 3.x moving to a hub + sqlite, Droid docs disagreeing with the
  shipped binary); profiles encode the latest observed truth only, and a future hook
  that hands Prowl a `transcript_path` should always beat computed paths.
- **Pre-minting is the plan for Prowl-spawned agents.** When Prowl itself dispatches a
  task, choosing the id at spawn (`--session-id`, `create-chat`, `amp threads new`)
  removes any need for detection; the research table is the contract for that future
  work. Detection exists for user-started sessions.
- **`medium` confidence is explicitly not resume-safe**: documented in
  `docs/components/cli.md` — a `medium` id must not drive automatic resume/fork without
  additional confirmation.

## Amendments

- None yet.
