# Handoff — Agent To Agent

> How to hand a task off between coding agents inside a Prowl runnable target: a durable
> artifact agents read and write, an auto-captured session excerpt, the
> `prowl handoff` command, and a command-palette action.

**Keywords:** handoff, hand off, codex, claude, switch agent, takeover, `.prowl/handoff`, current.md, prowl handoff, cross-agent, workspace

**Related:** [workspaces](workspaces.md) · [cli](cli.md) · [agent-detection](agent-detection.md) · [command-palette](command-palette.md)

## Why

Coding agents are independent processes; each keeps its own conversation
context. When you switch from one to another, the first agent's in-memory context
is **not** visible to the second. The only durable channel between them is the
filesystem. Handoff makes that channel a first-class, structured artifact so the
receiving agent (or you) can resume cold.

Handoff is centred on [workspaces](workspaces.md) — one task, several repos, a
shared root — but works for any runnable target.

## The artifact

Everything lives under the target's `.prowl/handoff/` directory:

```text
<root>/.prowl/handoff/
  .gitignore            self-ignore all local handoff state
  current.md            agent-authored handoff artifact (the cross-agent contract)
  context.md            Prowl-generated repository and session state
  log.md                append-only handoff history
  archive/<ts>-<from>-to-<to>.md
  sessions/<ts>-<pane>.md
```

Prowl creates `.prowl/handoff/.gitignore` with `*`, so the entire directory is
self-ignoring when the target is a git repository or worktree. No edit to the
repository's root `.gitignore` is required.

`current.md` contains only agent-authored prose: `Objective`, `Current State`,
`What Has Been Done`, `Open Questions`, `Risks`, `Next Steps`, and
`Suggested Prompt For Next Agent`. When Prowl has an exact or high-confidence
native session for a supported outgoing agent, `handoff save` and `handoff to`
first resume that agent in a read-only, non-interactive turn and ask it to
**reply** with the updated document; Prowl validates the reply (required
sections present, not the seeded template) and transcribes it into `current.md`.
The prose is always the agent's — Prowl never authors semantic content, it only
seeds the template and transcribes validated replies.

`context.md` contains the detected outgoing agent, a pointer to the captured
session excerpt, each repo's branch and change counts, and the changed files.
Prowl atomically replaces this generated file on every `save`. Separating it from
`current.md` prevents background saves from overwriting prose being edited by an
agent or editor. Archives combine a read-only snapshot of both files.

`sessions/<ts>-<pane>.md` is a normalized excerpt from the outgoing pane. It
captures the current terminal screen/scrollback and records the detected agent,
session id, pane, source, confidence, and native transcript path when one is
available. These native fields come from the pid-anchored session identity already
attached to the pane (the same metadata exposed by `prowl agents`); handoff does
not run a second cwd-based transcript scan. Ambiguous or unavailable sessions are
omitted rather than guessed. Prowl still writes the terminal excerpt with
`fallback` confidence.

## The protocol

For both agents to follow the same contract natively, put these instructions in
the target root's `AGENTS.md` (Codex reads it) **and** `CLAUDE.md` (Claude Code
reads it):

```markdown
## Handoff protocol (this is a Prowl runnable target)
- On start: read `.prowl/handoff/current.md`, `.prowl/handoff/context.md`, and `.prowl/workspace.json` if present. Continue from "Next Steps".
- Before you stop or hand off: update `.prowl/handoff/current.md` so another agent can resume cold.
- To hand the task to another agent, run:  `prowl handoff to <agent>`.
- Never commit/push or run destructive git unless asked. Do not put secrets in the handoff file.
```

This lets the outgoing agent run `prowl handoff to <agent>` itself as its last
step — the receiving agent then opens in a new tab pointed at the artifact.

## The `prowl handoff` command

```bash
prowl handoff save       [target] [--note "…"] [--no-prepare]   # refresh context + session excerpt + log
prowl handoff to <agent> [target] [--note "…"] [--no-launch] [--no-prepare]
prowl handoff status     [target]
```

