# 001.002 — Homebrew Cask Automation

## Context

Prowl is distributed through the personal tap `onevcat/homebrew-tap` as well as direct
DMG download. Releases are built and published locally
([000-plan.md](000-plan.md)), so nothing was keeping the tap's cask
(`Casks/prowl.rb`) in sync with new versions. Signing/notarization must stay local, but
cask metadata (`version` + `sha256`) is safe to automate in CI.

## Change

Added `.github/workflows/release-homebrew-cask.yml` (#73):

- Triggers on `release.published`, with a `workflow_dispatch` fallback that takes a tag
  input for manual re-runs.
- Downloads the just-published `Prowl.dmg` and computes its sha256.
- Updates (or creates) `Casks/prowl.rb` in `onevcat/homebrew-tap` and opens/updates a PR
  from branch `prowl-<version>`, authenticated via the `TAP_GITHUB_TOKEN` secret
  (`homebrew-release` environment).
- The generated cask installs the app only; no CLI `binary` stanza.

Two same-day fixes to keep the generated cask compliant with the tap's lint rules:

- #74 — `desc` changed to "Coding agent orchestrator"; tap style forbids platform names
  ("macOS") in `desc`, and existing casks are normalized on update.
- #75 — replaced broad `\s*` replacement regexes with line-scoped ones so blank lines
  after stanzas survive, fixing recurring `Cask/StanzaGrouping` failures in Homebrew
  `test-bot`.

## Refs

PRs #73, #74, #75 (all merged 2026-03-26).

## Current state

`.github/workflows/release-homebrew-cask.yml` is one of only two workflows in the repo
(alongside `test.yml`) and still follows this design: metadata-only sync, PR-based
updates to `onevcat/homebrew-tap`, app-only cask.
