# 004 — Prowl Rebrand: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-03-17 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #3, #19 |
| **Sources** | PR descriptions; change-list entries for `ea9259f8`, `9970560`, `962ba62`, `5f7d84a`…`5676418` (ledger lives at `docs-ai/017-upstream-sync-process/upstream-ledger.md`); commit messages |
| **Related** | [001-fork-bootstrap-and-release-pipeline](../001-fork-bootstrap-and-release-pipeline/000-plan.md), [017-upstream-sync-process](../017-upstream-sync-process/000-plan.md) |

## Background

The fork started as a private customization layer over supabitapp/supacode, but it was set
to become an independently distributed app: its own bundle identity, its own settings data,
its own release channel (see [001](../001-fork-bootstrap-and-release-pipeline/000-plan.md)).
Shipping under the upstream name "Supacode" with bundle ID `app.supabit.supacode` had
concrete problems:

- A user installing both apps would have them fight over the same `~/.supacode` config
  directory, the same bundle-ID-scoped state, and the same Sparkle feed — the fork would
  receive upstream updates and be overwritten.
- Fork-authored PRs opened by coding agents defaulted to the upstream repository (the
  GitHub fork relationship makes `gh pr create` target `supabitapp/supacode` by default),
  risking accidental disclosure of fork-private work.

Groundwork already existed: commit `ea9259f8` (2026-02-28, pre-rebrand) had moved per-repo
settings files out of repository roots (`<repo>/supacode.json`) into
`~/.supacode/repo/<repo-name>/`, with legacy migration — so by rebrand time all fork
settings lived under one relocatable directory.

## Goals

- Rename every user-visible identity from "Supacode" to "Prowl": app/window name, menus,
  alerts, permission usage strings, settings UI, app icon.
- New bundle ID `com.onevcat.prowl`; new UTType `com.onevcat.prowl.ghosttySurfaceId`.
- Move the config directory `~/.supacode` → `~/.prowl` with transparent migration on first
  launch; rename settings files `supacode.json` → `prowl.json` with legacy fallback.
- Detach from upstream's update channel: remove the upstream Sparkle feed URL and signing
  key (the fork's own feed comes later via the release pipeline, entry 001).
- Enforce, mechanically, that PRs never target upstream.

### Non-goals

- **Renaming code-level identifiers.** The Xcode module, scheme, target, source directory
  (`supacode/`), and type prefixes (`SupacodePaths`, `SupaLogger`, …) deliberately stay
  `supacode`-named. This is a recorded decision, not an oversight: every rename in code is
  a permanent merge-conflict surface against upstream, and the fork syncs upstream
  continuously (entry [017](../017-upstream-sync-process/000-plan.md)).

## Design / Approach

1. **String/identity sweep** (`supacode/Info.plist`, `supacode/App/supacodeApp.swift`,
   feature views, `supacode.xcodeproj/project.pbxproj`): display strings → "Prowl",
   `PRODUCT_BUNDLE_IDENTIFIER` → `com.onevcat.prowl`, `PRODUCT_NAME` → `Prowl`, with an
   explicit `PRODUCT_MODULE_NAME = supacode` so `import`/`@testable import supacode` and
   the test host keep working after the product rename.
2. **Config directory migration** in `supacode/Support/SupacodePaths.swift`: the
   `baseDirectory` getter checks for `~/.prowl`; if absent but `~/.supacode` exists, it
   migrates the whole directory on first access. As originally shipped in #3 this used
   `moveItem` (see Amendments — changed to copy).
3. **Settings file rename with fallback chain**: per-repo settings load `prowl.json`
   first, falling back to legacy `supacode.json` (and rewriting to the new name on
   successful legacy load), so existing users migrate transparently.
4. **Update-channel detach**: delete `SUFeedURL` (`https://supacode.sh/...`) and
   `SUPublicEDKey` from `Info.plist` so the fork can never install an upstream build over
   itself.
5. **PR-target guard**: a Claude Code `PreToolUse` hook
   (`.claude/hooks/block-upstream-pr.sh`, wired in `.claude/settings.json`) inspects every
   Bash tool call; any `gh pr create` that does not explicitly pass `--repo`/`-R` pointing
   at the fork is blocked (exit 2) before execution. A matching prose rule was added to
   `AGENTS.md`. Defense in depth: the rule tells agents what to do, the hook makes the
   wrong default impossible.

## Alternatives & decisions

- **Full rename vs. user-facing-only rename**: full rename (module, types, directories)
  was rejected for merge compatibility; only what users see was renamed. The change-list
  ledger records this as "Keep module name as `supacode` for code compatibility". This
  decision still pays off: upstream diffs to `supacode/**` apply without path rewrites.
- **Move vs. copy for `~/.supacode` migration**: #3 shipped `moveItem`. Fork issue #16
  showed this deletes the data of a co-installed upstream Supacode; #19 changed it to
  `copyItem` (see [002-migration-copy-not-move.md](002-migration-copy-not-move.md)).
- **Hook scope**: the guard only intercepts `gh pr create`, and only requires an explicit
  fork `--repo` flag — it does not try to parse every possible gh invocation. Simplicity
  over completeness; `AGENTS.md` covers intent.
- **Sparkle**: disabled rather than re-pointed at rebrand time; the fork feed
  (`https://github.com/onevcat/Prowl/releases/latest/download/appcast.xml`) was wired
  later by the release-pipeline work (entry 001).

## Amendments

- Updated 2026-03-20: migration changed from move to copy so a co-installed upstream
  Supacode keeps `~/.supacode` — see
  [002-migration-copy-not-move.md](002-migration-copy-not-move.md)