- **`save`** first asks the detected outgoing Claude Code or Codex session to
  reply with an updated `current.md` when its native session identity is exact
  or high confidence; Prowl validates and transcribes the reply. The resume is
  read-only (no permission flags) and bounded to **2 minutes** — a stalled or
  unusable reply is logged as `preparation=failed` and the existing artifact
  stays in place. It then refreshes generated context from live git state and
  logs one `save` line recording whether preparation completed, failed, or was
  skipped. `--no-prepare` skips the source turn entirely for a fast mechanical
  refresh (use it when the outgoing agent already maintains `current.md`
  itself, e.g. from inside its own session).
- **`to <agent>`** follows the same preparation path, then saves, archives the
  current artifact, and launches the receiving agent in a **new tab** with a
  semantic kickoff prompt for `current.md` and `context.md`. Interactive launch
  is verified for `claude` and `codex`. When Prowl observed the outgoing launch,
  it preserves an explicit unrestricted execution policy across those adapters
  for the **destination launch only**; model identifiers stay with the same
  agent family and are never translated between Codex and Claude Code.
  `--no-launch` still prepares, archives, and saves; it accepts the full
  detected-agent token list: `pi`, `claude`, `codex`, `gemini`, `cursor-agent`,
  `cline`, `opencode`, `copilot`, `kimi`, `droid`, `amp`, `qwen`, `grok`.
- **`status`** reports the artifact path, whether it exists, the detected current
  agent, and the last log line.

The outgoing agent is detected automatically (the same signal as
[`prowl list`](cli.md)'s `pane.agent`). Full flag/payload reference:
[cli](cli.md#prowl-handoff).

Prowl also auto-saves an initialized handoff artifact from the same detection
chain. Once `.prowl/handoff/current.md` exists for a runnable target, Prowl
refreshes it when a detected agent moves from **working** to **done** or
**blocked**. Auto-save is throttled per pane and does not create handoff files
for targets that have never run `prowl handoff save` or `prowl handoff to`.

## From the command palette

For any selected workspace, git repository, worktree, or plain folder, the
Command Palette (`⌘P`) offers **Hand off → Claude Code** and **Hand off → Codex**.
It runs the same source-session preparation when safe — showing a progress toast
in the toolbar while the source agent writes its summary — then refreshes +
archives the artifact and starts the receiving agent in a new tab using the same
adapter configuration rules as `prowl handoff to`. If preparation fails, a
warning toast notes the handoff continued with the existing notes.

## Safety

- Handoff never commits, pushes, or runs destructive git — `save` only **reads**
  git state (`status` / `diff --stat`).
- Auto-save uses the same read-only `save` path and only updates targets with an
  existing `.prowl/handoff/current.md`.
- Save writes generated state only to `context.md`; the only time Prowl touches
  `current.md` after scaffolding is to transcribe a validated preparation reply
  authored by the source agent itself.
- The preparation resume is **read-only by construction**: it never passes
  `--dangerously-*` flags, regardless of how the source session was launched.
  Unrestricted-mode inheritance applies only to the interactive destination
  launch of `handoff to`.
- `to` only **adds** a tab; it never closes the outgoing agent's session, so you
  can still read or roll back from it.
- It always saves + archives **before** launching, so a fresh artifact exists even
  if the launch is interrupted.
- Automatic source preparation is skipped when Prowl cannot prove an exact or
  high-confidence native session, when the agent has no verified resume
  adapter, or when `--no-prepare` is passed. A reply that fails validation is
  recorded as `preparation=failed` and never overwrites the existing artifact.
- Keep secrets/tokens out of the handoff file (the protocol asks agents not to
  write them).
- `.prowl/handoff/` is self-ignoring; session excerpts can contain terminal
  context that belongs in local handoff state, not source control.

## Gotchas

- Workspaces aggregate generated context across their child repositories. A
  regular repository or worktree covers just that repo; a plain folder omits git
  branch and diff details.
- If no safe native source session is available, Prowl skips automatic
  preparation rather than guessing which agent conversation to resume. Update
  `current.md` manually in that case.
- Launching uses the interactive receiving agent (so you can step in); don't use
  `--capture` against it — read its screen with `prowl read --wait-stable`.
