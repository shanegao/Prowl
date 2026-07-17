# 039 — gh CLI Hardening: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-08 | Tolerate login-shell noise in gh JSON output: `GithubCLIOutput` balanced-span scanner, all six decode sites routed through it, distinct no-payload vs undecodable errors, deterministic `activeAccount` host order. Port of upstream #378. | PR #418 |
| 2026-06-13 | Per-repo GitHub CLI identities: `GithubAccountOverride` in repo settings, scoped `gh auth switch` with per-host lock, multi-account GitHub settings pane, PR refresh batches keyed by host+identity. Docs updated. | PR #437 |
| 2026-06-22 | Invert login-shell fallback for git detection: retry under login shell for **all** shell errors except a confirmed "not a git repository". Fixes repos shown as plain folders when Xcode CLI tools are unusable (fork issue #486). | PR #493 |
| 2026-07-08 | Port four upstream gh-detection/login-shell fixes: non-POSIX shell fallback to `/bin/zsh`, argv capture before rc sourcing, positional clearing before rc sourcing, fixed-path gh fallback. Ports of upstream #410/#460/#482/#535. | PR #541 |

## Outcome & current state (as of 2026-07-12)

- `supacode/Clients/Github/GithubCLIClient.swift` — `GithubCLIOutput` (balanced-span
  scanning, decode-last, `noPayloadMessage` / `undecodableMessage`),
  `GithubAuthStatusParsing.activeAccount` (github.com-first deterministic order),
  `GithubAccountSwitchLock` actor, and `withExpectedGithubAccount` wrapping every
  account-sensitive operation (batch PR queries, merge/close/ready, run logs, reruns).
- `supacode/Clients/Github/GithubCLIModels.swift` — `GithubAccountOverride` (normalized
  host+login), `GithubAuthStatusResponse` / `GithubAuthAccountStatus` for the
  multi-account settings pane.
- `supacode/Features/Settings/Models/RepositorySettings.swift` — persisted
  `githubAccountOverride`, normalized on decode.
- `supacode/Features/Settings/Views/GithubSettingsView.swift` and
  `RepositorySettingsView.swift` (`RepositoryGithubIdentityViewModel`) — the settings UI.
- `supacode/Features/Repositories/BusinessLogic/PullRequestRefreshCoordinator.swift` —
  batches keyed by `BatchKey(host, accountOverride)`; `cancelHost` clears per-host state.
- `supacode/Clients/Git/GitClientShellHelpers.swift` — inverted
  `shouldFallbackToLoginShell` (fallback unless output contains "not a git repository");
  call site in `supacode/Clients/Git/GitClient.swift`.
- `supacode/Clients/Shell/ShellClient.swift` — login-shell wrapper drives only
  zsh/bash/fish; anything else falls back to `/bin/zsh`. The POSIX one-shot command
  captures `$@` into `__supacode_login_argv`, clears positionals with `set --`, sources
  the rc file, then `exec`s the captured argv.
- `supacode/Clients/Github/GithubCLIExecutableResolver.swift` — when shell PATH probes
  miss `gh`, falls back to `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`,
  `~/.local/bin/gh`, with an info log for traceability.
- Behavior docs: `docs/components/github-pull-requests.md` (identity override + switch
  semantics), `docs/reference/settings-fields.md` (`githubAccountOverride`).
- Tests: `supacodeTests/GithubCLIOutputTests.swift`, `GithubCLIClientTests.swift`,
  `GitClientShellFallbackTests.swift`, `ShellClientLoginShellTests.swift`,
  `PullRequestRefreshCoordinatorTests.swift`.

## Deviations from plan

None known — the two later waves extended the same theme and are recorded as amendments
rather than deviations.

## Open questions

- `withExpectedGithubAccount` mutates global `gh` state (auth switch + restore) under a
  per-host in-process lock; an external `gh auth switch` run by the user (or a crash
  between switch and restore) during the window would leave the host on the override
  account. Accepted trade-off of the CLI-based approach, but undocumented.
