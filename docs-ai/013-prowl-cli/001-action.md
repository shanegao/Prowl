# 013 — Prowl CLI: Action Log

## Timeline

### Phase 1 — Contracts (2026-03-30 → 2026-03-31)

| Date | Change | Ref |
| --- | --- | --- |
| 2026-03-30 | Output contracts for `open`, `list`, `focus`, `send`, `key`, `read` | #89, #90, #91, #92, #93, #94 |
| 2026-03-30 | v1 JSON Schemas for all command outputs (`schema.md`) | #97 |
| 2026-03-31 | Input contract (`input.md`) + phase-1 architecture plan (`architecture.md`) | #104 |

### Phase 2 — Runtime v1 (2026-04-02 → 2026-04-06)

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-02 | CLI v1 foundation: `prowl` executable target, shared envelope/response/input types, app-side router + `CLISocketServer` scaffold (stub handlers), Unix-socket length-prefixed JSON transport | #126 |
| 2026-04-02 | SPM `prowl` target wiring with smoke and integration tests | #127 |
| 2026-04-03 | `list` runtime via command service | #129 |
| 2026-04-03 | `send` runtime (argv vs stdin exclusivity honored) | #135 |
| 2026-04-03 | `focus` runtime (contract-driven) | #136 |
| 2026-04-04 | `read` runtime (viewport/screen capture, `--last N`) | #137 |
| 2026-04-04 | `key` runtime | #141 |
| 2026-04-04 | `open` runtime handler | #133 |
| 2026-04-04 | Auto-launch app when not running: `AppLauncher` polls the socket, `app_launched: true` in payload | #139 |
| 2026-04-04 | `send --capture`: pre/post screen-buffer snapshot + diff, echo/prompt stripping; invalid with `--no-wait`/`--no-enter` | #148 |
| 2026-04-05 | Auto-target resolution: `TargetSelector.auto` (pane UUID → tab UUID → worktree id/name/path), positional `<target>`, `-t/--target` flag; `input.md`/`schema.md` updated | #150 |
| 2026-04-06 | Key token expansion: general descriptor pipeline (modifier combos, printable keys, forward delete, F-keys) mapped to `NSEvent` specs | #157 |
| 2026-04-06 | Key token follow-up with ANSI control fixes | #164 |

### Phase 3 — Install & distribution (2026-04-05)

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-05 | In-app install: `CLIInstallClient`, symlink `/usr/local/bin/prowl` → bundled binary, three entry points (Settings › Advanced, app menu, Command Palette), Makefile embed targets | #146 |
| 2026-04-05 | CLI version unified with app `MARKETING_VERSION` via generated `ProwlVersion.swift` (`sync-cli-version`) | #151 |
| 2026-04-05 | Dev builds embed the debug CLI (faster iteration) | #152 |
| 2026-04-05 | Release CLI built as universal binary (arm64 + x86_64) | #153 |
| 2026-04-05 | Install feedback shown via toolbar toast for all entry points | #155 |

### Phase 4 — Hardening (2026-04-25 → 2026-06-26)

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-25 | Socket moved from `$TMPDIR` to `~/Library/Application Support/com.onevcat.prowl/cli.sock` — macOS periodically sweeps `/var/folders/.../T/`, deleting the path entry under a long-running app (`connect()` → ENOENT → spurious `APP_NOT_RUNNING`) | #239 |
| 2026-06-04 | Socket ownership: per-socket lock so secondary instances cannot unlink/replace a live owner; stale cleanup and shutdown unlink only when owning; app detection by bundle id | #387 |
| 2026-06-04 | `read` `truncated` semantics fixed: `true` now means "returned text may be incomplete", not "fewer lines than requested"; `read.md` updated | #388 |
| 2026-06-07 | Socket access hardening: owner-only permissions on directory/socket/lock; reject clients whose peer uid ≠ app uid | #404 |
| 2026-06-13 | JSON mode passes through app-encoded JSON instead of decode + re-render, fixing escaped C0 control characters in text/titles | #445 |
| 2026-06-26 | Socket errno diagnostics: distinguish missing/stale socket, sandbox permission-denied, invalid path (`SocketConnectionProbe`) | #516 |

### Phase 5 — Capability growth & agent guidance (2026-06-04 → 2026-06-14)

