# 016 — Amendment: CI Throughput & Caching Wave (2026-05-08 → 2026-05-24)

## Context

Through May 2026 the CI test workflow was slow and, in one case, dishonest:

- Rapid pushes to a PR queued redundant full runs.
- Local builds intermittently failed with "package manifest cannot be accessed": the SPM
  cache lived under `/tmp/supacode-spm-cache`, and macOS's daily `tmp_cleaner`
  (`-atime/-mtime/-ctime +3` rules) deleted per-checkout `Package.swift` files whose
  access time never refreshed after resolve — even on machines used daily.
- CLI smoke + integration tests ran serially after app tests, adding a ~40–50 s tail.
- The Xcode compilation cache (`CompilationCache.noindex`) was cached under a static
  `xcode-compilation-cache-v0` key; `actions/cache@v4` never re-saves on an exact key hit,
  so CI was frozen on the very first ~152 MB snapshot and cold-compiled almost everything.
- After parallelization, a bash pitfall made the parallel step report success even when a
  test target failed to compile (a broken PR merged green).

## Change

- **PR #266 (2026-05-08)** — add a `concurrency` group
  (`${{ github.workflow }}-${{ github.ref }}`, `cancel-in-progress: true`) to
  `test.yml` so superseded PR/main runs are canceled. Upstream's
  release-tip/warm-cache/inspect-dependencies workflow changes were deliberately skipped
  (absent or divergent in the fork).
- **PR #269 (2026-05-09)** — move `SPM_CACHE_DIR` to
  `~/Library/Caches/supacode-spm-cache/SourcePackages` (standard cache location,
  outside `tmp_cleaner`'s reach) and align the `actions/cache` path in
  `.github/actions/setup-macos/action.yml`.
- **PR #307 (2026-05-19)** — keep the explicit `make build-app` CI step; split a
  `test-app` target (app/unit tests only) out of `make test`; run `test-app`,
  `test-cli-smoke`, `test-cli-integration` concurrently after the build. `make test`
  stays self-contained locally by embedding the debug CLI before `test-app`.
  `ensure-ghostty` made to fail immediately when the GhosttyKit rebuild fails.
  (An earlier attempt that removed the standalone build step saved nothing — `make test`
  absorbed the full build cost — so only the independent tails were parallelized.)
- **PR #308 (2026-05-19)** — two levers for Debug build wall time:
  1. Compilation-cache key rotated to
     `xcode-compilation-cache-v1-${{ hashFiles('Package.resolved', 'supacode.xcodeproj/project.pbxproj') }}`
     so the cache refreshes when its content profile shifts, while routine code-only PRs
     hit the primary key and skip the ~30 s re-upload; `restore-keys` keeps older
     snapshots reachable.
  2. Type-checker hotspots found with `-warn-long-function-bodies` /
     `-warn-long-expression-type-checking`: replace
     `Dictionary(uniqueKeysWithValues: map)` with typed loops, promote an inline tuple to
     the nominal `ArchivedWorktreeGroup` struct, extract oversized SwiftUI bodies
     (`ArchivedWorktreesDetailView.body` 4312 ms → 346 ms). Plus
     `COMPILATION_CACHE_ENABLE_CACHING = YES` at the project Debug level and
     `EAGER_LINKING = YES` for Debug.
- **PR #333 (2026-05-24)** — the parallel step's `run_task` read `$?` after an
  `if cmd; then …; fi` block, which yields the `if` statement's own exit code (`0` when
  the condition fails with no `else`), so every task returned success. Fixed by capturing
  directly with `"$@" >"$log" 2>&1 || status=$?`. Only the parallel step was affected;
  `make build-app` already ran under `bash -o pipefail`.

## Refs

- PRs #266, #269, #307, #308, #333.
- `.github/workflows/test.yml`, `.github/actions/setup-macos/action.yml`, `Makefile`
  (`SPM_CACHE_DIR`, `test-app`), `supacode.xcodeproj/project.pbxproj`,
  `supacode/Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift`
  (`ArchivedWorktreeGroup`).

## Current state

All five changes are live as of 2026-07-12; the exit-status fix is preserved with an
explanatory inline comment in `test.yml`. See [001-action.md](001-action.md)
"Outcome & current state" for the file-level inventory.
