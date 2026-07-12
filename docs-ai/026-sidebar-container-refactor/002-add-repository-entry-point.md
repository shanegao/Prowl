# 026 — Amendment: Add Repository Entry Point & Onboarding Hint (#254)

## Context

Right after the container refactor landed, the "Repositories" list header (introduced by
#250 only for >10 repositories) was still absent in the common case, leaving the section
unlabeled, and the Add Repository action lived in the sidebar footer where new users did
not look for it.

## Change

PR #254 (merged 2026-05-05):

- Show the "Repositories" header unconditionally (`SidebarPresentation.showsListHeader`
  changed to always return `true`).
- Move Add Repository from the sidebar footer to a `+` icon-button next to the
  expand/collapse chevron in the header; the footer dropped the action and its
  `commandKeyObserver`-based shortcut chip.
- Render a zero-repo onboarding hint row under the header — `arrow.turn.up.right` with a
  pulsing symbol effect and "Add your first repository".
- Tighten `EmptyStateView` copy to talk about *adding* a repository, keeping the dynamic
  `openRepository` shortcut so keybinding overrides show through.

## Refs

- PR #254 (merged 2026-05-05), merge `c21bc209`.
- Superseded by: PR #332 commits `13fc410d` / `18de41f2` (2026-05-22/24, part of the
  [033-ui-refresh-2026-05](../033-ui-refresh-2026-05/000-plan.md) wave) moved Add
  Repository from the header `+` into a sidebar toolbar item and removed the pulsing
  zero-repo hint; PR #520 (2026-06-27,
  [042-project-workspaces](../042-project-workspaces/000-plan.md)) turned that toolbar
  action into the "Add..." (`folder.badge.plus`) button presenting the `AddToProwlView`
  popover (Browse / Clone / Workspace).

## Current state

As of 2026-07-12 the #254 affordances themselves are gone, but the header it made
unconditional survives: `supacode/Features/Repositories/Views/SidebarListView.swift`
renders the "Repositories" header (with only the expand/collapse-all button) whenever
the repository list is non-empty; with zero repositories the sidebar stays intentionally
empty and the detail pane's
`supacode/Features/Repositories/Views/EmptyStateView.swift` carries the prompt; adding
happens through the sidebar toolbar's "Add..." button and
`supacode/Features/Repositories/Views/AddToProwlView.swift`.
