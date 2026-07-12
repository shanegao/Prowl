# 019 — Amendment: Add to Prowl Popover with Clone Support (#520)

## Context

The sidebar "Add…" button showed a system `confirmationDialog`, and Prowl had no way to
clone a remote repository from within the app — every repository had to exist on disk
first.

## Change

PR #520 (merged 2026-06-28, "Redesign Add to Prowl popover with clone support"):

- Custom popover replacing the `confirmationDialog`: app-icon header, drag-and-drop zone
  for folders from Finder, **Browse…** (file picker), **Clone…**, and **Add Workspace**
  (workspace creation is owned by
  [042-project-workspaces](../042-project-workspaces/000-plan.md)).
- **Clone…** switches the popover to a clone form (URL + location fields); the URL field
  is pre-filled from the clipboard when it contains a git URL, and the result is added as
  a git repository, not a plain folder.
- The newly added repository is auto-selected after add/clone/drag-drop; initial app load
  does not auto-select.
- The PR's test plan notes a prior `.sheet` on `SidebarListView` caused an AttributeGraph
  crash on launch — the popover-based design avoids it.

## Refs

- PR #520.

## Current state

`supacode/Features/Repositories/Views/AddToProwlView.swift` (drop zone via
`.dropDestination(for: URL.self)`, Browse/Clone/Workspace actions) and
`supacode/Features/Repositories/Views/CloneRepositoryView.swift` (clone form). The Add
popover behavior is described in `docs/components/repositories-and-worktrees.md`.
