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
