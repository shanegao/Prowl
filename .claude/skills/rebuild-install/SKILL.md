---
name: rebuild-install
description: Rebuild the Prowl CLI + macOS app and install to /Applications (Release by default; pass "debug" for a Debug build), then verify the CLI round-trip. Resilient to a broken xcsift in mise.
---

# Rebuild Install

Rebuild the Prowl CLI + macOS app, reinstall the bundle into `/Applications/Prowl.app`, then launch it and verify the embedded CLI can talk to the running daemon over the Unix domain socket.

Builds the **Release** configuration by default — its `PRODUCT_NAME` is `Prowl`, so the installed app and its menu-bar/About name read "Prowl". Pass `debug` to build the Debug configuration instead (unoptimized + debuggable, but named "Prowl Debug").

## When to use

- After source changes, to refresh the locally installed app
- For a clean date-bump build (the version stamp `prowl --version` rolls forward to today's date even with no source changes — useful when reproducing date-sensitive bugs)
- After pulling fresh changes from `main` or `upstream/main`

## Steps

### 0. Choose the configuration

Default to the **Release** configuration. Build **Debug** only when the invocation
explicitly asked for it (e.g. `/rebuild-install debug`). Do **not** prompt for the
configuration — use Release unless another is given. Every step below reads `$CONFIG`.

```bash
# Default Release (product name "Prowl"); set to "Debug" only on an explicit request.
CONFIG="Release"
```

### 1. Pre-flight check

Show the user the tree state and currently installed version, so they know what this rebuild will and won't pick up:

```bash
git status --short
git log -1 --oneline
/usr/local/bin/prowl --version 2>/dev/null || echo "prowl CLI not on PATH"
```

If the working tree has unstaged or staged changes, surface them — those will be baked into this build only if they are present in the worktree (which they are; the build reads from the working tree, not git history).

### 2. Build the standalone CLI artifact

```bash
make build-cli
```

This produces `.build/debug/prowl` via SwiftPM. It depends on `sync-cli-version`, which regenerates `ProwlVersion.swift` with today's date — be aware this invalidates downstream caches that import `ProwlCLIShared` and forces partial recompiles.

### 3. Embed the CLI into the app's Resources

```bash
make embed-cli-debug
```

This re-runs `build-cli` (cache hit unless step 2 was skipped) and `cp`s the binary to `Resources/prowl-cli/prowl`. Xcode's Copy Bundle Resources phase reads this path during the app build — skipping this step ships a stale CLI inside the .app even on a successful app rebuild.

### 4. Build the macOS app

Build `$CONFIG`. The build **signs with a stable Apple Development identity when one is
configured** — so macOS keeps its Documents/privacy grant across rebuilds (see *Stable
code signing* below) — and falls back to **ad-hoc** otherwise (which makes macOS
re-prompt for Documents access on every rebuild). `make build-app` is hardcoded to
Debug and exposes no signing hook, so call `xcodebuild` directly:

```bash
make ensure-ghostty embed-cli-debug embed-docs

# Stable signing when an identity is configured ($PROWL_SIGN_ID wins, else the local
# untracked file written during signing setup); ad-hoc otherwise. The Release config
# uses CODE_SIGN_STYLE = Automatic with an empty team, so the ad-hoc path needs
# CODE_SIGNING_ALLOWED=NO (Apple Silicon still applies an ad-hoc signature, so it runs).
PROWL_SIGN_ID="${PROWL_SIGN_ID:-$(cat "$HOME/.config/prowl/dev-sign-identity" 2>/dev/null || true)}"
if [ -n "${PROWL_SIGN_ID:-}" ]; then
  echo "Signing with stable Apple Development identity: $PROWL_SIGN_ID"
  SIGN_FLAGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$PROWL_SIGN_ID" PROVISIONING_PROFILE_SPECIFIER="")
else
  echo "No PROWL_SIGN_ID configured — ad-hoc build (expect a Documents re-prompt)."
  SIGN_FLAGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
fi

timeout 600s xcodebuild -project supacode.xcodeproj -scheme supacode -configuration "$CONFIG" build \
  -skipMacroValidation \
  -clonedSourcePackagesDirPath "$HOME/Library/Caches/supacode-spm-cache/SourcePackages" \
  "${SIGN_FLAGS[@]}" \
  SWIFT_COMPILATION_MODE=incremental 2>&1 | mise exec -- xcsift -w --format toon
```

For a **Debug** build, set `CONFIG="Debug"` and the same `xcodebuild` line works (the
`make build-app` shortcut only covers the ad-hoc Debug path and has no signing hook).
Do **not** use `make install-release` — that is the gated, notarized release path, not
this ad-hoc dev install.

**If `xcsift` is broken** (mise plugin shim missing — `No such file or directory`),
drop the `| mise exec -- xcsift …` pipe and append `| grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -10` instead (xcsift is purely a log formatter). To repair it permanently: `mise install xcsift@latest`.

Do **not** add `-derivedDataPath` overrides — the global rules forbid custom DerivedData paths.

Note: Release is optimized (slower incremental builds, limited debugging) — pass `debug` when you need to step through the app.

#### Stable code signing (stops the macOS privacy re-prompt loop)

Ad-hoc builds change code identity (cdhash) on every compile, so macOS TCC treats each
rebuild as a new app and re-prompts for Documents/privacy access — often under a
disambiguated name like "Prowl 12-42-16-206". Signing with a stable *Apple Development*
identity gives the app a fixed designated requirement, so a granted permission persists
across rebuilds. The cert SHA-1 is **never hardcoded in this file** — it lives in an
untracked local file the build reads (overridable per-invocation with `$PROWL_SIGN_ID`):

- File: `~/.config/prowl/dev-sign-identity` — one line, the 40-char cert SHA-1.
- It lives outside the repo, so it is never committed.

To (re)configure — first-time setup, or when the cert expires — pick a **valid** Apple
Development identity (prefer the longest remaining validity) and write its SHA-1:

```bash
security find-identity -v -p codesigning | grep "Apple Development"
mkdir -p "$HOME/.config/prowl"
printf '%s\n' "<paste the 40-char SHA-1>" > "$HOME/.config/prowl/dev-sign-identity"
```

Use **manual + the cert SHA-1** — not `CODE_SIGN_STYLE=Automatic` with
`CODE_SIGN_IDENTITY="Apple Development"`: automatic resolves to the legacy "Mac
Development" type, fails to match the team, and also tries to sign the SPM macro
plugins. Verify after install: `codesign -dvv /Applications/Prowl.app` should report
`Authority=Apple Development: …` (not `Signature=adhoc`). To force ad-hoc again, delete
the file (or unset `PROWL_SIGN_ID`).

### 5. Install into /Applications

Resolve the build output path from Xcode build settings (don't hardcode the DerivedData hash — it's per-user and can rotate after Xcode updates):

```bash
set -euo pipefail
settings="$(xcodebuild -project supacode.xcodeproj -scheme supacode -configuration "$CONFIG" -showBuildSettings -json 2>/dev/null)"
src="$(echo "$settings" | jq -er '.[0].buildSettings.BUILT_PRODUCTS_DIR')/$(echo "$settings" | jq -er '.[0].buildSettings.FULL_PRODUCT_NAME')"
dst="/Applications/$(echo "$settings" | jq -er '.[0].buildSettings.FULL_PRODUCT_NAME')"

# Safety gates (mirror Makefile install-dev-build)
case "$dst" in /Applications/*.app) ;; *) echo "refusing $dst"; exit 1 ;; esac
[ -d "$src" ] || { echo "src missing: $src"; exit 1; }

# Terminate any running instance FIRST. Trashing the bundle does NOT kill a
# running process, and `open` on a live app with the same bundle id just
# re-foregrounds it — so the freshly-built binary would never launch (a silent
# no-op deploy). Quit gracefully, wait, then SIGTERM as a fallback.
appProc="Prowl.app/Contents/MacOS/ProwlApp"
osascript -e 'quit app "Prowl"' 2>/dev/null || true
for i in $(seq 1 12); do pgrep -f "$appProc" >/dev/null 2>&1 || break; sleep 1; done
pgrep -f "$appProc" >/dev/null 2>&1 && { pkill -f "$appProc" 2>/dev/null || true; sleep 2; }

[ -e "$dst" ] && trash "$dst"
ditto "$src" "$dst"

# Prevent the macOS privacy re-prompt loop (see "Stopping the … prompt" below):
# the trashed old app keeps a LaunchServices registration that macOS later
# surfaces in prompts under a disambiguated name ("Prowl <timestamp>"), even when
# nothing is running. Drop those stale registrations and (re-)register the new app.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u "$HOME/.Trash/Prowl"*.app 2>/dev/null || true
"$LSREG" -f "$dst"
```

**Terminating the running instance first is essential.** Trashing the bundle does *not* kill a running `ProwlApp`, and `open` on a still-running app with the same bundle id just brings it to the front — so the freshly-built binary never launches and the deploy is a **silent no-op**. This is easy to miss because the embedded CLI *does* update, so `prowl --version` looks new while it talks to the stale app. Always quit/kill before `open` (the terminate block above), and confirm a fresh PID in step 7 (`ps -o lstart` should show a just-now start time).

### 6. Launch + bounded socket wait

```bash
open /Applications/Prowl.app
ok=0
for i in $(seq 1 15); do
  if /usr/local/bin/prowl list >/dev/null 2>&1; then ok=1; echo "socket bound after ${i}s"; break; fi
  sleep 1
done
[ "$ok" = 1 ] || { echo "socket did NOT bind within 15s"; exit 1; }
```

A bounded retry (not an `until` loop) avoids the failure mode where the harness terminates an unbounded poll and leaves verification incomplete. The newly-installed app typically binds the socket within 1–2 seconds.

### 7. Verify CLI round-trip

```bash
ls -la /Applications/Prowl.app/Contents/Resources/prowl-cli/prowl
/usr/local/bin/prowl --version
# Confirm the new binary actually launched (catches a failed terminate in step 5):
# the start time must be just now, not hours ago.
ps -axo pid,lstart,etime,comm | grep "Prowl.app/Contents/MacOS/ProwlApp" | grep -v grep
/usr/local/bin/prowl list 2>&1 | head -8
```

A successful `prowl list` exit-0 with live worktree/tab/pane state proves three layers in one shot:
1. Embedded CLI binary parses argv correctly
2. Unix domain socket connection is alive
3. App's socket server returns serialized state

If `prowl list` returns `error [APP_NOT_RUNNING]`, the socket didn't bind — re-run step 6 or check Console for ProwlApp launch errors.

## Stopping the repeated "access your Documents folder" prompt

Dev rebuilds make macOS re-ask for Documents access on nearly every launch, often with a disambiguated name like **"Prowl 12-42-16-206"**. Two compounding causes:

1. **Ad-hoc signing** — each build's code identity (cdhash) changes, so TCC can't match the prior grant to the new binary. Fix: sign with a stable Apple Development identity (step 4's *Stable code signing*).
2. **Orphaned LaunchServices registrations** — step 5 `trash`es the old `/Applications/Prowl.app` each rebuild, and macOS renames each copy in the Trash (`Prowl <timestamp>.app`). Emptying the Trash deletes the *file* but **not** the LaunchServices registration, so an orphaned `com.onevcat.prowl` record — named for the trashed copy — lingers, and macOS surfaces every Documents prompt under that stale name **even when no Prowl is running**. (Check: `lsregister -dump | grep -c com.onevcat.prowl`.)

Clear it once, **after** switching to stable signing:

```bash
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# 1) reset the Documents-folder grant for this bundle id
tccutil reset SystemPolicyDocumentsFolder com.onevcat.prowl
# 2) drop the stale registrations. macOS 26 REMOVED `lsregister -kill`, so instead
#    unregister the orphaned Trash bundle(s) by path, re-register the real app,
#    and re-scan the domains (which prunes dead paths).
"$LSREG" -u "$HOME/.Trash/Prowl"*.app 2>/dev/null || true
"$LSREG" -f /Applications/Prowl.app
"$LSREG" -r -domain local -domain user
# verify the disambiguated registration is gone:
"$LSREG" -dump | grep -E "Prowl [0-9-]{6,}\.app" || echo "✓ no disambiguated Prowl registration"
```

Then launch the stably-signed app once and click **Allow**, or grant it under **System Settings → Privacy & Security → Files and Folders** (toggle Documents) or **Full Disk Access**. With a stable signature the grant now persists across rebuilds.

- macOS 26 removed `lsregister -kill` ("dangerous and no longer useful"), so the older full-DB-rebuild trick no longer works — target the stale path with `-u` + a `-r` re-scan instead.
- `tccutil` and the System-Settings toggle **must be run by you** — no process can grant another app's privacy access on your behalf, so this skill can document the steps but cannot execute the grant.

## Notes

- **Do not auto-commit anything.** This skill ends at "installed and verified" — committing is a separate explicit ask.
- **Do not run `make install-release`** — that target is for signed/notarized release builds and is gated by stricter rules (see the `release` skill).
- **The build is reproducible from current worktree state, not from HEAD.** Uncommitted changes are included; committed-but-not-checked-out changes are not.
- The CLI binary at `Resources/prowl-cli/prowl` is what gets bundled. The `/usr/local/bin/prowl` symlink points to that bundled binary, so smoke-testing the CLI tests the same artifact end-users get.
