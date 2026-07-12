# 019 — Amendment: Advanced Placement Overrides (#424, #427)

## Context

The worktree folder always landed at `<defaultBase>/<branch>`; the only control was the
global / per-repo default base directory, which is coarse and affects every creation.
Upstream #351 added per-creation overrides; the fork ported the GUI part.

## Change

PR #424 (merged 2026-06-08, "Let users override the new worktree's name and parent
directory", port of upstream #351, GUI only):

- Default-collapsed **Advanced** `DisclosureGroup` in the New Worktree dialog with two
  optional fields: **Worktree name** (leaf folder, placeholder = branch name) and
  **Parent folder** (placeholder = resolved base directory). Both blank keeps `wt`'s
  default `base/<branch>` placement — zero behavior change.
- `WorktreePlacementOverride` model: optional `name`/`path`; `nameValidationError`
  rejects slashes, `.`/`..`, and `.git`. Shared by the prompt and the reducer create
  path.
- `SupacodePaths.resolvedWorktreeDirectory` (returns `nil` without an override so callers
  keep the default) and `previewWorktreeDirectory` (always concrete, drives the live
  destination preview / inline validation error in the dialog footer).
- Applied via `wt sw --path <dir>` with the branch kept as the positional argument, so
  the sidebar name still tracks the branch.
- Not ported: upstream's `worktree-new --name/--location` CLI and deeplink params — the
  fork's `prowl` CLI has no worktree-management commands and there is no deeplink
  subsystem.

PR #427 (merged 2026-06-09, "Label the worktree creation Advanced fields"): under
`.roundedBorder` style the `TextField` label argument is not rendered — only the
placeholder is, and the name field's placeholder is empty until a branch name is typed,
leaving two anonymous boxes. Fix matches the visible-label pattern of the "Branch name"
field: secondary `Text` labels above each field plus a one-line caption explaining the
blank-falls-back-to-default behavior. View-only change.

The same dialog later gained on-device Foundation Model branch-name suggestions (#518);
that work is documented in
[044-foundation-model-branch-names](../044-foundation-model-branch-names/000-plan.md).

## Refs

- PRs #424, #427; upstream #351.
- Tests added with #424: `WorktreeCreationPlacementTests`,
  `WorktreeCreationPromptPlacementTests`.

## Current state

`supacode/Features/Repositories/Models/WorktreePlacementOverride.swift`;
`resolvedWorktreeDirectory` / `previewWorktreeDirectory` in
`supacode/Support/SupacodePaths.swift`; `showAdvancedOptions` and placement threading in
`supacode/Features/Repositories/Reducer/WorktreeCreationPromptFeature.swift` and
`RepositoriesFeature+WorktreeCreation.swift`; labeled fields in
`supacode/Features/Repositories/Views/WorktreeCreationPromptView.swift`; the `--path`
argument is appended in `supacode/Clients/Git/GitClient.swift`. Documented in
`docs/components/repositories-and-worktrees.md`.
