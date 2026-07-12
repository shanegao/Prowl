# 022 — Amendment: Persistent Custom Tab Titles (#259)

## Context

Until May 2026 a user-set title simply overrode the tab's single `title` string (the
#214 model). That conflated two things: the live shell title (OSC 2, constantly
updated) and the user's chosen name. Snapshots persisted whatever string was current,
so restores could freeze a stale shell title as if the user had chosen it. Upstream
solved this with dedicated custom titles (upstream #269, commit `6615f49c`); fork
PR #259 (merged 2026-05-08) adapted that design onto the fork's own tab model and
snapshot pipeline.

## Change

- Split live shell titles from user titles: `TerminalTabItem.customTitle: String?`
  alongside `title`, with `displayTitle = customTitle ?? title`. The shell keeps
  updating `title` underneath a custom name.
- Inline rename for the normal tab bar (text field inside the tab,
  `TerminalTabView`); Shelf and Canvas keep the existing modal NSAlert path
  (`promptChangeTabTitle`). The context-menu entry was relabeled from
  "Change Tab Title..." to "Rename Tab" (commit `f72ed4cd`), hidden for title-locked
  tabs (RUN SCRIPT).
- Persistence: `SnapshotTab` gains `customTitle`; a v1→v2 payload migration promotes a
  v1 `title` to `customTitle` (a v1 snapshot could not distinguish the two, and
  promoting preserves what the user saw). Display titles also surface in
  Canvas/Shelf/CLI snapshots.
- `TerminalTabManager.setCustomTitle` replaced the old title-override entry points.

## Refs

- PR #259 (2026-05-08); upstream reference supabitapp/supacode `6615f49c` (upstream #269)
- Cross-link: [014-terminal-layout-persistence](../014-terminal-layout-persistence/000-plan.md)
  for the snapshot pipeline this migration lives in.

## Current state

Live as described; key files: `supacode/Features/Terminal/Models/TerminalTabItem.swift`,
`TerminalTabManager.swift`, `TerminalLayoutSnapshotPayload.swift` (migration comment at
the top of the payload), `supacode/Features/Terminal/TabBar/Views/TerminalTabView.swift`.
