# 046 — CLI Short Handles: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-13 |
| **Primary PRs** | — |
| **Related** | [013-prowl-cli](../013-prowl-cli/000-plan.md), `docs/components/cli.md`, `docs-ai/013-prowl-cli/contracts/input.md` |

## Background

Prowl's CLI currently exposes a UUID for every tab and pane and only resolves explicit
`--tab` and `--pane` selectors after parsing a UUID. UUIDs are valid canonical runtime
identifiers, but they are expensive and error-prone handles for a human or a coding agent
to copy between CLI calls. Issue #474 requests compact session-scoped selectors.

## Goals

- Assign a process-lifetime, globally monotonic, non-reused short handle to every live
  tab and pane observed by the CLI snapshot builders.
- Display tab and pane handles in text `prowl list` and pane handles in text `prowl agents`.
- Accept a canonical UUID, a prefixed handle (`tN` / `pN`), or the numeric suffix in
  explicit `--tab` / `--pane` selectors.
- Preserve UUIDs as the `id` values in every `--json` payload and retain the v1 JSON schema.
- Add focused unit tests for handle allocation, snapshot propagation, resolver behavior,
  text payloads, and JSON compatibility.

### Non-goals

- Do not add handles to `--target`; a bare number can be a worktree name, so explicit
  selector flags remain the unambiguous short-handle interface.
- Do not change persisted tab/surface UUIDs or terminal layout persistence.
- Do not add a UI copy control until the issue reporter clarifies whether it should copy
  a Prowl pane handle or a native agent session identifier.

## Design / Approach

`WorktreeTerminalManager` will own a small allocator keyed by canonical UUID and terminal
kind. It will allocate from one increasing sequence, release a mapping when its target
closes, and never decrement the sequence, so new UUIDs never reuse an exposed handle while
the app is running. Snapshot builders will ask the manager for handles while building
`ListRuntimeSnapshot` and `TargetResolutionSnapshot`; this keeps allocation centralized
without changing terminal layout models.

The snapshot tab and pane records will carry their handle alongside their canonical UUID.
`TargetResolver` will first retain UUID behavior and then match the type-appropriate
handle for explicit tab or pane selectors. The auto selector will remain UUID/worktree
only to avoid a numeric-worktree ambiguity.

`ListCommandHandler` and `AgentsCommandHandler` will include handles only when the envelope
requests text output. The shared payload types will make those fields optional, so
`--json` encodes exactly the existing UUID-only shape. `ProwlCLI/Output/OutputRenderer.swift`
will render the handles instead of UUIDs in its human-facing list and agents output.

## Alternatives & decisions

| Option | Decision |
| --- | --- |
| Replace JSON `id` with a short value | Rejected: v1 contracts define UUID `id` fields and consumers may depend on them. |
| Add a permanent JSON `handle` field | Deferred: useful, but it expands a strict v1 schema and needs an explicit contract-versioning decision. |
| Use per-worktree or reusable counters | Rejected: a CLI handle needs to be globally unambiguous for its terminal kind and must not silently retarget after a close. |
| Use only bare integers | Rejected as canonical rendering: `pN` / `tN` communicate selector kind; numeric suffixes remain accepted by explicit flags for ergonomic compatibility. |

## Verification

- Run targeted Swift Testing suites for the allocator/snapshot/resolver and CLI handlers.
- Run the required CLI build, smoke, and integration commands, `make check`, and `make build-app`.
- Launch an isolated debug Prowl instance and prove `list` shows a short pane handle while
  `list --json` still returns UUIDs, then use that handle with `read --pane` and close the
  temporary tab by its short tab handle.

## Amendments
