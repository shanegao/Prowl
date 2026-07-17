# 004 — Amendment: Copy, Don't Move, `~/.supacode`

## Context

PR #3's first-launch migration moved `~/.supacode` to `~/.prowl` with
`FileManager.moveItem`. Fork issue #16 (2026-03-20) reported the consequence for users
running both apps: launching Prowl while upstream Supacode was installed moved the entire
directory — including `repos/<repo>/` worktrees — leaving Supacode with no data and its
worktrees untracked.

## Change

PR #19 (merged 2026-03-20) changed `moveItem` to `copyItem` in
`SupacodePaths.baseDirectory`. First launch now duplicates `~/.supacode` into `~/.prowl`
and leaves the original untouched, so a co-installed upstream Supacode keeps working.
The migration still only fires when `~/.prowl` does not exist yet, so it runs at most
once; after that the two apps' state diverges independently.

Trade-off accepted: the two directories are a fork, not a sync — changes made in Supacode
after Prowl's first launch are not seen by Prowl, and disk usage doubles for the copied
data (including any worktrees stored under the default `~/.prowl/repos/` base). This was
judged correct: silently destroying another app's data is worse than a one-time copy.

## Refs

- PR #19 "Fix migration: copy instead of move to preserve ~/.supacode"
- Fork issue #16 "Prowl moves everything in .supacode to .prowl"

## Current state

`supacode/Support/SupacodePaths.swift` — `baseDirectory` still uses
`try? FileManager.default.copyItem(at: legacyDir, to: prowlDir)` guarded by
"`~/.prowl` missing and `~/.supacode` present". Unchanged since #19.
