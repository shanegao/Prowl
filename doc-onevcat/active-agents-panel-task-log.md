# Active Agents Panel Task Log

## 2026-05-09

### Scope

- Implement Phase 0, Phase 1, and Phase 2 from `doc-onevcat/plans/2026-05-09-active-agents-panel-plan.md`.
- Keep commits small enough to audit.
- Maintain high test coverage for pure detection logic and state transitions.

### Progress

- Started from branch `feat/active-agents-panel`.
- Initial worktree was clean; only existing branch commit was the implementation plan.
- Confirmed Xcode uses file-system synchronized root groups, so new Swift source/test files under `supacode/` and `supacodeTests/` are picked up automatically.

### Decisions And Notes

- Pure detection logic is implemented first with tests before wiring, because it is the most important stable contract for later UI iteration.
- Created `onevcat/ghostty` and pushed `release/v1.3.1-patched` with `ghostty_surface_pid`.
- `make sync-ghostty` currently fails before compiling Ghostty sources because Zig 0.15.2 cannot link even a trivial native macOS executable on this host without an explicit lower target/sysroot. Direct `zig build-exe -target aarch64-macos.15.0 --sysroot "$(xcrun --sdk macosx --show-sdk-path)"` succeeds, so this is tracked as a local Zig host toolchain issue.
- Added Active Agents reducer/UI wiring and terminal detection loop. `GhosttySurfaceBridge.childPID()` uses `dlsym` so the app still compiles before the patched GhosttyKit binary is rebuilt; after rebuild, the exported `ghostty_surface_pid` symbol is used automatically.

### Verification

- `xcodebuild test -project supacode.xcodeproj -scheme supacode -destination "platform=macOS" -only-testing:supacodeTests/AgentClassifierTests -only-testing:supacodeTests/ScreenHeuristicsTests -only-testing:supacodeTests/PaneAgentStateTests -only-testing:supacodeTests/ActiveAgentsFeatureTests -only-testing:supacodeTests/ProcessDetectionSmokeTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -skipMacroValidation 2>&1 | xcsift -f toon -w` passed 17 tests. One unrelated existing compile warning remains in `GithubCLIClientTests.swift:93`.
