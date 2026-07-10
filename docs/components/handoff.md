# Handoff — Agent To Agent

> How to hand a task off between coding agents inside a Prowl workspace: a durable
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
`Suggested Prompt For Next Agent`. The outgoing agent maintains these sections;
Prowl creates the template but never rewrites this file during a save.

`context.md` contains the detected outgoing agent, a pointer to the captured
session excerpt, each repo's branch and change counts, and the changed files.
Prowl atomically replaces this generated file on every `save`. Separating it from
`current.md` prevents background saves from overwriting prose being edited by an
agent or editor. Archives combine a read-only snapshot of both files.

`sessions/<ts>-<pane>.md` is a normalized excerpt from the outgoing pane. Today it
captures the current terminal screen/scrollback and records the detected agent,
session id, pane, source, confidence, and native transcript path when one is
available. Claude Code sessions are resolved from
`~/.claude/projects/<encoded-cwd>/*.jsonl`; Codex sessions are resolved from
`~/.codex/sessions/**/rollout-*.jsonl` by matching the rollout `cwd`. When native
exactly one native session matches, `confidence` is `medium`; ambiguous native
matches are omitted. Prowl still writes the terminal excerpt with fallback
confidence.

## The protocol

For both agents to follow the same contract natively, put these instructions in
the workspace root's `AGENTS.md` (Codex reads it) **and** `CLAUDE.md` (Claude Code
reads it):

```markdown
## Handoff protocol (this is a Prowl workspace)
- On start: read `.prowl/handoff/current.md`, `.prowl/handoff/context.md`, and `.prowl/workspace.json`. Continue from "Next Steps".
- Before you stop or hand off: update `.prowl/handoff/current.md` so another agent can resume cold.
- To hand the task to another agent, run:  `prowl handoff to <agent>`.
- Never commit/push or run destructive git unless asked. Do not put secrets in the handoff file.
```

This lets the outgoing agent run `prowl handoff to <agent>` itself as its last
step — the receiving agent then opens in a new tab pointed at the artifact.

## The `prowl handoff` command

```bash
prowl handoff save       [target] [--note "…"]              # refresh context + session excerpt + log
prowl handoff to <agent> [target] [--note "…"] [--no-launch]
prowl handoff status     [target]
```

- **`save`** refreshes the auto appendix from live git state and logs a line.
- **`to <agent>`** does `save`, archives the current artifact, then launches the
  receiving agent in a **new tab** whose kickoff prompt points it at
  `.prowl/handoff/current.md` and `.prowl/handoff/context.md`. Interactive launch is verified for `claude` and
  `codex`. `--no-launch` archives + saves only and accepts the full detected-agent
  token list: `pi`, `claude`, `codex`, `gemini`, `cursor-agent`, `cline`,
  `opencode`, `copilot`, `kimi`, `droid`, `amp`, `qwen`.
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

In a workspace, the Command Palette (`⌘P`) offers **Hand off → Claude Code** and
**Hand off → Codex**. Selecting one refreshes + archives the handoff artifact and
launches the receiving agent in a new tab — the GUI equivalent of
`prowl handoff to`. These actions appear only when the selected runnable target is
a workspace.

## Safety

- Handoff never commits, pushes, or runs destructive git — `save` only **reads**
  git state (`status` / `diff --stat`).
- Auto-save uses the same read-only `save` path and only updates targets with an
  existing `.prowl/handoff/current.md`.
- Save writes generated state only to `context.md`; after scaffolding it never
  rewrites agent-authored `current.md`.
- `to` only **adds** a tab; it never closes the outgoing agent's session, so you
  can still read or roll back from it.
- It always saves + archives **before** launching, so a fresh artifact exists even
  if the launch is interrupted.
- Keep secrets/tokens out of the handoff file (the protocol asks agents not to
  write them).
- `.prowl/handoff/` is self-ignoring; session excerpts can contain terminal
  context that belongs in local handoff state, not source control.

## Gotchas

- Handoff is workspace-centric; in a plain git worktree the same `.prowl/handoff/`
  works but the appendix covers just that one repo.
- The artifact's prose is only as good as what the outgoing agent wrote — the
  protocol in `AGENTS.md`/`CLAUDE.md` is what keeps it honest.
- Launching uses the interactive agent (so you can step in); don't use
  `--capture` against it — read its screen with `prowl read --wait-stable`.
