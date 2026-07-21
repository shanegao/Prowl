# 047.004 — Inline-First Handoff Redesign

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-07-21 |
| **Primary PRs** | (this wave) |
| **Related** | [047 plan](000-plan.md), [047.002](002-resume-authored-handoff.md), [047.003](003-plan-calibration.md), [045-native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), `docs/components/handoff.md` |

## Context

A design review of the shipped handoff flow (047.001–047.003) surfaced structural problems
in how the transition acquires its briefing and how the CLI models the source:

1. **The preparation resume mutates the live source session.** The Claude adapter renders
   `claude -p --resume <id> <prompt>` without `--fork-session`; on current Claude Code
   (verified against 2.1.216) `--resume` defaults to *continuing the same session ID*, so a
   headless preparation appends turns to the transcript of a session that is still open in
   the pane — a dual-writer on one JSONL. "Read-only by construction" held for permission
   flags but not for session state.
2. **The CLI has no source identity.** `prowl handoff` reuses the generic target selector;
   with no selector it resolves the *focused* pane — unstable UI state. An agent running the
   documented protocol (`prowl handoff to <agent>` as its last step) triggers a resume of
   *its own mid-turn session*: the fork misses the in-flight turn, overwrites the agent's
   freshly written `current.md` with an older-context reply, and blocks the Bash call for up
   to two minutes.
3. **Stale artifacts impersonate fresh contracts.** When preparation is unavailable, the
   previous `current.md` (or the scaffold template) stays in place and the static kickoff
   prompt still points the receiver at it. The transition archive is also taken *after*
   preparation rewrote the file, so it records the new state, not the outgoing one.
4. **The CLI path hijacks the UI.** `launchHandoffReceiver` selects the target worktree and
   focuses the new tab; an agent-initiated handoff yanks the user's screen.
5. **Resume-fork briefings are structurally worse than they looked.** Transcripts on current
   models persist thinking blocks as *empty signed shells* (measured across 15 recent
   sessions: 300+ blocks, zero non-empty). A forked session cold-reads a record whose
   reasoning layer is empty; the live agent holds the reasoning, the salience ranking, and
   the handoff intent in working memory.

## Decision

Rebuild the handoff flow around one **pure transition function** with an **inline,
agent-authored briefing** as the primary input, executed **headlessly**:

```
transition(source, destination, briefing) =
  archive(previous current.md + context.md)          // outgoing state first
  → current.md ← validated briefing | absent          // never a template, never stale
  → context.md ← live git + session state             // recomputed, not maintained
  → launch destination (background tab, no UI focus)  // headless by construction
  → log + notification
```

### Source identity: caller pane, not focused pane

- Explicit selector (`--pane/--tab/--worktree/target`) wins, unchanged.
- Otherwise the source is the **caller pane**: the CLI service reads the peer PID of the
  socket connection (`getsockopt(LOCAL_PEERPID)`) and walks the process ancestry to the
  pane whose shell owns the calling `prowl` process.
- No selector and no caller pane (invoked outside Prowl) → **error** with guidance. The
  focused-pane default is removed; a handoff must never guess its subject.

### Briefing: inline first, fork as explicit fallback

- **CLI self-handoff** (caller == source): `prowl handoff to <agent> --brief -` reads the
  briefing from stdin. The author is the live agent — full working context, the handoff
  intent, zero extra model calls, zero latency. Missing `--brief` errors with a
  copy-pasteable fix; `--no-brief` is the explicit context-only escape. A brief that fails
  validation errors with zero side effects.
- **UI (HUD / palette)**: no headless resume. Prowl **injects a self-contained instruction
  into the source pane** asking the live agent to run the CLI self-handoff; completion is
  observed via the caller-pane identity (caller == source correlates the CLI call with the
  HUD run). The HUD becomes a trigger + observer with a fallback ladder: wait (queued while
  the agent is busy) → resume-fork → context-only, chosen by the user on timeout. This also
  widens source coverage from claude/codex to every detected agent.
- **CLI third-party** (caller ≠ source): resume-fork remains the default — the author is
  not present. The fork is made side-effect-free: Claude adds `--fork-session`, Codex adds
  `--ephemeral`. On failure/timeout/no-safe-session the transition **degrades to
  context-only and continues** (`preparation=failed` in log and payload) — this path's
  rescue scenario (wedged agent being relieved) must not be blocked by the wedged agent.

### Artifact semantics

- **`current.md` exists ⟺ it is a validated briefing product.** Template seeding and the
  "agent maintains current.md" protocol are abolished; when no briefing is available the
  file is archived and removed, and the kickoff prompt (now generated per-transition)
  points the receiver at `context.md` + `archive/` only.
- Archive-before-write is a global invariant: any write of `current.md` first archives the
  previous version; a transition archives the *outgoing* state before producing the new one.
- `handoff status` and status-transition auto-save are **deleted**: under the pure model
  `context.md` is derived at transition time, nothing consumes it in between, and artifact
  existence is no longer meaningful state. `handoff save` survives, redefined as the
  deferred-handoff checkpoint (briefing + context, no destination/launch/transition log).

### Headless launch and awareness

- The destination tab is created in the source's worktree with `focusing: false` and
  without `selectCLIWorktreeContext`; surfaces start their pty eagerly, so the agent runs
  regardless of visibility. Nothing selects, focuses, or raises.
- A completion notification (`<from> → <to> · <worktree>`, click-to-focus) reuses the bell
  pipeline and its suppression rule (silent when the target worktree is selected and the
  app is frontmost — the appearing tab is the signal there). The HUD, being user-present,
  focuses the new pane itself on completion; the core never does.

## Alternatives considered

- **mtime freshness checks on `current.md`** — superseded: freshness by construction
  (regenerate every transition) removes the need for staleness heuristics entirely.
- **Skip-preparation-when-working guard** — a proxy for self-handoff detection; replaced by
  exact caller-pane identity.
- **Moving handoff under `prowl agents`** — rejected: the CLI grammar is uniformly
  "verb + selector"; the real defect was source identity, not command placement.
- **Uniform resume-fork for all paths** — rejected on evidence: fork latency (≤2 min),
  full-history cost, and empty-thinking transcripts make it strictly worse whenever the
  author is present.

## Implementation

(to be completed with the PR)

## Verification

(to be completed with the PR)
