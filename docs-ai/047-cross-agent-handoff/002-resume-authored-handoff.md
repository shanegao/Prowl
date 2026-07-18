# 047.002 — Resume-Authored Semantic Handoff

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-18 |
| **Primary PRs** | #554 (artifact base); follow-up PR unassigned |
| **Related** | [047 plan](000-plan.md), [048 runtime adapters](../048-agent-runtime-adapters/000-plan.md), [045 native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), #473, `docs/components/handoff.md` |

## Context

#554 separated agent-authored semantic state in `current.md` from Prowl-generated
repository and terminal state in `context.md`. That preserves ownership, but a handoff command
could still create or archive a stale template when the outgoing agent had not manually updated it.

Prowl already attaches a pid-anchored `AgentSession` and detected launch arguments to each pane.
The runtime-adapter work in [048](../048-agent-runtime-adapters/000-plan.md) provides verified
direct-argv resume invocations for Claude Code and Codex. This amendment consumes that evidence
only at the existing handoff boundary.

## Decision

`prowl handoff save` and `prowl handoff to <agent>` now make a best-effort, source-authored
preparation request before Prowl saves generated context:

1. Require a detected Claude Code or Codex source with an attached `exact` or `high` confidence
   `AgentSession`. No cwd scan, transcript recency, screen text, or heuristic status can qualify.
2. Resume that session headlessly through `AgentRuntimeClient` with the target root as cwd. The
   prompt asks the source agent to update semantic sections in `current.md`, preserve useful notes,
   leave `context.md`/logs/archives alone, and avoid repository or git mutations.
3. Record `preparation=completed`, `failed`, or `skipped` in the handoff log. Prowl then performs
   its normal mechanical save; `to` continues with archive and destination launch.

There is deliberately no new `summarize` command, timeout flag, summary payload field, or
`--no-summary` escape hatch. The existing command surface stays stable. A failed or unavailable
preparation does not fabricate prose or block the existing manual handoff workflow; the existing
`current.md` (or scaffold) remains the artifact.

## Launch configuration

The same argv observation drives both preparation and the receiving start:

- An explicit source `--model` remains only with the same adapter. A Codex model identifier is not
  passed to Claude Code, and vice versa.
- An explicitly observed unrestricted source mode maps between the two verified adapters:
  Codex `--dangerously-bypass-approvals-and-sandbox` and Claude Code
  `--dangerously-skip-permissions`.
- Absence of a flag means unknown source intent. Prowl uses the destination adapter's standard
  configuration rather than assuming a source configuration default.

The Command Palette follows the same path. It captures the selected pane's session and observation,
prepares the source when safe, persists the artifact, and starts the receiving tab through the
adapter rather than a hard-coded shell line.

## Safety boundaries

| Condition | Result |
| --- | --- |
| No source session, ambiguous mapping, or confidence below `high` | Skip automatic preparation; preserve the normal save/archive/launch workflow. |
| Unsupported source or destination adapter | Skip source preparation; `handoff to` still rejects unsupported interactive launch and supports `--no-launch`. |
| Resume command exits unsuccessfully | Mark preparation failed in `log.md`; retain existing agent prose and continue mechanical handoff. |
| Source session resumes successfully | Prowl still never writes semantic prose itself; it saves only generated state to `context.md`. |
| Cross-agent handoff with source model | Omit the model. Preserve only the verified unrestricted execution intent. |

This is an identity-safety boundary, not proof that a source conversation has stopped. Prowl does
not claim to own or fork a live agent session; it issues one headless resume request only when the
pid-anchored resolver already established a safe session identity.

## Implementation

- `AgentRuntimeAdapterRegistry` owns adapter-specific launch observation, structured start/resume
  invocation creation, and source-to-destination configuration inheritance.
- `PaneAgentState` retains argv-derived launch observation only while the detected process PID is
  unchanged. This prevents a stale dangerous-mode flag from leaking to a later process.
- `HandoffCommandHandler` receives the resolved source session and observation, requests
  preparation before save/archive, and passes `AgentStartRequest` to the composition root.
- `AgentRuntimeClient` executes preparation through `ShellClient` using direct argv and the target
  working directory. The tab launcher renders only the destination start invocation.
- `TerminalClient` exposes selected-pane session/launch observation for the Command Palette, whose
  reducer uses the same preparation request and runtime client.

## Verification

- `AgentRuntimeAdapterTests` covers Codex/Claude start and resume argv, explicit unrestricted
  observation, cross-agent model isolation, same-adapter model inheritance, and direct shell
  execution through `AgentRuntimeClient`.
- `PaneAgentStateTests` covers PID-scoped retention of launch observation.
- `HandoffCommandHandlerTests` covers verified-source preparation before persistence, preserved
  source-authored prose, medium-confidence rejection, destination configuration, archive, and
  launch behavior.
- `AppFeatureHandoffTests` covers the Command Palette's source preparation, destination argv, and
  preserved cross-agent execution policy.

## Alternatives and decisions

- **Do not render prose in Prowl.** The source session holds the reasoning that is absent from
  repository state and terminal excerpts.
- **Do not add a second session scanner.** The existing pid-anchored resolver rejects ambiguity;
  reintroducing cwd-based matching would reintroduce sibling-pane attribution risk.
- **Do not block handoff when preparation is unavailable.** A manual, existing `current.md` is
  still valuable, and an unavailable resume path must not silently remove the documented
  `--no-launch` workflow.
- **Keep Stop hooks separate.** #473 may eventually provide a last assistant message, but that
  message is neither a safe session identity nor a structured handoff document.
