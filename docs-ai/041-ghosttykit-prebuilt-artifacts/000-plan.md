# 041 — GhosttyKit Prebuilt Artifacts: Plan

| | |
| --- | --- |
| **Status** | Implemented (retrospective) |
| **Anchor date** | 2026-06-14 |
| **Documented** | 2026-07-12 (backfilled) |
| **Primary PRs** | #450 |
| **Sources** | `doc-onevcat/plans/2026-06-14-ghosttykit-prebuilt-artifacts-plan.md` (absorbed here; original removed in the docs-ai migration), PR #450 description |
| **Related** | [016-dev-build-and-ci-workflow](../016-dev-build-and-ci-workflow/000-plan.md), [007-ghostty-embedding-integration](../007-ghostty-embedding-integration/000-plan.md), [ghostty-fork-sync runbook](../007-ghostty-embedding-integration/ghostty-fork-sync.md) |

## Background

Prowl links `Frameworks/GhosttyKit.xcframework` directly from the Xcode project and
bundles `Resources/ghostty` + `Resources/terminfo`, all generated from the
`ThirdParty/ghostty` submodule (pinned to the `onevcat/ghostty` fork) via
`zig build -Doptimize=ReleaseFast -Demit-xcframework=true -Dsentry=false`. That Zig build
is the expensive step: cold worktrees lack the generated framework/resources, so a fresh
`make build-app` triggered a full Ghostty source build. It also requires a full Zig
toolchain via mise, and — a real constraint on this machine — the Ghostty Zig source only
links with the Xcode 26.3 toolchain (`DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/...`);
newer Xcode versions fail at link time. Entry 016 had already added SHA-based skip logic
(`.ghostty_hash` / `.ghostty_build_stamp`), but a cache miss still meant compiling Ghostty.

The plan: make prebuilt, checksummed GhosttyKit artifacts the default acquisition path,
keeping the local source build as an explicit maintenance operation and emergency
fallback.

## Goals

- Publish per-commit artifact sets as `onevcat/ghostty` GitHub Releases, tagged
  `xcframework-<ghostty_commit_sha>-prowl-v1`, with two assets:
  `GhosttyKit.xcframework.tar.gz` and `GhosttyKit-resources.tar.gz` (containing exactly
  `ghostty/` and `terminfo/`).
- Key artifacts by the Ghostty **gitlink** recorded in Prowl
  (`git rev-parse HEAD:ThirdParty/ghostty`), not the submodule working tree — so cold
  worktrees can download artifacts before the heavy submodule is even initialized.
- Store a reviewed SHA256 manifest in-repo (`scripts/ghosttykit-checksums.txt`, one line
  per pinned commit: `<ghostty_sha> <xcframework_sha256> <resources_sha256>`) as the
  source of truth for artifact integrity.
- `make ensure-ghostty` prefers download+verify+install; falls back to the local Zig build
  when no artifact is pinned or the download is unavailable.
- Checksum mismatch or unsafe archive shape is a **hard failure**, never a silent
  fallback — that signals a broken or tampered artifact.
- CI (`.github/actions/setup-macos`) keys its cache on the pinned gitlink and runs
  `make ensure-ghostty` on cache miss, making misses much faster.

### Non-goals

- No SwiftPM binary target migration — the app target links the xcframework directly and
  bundles resources separately; a Makefile downloader matches that shape with less churn.
- No dependency on upstream `ghostty-org/ghostty` release assets.
- No "latest release" behavior — only the exact pinned commit's artifact is ever used.
- No committing of generated `GhosttyKit.xcframework` or runtime resources.

## Design / Approach

Four scripts plus Makefile/CI wiring:

- `scripts/ensure-ghosttykit-artifacts.sh` — the downloader. Reads the pinned gitlink;
  fast-exits when artifacts exist and `.ghostty_hash` matches; otherwise looks up the SHA
  in the checksum manifest, downloads both release assets, verifies SHA256, validates
  archive shape, extracts into `Frameworks/` and `Resources/`, refreshes `libghostty.a`'s
  archive index with `xcrun ranlib`, and writes the `.ghostty_hash` /
  `.ghostty_build_stamp` markers. Exit code contract: `0` = installed/up-to-date, `2` =
  fall back to local build, anything else = hard failure.
- `scripts/validate-ghosttykit-artifacts.py` — tar allowlist validator: rejects absolute
  paths, `..` traversal, unsafe link targets, unexpected roots, and non-file/dir/link
  members; requires the expected roots to be present.
- `scripts/package-ghosttykit-artifacts.sh` — packages the current `Frameworks/` +
  `Resources/` outputs into the two tarballs, validates them, and prints the release tag
  plus the ready-to-paste manifest line.
- `scripts/ghosttykit-checksums.txt` — the reviewed manifest.
- `Makefile ensure-ghostty` — runs the downloader; on exit 2 rebuilds via
  `make -B build-ghostty-xcframework` and clears Xcode DerivedData when the pinned SHA
  changed (preserving 016's stale-module-cache behavior). `make sync-ghostty` stays the
  explicit "force local rebuild from source" command.

**Publishing flow** (fork maintenance, per new Ghostty commit): build locally with
`DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer make sync-ghostty`, run
the packager, create the matching `onevcat/ghostty` release with both assets, append the
emitted line to the manifest, then verify a clean acquisition
(`rm -rf` artifacts + markers → `make ensure-ghostty` → `make build-app`). The Xcode 26.3
pin applies only to building the Ghostty Zig source; Prowl itself builds with the current
Xcode. The operational steps live in the
[ghostty-fork-sync runbook](../007-ghostty-embedding-integration/ghostty-fork-sync.md).

## Alternatives & decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Distribution shape | Makefile downloader | SwiftPM binary target would churn the project for no gain given direct xcframework linking + separate resource bundling |
| Artifact key | Pinned gitlink, not submodule working tree | Works in cold worktrees before submodule init |
| Integrity | In-repo reviewed SHA256 manifest + tar shape validator | Pinned tags alone don't protect against replaced assets; unsafe extraction is a real tar risk |
| Failure policy | Missing artifact → fallback; checksum/shape failure → hard error | Absence is expected for new commits; mismatch means something is wrong |
| Fallback | Keep local Zig source build | Fork maintenance and new-commit development must not be blocked |

## Amendments

(none)
