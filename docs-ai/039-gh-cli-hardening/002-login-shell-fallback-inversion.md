# 039 — Amendment: Invert Login-Shell Fallback for Git Detection

## Context

Git commands run directly first and retry under a login shell only when the direct run
fails in a way a login shell could fix. The original logic kept an **allowlist** of
retryable errors, so failure modes outside the list — notably Xcode CLI-tool shim
failures (unaccepted license, broken active developer path) — never triggered the retry.
Result: real git repositories were shown as plain folders (fork issue #486).

## Change

PR #493 (merged 2026-06-22) inverts `shouldFallbackToLoginShell`
(`supacode/Clients/Git/GitClientShellHelpers.swift`): retry under a login shell for
**every** shell error except the one case where retrying is provably pointless — git ran
and confirmed "not a git repository". The worst case of an unnecessary fallback is one
extra failing shell invocation.

Decision: the competing PR #487 pattern-matched specific Xcode error strings
(`"xcode license"`, `"invalid active developer path"`, …) and was closed unmerged —
Apple can reword, add, or localize those messages, while the inverted rule covers unknown
future failure modes by default.

## Refs

- PR #493 (closes fork issue #486; supersedes #487)
- Tests: `supacodeTests/GitClientShellFallbackTests.swift` (fallback on exit 127 /
  license errors / unknown errors; no fallback on genuine non-repo or non-shell errors)

## Current state

Logic unchanged since merge; the fallback call site lives in
`supacode/Clients/Git/GitClient.swift`.