| Date | Change | Ref |
| --- | --- | --- |
| 2026-06-04 | `read --wait-stable` (+ `--stable-interval/--stable-period/--wait-timeout`): app-side polling until the rendered buffer stops changing; response gains `stabilized`/`waited_ms`/`samples`; prowl-cli skill hardened; skill discovery symlinks added | #384 |
| 2026-06-04 | prowl-cli `SKILL.md` YAML frontmatter fixed so strict parsers discover it | #389 |
| 2026-06-07 | `prowl tab create` / `tab close` / `pane close` commands with app-side handlers and payloads | #405 |
| 2026-06-07 | prowl-cli skill targeting guidance clarified | #407 |
| 2026-06-14 | `prowl agents` roster command — see [002-agents-command.md](002-agents-command.md) | #442 |

## Outcome & current state (as of 2026-07-12)

- **Package**: `Package.swift` defines `ProwlCLIShared` (path
  `supacode/CLIService/Shared` — shared between app and CLI), executable `prowl` (path
  `ProwlCLI`), and `ProwlCLITests`; dependencies: swift-argument-parser, Rainbow.
- **CLI**: `ProwlCLI/Commands/ProwlCommand.swift` registers nine subcommands with
  `open` as default: `open`, `list`, `agents`, `focus`, `send`, `key`, `read`, `tab`,
  `pane`; shared flags in `SelectorOptions.swift` / `GlobalOptions.swift`. Transport in
  `ProwlCLI/Transport/SocketTransportClient.swift` and `SocketConnectionProbe.swift`
  (errno diagnostics); `ProwlCLI/AppLauncher.swift` handles cold launch;
  `ProwlCLI/Output/OutputRenderer.swift` renders text mode and passes through
  app-encoded JSON.
- **App service**: `supacode/CLIService/` — `CLICommandRouter.swift` (stamps
  `prowl.cli.<command>.v1` schema versions), `CLISocketServer.swift` (ownership lock,
  owner-only permissions, peer-uid check), one handler per command
  (`OpenCommandHandler.swift` … `AgentsCommandHandler.swift`), `TargetResolver.swift`,
  `ListRuntimeSnapshotBuilder.swift`.
- **Shared types**: `supacode/CLIService/Shared/` — envelope/response/input/payload
  models, `ErrorCodes.swift`, `SocketConstants.swift` (default socket
  `~/Library/Application Support/com.onevcat.prowl/cli.sock`, `PROWL_CLI_SOCKET`
  override, fallback to `NSTemporaryDirectory()` only when the path would exceed the
  104-byte AF_UNIX limit), generated `ProwlVersion.swift`.
- **Install**: `supacode/Clients/CLIInstall/CLIInstallClient.swift`; binary embedded
  under `Resources/prowl-cli/`.
- **Build/test**: Makefile targets `build-cli`, `build-cli-release` (universal),
  `embed-cli`, `embed-cli-debug`, `sync-cli-version`, `test-cli-smoke`,
  `test-cli-integration`.
- **Agent-facing docs**: `skills/prowl-cli/SKILL.md` (discovery symlinks
  `.claude/skills/prowl-cli`, `.agents/skills/prowl-cli`); user manual
  `docs/components/cli.md`; normative contracts remain `docs-ai/013-prowl-cli/contracts/`.

## Deviations from plan

- `architecture.md` left the IPC channel abstract ("implementation choice can be
  refined"); v1 fixed it as a Unix domain socket at `$TMPDIR/prowl-cli.sock` (#126),
  which proved operationally wrong and was relocated to Application Support (#239).
- The command surface grew beyond the phase-1 six: `tab`, `pane` (#405) and `agents`
  (#442) have runtime schema ids (`prowl.cli.tab.v1`, `.pane.v1`, `.agents.v1`) but no
  contract docs under `docs-ai/013-prowl-cli/contracts/`.
- The contract's "`--json` = raw contract payload" was initially implemented as decode +
  re-encode in the CLI; #445 changed it to byte pass-through of the app-encoded JSON
  (arguably closer to the original contract intent).
- M4's planned schema validation of `--json` payloads against `schema.md` appears to
  have landed as pinned-string tests (e.g. `supacodeTests/CLICommandRouterTests.swift`
  asserts the `prowl.cli.*.v1` version strings) plus socket integration round-trips
  (`ProwlCLITests/ProwlCLIIntegrationTests.swift`), not automated JSON-Schema
  validation.

## Open questions

- `docs-ai/013-prowl-cli/contracts/send.md` still describes `--capture` as "a future
  `--capture` flag" even though #148 shipped it in 2026-04 (#148 explicitly deferred the
  contract-doc update; it never landed).
- `docs-ai/013-prowl-cli/contracts/read.md` does not document `--wait-stable` or the
  `stabilized`/`waited_ms`/`samples` response fields (#384 documented them in the skill
  and PR body only).
- No contract docs exist for `tab`, `pane`, or `agents` — the living spec covers only
  the phase-1 commands, so the contract dir currently understates the CLI surface.
