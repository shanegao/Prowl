# 047.002 — Resume-Authored Semantic Handoff

| | |
| --- | --- |
| **Status** | Planned |
| **Anchor date** | 2026-07-18 |
| **Primary PRs** | #554 (base implementation); follow-up PR unassigned |
| **Related** | [047 plan](000-plan.md), [045 native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), #473, `docs/components/handoff.md` |

## Context

#554 deliberately separates agent-authored semantic state in `current.md` from Prowl-generated
repository and terminal state in `context.md`. This prevents `save` and background auto-save from
racing an agent or editor that is updating the handoff prose. It also leaves a material gap: a
source agent that reaches a handoff point can leave the semantic artifact as a template or stale
summary.

The native `AgentSession` resolver introduced by #556 exists partly to enable safe future
handoff/dispatch operations. Its research records headless resume commands for the two currently
launchable agents:

```bash
codex exec resume <session-id> "<prompt>"
claude -p --resume <session-id> "<prompt>"
```

This amendment turns that capability into a narrow, explicit handoff preparation step. Prowl does
not generate semantic prose; it asks the source agent, in its own native session, to author the
artifact before Prowl creates the generated context, archive, and receiving pane.

## Goals

- Make `prowl handoff to <agent>` produce a current, agent-authored `current.md` before it saves,
  archives, or launches the receiving agent.
- Expose the same operation explicitly as `prowl handoff summarize [target]` for a human or agent
  that wants to refresh semantic state without handing work to another agent.
- Resume only a verified source session for Claude Code or Codex; never derive a session id from
  cwd, transcript recency, or terminal text.
- Preserve the #554 ownership boundary: Prowl writes only scaffolding and generated files, while
  the resumed source agent writes the semantic handoff document.
- Fail closed: without a verified summary, do not launch a receiving agent unless the caller
  explicitly opts into the existing manual workflow.

### Non-goals

- Resuming an active source agent, guessing whether concurrent access to a live session is safe,
  or using `.working`, `.done`, or `.blocked` screen heuristics as proof that it is safe.
- General resume, fork, restore, or dispatch support for every detected agent.
- Reconstructing a semantic handoff from a viewport, terminal scrollback, transcript, or an agent's
  final response. The native Stop-hook design remains separate in #473.
- Having Prowl or a local model write the prose on the source agent's behalf.

## Command contract

```bash
prowl handoff summarize [target] [--timeout <seconds>]
prowl handoff to <agent> [target] [--no-summary] [--note "…"] [--no-launch]
```

- `summarize` resolves the target's source pane and makes one bounded headless resume request to
  the source agent. Its only intended effect is an updated `.prowl/handoff/current.md`.
- `to` runs `summarize` first by default. On success it retains the existing #554 ordering:
  `save` → archive → launch receiving pane.
- `--no-summary` is the explicit escape hatch for the existing manual protocol. It preserves the
  current `save` → archive → launch behavior when an operator has already authored `current.md`.
- `save` remains a mechanical refresh and does not spend an agent turn. It continues to seed the
  template only when needed and update `context.md`, session excerpts, and `log.md`.

## Design / approach

1. Extend the shared handoff input and CLI parser with the `summarize` action, a bounded timeout,
   and `--no-summary` for `to`. The text and JSON output must report whether semantic preparation
   ran, the source agent, and an actionable unavailable/failed reason.
2. Resolve the target through the existing `TargetResolver`, then obtain its already-attached
   `PaneAgentState.session`. Summary preparation accepts only a source agent with an `exact` or
   `high` session mapping and a dedicated Claude Code or Codex summary adapter.
3. Add a source-ownership safety check before resuming. The adapter must refuse when the native
   session is still owned by a live source process or Prowl cannot prove that headless resume is
   safe for the installed CLI. Revalidate each agent's resume semantics against the installed CLI
   during implementation; the 2026-07 research is a command contract, not a substitute for this
   concurrency check.
4. `HandoffStore` creates the handoff scaffold if necessary, then records the pre-request artifact
   state. Run the adapter through an argv-based process invocation with the target root as cwd; do
   not synthesize terminal input or interpolate the prompt into a shell command.
5. The source prompt names the absolute target file and requires a complete replacement of the
   semantic sections: Objective, Current State, What Has Been Done, Open Questions, Risks / Watch
   Out, Next Steps, and Suggested Prompt For Next Agent. It forbids changing repository files,
   mutating git state, committing, pushing, or adding secrets.
6. After the process exits, validate that `current.md` was updated and contains substantive
   semantic sections rather than the initial template. Only then call the existing `save`, archive,
   and receiving-launch path. A summary failure leaves the source pane and existing artifact in
   place, logs a diagnostic event, and returns a handoff error without creating a receiving pane.

The proposed implementation boundary is a small `HandoffSummaryAdapter` selected by agent token,
used by `HandoffCommandHandler`, and backed by `HandoffStore` validation. `HandoffStore` must not
become a prose renderer. `ProwlCLI/Commands/HandoffCommand.swift`, shared command/payload models,
`supacode/CLIService/HandoffCommandHandler.swift`, `supacode/App/supacodeApp.swift`, and
`docs/components/handoff.md` / `docs/components/cli.md` are the expected touch points.

## Safety and failure semantics

| Condition | Result |
| --- | --- |
| No `AgentSession`, ambiguous session, or confidence below `high` | `summarize` fails; `to` does not launch the receiver. |
| Unsupported source agent | Same failure; use `--no-summary` only after manually authoring the artifact. |
| Live-session ownership is not disproven | Refuse to resume. |
| Headless command times out or exits unsuccessfully | Preserve the existing artifact; do not archive or launch. |
| `current.md` is unchanged or still only the template | Treat preparation as failed. |
| Caller passes `--no-summary` | Execute the existing manual handoff contract without a resume request. |

## Verification

- Parser and socket integration coverage for `summarize`, `--no-summary`, timeout validation, and
  output/error payloads.
- Adapter tests asserting argv construction for Codex and Claude Code without shell interpolation.
- Handler tests for exact/high acceptance, low/medium/ambiguous rejection, live-source rejection,
  summary timeout/failure, and the invariant that a failed summary creates no receiving pane or
  archive.
- Store tests for template detection and semantic-artifact validation without overwriting agent
  prose.
- Manual end-to-end checks against the installed Codex and Claude Code versions: resume a stopped
  source session, verify the semantic artifact is authored, then verify the receiver starts only
  after save and archive complete.

## Alternatives and decisions

- **Resume the source agent, rather than synthesize prose in Prowl.** The source session has the
  missing reasoning context. Prowl has mechanical state but cannot safely infer decisions, risks,
  or next steps from a screen snapshot.
- **Fail closed by default.** Launching a receiver with a blank or stale semantic artifact defeats
  the feature. `--no-summary` keeps the intentional manual path available without silently
  weakening the default.
- **Use exact/high native identity, not a new handoff-local scanner.** #556's pid-anchored resolver
  already encodes ambiguity and ownership safety. A second cwd-based lookup would reintroduce the
  sibling-pane attribution bug removed from #554.
- **Keep Stop hooks separate.** #473 may eventually provide a reliable last assistant message, but
  that message is not a structured handoff and cannot replace a source-authored summary.
