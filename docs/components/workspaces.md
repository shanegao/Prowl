# Workspaces

**Keywords:** workspace, multi-repo, many repositories, agent cwd, `.prowl/workspace.json`, workspace metadata, `prowl list`

Workspaces let one agent work on a task that spans several repositories. A
workspace is a folder added to Prowl as a runnable project, with metadata at
`.prowl/workspace.json` describing the repositories inside it.

When you open a workspace in Prowl:

- The terminal starts in the workspace root.
- The sidebar/detail view uses the workspace title and repository list from
  `.prowl/workspace.json`.
- The `prowl` CLI reports the runnable target's `worktree.kind` as `workspace`.
- Git worktree, branch, diff, and PR controls remain per-repository features; a
  workspace is intentionally a multi-repo working directory rather than a single
  git repository.

## Folder layout

Use **New Workspace** from the sidebar toolbar, Worktrees menu, or command
palette to create a workspace. Prowl creates the shared folder, materializes the
selected repositories, writes `.prowl/workspace.json`, and opens the workspace
as a runnable folder.

```text
my-feature-workspace/
├─ .prowl/
│  └─ workspace.json
├─ app/
├─ api/
└─ shared-package/
```

Repository sources can be mixed in one workspace:

- Already opened repositories are added as symlinks with `source_kind:
  existing_path`.
- Local repository folders selected from disk are added as symlinks with
  `source_kind: local_repository`.
- Remote repositories are cloned into the workspace folder with `source_kind:
  remote`. If a branch and base ref are supplied, Prowl checks out the branch
  from the base after cloning.
- Bare repositories are materialized with `git worktree add` and recorded with
  `source_kind: bare_repository`. If both branch and base ref are supplied,
  Prowl creates the worktree branch from that base ref.

The creation prompt detects base-ref candidates for already opened, local, and
bare repositories by reading local git refs, preferring the detected default
branch such as `main` or `master`. Base refs are selected from detected refs so
workspace creation does not try to checkout an arbitrary, nonexistent branch.
Remote clone entries can be created without a base ref; after cloning, a branch
name without an explicit base is created from the repository's default checkout.

## Metadata

Example `.prowl/workspace.json`:

```json
{
  "title": "Checkout Flow",
  "description": "Update app UI, API contract, and shared package together.",
  "task_links": [
    "https://github.com/onevcat/Prowl/issues/123"
  ],
  "repositories": [
    {
      "name": "App",
      "role": "macOS app",
      "path": "app",
      "source_kind": "local_repository",
      "source_location": "/Users/mikoto/Documents/Repos/github/Prowl",
      "branch_name": "codex/checkout-flow"
    },
    {
      "name": "API",
      "role": "backend",
      "path": "api",
      "source_kind": "remote",
      "source_location": "git@github.com:onevcat/api.git",
      "base_ref": "main"
    },
    {
      "name": "Shared Package",
      "role": "library",
      "path": "shared-package",
      "source_kind": "bare_repository",
      "source_location": "/Users/mikoto/Documents/Repos/bare/shared-package.git",
      "branch_name": "codex/checkout-flow"
    }
  ]
}
```

Top-level fields:

- `id` — optional stable identifier. Defaults to the workspace root path.
- `title` — display title. Defaults to the folder name.
- `description` — optional task summary shown in the detail view.
- `task_links` — optional links or identifiers for the work item.
- `repositories` — repo entries that belong to the workspace.
- `created_at` / `updated_at` — optional ISO-8601 timestamps.

Repository entry fields:

- `id` — optional stable identifier. Defaults to `path`.
- `name` — display name. Defaults to the last path component.
- `role` — optional short role such as `app`, `backend`, or `docs`.
- `path` — relative path under the workspace root, or an absolute path.
- `source_kind` — `existing_path`, `remote`, `local_repository`, or
  `bare_repository`.
- `source_location` — optional remote URL, local repository path, or bare repo
  path.
- `branch_name` — optional branch/worktree name expected for the task.
- `base_ref` — optional base branch or ref.

## Agent usage

Because the terminal cwd is the workspace root, agents can inspect and modify
all listed repositories in one session:

```bash
git -C app status
git -C api status
git -C shared-package status
```

Use the metadata as the contract: it tells the agent which repos are in scope,
where they are on disk, and what role each repo plays in the task.
