# 027 — Amendment: Split-Zoom UX (PR #435)

## Context

Fork issue #369 (user request) reported that pane zoom was effectively
unreachable in Prowl: Ghostty's default zoom binding `⌘⇧↵` is claimed by the
Shelf toggle ([023-shelf-mode](../023-shelf-mode/000-plan.md)), whose unbind
argument also removed Ghostty's own zoom binding, and there was no mouse
affordance either. The same issue also asked for a "focus mode" (hide chrome,
terminal only), which was explicitly scoped out and tracked separately. The
implementation plan was captured in a planning comment on #369.

## Change

PR #435 (merged 2026-06-10):

- **Per-pane zoom UI** — hovering a split pane's top drag handle reveals a
  zoom button in that pane's top-right corner; a zoomed pane keeps a persistent
  exit-zoom button in the same spot, so it is always visible that the pane is
  zoomed and how to exit. Buttons carry tooltips with the resolved shortcut.
- **New keybinding `⌘⌥⇧F` → `toggle_split_zoom`** — registered through
  `ghosttyManagedActionBindings` so it works inside terminal panes and is
  user-remappable in Settings → Shortcuts (Terminal group; see
  [012-keybinding-system](../012-keybinding-system/000-plan.md)). `⌘⌃F` stays
  the system fullscreen toggle and `⌘⇧F` remains reserved for a future focus
  mode.
- **Palette focus-race fix** (ported from upstream #337) — palette-dispatched
  Ghostty binding actions previously ran via an async effect, by which time
  AppKit could have moved first responder to another pane. The reducer now
  captures the target surface synchronously and routes through a new
  surface-targeted `performBindingActionOnSurface` terminal command (see
  [031-command-palette-architecture](../031-command-palette-architecture/000-plan.md)).

Note: the upstream ledger lists upstream #337 ("split-zoom indicator button to
tab bar") under "Not yet ported" — the fork deliberately chose per-pane buttons
over upstream's tab-bar indicator and absorbed only the focus-race fix.

## Refs

- PR #435; fork issue #369 (closed by it); upstream #337.

## Current state (as of 2026-07-12)

- `supacode/Features/Terminal/Views/TerminalSplitTreeView.swift` —
  `SplitZoomButton` view; reveal logic keyed on `isZoomed`, `isHandleHovering`,
  and `isZoomButtonHovering` (the latter survives the cursor hand-off from the
  drag handle to the button); tooltip resolved via
  `AppShortcuts.CommandID.toggleSplitZoom`.
- `supacode/Features/Terminal/Models/SplitTree.swift` — `zoomed: Node?` model
  state, cleared/remapped on split mutations;
  `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift`
  handles the `.toggleZoom(surfaceId:)` operation.
- `supacode/App/AppShortcuts.swift` — `CommandID.toggleSplitZoom`,
  `AppShortcut(key: "f", modifiers: [.command, .option, .shift])`, and the
  managed-binding pair `(CommandID.toggleSplitZoom, "toggle_split_zoom")`.
- `supacode/Clients/Terminal/TerminalClient.swift` —
  `Command.performBindingActionOnSurface(Worktree, surfaceID: UUID, action:
  String)`, dispatched synchronously from
  `supacode/Features/App/Reducer/AppFeature+CommandPalette.swift`.
- Behavior documented in `docs/components/terminal.md` and
  `docs/reference/keyboard-shortcuts.md`.
