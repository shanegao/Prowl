# Ghostty Fork Sync

Prowl embeds GhosttyKit from `ThirdParty/ghostty`. The submodule points to the `onevcat/ghostty` fork so Prowl can carry small embedded API patches that are not yet upstream.

## Branch Model

- Upstream remote: `https://github.com/ghostty-org/ghostty`
- Fork remote: `git@github.com:onevcat/ghostty.git`
- Per-version patched branches: `release/v<UPSTREAM_TAG>-patched`
- Current patched branch: `release/v1.3.1-patched`

Each patched branch starts at the matching upstream tag and only adds onevcat patches. Do not rewrite an existing patched branch after publishing it.

## Current Patch

- Commit: `76dce319f55db097b2b7ae3cad2f6267475936f0`
- Summary: expose `ghostty_surface_pid(ghostty_surface_t)` from the embedded C API.
- Behavior: returns the local surface child process PID, or `0` when unavailable or exited.

## Upgrade To A New Ghostty Tag

```bash
cd ThirdParty/ghostty

git fetch upstream --tags
git fetch onevcat

PREV=v1.3.1
NEXT=v1.3.2

git checkout -b "release/${NEXT}-patched" "${NEXT}"
git cherry-pick "${PREV}..onevcat/release/${PREV}-patched"
git push -u onevcat "release/${NEXT}-patched"

cd ../..
git -C ThirdParty/ghostty checkout "release/${NEXT}-patched"
git add ThirdParty/ghostty
git commit -m "ghostty: bump submodule to ${NEXT}-patched"
make sync-ghostty
make build-app
```

## Force Push Policy

Do not force-push `release/v*-patched` branches. If a cherry-pick needs repair, use a temporary fix branch, validate it, then fast-forward the patched branch.

## Build Note

On macOS 26.3.1 with Zig 0.15.2, native `zig build` can fail before running Ghostty's build script because Zig links the build runner with `-platform_version macos 26.3.1 26.4` and fails to resolve libSystem symbols. Direct `zig build-exe -target aarch64-macos.15.0 --sysroot "$(xcrun --sdk macosx --show-sdk-path)"` works, so this is a local Zig host-target/toolchain issue rather than a Ghostty patch syntax error. Re-run `make sync-ghostty` after the Zig toolchain issue is resolved.
