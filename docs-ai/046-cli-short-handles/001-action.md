# 046 — CLI Short Handles: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-07-13 | Added session-scoped short tab and pane handles for explicit CLI targeting, while preserving UUID-only JSON contracts. | Issue #474 |

## Outcome & current state

- `TerminalTargetHandleRegistry` is owned by `WorktreeTerminalManager` and shared by all
  active `WorktreeTerminalState` instances. It allocates one global, increasing sequence
  for tab and pane UUIDs, releases a mapping at teardown, and never reuses a number during
  the app process.
- Tab creation, splits, layout restoration, tab/pane close paths, and worktree pruning
  register or unregister their targets. Restoring a persisted UUID therefore gets a fresh
  short handle rather than inheriting a stale one.
- Explicit `--pane` accepts a pane UUID, `pN`, or bare `N`; explicit `--tab` accepts a tab
  UUID, `tN`, or bare `N`. Auto and positional target resolution deliberately remain
  UUID/worktree-only because a bare number can be a worktree name.
- Text `prowl list` displays `tN` and `pN`; text `prowl agents` displays `pN`. The app only
  includes optional handle fields in text-mode socket payloads, so `--json` remains exactly
  the existing UUID-only v1 shape.
- User-facing CLI, terminal, and Active Agents documentation now explains the lifetime,
  explicit-selector requirement, and UUID-versus-handle choice. The bundled `prowl-cli`
  skill follows the same guidance.

## Tests and verification

- Added allocator, resolver, lifecycle/restore, list/agents payload, and CLI text rendering
  regression coverage. The targeted Swift Testing invocation passed 9/9 tests; Xcode also
  emitted existing SwiftPM dependency-scan diagnostics without test failures.
- `make check` passed.
- `make build-app` passed with 0 errors and 0 warnings.
- `make build-cli` and `make test-cli-smoke` passed; `make test-cli-integration` passed
  55/55 tests.
- An isolated Debug Prowl instance showed `t5` / `p6` in text `list`, kept UUID-only
  `list --json` output, resolved the created pane through both `read --pane p6` and
  `read --pane 6`, and closed the exact created tab with `tab close --tab t5`. The temporary
  tabs, Debug app, and dedicated socket were removed afterwards.
- The full `make test` run reached 1,792 passing tests before the unrelated
  `ExternalDiffToolTests.snapshotPairIncludesModifiedAndUntrackedFiles()` fixture failed:
  the host-wide `core.hooksPath` ran an identity-enforcement `commit-msg` hook against its
  temporary `git commit -m Initial`. A standalone reproduction succeeds with hooks disabled;
  no unrelated test or production code was changed for this task.

## Open questions

- The requested copy affordance is intentionally not included. The reporter needs to clarify
  whether it should copy the Prowl pane handle or the native agent session identifier; those
  values serve different handoff workflows.
