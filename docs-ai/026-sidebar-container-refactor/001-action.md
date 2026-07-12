# 026 — Sidebar Container Refactor: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-04-30 | Sidebar "Repositories" header (shown when repo count > 10) with an icon-only expand/collapse-all toggle; collapse preferred when any expandable repo is open; plain folders excluded from the expandable set. Exposed the unstable bulk-collapse animation → issue #249 | PR #250 |
| 2026-05-03 | The container refactor, in one PR: reducer-level drag gate deferring notification reorders, pure `SidebarPresentation` model, `ScrollView`/`LazyVStack` container replacing `List(selection:)`, custom repository/worktree drag & drop with overlay insertion indicators, explicit selection visuals, plain-text internal drag payloads; old `List` path removed in the same change | PR #252 (refs #249, #222) |
| 2026-05-05 | Add Repository moved to the sidebar header + zero-repo onboarding hint; header made unconditional | PR #254 — see [002-add-repository-entry-point.md](002-add-repository-entry-point.md) |

Later changes that reshaped this surface belong to other entries: the 2026-05-24 UI
refresh reworked the header/empty state
([033-ui-refresh-2026-05](../033-ui-refresh-2026-05/000-plan.md)), #398 replaced
`LazyVStack` with a plain `VStack`
([032-performance-hardening](../032-performance-hardening/000-plan.md)), and workspaces
added child-repository rows to the containers
([042-project-workspaces](../042-project-workspaces/000-plan.md)).

## Outcome & current state (as of 2026-07-12)

- `supacode/Features/Repositories/Models/SidebarPresentation.swift` — the pure model:
  `SidebarPresentation.items` with `SidebarItem`
  (`listHeader` / `repository` / `failedRepository` / `archivedWorktrees`),
  `SidebarPresentationItemID`, `SidebarScrollID`, and
  `SidebarRepositoryContainerModel` (worktree sections built only when expanded). The
  builder lives in the same file as
  `RepositoriesFeature.State.sidebarPresentation(expandedRepositoryIDs:includesArchivedWorktreesRow:)`,
  converging empty and custom ordered roots into one path. Drop mapping:
  `SidebarWorktreeDropTarget.action` dispatches the pre-existing
  `pinnedWorktreesMoved` / `unpinnedWorktreesMoved` ordering actions;
  `repositoryOrderAfterMove(fromOffsets:toOffset:)` computes the new root order.
  Workspace additions (`isWorkspace`, `workspaceChildRows`) came later via 042.
- `supacode/Features/Repositories/Views/SidebarListView.swift` — the container view:
  `ScrollViewReader` + `ScrollView` + `VStack` (a comment explains why not `LazyVStack`;
  swapped by #398, see 032), repository list header with the expand/collapse-all button
  from #250, explicit selection handling, root-level URL drop, and reveal via
  `.task(id: pendingSidebarReveal?.id)` → `revealPendingSidebarWorktree`.
- `supacode/Features/Repositories/Views/SidebarDragSupport.swift` — `SidebarDragProvider`
  (plain-text `NSItemProvider` payloads with repo/worktree prefixes, chosen for SwiftUI
  drop compatibility), `SidebarRepositoryDropDelegate` / `SidebarWorktreeDropDelegate`,
  `SidebarDropIndicator` (drawn as an overlay so it does not affect layout, one
  indicator per boundary), and `SidebarDropTargetActions`.
- Drag gate: `RepositoriesFeature.State.isSidebarDragActive` and
  `pendingSidebarNotifyReorderIDs` (`supacode/Features/Repositories/Reducer/RepositoriesFeature.swift`);
  `setSidebarDragActive` handling and the deferred
  `worktreeNotificationReceived` path in
  `supacode/Features/Repositories/Reducer/RepositoriesFeature+WorktreeOrdering.swift` —
  pending IDs are de-duplicated, flushed in order on drag end, and persistence runs only
  when a reorder actually applied.
- `supacode/Features/Repositories/Views/RepositorySectionView.swift` and
  `WorktreeRowsView.swift` were *not* deleted (the plan's Phase 6 allowed folding them
  in): they survive as the container's header row and child-row stack inside the new
  scroll container. `supacode/Features/Repositories/Views/WorkspaceChildRowsView.swift`
  joined later (042).
- Expanded/collapsed persistence preserved as required:
  `supacode/Features/Repositories/Views/SidebarView.swift` holds
  `@Shared(.appStorage("sidebarCollapsedRepositoryIDs"))` and derives the expanded-set
  binding that `SidebarListView` consumes.
- Tests: `supacodeTests/SidebarPresentationTests.swift` (one outer item per expanded
  repo, failed repos participate in root order, plain folders have no children,
  pinned/main/pending/unpinned preserved, empty vs custom roots equivalence, drop
  mapping), `supacodeTests/SidebarDragSupportTests.swift`, drag-gate tests in
  `supacodeTests/RepositoriesFeatureTests.swift`
  (`worktreeNotificationDuringSidebarDragDefersReorder`,
  `endingSidebarDragAppliesPendingNotificationReordersInOrder`), and
  `supacodeTests/RepositorySectionViewTests.swift` (expand-toggle logic from #250,
  e.g. `SidebarListView.expandableRepositoryIDs` / `repositoryListHeaderAction`).

## Deviations from plan

- The phased rollout (render-only path behind a switch, then selection, then repo
  reorder, then worktree reorder, then delete the `List` path) collapsed into the single
  PR #252, which shipped the container path and removed `List(selection:)` directly.
- The plan recommended starting with `LazyVStack`; #252 did, but PR #398 (2026-06-06,
  see [032-performance-hardening](../032-performance-hardening/000-plan.md)) replaced it
  with a plain `VStack` because SwiftUI's lazy placement cache could spin on the main
  thread while scrolling after collapse/expand of large sections — the fallback the
  plan's Phase 0 metrics had anticipated.
- The plan required replacing fixed-yield reveal with an event-driven row-availability
  signal; `revealPendingSidebarWorktree` still uses two fixed `await Task.yield()` calls
  before `scrollTo`. PR #252's notes explicitly left this (and keyboard/accessibility
  parity beyond command shortcuts) as follow-up.
- `RepositorySectionView` / `WorktreeRowsView` were repurposed rather than removed.

## Open questions

- The fixed two-`Task.yield()` reveal materialization
  (`supacode/Features/Repositories/Views/SidebarListView.swift`,
  `revealPendingSidebarWorktree`) was never replaced with the event-driven signal the
  plan demanded; it works in practice but remains timing-based.
- `SidebarPresentation.showsListHeader(repositoryCount:)` ignores its parameter and
  returns `true` unconditionally — a vestige of the #250 ">10 repos" rule that #254
  removed; the actual gating today is `!repositoryItems.isEmpty` in `SidebarListView`.
  Harmless, but the function is dead logic.
- The accessibility parity pass (plan's Phase 6 "final accessibility pass") has no
  dedicated follow-up PR in this entry's scope; command-shortcut coverage exists, but
  full native-`List` accessibility equivalence was never verified in the sources.
