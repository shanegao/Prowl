---
name: prowl-cli
description: Use the Prowl CLI to inspect or control a running Prowl app, especially when a user asks to read from, coordinate, focus, send text to, or send keys to Prowl worktrees, tabs, panes, or sibling agent sessions.
---

# Prowl CLI

Use `prowl` when the user explicitly wants to inspect or control Prowl: reading another pane, checking sibling agent progress, focusing a tab/pane, opening a repo/path in Prowl, or sending text/keys to a Prowl terminal pane.

Do not use it just because the current shell happens to be inside a Prowl repository. It is a remote-control interface for the running Prowl GUI app.

## ⚠️ Resolve the target by UUID — and know which pane is *you*

Targeting is the #1 source of mistakes. Two rules apply to **every** command:

**1. Resolve the target from `prowl list --json` by UUID — never from the tab title.**
A pane's tab *title* is free-form and will lie: a tab titled "MyGreateProject" can actually have `cwd` `/some/other/repo`. Decide the target from `pane.id` (UUID), `worktree.path`, `cwd`, and the `focused` flag — not only the title — then pass the explicit `--pane <id>`.

**2. Know which pane is yourself, because one of them usually is.**
If your session was launched from a Prowl terminal, `prowl list` includes your own pane (it does not exclude the caller). Your own pane is the `focused` one, with `cwd` matching your `$PWD`:

```bash
echo "$PWD"
prowl list --json | jq -r '.data.items[] | select(.pane.focused == true) | .pane.id'
```

Operating on yourself is **not forbidden** — plenty of self-actions are legitimate: `read` (grab your own scrollback), `focus` (raise the window when a long job finishes), `key cmd-k` (clear), or `send --no-enter` (pre-fill a command for the user to review). What you must avoid is *accidentally* hitting yourself with an **interrupting** action:

- `key esc` / `ctrl-c` on yourself aborts your own current request.
- `send` *with* a trailing Enter on yourself submits a prompt to yourself — this is how runaway self-recursion starts.
- **Omitting `--target`/`--pane` defaults to the focused pane — usually you.** So a bare `prowl send 'x'` or `prowl key ctrl-c` lands on yourself. Always pass an explicit `--pane`.

Danger signs that a pane you're reading **is yourself**: its content is your own transcript, or a prompt identical to the one you're currently running.

To run an agent "over in project X", don't reuse a same-looking existing pane — open a fresh one and confirm its id differs from your own:

```bash
prowl open /path/to/project-X --json   # returns a brand-new pane id
# verify: .data.target.pane.id != your own focused pane id
```

## Core Workflow

Discover panes first — and immediately mark which pane is yourself (see the warning above) so you never send/key/focus it:

```bash
prowl list --json
```

Select explicit UUIDs from the JSON. Prefer `--pane <pane-id>` for `read`, `send`, `key`, and `focus`.

Read a pane:

```bash
prowl read --pane <pane-id> --last 80 --json
```

Send text without waiting:

```bash
prowl send --pane <pane-id> 'command here' --no-wait --json
```

Send and capture command output when machine verification matters:

```bash
prowl send --pane <pane-id> 'command here' --capture --timeout 30 --json
```

Send a key (double-check `<pane-id>` is **not your own** — `esc`/`ctrl-c` sent to yourself aborts your current request):

```bash
prowl key --pane <pane-id> enter --json
prowl key --pane <pane-id> ctrl-c --json
```

Focus a pane:

```bash
prowl focus --pane <pane-id> --json
```

Open a path in Prowl. **Side effect:** this *always creates a new tab + pane* for the path — even a non-git path like `/tmp` (`created_tab: true`) — and brings the app to front. To re-focus an already-open worktree without spawning a tab, use `focus`, not `open`:

```bash
prowl open /path/to/repo --json
```

## `send` / `key` argument shapes

Positional arguments are **position-sensitive** — the count changes their meaning:

| command | 0 args | 1 arg | 2 args |
|---|---|---|---|
| `send` | text from **stdin** | text → **current** pane | `<target> <text>` |
| `key`  | error (`INVALID_ARGUMENT`) | token → **current** pane | `<target> <token>` |

"current pane" = the focused pane = **usually yourself**, so always prefer the explicit `--pane <id>` form over a positional target.

- `key --repeat <1-100>` repeats the token, e.g. `prowl key --pane <id> down --repeat 10` (out-of-range → `INVALID_REPEAT`).
- `send --no-enter` sends text without a trailing Enter (key Enter yourself later).
- `send --capture` requires waiting *and* a trailing Enter; it diffs the screen before/after the command, so it **cannot** combine with `--no-wait` or `--no-enter` (either → `INVALID_ARGUMENT`).
- Don't mix stdin piping and a positional text arg (→ `INVALID_ARGUMENT`).

## Finding Pane IDs

By worktree path or repository directory name:

```bash
prowl list --json | jq -r '
  .data.items[]
  | select(.worktree.path | rtrimstr("/") | endswith("/Prowl"))
  | .pane.id
'
```

By selected/focused pane (this is almost always **yourself** — use it to exclude, not to target):

```bash
prowl list --json | jq -r '.data.items[] | select(.pane.focused == true) | .pane.id'
```

By tab or pane title substring:

```bash
prowl list --json | jq -r '
  .data.items[]
  | select((.tab.title + " " + .pane.title) | contains("ProwlCLI"))
  | .pane.id
'
```

For a compact human scan:

