# 039 — gh CLI Hardening: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-06-08 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #418, #437 (later waves: #493, #541 — see Amendments) |
| **Sources** | PR descriptions #418/#437/#493/#541, upstream review ledger entries 2026-06-09 and 2026-07-09 ([upstream-ledger.md](../017-upstream-sync-process/upstream-ledger.md)) |
| **Related** | [028-pr-status-tracking](../028-pr-status-tracking/000-plan.md), [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md), `docs/components/github-pull-requests.md`, `docs/reference/settings-fields.md` |

## Background

Prowl's GitHub integration (PR chips, merge/close actions, workflow-run logs) shells out
to the `gh` CLI, and git discovery shells out to `git`/`wt`. To pick up the user's real
PATH and version managers, one-shot commands run through a **login shell** wrapper in
`supacode/Clients/Shell/ShellClient.swift`. That wrapper is the root of a whole fragility
class:

- A login shell sources `.zprofile` / `.zlogin` / rc files before the command runs, so a
  banner or version-manager line (nvm, mise, …) can prepend to captured stdout and corrupt
  the JSON `gh` prints. `JSONDecoder` then fails with an opaque *"The data couldn't be
  read because it isn't in the correct format"* in the GitHub settings pane — even though
  `gh` works fine in the user's terminal. onevcat runs zsh startup scripts, so this was a
  high-probability hit (upstream hit it too: upstream #378).
- Separately, `gh` supports multiple authenticated hosts and accounts, but the client
  flattened auth status to a single account picked from an **unordered dictionary** —
  non-deterministic with more than one active host — and there was no way to pin a
  repository to a specific GitHub identity. Fork/multi-account workflows (e.g. a work
  account and a personal account on github.com) could hit the wrong account.

## Goals

- Tolerate arbitrary shell-startup noise around `gh` JSON output instead of failing with
  an opaque decode error; when decoding still fails, produce an actionable message.
- Make multi-account `gh` setups first-class: show every authenticated host/account, and
  let a repository pin the identity used for its GitHub operations.
- Keep background PR refresh batches from mixing accounts.

**Non-goals**

- Replacing `gh` with direct API calls or a GitHub SDK — the CLI remains the integration
  surface.
- Changing how the interactive terminal spawns the user's shell (only one-shot command
  wrapping is in scope).

## Design / Approach

Two strands, landed a few days apart:

**1. Login-shell noise tolerance (#418, port of upstream #378).**
`GithubCLIOutput` (in `supacode/Clients/Github/GithubCLIClient.swift`) scans captured
stdout for every *balanced* top-level JSON value (`{...}` / `[...]`), skipping stray
unbalanced openers so leading noise cannot swallow a real payload, and decodes the
**last** decodable span (gh prints its JSON after any leading noise). All six gh JSON
decode sites route through it; `latestRun` and `resolveRemoteInfo` use `decodeIfPresent`
so a genuinely absent payload stays `nil`. Failure modes get distinct, readable errors:
no payload → shell-pollution message; payload present but undecodable → gh-version
message. The port was adapted to the fork's client, which keeps a fork-specific
`CrossRepoPullRequestResponse` decode path. As a drive-by, `GithubAuthStatusParsing.activeAccount`
got a deterministic host order (prefer `github.com`, then sorted), fixing the latent
multi-host nondeterminism.

**2. Per-repo GitHub CLI identities (#437, fork feature).**
- `GithubAccountOverride` (`supacode/Clients/Github/GithubCLIModels.swift`): a
  host+login pair, persisted per repository as `githubAccountOverride` in
  `supacode/Features/Settings/Models/RepositorySettings.swift`.
- Every GithubCLIClient operation takes an optional override; `withExpectedGithubAccount`
  runs a scoped `gh auth switch` to the override's account, executes, then switches the
  host back to the previously active account. A per-host `GithubAccountSwitchLock` actor
  serializes switches so concurrent operations cannot interleave identities.
- Settings → GitHub (`supacode/Features/Settings/Views/GithubSettingsView.swift`) lists
  all authenticated hosts/accounts instead of flattening to one; repo settings gain an
  identity picker (`RepositoryGithubIdentityViewModel` in
  `supacode/Features/Settings/Views/RepositorySettingsView.swift`).
- `PullRequestRefreshCoordinator` batches background PR refreshes by
  `BatchKey(host, accountOverride)` so a batch never mixes accounts.

## Alternatives & decisions

- **Decode-last-span over decode-first / regex stripping** (#418, inherited from upstream
  #378): scanning balanced spans and preferring the last one is robust against both
  leading banners and stray braces inside noise; stripping heuristics are not.
- **Scoped `gh auth switch` over per-command credential injection** (#437): `gh` has no
  per-invocation account flag, so switch-execute-restore under a per-host lock is the
  workable primitive; the cost is serialization of same-host operations.
- Later waves made two more decisions of note — rejecting an error-string allowlist in
  favor of inverting the login-shell fallback (see 002), and keeping upstream's
  `__supacode_login_argv` variable name to minimize sync friction (see 003).

## Amendments

- Updated 2026-06-22: invert login-shell fallback for git detection (#493, replaces
  allowlist approach #487) — see [002-login-shell-fallback-inversion.md](002-login-shell-fallback-inversion.md)
- Updated 2026-07-08: port of four upstream gh-detection/login-shell fixes (#541) — see
  [003-upstream-hardening-batch.md](003-upstream-hardening-batch.md)
