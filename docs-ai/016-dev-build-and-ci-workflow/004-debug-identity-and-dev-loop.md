# 016 — Amendment: Debug App Identity & Dev-Loop Acceleration (2026-06-05 → 2026-06-20)

## Context

By June 2026 the remaining friction was in the local edit-build-run loop:

- `make run-app` refused to launch when another Prowl instance was running, blocking the
  common "run a Debug build next to the installed Release app" workflow.
- Debug builds shared the Release identity, so every reinstall re-triggered macOS TCC
  permission prompts (fork issue #464); an earlier fix (#465) patched the installed app's
  Info.plist with PlistBuddy and re-signed it, which stripped entitlements/hardened-runtime
  flags and only helped `install-dev-build`, not `run-app`.
- `make build-app` rewrote its own inputs on every run (`ProwlVersion.swift` regenerated,
  CLI binary recopied), invalidating xcodebuild's incremental state for no reason.
- `xcodebuild -showBuildSettings -json` took 8–63 s per `run-app`/`install-dev-build`
  invocation, and Debug builds used `wholemodule` compilation.

## Change

- **PR #391 (2026-06-05)** — remove the running-instance guard from `run-app`; the Debug
  build path resolution and direct executable launch stay unchanged.
- **PR #461 (2026-06-17)** — make `build-app` inputs content-aware: `sync-cli-version`
  writes `supacode/CLIService/Shared/ProwlVersion.swift` only when the version actually
  differs (`cmp -s` against a temp render), and the debug CLI copy to
  `Resources/prowl-cli/prowl` happens only when the built binary changed. No build stamp
  or xcodebuild skip was introduced — `build-app` remains a direct verification path.
- **PR #479 (2026-06-19, supersedes #465)** — move the Debug identity into the Xcode
  project's Debug configuration: `PRODUCT_NAME = "Prowl Debug"`,
  `PRODUCT_BUNDLE_IDENTIFIER = com.onevcat.prowl.debug`,
  `INFOPLIST_KEY_CFBundleDisplayName`, `ENABLE_DEBUG_DYLIB = NO`, and a matching Debug
  `TEST_HOST`. The build output is natively correct, so `install-dev-build` returns to a
  plain `ditto` copy with no signing-identity discovery or re-signing; both `run-app` and
  `install-dev-build` benefit. Release configuration untouched.
- **PR #482 (2026-06-20)** — cache `xcodebuild -showBuildSettings -json` output in
  `.build_settings_cache.json`, invalidated by comparing mtime against
  `supacode.xcodeproj/project.pbxproj` (measured 62.9 s → 0.7 s); switch Debug builds to
  `SWIFT_COMPILATION_MODE=incremental` in `build-app`/`test-app` (no-change rebuild
  127 s → 64 s on the benchmark machine). Release/archive keep `wholemodule`.

## Refs

- PRs #391, #461, #479, #482; fork issues #464 (TCC prompts), superseded PR #465.
- `Makefile` (`run-app`, `install-dev-build`, `sync-cli-version`, `embed-cli-debug`,
  `BUILD_SETTINGS_CACHE`), `supacode.xcodeproj/project.pbxproj` (Debug configuration),
  `.gitignore` (`.build_settings_cache.json`).

## Current state

All four changes are live as of 2026-07-12: Debug builds produce `Prowl Debug.app` with
bundle id `com.onevcat.prowl.debug`, `run-app` launches the Debug executable directly
regardless of other running instances, and the build-settings cache is used by both
`run-app` and `install-dev-build`. See [001-action.md](001-action.md) for the verified
inventory and the cache-staleness caveat under Open questions.
