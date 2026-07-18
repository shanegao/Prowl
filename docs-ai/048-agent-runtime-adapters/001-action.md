# 048 — Agent Runtime Adapters: Action

| | |
| --- | --- |
| **Status** | Completed |
| **Anchor date** | 2026-07-18 |
| **Primary PRs** | Follow-up PR unassigned |
| **Plan** | [000-plan.md](000-plan.md) |
| **Related** | [047.002 resume-authored handoff](../047-cross-agent-handoff/002-resume-authored-handoff.md) |

## Delivered

- Added `AgentRuntimeAdapter`, `AgentRuntimeAdapterRegistry`, structured start/resume requests,
  `AgentInvocation`, and `AgentRuntimeClient`.
- Implemented verified Codex and Claude Code adapters. Start input is shell-rendered only at the
  existing terminal-tab boundary; headless resume runs direct argv through `ShellClient`.
- Promoted lossless process argv to `ForegroundProcess`, derived explicit model/unrestricted launch
  observations during detection, and retained each observation only for the same PID.
- Replaced handoff's hard-coded interactive shell strings with `AgentStartRequest`. Handoff now
  inherits only portable source intent: an explicitly observed unrestricted mode crosses between
  Codex and Claude Code, while a model remains same-adapter only.
- Added source-authored preparation to `handoff save`, `handoff to`, and the Command Palette. An
  exact/high source session is resumed before Prowl saves generated context; completion, failure,
  and skipped preparation are recorded in `log.md`.
- Updated the handoff, CLI, and Command Palette documentation with the safety boundary and
  configuration inheritance rules.

## Verification

- `make check`
- Focused `xcodebuild test` selection covering `AgentRuntimeAdapterTests`, PID-scoped launch
  observation, `HandoffCommandHandlerTests`, and Command Palette source preparation: 21 passed.
- `make build-app`: Debug macOS app built successfully with zero warnings.

## Deliberate limits

Only Claude Code and Codex have verified runtime adapters. Prowl never infers an execution policy
from an absent argv flag, never passes a model identifier across those agent families, and never
falls back to a cwd-based session scan. Unsupported detected agents remain available through
`handoff to --no-launch`.
