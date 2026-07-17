# 001.003 — Serve Sparkle Appcast from GitHub Releases

## Context

The 2026-03-18 release infrastructure (`1b0eb02b`) published the Sparkle feed at
`https://prowl.onev.cat/appcast.xml`, which meant every release also had to push
`appcast.xml` into the Prowl-Site repository and wait for a site deploy — an extra step
and an extra failure point on the critical update path.

## Change

- `SUFeedURL` in `supacode/Info.plist` now points at
  `https://github.com/onevcat/Prowl/releases/latest/download/appcast.xml`, i.e. the
  appcast is just another asset on the latest GitHub Release (GitHub 302-redirects
  `releases/latest/download/...` to the newest release's asset).
- `release.sh` seeds appcast version history by downloading the previous `appcast.xml`
  from the latest GitHub Release instead of from Prowl-Site, then regenerates it with
  `bins/generate_appcast`.
- The Prowl-Site appcast push step was removed from the release script entirely. The
  optional `NETLIFY_BUILD_HOOK` site-rebuild trigger remains, but only for the website
  itself, not for update delivery.

## Refs

PR #154 (merged 2026-04-05).

## Current state

Matches the change: `supacode/Info.plist` carries the GitHub Releases `SUFeedURL`, and
`scripts/release.sh` fetches the prior appcast from
`releases/latest/download/appcast.xml` before generating and uploading the new one
alongside `Prowl.dmg` and `Prowl.app.zip`.
