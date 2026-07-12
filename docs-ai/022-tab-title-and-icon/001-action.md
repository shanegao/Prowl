# 022 — Tab Title and Icon: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-08 | Groundwork: `SnapshotTab` gains optional `title`/`icon`, captured/restored with the layout snapshot (documented in entry 014) | PR #186, fork issue #172 |
| 2026-04-18 | "Change Tab Title..." added to the tab context menu, reusing the `promptTabTitle` NSAlert flow | PR #214 |
| 2026-04-18 | "Change Tab Icon..." in context menu + command palette; `TabIconPickerView` (preset grid + free-form SF Symbol name); icon lock + snapshot round-trip | PR #215, fork issue #194 |
| 2026-04-22 | Auto-detect tab icon from the running command (see amendment 002) | PR #234 |
| 2026-04-27 | Run Script / Custom Command icons pinned over auto-detection; icon-lock bools collapsed into `TerminalTabIconLock` enum (see amendment 002) | PR #245 |
| 2026-05-08 | Persistent custom tab titles: `customTitle`/`displayTitle` split, inline rename in the tab bar, context-menu entry relabeled "Rename Tab" (see amendment 003) | PR #259, upstream #269 |

## Outcome & current state (as of 2026-07-12)

- **Tab model** — `supacode/Features/Terminal/Models/TerminalTabItem.swift`:
  `TerminalTabItem` carries `title` (live shell title), `customTitle: String?`,
  `icon: String?`, `isTitleLocked: Bool`, and `iconLock: TerminalTabIconLock`
  (`auto` / `script` / `user`). `displayTitle` is `customTitle ?? title`.
- **Mutation APIs** — `supacode/Features/Terminal/Models/TerminalTabManager.swift`:
  `setCustomTitle`, `updateIcon` (respects locks), `overrideIcon` (user lock),
  `clearIconOverride` (back to auto). The original `overrideTitle`-style title lock
  survives only as `isTitleLocked` on the RUN SCRIPT tab.
- **Context menu** — `supacode/Features/Terminal/TabBar/Views/TerminalTabContextMenu.swift`:
  "Rename Tab" (hidden for title-locked tabs) and "Change Tab Icon...". The #214 label
  "Change Tab Title..." no longer exists; #259 renamed it.
- **Rename routing** — the horizontal tab bar renames inline
  (`supacode/Features/Terminal/TabBar/Views/TerminalTabView.swift`, rename field +
  `onRename`); Shelf spines and Canvas cards still use the modal NSAlert via
  `WorktreeTerminalState.promptChangeTabTitle(_:)` in
  `supacode/Features/Terminal/Models/WorktreeTerminalState+Surfaces.swift`.
- **Icon picker** — `supacode/Features/Terminal/TabBar/Views/TabIconPickerView.swift`;
  palette wiring via `CommandPaletteItem.Kind.changeFocusedTabIcon`
  (`supacode/Features/CommandPalette/CommandPaletteItem.swift`) and
  `TerminalClient.Command.presentTabIconPicker`
  (`supacode/Clients/Terminal/TerminalClient.swift`).
- **Auto-detection** — `supacode/Features/Terminal/Models/WorktreeTerminalState+TabIcons.swift`
  (`noteTitleForCommandDetection`, `isLikelyIdleTitleByShape`, per-surface learned-idle
  titles, focused-surface gate), `supacode/Features/Terminal/Models/CommandIconMap.swift`
  (first-token map, ~66 tokens today), `supacode/Features/Terminal/Models/TabIconSource.swift`
  (`@asset:` marker), `supacode/Features/Terminal/Views/TabIconImage.swift` (shared
  renderer used by tab labels and Shelf spines). Brand artwork lives in
  `supacode/Assets.xcassets/CommandIcons/` (44 imagesets today; grown from 19 at #234).
- **Debug surface** — the DEBUG-only Icon Catalog from #234 still exists:
  `supacode/Features/Debug/Views/DebugSection.swift`, `DebugView.swift`,
  `IconCatalogView.swift`, fed by `CommandIconMap.debugAllEntries`.
- **Persistence** — `supacode/Features/Terminal/Models/TerminalLayoutSnapshotPayload.swift`
  (`SnapshotTab` with `title`, `customTitle`, `icon`; v1→v2 migration promotes a v1
  `title` to `customTitle`) and
  `supacode/Features/Terminal/Models/WorktreeTerminalState+LayoutSnapshot.swift`
  (capture skips blocking-script tabs, persists the icon only when `iconLock == .user`;
  restore sets `iconLock = .user` iff an icon was persisted).
- **User-facing docs** — behavior is documented in `docs/components/terminal.md`
  (title precedence, Rename Tab, Change Tab Icon, icon auto-detection).

## Deviations from plan

- The #214 modal "Change Tab Title..." flow was superseded three weeks later: #259
  replaced the context-menu label with "Rename Tab" and made the tab-bar path an inline
  text field; the modal survives only for Shelf/Canvas variants.
- #215's boolean `isIconLocked` (and #245's second boolean `isScriptIconActive`) were
  collapsed into the `TerminalTabIconLock` enum before #245 merged; the PR bodies
  describe booleans that no longer exist.

## Open questions

- Fork issue #172 asked to persist tab *tint color* alongside title/icon; #186 closed
  it with title+icon only and no per-tab tint exists anywhere in the model today.
  Presumably dropped deliberately (repo-level color identity arrived in entry 025), but
  no recorded decision was found.
