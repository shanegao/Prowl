# 047 — Post-Tag Commit Audit: Plan

| | |
| --- | --- |
| **Status** | Implemented |
| **Anchor date** | 2026-07-13 |
| **Primary PRs** | — |
| **Related** | `docs-ai/034-worktree-watcher-correctness/000-plan.md`, [045-native-agent-session-detection](../045-native-agent-session-detection/000-plan.md), [046-cli-short-handles](../046-cli-short-handles/000-plan.md) |

## Background

`v2026.7.10` is the most recent reachable release tag. The 33 commits between that tag and
`HEAD` span plain-repository watcher upgrades, native agent session detection, documentation
reorganization, settings/build cleanup, Active Agents presentation, worktree deletion,
test stabilization, and CLI short handles. A focused post-review should validate the
integrated behavior as well as each logical change set.

## Goals

- Inventory each commit in `v2026.7.10..HEAD` and group merges and follow-up commits by
  delivered behavior.
- Review changed production code and regression tests for correctness, lifecycle safety,
  contract compatibility, and missing edge-case coverage.
- Run proportionate verification and report only observations backed by the checked code or
  an executed command.
- Record severity-ranked, actionable findings without changing production behavior.

### Non-goals

- Do not modify product code, tests, release metadata, or user documentation as part of the
  audit.
- Do not reopen or duplicate historical design records; link to their established entries
  where they provide the relevant intent.

## Design / Approach

Use `v2026.7.10` as the baseline and inspect every non-merge commit, with merge commits
used to retain PR grouping. Diff the principal implementation files and tests together, then
cross-check public CLI contracts and lifecycle transitions against their existing docs. Run
repository checks and focused tests when the audit identifies a testable concern. Capture the
final inventory, verification, and findings in `001-action.md`.

## Alternatives & decisions

| Option | Decision |
| --- | --- |
| Review only commits after the previous merge commit | Rejected: it would omit the post-tag plain-repository and session-detection work. |
| Treat merge commits as sufficient evidence | Rejected: fix-up commits contain important behavioral corrections and must be inspected directly. |
| Make opportunistic fixes during review | Rejected: the request is a post-review; findings should remain separately reviewable. |

## Verification

- Confirm the release baseline and commit inventory with Git.
- Run diff whitespace validation, targeted tests for affected behavior where useful, and the
  repository build gate.
- Verify that all file references in the final action log exist.

## Amendments
