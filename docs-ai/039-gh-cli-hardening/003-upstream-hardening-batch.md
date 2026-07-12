# 039 — Amendment: Upstream gh-Detection / Login-Shell Hardening Batch

## Context

The 2026-07-09 upstream review batch (see
[upstream-ledger.md](../017-upstream-sync-process/upstream-ledger.md) and
[017-upstream-sync-process](../017-upstream-sync-process/000-plan.md)) found four
upstream fixes to the same gh/login-shell subsystem that #418 had partially ported; the
fork still carried the pre-fix form of all four defects.

## Change

PR #541 (merged 2026-07-08) ports all four into `supacode/Clients/Shell/ShellClient.swift`
and `supacode/Clients/Github/GithubCLIExecutableResolver.swift`:

| Upstream | Fix |
| --- | --- |
| upstream #410 | Non-POSIX login shells (nushell, pwsh, csh — and sh/dash/ksh, which cannot parse the zsh rc snippet) fall back to `/bin/zsh` for one-shot commands instead of failing every git/wt/gh invocation as a bogus "not a git repository". The interactive terminal still uses the user's real shell. |
| upstream #460 | Capture `$@` into `__supacode_login_argv` before sourcing the rc file — an rc running `set --` could wipe the command before `exec`, making gh undetectable (upstream issue #441). |
| upstream #482 | Clear live positionals (`set --`) before sourcing — a dual-mode rc script dispatching on `$1` (e.g. `fzf-git.sh`) could see the probe's arguments, hit its own `exit`, and kill the probe shell. |
| upstream #535 | When both `which gh` probes fail (broken PATH/rc), fall back to `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, `~/.local/bin/gh`, with a breadcrumb log. |

Structural adaptation: upstream's ShellClient lives in `SupacodeSettingsShared`; the
fork's is `supacode/Clients/Shell/ShellClient.swift`, and the fork had already extracted
`GithubCLIExecutableResolver` into its own file. Decision: keep upstream's
`__supacode_login_argv` variable name to minimize future sync friction.

## Refs

- PR #541 (ports upstream #410 / #460 / #482 / #535)
- Tests: `supacodeTests/ShellClientLoginShellTests.swift` (drivable-shell selection, fish
  snippet isolation, capture → `set --` → source ordering),
  `supacodeTests/GithubCLIClientTests.swift` (fallback path resolution and ordering)

## Current state

All four fixes present as described; the login-shell wrapper drives only zsh/bash/fish
(`drivable` set in `ShellClient.swift`) and logs `Using fallback: /bin/zsh` when a
non-drivable shell is replaced.
