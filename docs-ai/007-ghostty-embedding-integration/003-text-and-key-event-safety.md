# 007 — Amendment: Text & Key-Event Safety (2026-05-13 → 2026-05-30)

## Context

Three independent defects at the GhosttyKit C-ABI / AppKit event boundary:

1. **Memory leak on text reads** — an Instruments trace showed leaked Zig
   `heap.CAllocator.alloc` buffers on the viewport-read path. Root cause is upstream
   `ghostty-org/ghostty#12020`: the public header declares
   `ghostty_surface_free_text(ghostty_surface_t, ghostty_text_s*)`, but the Zig export
   accepted only `*Text`, so the surface pointer was interpreted as the text pointer and
   the real allocation was never freed. Upstream fixed it in `ghostty-org/ghostty#12025`,
   but no tagged release contained the fix yet.
2. **NUL-truncated decoding** — Prowl decoded `ghostty_text_s` buffers as NUL-terminated C
   strings even though Ghostty returns an explicit `text_len`; terminal content containing
   an interior NUL byte would be silently truncated.
3. **Exceptions/garbage from modifier events** — `NSEvent.characters` throws on non-key
   events, and Ghostty key-event construction could touch it for `.flagsChanged`
   (modifier-only) events.

## Change

| Date | Change | Ref |
| --- | --- | --- |
| 2026-05-13 | Backport upstream `ghostty-org/ghostty#12025` onto `onevcat/ghostty` `release/v1.3.1-patched`; advance the submodule to `48365577c`; keep the upstream-compatible two-argument `ghostty_surface_free_text` call shape; document the split toolchain (GhosttyKit with Xcode 26.3, app with Xcode 26.4) | PR #286 |
| 2026-05-25 | Decode all `ghostty_text_s` reads (selection, viewport, accessibility, Quick Look, Services) through a shared bounded decoder using explicit `text_len`; interior-NUL regression tests | PR #348 |
| 2026-05-30 | Guard key text extraction: `.flagsChanged` events stay textless; only `keyDown`/`keyUp` read `NSEvent.characters`; regression tests for both | PR #374 |

## Refs

- PRs #286, #348, #374; upstream `ghostty-org/ghostty#12020` / `#12025`.
- Fork patch lifecycle: [ghostty-fork-sync.md](ghostty-fork-sync.md) — the #286 patch is
  explicitly marked droppable once the submodule reaches an upstream tag containing
  upstream commit `4803d58`.

## Current state (as of 2026-07-12)

- `ThirdParty/ghostty` is at `48365577c` (`v1.3.1` + 4 patches; the text-free ABI fix is
  the tip commit). Every Swift call site pairs text reads with
  `ghostty_surface_free_text(surface, &text)` — see the `GhosttySurfaceView+Services` /
  `+Mouse` / `+TextInput` / `+Accessibility` extensions under
  `supacode/Infrastructure/Ghostty/`.
- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift` —
  `stringFromGhosttyText(pointer:length:)` (bounded, UTF-8, empty on nil/0) and
  `string(from: ghostty_text_s)` using `text_len`; `GhosttySurfaceBridge.swift` has
  matching private length-taking `string(from:length:)` helpers for action payloads.
- `supacode/Infrastructure/Ghostty/GhosttySurfaceView.swift` — `GhosttyEventText.characters(for:)`
  returns `nil` unless the event is `keyDown`/`keyUp` (also strips control-modified and
  function-key private-use characters); used by
  `GhosttySurfaceView+EventTranslation.swift`, whose `translationState` likewise skips
  `characters`-family APIs for modifier-only events. `MirroredTerminalKey.init?(event:)`
  only accepts `.keyDown` events.
- Tests: `supacodeTests/GhosttySurfaceViewTests.swift` (interior-NUL decoding),
  `supacodeTests/MirroredTerminalKeyTests.swift` (`.flagsChanged` yields no text; plain
  keyDown yields its character).