```bash
prowl list --no-color
```

## Waiting and Completion

`prowl send` waits for shell integration by default. If the target pane does not report command completion, it can return `WAIT_TIMEOUT`.

Default to `--no-wait` for simple input delivery. Use `--capture --timeout <seconds>` when you need an exit code, duration, and captured output.

`task.status` from `prowl list --json` is useful for coordinating sibling sessions:

- `running`: the pane/worktree is still busy.
- `idle`: it is likely ready for the next step.

Polling pattern:

```bash
prowl list --json | jq -r '
  .data.items[]
  | select(.pane.id == "<pane-id>")
  | .task.status
'
```

### `idle` does not mean the output finished rendering

`task.status: idle` means the agent's model generation ended — **not** that the
terminal has finished painting its reply. Claude Code's TUI repaints a long
markdown answer line by line, and that rendering lags well behind `idle`. So
reading a pane the instant it goes `idle` (or after a fixed `sleep`) routinely
catches a half-drawn screen: the visible buffer stops mid-answer with the input
prompt `❯` right under it. (Measured: at `idle` only the first ~2 of 6 sections
had rendered; 10s later it still had not finished.) `--last` size does not fix
this — the rest of the answer is not in the buffer yet.

Two reliable ways to get the **final** output:

1. **`prowl read --wait-stable`** — re-reads the pane on an interval until its
   content stops changing, then returns the settled snapshot:

   ```bash
   # bare: 200ms sampling / settle after 800ms quiet / 10s cap
   prowl read --pane <pane-id> --last 200 --wait-stable --json

   # tuned
   prowl read --pane <pane-id> --wait-stable \
     --stable-interval 200 \   # sample every 200ms
     --stable-period 800 \     # content must hold steady 800ms to count as stable
     --wait-timeout 10 --json  # give up after 10s, return latest anyway
   ```

   The JSON gains `stabilized` (true = settled, false = hit the timeout),
   `waited_ms`, and `samples`. Prefer this over manual `sleep`-then-`read`. The
   `--stable-*` options only work **with** `--wait-stable` — passing them alone
   returns `INVALID_ARGUMENT`.

   Note this still only sees the rendered buffer, so content Claude Code has
   **folded** (`⎿ … +N lines (ctrl+o to expand)`) is never captured no matter
   how stable it is.

2. **Have the agent write its result to a file**, then read the file. This
   bypasses both async rendering and folding, so it is the most robust when you
   need the complete answer:

   ```bash
   prowl send --pane <pane-id> 'summarize … and write it to /tmp/out.md' --no-wait
   # … wait for idle … then:
   cat /tmp/out.md
   ```

## Quoting

Protect commands from the local shell when they should expand inside the target pane:

```bash
prowl send --pane <pane-id> 'printf "PWD:%s\n" "$PWD"' --no-wait
```

Avoid outer double quotes around payloads containing `$PWD`, `$VAR`, backticks, or command substitutions unless local expansion is intended.

For multiline or generated input, pipe stdin:

```bash
printf '%s\n' 'echo first' 'echo second' | prowl send --pane <pane-id> --no-wait --json
```

## Error Handling

In `--json` mode, command-level errors come back as `{ "ok": false, "error": { "code", "message" } }`. Common codes:

- `APP_NOT_RUNNING`: Prowl is not running, or its CLI service is unavailable. Ask the user before restarting Prowl.
- `TARGET_NOT_FOUND` / `TARGET_NOT_UNIQUE`: re-run `prowl list --json` and resolve an explicit pane UUID (the error does **not** enumerate the candidates).
- `EMPTY_INPUT`: `send` got no text (no argument and no stdin).
- `INVALID_ARGUMENT`: bad flag value or illegal combo (e.g. `--capture` with `--no-wait`, `--stable-*` without `--wait-stable`, `--last 0`).
- `PATH_NOT_FOUND` / `PATH_NOT_DIRECTORY` / `PATH_NOT_ALLOWED`: `open` path problems.
- `UNSUPPORTED_KEY` / `INVALID_REPEAT`: bad key token or out-of-range `--repeat`; see `prowl key --help`. Canonical tokens: `enter`, `esc`, `tab`, `up`, `down`, `ctrl-c`, `cmd-k`, `f1`, …
- `WAIT_TIMEOUT`: `send` waited but the command never reported completion — retry with `--no-wait`, or use a shell-integrated pane for `--capture`.

> ⚠️ **Not every failure is JSON.** Argument-*parsing* errors (unknown flag, wrong type such as `read --last abc`) are caught by the parser *before* `--json` takes effect: they print a plaintext usage error to **stderr** and exit non-zero. A `| jq …` pipeline will choke on these. Get flag names/types right, and always check the exit code rather than assuming stdout is JSON.

## Notes

- JSON output is the automation surface; text output is for humans. JSON keys are snake_case (`line_count`, `waited_ms`, `created_tab`, `trailing_enter_sent`, …) — match them exactly in `jq` or you'll silently get `null`.
- `--no-color` is global (works on every command) and safe in automation.
- `-t/--target` auto-resolves pane UUID, tab UUID, or worktree id/name/path, but explicit `--pane` is safer for automation.
- The current commands are `list`, `read`, `send`, `key`, `focus`, and `open` (the default). There is **no close/quit command** — you cannot close a tab/pane via the CLI (send `cmd-w` as a key if you must). Run `prowl --help` to confirm the command set before automating.
